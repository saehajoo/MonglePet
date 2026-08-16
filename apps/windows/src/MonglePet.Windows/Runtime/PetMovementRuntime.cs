using System.Diagnostics;
using Microsoft.UI.Dispatching;
using MonglePet.Activity;
using MonglePet.Core.Behavior;
using MonglePet.Core.Movement;
using MonglePet.Settings;
using MonglePet.Shell;
using MonglePet.Windows.Overlay;

namespace MonglePet.Windows.Runtime;

internal sealed class PetMovementRuntime : IDisposable
{
    private static readonly TimeSpan MovementInterval =
        TimeSpan.FromTicks(TimeSpan.TicksPerSecond / 60);
    private static readonly TimeSpan PointerInterval = TimeSpan.FromMilliseconds(100);
    private static readonly TimeSpan RetryInterval = TimeSpan.FromSeconds(1);

    private readonly PetOverlayWindow _overlay;
    private readonly PetDesktopEnvironment _environment;
    private readonly IWindowsFrontmostWindowProvider _frontmostWindowProvider;
    private readonly HashSet<string> _availableMotionIds;
    private readonly DispatcherQueueTimer _timer;
    private readonly PointerHoverTracker _hoverTracker = new();
    private IReadOnlyList<MonitorWorkArea>? _resolvedWorkAreasSource;
    private MovementBoundarySettings? _resolvedBoundary;
    private IReadOnlyList<MovementScreen>? _resolvedScreens;
    private PetMovementSettings _settings = PetMovementSettings.Default;
    private MovementBoundarySettings _boundary = MovementBoundarySettings.Default;
    private OverlaySettings _overlaySettings = OverlaySettings.Default;
    private string? _pettingMotionId;
    private PetPresentation _presentation = PetPresentation.TuckedAway;
    private bool _isSystemSuspended = true;
    private bool _isUserDragging;
    private bool _isEscaping;
    private MovementPoint? _target;
    private MovementPositionAccumulator? _positionAccumulator;
    private long? _dwellUntil;
    private long _lastTickTimestamp = Stopwatch.GetTimestamp();
    private ScreenPoint? _lastPointer;
    private ScreenPoint? _directDragOffset;
    private bool _isDirectDragging;
    private bool _wasPrimaryButtonPressed;
    private string? _reportedMotionId;
    private TimeSpan? _scheduledInterval;
    private bool _disposed;

    public PetMovementRuntime(
        PetOverlayWindow overlay,
        WindowsMonitorPlacementService monitorService,
        IEnumerable<string> availableMotionIds,
        IWindowsFrontmostWindowProvider? frontmostWindowProvider = null,
        PetDesktopEnvironment? environment = null)
    {
        ArgumentNullException.ThrowIfNull(overlay);
        ArgumentNullException.ThrowIfNull(monitorService);
        ArgumentNullException.ThrowIfNull(availableMotionIds);
        _overlay = overlay;
        _environment = environment ?? new PetDesktopEnvironment(monitorService);
        _frontmostWindowProvider =
            frontmostWindowProvider ?? new WindowsFrontmostWindowProvider();
        _availableMotionIds = new HashSet<string>(
            availableMotionIds,
            StringComparer.Ordinal);
        _timer = DispatcherQueue.GetForCurrentThread().CreateTimer();
        _timer.IsRepeating = true;
        _timer.Tick += Timer_Tick;
    }

    public string Status { get; private set; } = "이동 대기 중";

    public string PointerStatus { get; private set; } = "포인터 감시 대기";

    public string WindowPreferenceStatus { get; private set; } = "전면 창 선호 대기";

    public event EventHandler? StateChanged;

    public event EventHandler<MovementMotionChangedEventArgs>? MovementMotionChanged;

    public event EventHandler<PettingRequestedEventArgs>? PettingRequested;

    public event EventHandler<DirectDragCompletedEventArgs>? DirectDragCompleted;

    public void Update(
        BehaviorProfile profile,
        OverlaySettings overlaySettings,
        PetPresentation presentation,
        bool isSystemSuspended)
    {
        ArgumentNullException.ThrowIfNull(profile);
        ArgumentNullException.ThrowIfNull(overlaySettings);
        ThrowIfDisposed();
        PetMovementSettings nextSettings = profile.Movement;
        MovementBoundarySettings nextBoundary = overlaySettings.MovementBoundary;
        string? nextPettingMotionId = ValidMotionId(profile.PettingMotionId);
        bool targetSettingsChanged = nextSettings != _settings ||
            nextBoundary != _boundary;
        bool observationSettingsChanged =
            overlaySettings.ClickThrough != _overlaySettings.ClickThrough ||
            overlaySettings.PointerOverlapFadeEnabled !=
                _overlaySettings.PointerOverlapFadeEnabled ||
            nextPettingMotionId != _pettingMotionId;
        bool lifecycleChanged = presentation != _presentation ||
            isSystemSuspended != _isSystemSuspended;
        _settings = nextSettings;
        _boundary = nextBoundary;
        _overlaySettings = overlaySettings;
        _pettingMotionId = nextPettingMotionId;
        _presentation = presentation;
        _isSystemSuspended = isSystemSuspended;
        if (!targetSettingsChanged &&
            !observationSettingsChanged &&
            !lifecycleChanged)
        {
            return;
        }
        if (_isDirectDragging && !CanDirectDrag)
        {
            CompleteDirectDrag();
        }
        if (targetSettingsChanged)
        {
            ResetMovementTarget();
            InvalidateResolvedScreens();
        }
        if (targetSettingsChanged)
        {
            _frontmostWindowProvider.Invalidate();
        }
        Reconfigure();
    }

    public void SetUserDragging(bool isDragging)
    {
        ThrowIfDisposed();
        if (_isUserDragging == isDragging)
        {
            return;
        }
        _isUserDragging = isDragging;
        if (isDragging)
        {
            ResetMovementTarget();
            ReportMotion(null);
            Status = "사용자가 펫을 이동하는 중";
            StateChanged?.Invoke(this, EventArgs.Empty);
        }
        Reconfigure();
    }

    public void InvalidateEnvironment()
    {
        ThrowIfDisposed();
        _frontmostWindowProvider.Invalidate();
        _environment.InvalidateDisplays();
        InvalidateResolvedScreens();
        ResetMovementTarget();
        Reconfigure();
    }

    public void Dispose()
    {
        if (_disposed)
        {
            return;
        }
        if (_isDirectDragging)
        {
            CompleteDirectDrag();
        }
        _disposed = true;
        StopTimer();
        _timer.Tick -= Timer_Tick;
        _frontmostWindowProvider.Invalidate();
        _overlay.SetPointerOverVisibleContent(false);
        ReportMotion(null);
        GC.SuppressFinalize(this);
    }

    private bool IsActive =>
        _presentation == PetPresentation.Awake &&
        !_isSystemSuspended &&
        !_isUserDragging &&
        _overlay.IsVisible;

    private bool NeedsPointerObservation =>
        CanDirectDrag ||
        _pettingMotionId is not null ||
        ShouldMonitorOpacity ||
        _settings.Mode is PetMovementMode.CursorFollowing or PetMovementMode.CursorAvoiding;

    private bool CanDirectDrag =>
        _settings.Mode == PetMovementMode.Fixed &&
        !_overlaySettings.ClickThrough;

    private bool ShouldMonitorOpacity =>
        _overlaySettings.ClickThrough &&
        _overlaySettings.PointerOverlapFadeEnabled;

    private bool ShouldObserveAlpha =>
        CanDirectDrag ||
        ShouldMonitorOpacity ||
        (_pettingMotionId is not null &&
            _settings.Mode != PetMovementMode.CursorAvoiding);

    private void Reconfigure()
    {
        StopTimer();
        if (!IsActive)
        {
            ResetMovementTarget();
            _hoverTracker.Reset();
            _overlay.SetAlphaMaskObservationEnabled(false);
            _overlay.SetPointerOverVisibleContent(false);
            ReportMotion(null);
            Status = _presentation == PetPresentation.TuckedAway
                ? "펫이 숨겨져 이동을 멈췄습니다"
                : _isSystemSuspended
                    ? "시스템 상태로 이동을 멈췄습니다"
                    : "사용자 드래그로 이동을 멈췄습니다";
            StateChanged?.Invoke(this, EventArgs.Empty);
            return;
        }

        _lastTickTimestamp = Stopwatch.GetTimestamp();
        bool canPreferFrontmostWindow = _settings.Mode == PetMovementMode.FreeRoaming ||
            (_settings.Mode == PetMovementMode.CursorAvoiding &&
                _settings.CursorAvoidingIdleBehavior ==
                    CursorAvoidingIdleBehavior.FreeRoaming);
        if (!canPreferFrontmostWindow)
        {
            WindowPreferenceStatus = "전면 창 선호 대기";
        }
        else if (!_settings.PrefersFrontmostWindow)
        {
            WindowPreferenceStatus = "전면 창 선호 꺼짐";
        }
        _overlay.SetAlphaMaskObservationEnabled(ShouldObserveAlpha);
        if (!ShouldMonitorOpacity)
        {
            _overlay.SetPointerOverVisibleContent(false);
        }
        Status = _settings.Mode switch
        {
            PetMovementMode.Fixed => "위치 고정",
            PetMovementMode.CursorFollowing => "마우스 따라가기",
            PetMovementMode.FreeRoaming => "자유 이동",
            PetMovementMode.CursorAvoiding => "마우스 도망가기",
            _ => "이동 대기 중",
        };
        Schedule(_settings.Mode == PetMovementMode.Fixed
            ? CanDirectDrag
                ? MovementInterval
                : NeedsPointerObservation ? PointerInterval : null
            : MovementInterval);
        StateChanged?.Invoke(this, EventArgs.Empty);
    }

    private void Timer_Tick(DispatcherQueueTimer sender, object args)
    {
        if (_disposed || !IsActive)
        {
            Reconfigure();
            return;
        }

        long now = Stopwatch.GetTimestamp();
        double elapsedSeconds = Math.Max(
            0,
            Stopwatch.GetElapsedTime(_lastTickTimestamp, now).TotalSeconds);
        _lastTickTimestamp = now;
        try
        {
            PetDesktopEnvironmentSnapshot environment = _environment.Capture();
            ScreenPoint pointer = environment.Pointer;
            if (HandleDirectDrag(pointer, environment.IsPrimaryButtonPressed))
            {
                return;
            }
            ObserveHover(pointer, now);
            TickMovement(pointer, environment.WorkAreas, now, elapsedSeconds);
        }
        catch (Exception exception)
        {
            Status = $"이동 환경을 확인하지 못했습니다: {exception.Message}";
            ReportMotion(null);
            StateChanged?.Invoke(this, EventArgs.Empty);
            Schedule(RetryInterval);
        }
    }

    private bool HandleDirectDrag(ScreenPoint pointer, bool isPrimaryButtonPressed)
    {
        bool didPress = isPrimaryButtonPressed && !_wasPrimaryButtonPressed;
        _wasPrimaryButtonPressed = isPrimaryButtonPressed;

        if (_isDirectDragging)
        {
            if (!isPrimaryButtonPressed || !CanDirectDrag)
            {
                CompleteDirectDrag();
                return false;
            }

            ScreenPoint offset = _directDragOffset ?? new ScreenPoint(0, 0);
            _overlay.MoveTo(pointer.X - offset.X, pointer.Y - offset.Y);
            Status = "사용자가 펫을 이동하는 중";
            PointerStatus = "왼쪽 버튼 드래그 중";
            Schedule(MovementInterval);
            return true;
        }

        if (!CanDirectDrag || !didPress ||
            !_overlay.IsTopmostWindowAt(pointer.X, pointer.Y))
        {
            return false;
        }

        double localX = pointer.X - _overlay.OriginX;
        double localY = pointer.Y - _overlay.OriginY;
        if (!_overlay.ContainsVisibleContent(localX, localY))
        {
            return false;
        }

        _isDirectDragging = true;
        _directDragOffset = new ScreenPoint(
            pointer.X - _overlay.OriginX,
            pointer.Y - _overlay.OriginY);
        ResetMovementTarget();
        _hoverTracker.Reset();
        ReportMotion(null);
        Status = "사용자가 펫을 이동하는 중";
        PointerStatus = "왼쪽 버튼 드래그 시작";
        StateChanged?.Invoke(this, EventArgs.Empty);
        Schedule(MovementInterval);
        return true;
    }

    private void CompleteDirectDrag()
    {
        if (!_isDirectDragging)
        {
            return;
        }

        _isDirectDragging = false;
        _directDragOffset = null;
        Status = "위치 고정";
        PointerStatus = "드래그 위치 저장";
        DirectDragCompleted?.Invoke(
            this,
            new DirectDragCompletedEventArgs(_overlay.OriginX, _overlay.OriginY));
        StateChanged?.Invoke(this, EventArgs.Empty);
    }

    private void TickMovement(
        ScreenPoint pointer,
        IReadOnlyList<MonitorWorkArea> workAreas,
        long now,
        double elapsedSeconds)
    {
        IReadOnlyList<MovementScreen> screens = ResolvedScreens(workAreas);
        var observedOrigin = new MovementPoint(_overlay.OriginX, _overlay.OriginY);
        _positionAccumulator ??= new MovementPositionAccumulator(observedOrigin);
        MovementPoint origin = _positionAccumulator.Origin;
        var size = new MovementSize(_overlay.Width, _overlay.Height);
        var pointerPoint = new MovementPoint(pointer.X, pointer.Y);
        switch (_settings.Mode)
        {
            case PetMovementMode.Fixed:
                ReportMotion(null);
                Schedule(CanDirectDrag
                    ? MovementInterval
                    : NeedsPointerObservation ? PointerInterval : null);
                return;
            case PetMovementMode.CursorFollowing:
                _target = PetMovementGeometry.CursorFollowingTarget(
                    pointerPoint,
                    origin,
                    size,
                    _settings.CursorDistance,
                    screens);
                bool arrived = MoveToward(
                    origin,
                    size,
                    _settings.Speed,
                    elapsedSeconds,
                    screens,
                    false);
                Schedule(arrived ? PointerInterval : MovementInterval);
                return;
            case PetMovementMode.FreeRoaming:
                TickFreeRoaming(origin, size, now, elapsedSeconds, screens, false);
                return;
            case PetMovementMode.CursorAvoiding:
                TickCursorAvoiding(pointerPoint, origin, size, now, elapsedSeconds, screens);
                return;
            default:
                Schedule(RetryInterval);
                return;
        }
    }

    private void TickFreeRoaming(
        MovementPoint origin,
        MovementSize size,
        long now,
        double elapsedSeconds,
        IReadOnlyList<MovementScreen> screens,
        bool avoidingIdle)
    {
        if (_dwellUntil is long dwellUntil && now < dwellUntil)
        {
            ReportMotion(null);
            Status = avoidingIdle ? "도망가기 · 자유 이동 대기" : "자유 이동 · 머무는 중";
            Schedule(PointerInterval);
            return;
        }
        _dwellUntil = null;
        if (_target is null)
        {
            MovementRect? preferredWindow = null;
            if (_settings.PrefersFrontmostWindow)
            {
                preferredWindow = _frontmostWindowProvider
                    .RepresentativeWindow(screens);
                WindowPreferenceStatus = _frontmostWindowProvider.Status;
            }
            _target = PetMovementGeometry.FreeRoamingTarget(
                screens,
                size,
                new MovementRandomSample(
                    Random.Shared.NextDouble(),
                    Random.Shared.NextDouble(),
                    Random.Shared.NextDouble()),
                preferredWindow: preferredWindow);
        }
        bool arrived = MoveToward(
            origin,
            size,
            _settings.Speed,
            elapsedSeconds,
            screens,
            avoidingIdle);
        if (arrived)
        {
            _target = null;
            _dwellUntil = now + MillisecondsToStopwatchTicks(
                _settings.FreeRoamingDwellMilliseconds);
        }
        Schedule(arrived ? PointerInterval : MovementInterval);
    }

    private void TickCursorAvoiding(
        MovementPoint pointer,
        MovementPoint origin,
        MovementSize size,
        long now,
        double elapsedSeconds,
        IReadOnlyList<MovementScreen> screens)
    {
        double distance = PetMovementGeometry.DistanceFromPointerToPet(
            pointer,
            origin,
            size) ?? double.MaxValue;
        double releaseDistance = _settings.CursorAvoidingDetectionDistance +
            Math.Max(64, _settings.StopRadius * 2);
        if (distance <= _settings.CursorAvoidingDetectionDistance ||
            (_isEscaping && distance < releaseDistance))
        {
            _isEscaping = true;
            _dwellUntil = null;
            _target = PetMovementGeometry.CursorAvoidingTarget(
                pointer,
                origin,
                size,
                releaseDistance,
                screens);
            MoveToward(
                origin,
                size,
                _settings.CursorAvoidingSpeed,
                elapsedSeconds,
                screens,
                true);
            Status = "마우스에서 도망가는 중";
            Schedule(MovementInterval);
            return;
        }

        _isEscaping = false;
        _target = null;
        ReportMotion(null);
        if (_settings.CursorAvoidingIdleBehavior == CursorAvoidingIdleBehavior.FreeRoaming)
        {
            TickFreeRoaming(origin, size, now, elapsedSeconds, screens, true);
        }
        else
        {
            Status = "마우스 도망가기 · 대기";
            Schedule(PointerInterval);
        }
    }

    private bool MoveToward(
        MovementPoint origin,
        MovementSize size,
        double speed,
        double elapsedSeconds,
        IReadOnlyList<MovementScreen> screens,
        bool avoiding)
    {
        if (_target is not { } target)
        {
            ReportMotion(null);
            return false;
        }
        MovementAdvance advance = _positionAccumulator!.Advance(
            target,
            speed,
            elapsedSeconds,
            _settings.StopRadius);
        if (!advance.DidMove)
        {
            ReportMotion(null);
            return advance.HasArrived;
        }

        bool allowsInterDisplayTransit =
            _boundary.Mode == MovementBoundaryMode.AllDisplays ||
            string.IsNullOrWhiteSpace(_boundary.ScreenIdentifier);
        MovementPoint applied = allowsInterDisplayTransit
            ? advance.Origin
            : PetMovementGeometry.ClampToNearestScreen(
                advance.Origin,
                size,
                screens) ?? advance.Origin;
        _positionAccumulator.SetOrigin(applied);
        (int pixelX, int pixelY) = _positionAccumulator.RoundedPixelOrigin();
        _overlay.MoveTo(pixelX, pixelY);
        double actualDeltaX = applied.X - origin.X;
        double actualDeltaY = applied.Y - origin.Y;
        MovementAnimationSettings animation = avoiding
            ? _settings.CursorAvoidingAnimation
            : _settings.Mode == PetMovementMode.CursorFollowing
                ? _settings.CursorFollowingAnimation
                : _settings.FreeRoamingAnimation;
        ReportMotion(ResolveMovementMotion(animation, actualDeltaX, actualDeltaY));
        Status = _settings.Mode switch
        {
            PetMovementMode.CursorFollowing => "마우스를 따라 이동 중",
            PetMovementMode.FreeRoaming => "자유 이동 중",
            PetMovementMode.CursorAvoiding when avoiding => "마우스에서 도망가는 중",
            _ => "이동 중",
        };
        return advance.HasArrived;
    }

    private void ObserveHover(ScreenPoint pointer, long timestamp)
    {
        bool moved = _lastPointer is null || _lastPointer.Value != pointer;
        _lastPointer = pointer;
        bool insidePanel = pointer.X >= _overlay.OriginX &&
            pointer.X < _overlay.OriginX + _overlay.Width &&
            pointer.Y >= _overlay.OriginY &&
            pointer.Y < _overlay.OriginY + _overlay.Height;
        bool pettingEnabled = _pettingMotionId is not null &&
            _settings.Mode != PetMovementMode.CursorAvoiding;
        bool overVisibleContent = insidePanel &&
            (pettingEnabled || ShouldMonitorOpacity) &&
            _overlay.ContainsVisibleContent(
                pointer.X - _overlay.OriginX,
                pointer.Y - _overlay.OriginY);
        string pointerStatus = !insidePanel
            ? "포인터: 패널 밖"
            : overVisibleContent
                ? "포인터: 표시 픽셀"
                : "포인터: 투명 픽셀";
        if (!string.Equals(PointerStatus, pointerStatus, StringComparison.Ordinal))
        {
            PointerStatus = pointerStatus;
            StateChanged?.Invoke(this, EventArgs.Empty);
        }
        _overlay.SetPointerOverVisibleContent(
            ShouldMonitorOpacity && overVisibleContent);
        long milliseconds = (long)Math.Max(
            0,
            Stopwatch.GetElapsedTime(0, timestamp).TotalMilliseconds);
        if (_hoverTracker.Update(
                milliseconds,
                insidePanel,
                overVisibleContent,
                moved,
                pettingEnabled,
                _isUserDragging) &&
            _pettingMotionId is { } motionId)
        {
            PettingRequested?.Invoke(this, new PettingRequestedEventArgs(motionId));
        }
    }

    private IReadOnlyList<MovementScreen> ResolvedScreens(
        IReadOnlyList<MonitorWorkArea> workAreas)
    {
        if (ReferenceEquals(_resolvedWorkAreasSource, workAreas) &&
            _resolvedBoundary == _boundary &&
            _resolvedScreens is not null)
        {
            return _resolvedScreens;
        }

        MovementScreen[] available = workAreas
            .Select(area => new MovementScreen(
                area.Identifier,
                new MovementRect(area.Left, area.Top, area.Width, area.Height)))
            .ToArray();
        if (_boundary.Mode == MovementBoundaryMode.AllDisplays ||
            string.IsNullOrWhiteSpace(_boundary.ScreenIdentifier))
        {
            return CacheResolvedScreens(workAreas, available);
        }

        MovementScreen? selected = available.FirstOrDefault(screen => string.Equals(
            screen.Identifier,
            _boundary.ScreenIdentifier,
            StringComparison.OrdinalIgnoreCase));
        if (selected is null)
        {
            return CacheResolvedScreens(workAreas, available);
        }
        if (_boundary.Mode != MovementBoundaryMode.CustomArea ||
            _boundary.NormalizedRect is not { IsValid: true } normalized)
        {
            return CacheResolvedScreens(workAreas, [selected]);
        }
        MovementRect frame = selected.WorkArea;
        return CacheResolvedScreens(workAreas, [new MovementScreen(selected.Identifier, new MovementRect(
            frame.X + (frame.Width * normalized.X),
            frame.Y + (frame.Height * normalized.Y),
            frame.Width * normalized.Width,
            frame.Height * normalized.Height))]);
    }

    private IReadOnlyList<MovementScreen> CacheResolvedScreens(
        IReadOnlyList<MonitorWorkArea> workAreas,
        IReadOnlyList<MovementScreen> screens)
    {
        _resolvedWorkAreasSource = workAreas;
        _resolvedBoundary = _boundary;
        _resolvedScreens = screens;
        return screens;
    }

    private void InvalidateResolvedScreens()
    {
        _resolvedWorkAreasSource = null;
        _resolvedBoundary = null;
        _resolvedScreens = null;
    }

    private string? ResolveMovementMotion(
        MovementAnimationSettings animation,
        double deltaX,
        double deltaY)
    {
        if (!animation.UsesDirectionalMotions)
        {
            return ValidMotionId(animation.FallbackMotionId);
        }
        MovementDirection? direction = PetMovementGeometry.Direction(
            deltaX,
            deltaY,
            animation.UsesDiagonalMotions);
        string? exact = direction switch
        {
            MovementDirection.Left => animation.DirectionMotionIds.Left,
            MovementDirection.Right => animation.DirectionMotionIds.Right,
            MovementDirection.Up => animation.DirectionMotionIds.Up,
            MovementDirection.Down => animation.DirectionMotionIds.Down,
            MovementDirection.UpLeft => animation.DirectionMotionIds.UpLeft,
            MovementDirection.UpRight => animation.DirectionMotionIds.UpRight,
            MovementDirection.DownLeft => animation.DirectionMotionIds.DownLeft,
            MovementDirection.DownRight => animation.DirectionMotionIds.DownRight,
            _ => null,
        };
        exact = ValidMotionId(exact);
        if (exact is not null)
        {
            return exact;
        }
        string? axisFallback = Math.Abs(deltaX) >= Math.Abs(deltaY)
            ? ValidMotionId(deltaX < 0
                ? animation.DirectionMotionIds.Left
                : animation.DirectionMotionIds.Right)
            : ValidMotionId(deltaY < 0
                ? animation.DirectionMotionIds.Up
                : animation.DirectionMotionIds.Down);
        return axisFallback ?? ValidMotionId(animation.FallbackMotionId);
    }

    private string? ValidMotionId(string? value) =>
        value is not null && _availableMotionIds.Contains(value) ? value : null;

    private void ReportMotion(string? motionId)
    {
        if (string.Equals(_reportedMotionId, motionId, StringComparison.Ordinal))
        {
            return;
        }
        _reportedMotionId = motionId;
        MovementMotionChanged?.Invoke(
            this,
            new MovementMotionChangedEventArgs(motionId));
    }

    private void ResetMovementTarget()
    {
        _target = null;
        _positionAccumulator = null;
        _dwellUntil = null;
        _isEscaping = false;
    }

    private void Schedule(TimeSpan? interval)
    {
        if (interval is null || _disposed)
        {
            StopTimer();
            return;
        }
        if (_timer.IsRunning && _scheduledInterval == interval)
        {
            return;
        }
        _timer.Stop();
        _scheduledInterval = interval;
        _timer.Interval = interval.Value;
        _timer.Start();
    }

    private void StopTimer()
    {
        _timer.Stop();
        _scheduledInterval = null;
    }

    private static long MillisecondsToStopwatchTicks(long milliseconds) =>
        checked((long)Math.Round(milliseconds * (Stopwatch.Frequency / 1000d)));

    private void ThrowIfDisposed() => ObjectDisposedException.ThrowIf(_disposed, this);
}

internal sealed record MovementMotionChangedEventArgs(string? MotionId);

internal sealed record PettingRequestedEventArgs(string MotionId);

internal sealed record DirectDragCompletedEventArgs(int X, int Y);
