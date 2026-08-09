using System.Diagnostics;
using Microsoft.UI.Dispatching;
using MonglePet.Core.Behavior;
using MonglePet.Packages;
using MonglePet.Settings;
using MonglePet.Windows.Overlay;

namespace MonglePet.Windows.Runtime;

internal sealed class PetBehaviorRuntime : IDisposable
{
    private readonly BehaviorResolver _resolver = new();
    private readonly MotionScheduler _scheduler;
    private readonly IReadOnlyDictionary<string, TimeSpan> _cycleDurations;
    private readonly PetOverlayWindow _overlay;
    private readonly DispatcherQueueTimer _boundaryTimer;
    private readonly DispatcherQueueTimer _interactionTimer;
    private readonly long _originTimestamp = Stopwatch.GetTimestamp();
    private long _lastAdvancedTimestamp;
    private ScheduledMotion? _currentMotion;
    private string? _movementMotionId;
    private string? _interactionMotionId;
    private string? _displayedMotionId;
    private ActivitySnapshot _activitySnapshot = new(
        TimeSpan.Zero,
        TimeSpan.Zero,
        null,
        false,
        false);
    private bool _waitingForPlaybackReady;
    private bool _disposed;

    public PetBehaviorRuntime(LoadedPetPackage package, PetOverlayWindow overlay)
    {
        ArgumentNullException.ThrowIfNull(package);
        ArgumentNullException.ThrowIfNull(overlay);
        _overlay = overlay;
        _cycleDurations = BuildCycleDurations(package);
        _scheduler = new MotionScheduler(package.DefaultMotionId, _cycleDurations);
        _boundaryTimer = DispatcherQueue.GetForCurrentThread().CreateTimer();
        _boundaryTimer.IsRepeating = false;
        _boundaryTimer.Tick += BoundaryTimer_Tick;
        _interactionTimer = DispatcherQueue.GetForCurrentThread().CreateTimer();
        _interactionTimer.IsRepeating = false;
        _interactionTimer.Tick += InteractionTimer_Tick;
        _overlay.StateChanged += Overlay_StateChanged;
        _lastAdvancedTimestamp = Stopwatch.GetTimestamp();
    }

    public string Status { get; private set; } = "행동 대기 중";

    public string? SequenceId => _currentMotion?.SequenceId;

    public int? StepIndex => _currentMotion?.StepIndex;

    public bool IsPaused => _scheduler.IsPaused;

    public event EventHandler? StateChanged;

    public void SetMovementMotion(string? motionId)
    {
        ThrowIfDisposed();
        if (string.Equals(_movementMotionId, motionId, StringComparison.Ordinal))
        {
            return;
        }
        _movementMotionId = motionId;
        RenderPreferredMotion(restart: _interactionMotionId is null && motionId is not null);
        StateChanged?.Invoke(this, EventArgs.Empty);
    }

    public void PlayInteraction(string motionId)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(motionId);
        ThrowIfDisposed();
        if (_interactionMotionId is not null ||
            !_cycleDurations.TryGetValue(motionId, out TimeSpan duration))
        {
            return;
        }

        long now = Stopwatch.GetTimestamp();
        AdvanceTo(now);
        _boundaryTimer.Stop();
        _scheduler.Pause();
        _interactionMotionId = motionId;
        _interactionTimer.Interval = duration > TimeSpan.Zero
            ? duration
            : TimeSpan.FromMilliseconds(1);
        _interactionTimer.Start();
        RenderPreferredMotion(restart: true);
        Status = $"쓰다듬기 · {motionId}";
        StateChanged?.Invoke(this, EventArgs.Empty);
    }

    public void Update(BehaviorProfile profile, PetPresentation presentation)
    {
        ArgumentNullException.ThrowIfNull(profile);
        ThrowIfDisposed();
        long now = Stopwatch.GetTimestamp();
        AdvanceTo(now);
        BehaviorDecision decision = _resolver.Resolve(
            Configuration(profile),
            _activitySnapshot with
            {
                CapturedAt = Stopwatch.GetElapsedTime(_originTimestamp, now),
            },
            new BehaviorRuntimeState(presentation));
        Apply(decision, now);
    }

    public void UpdateActivity(ActivitySnapshot snapshot, BehaviorProfile profile, PetPresentation presentation)
    {
        ArgumentNullException.ThrowIfNull(snapshot);
        _activitySnapshot = snapshot;
        Update(profile, presentation);
    }

    public void Dispose()
    {
        if (_disposed)
        {
            return;
        }

        _disposed = true;
        _boundaryTimer.Stop();
        _boundaryTimer.Tick -= BoundaryTimer_Tick;
        _interactionTimer.Stop();
        _interactionTimer.Tick -= InteractionTimer_Tick;
        _overlay.StateChanged -= Overlay_StateChanged;
        GC.SuppressFinalize(this);
    }

    private void Apply(BehaviorDecision decision, long now)
    {
        switch (decision)
        {
            case BehaviorDecision.TuckedAway:
                Pause("사용자가 펫을 숨겼습니다", now);
                break;
            case BehaviorDecision.Suspended:
                Pause("시스템 상태로 일시 정지했습니다", now);
                break;
            case BehaviorDecision.Sequence sequence:
                _scheduler.Resume();
                bool changed = _scheduler.Request(sequence.Value);
                _lastAdvancedTimestamp = now;
                if (_interactionMotionId is not null)
                {
                    _scheduler.Pause();
                }
                EmitCurrentMotion(changed);
                if (_interactionMotionId is null)
                {
                    ScheduleNextBoundary();
                }
                break;
            case BehaviorDecision.Unavailable:
                _boundaryTimer.Stop();
                _interactionTimer.Stop();
                _interactionMotionId = null;
                _scheduler.Stop();
                _overlay.PausePlayback();
                _currentMotion = null;
                Status = "재생 가능한 행동 루틴이 없습니다";
                StateChanged?.Invoke(this, EventArgs.Empty);
                break;
        }
    }

    private void Pause(string status, long now)
    {
        _boundaryTimer.Stop();
        _interactionTimer.Stop();
        _interactionMotionId = null;
        _scheduler.Pause();
        _overlay.PausePlayback();
        _waitingForPlaybackReady = false;
        _lastAdvancedTimestamp = now;
        Status = status;
        StateChanged?.Invoke(this, EventArgs.Empty);
    }

    private void BoundaryTimer_Tick(DispatcherQueueTimer sender, object args)
    {
        if (_disposed)
        {
            return;
        }

        AdvanceTo(Stopwatch.GetTimestamp());
        EmitCurrentMotion(restart: false);
        ScheduleNextBoundary();
    }

    private void InteractionTimer_Tick(DispatcherQueueTimer sender, object args)
    {
        if (_disposed || _interactionMotionId is null)
        {
            return;
        }

        _interactionMotionId = null;
        _scheduler.Resume();
        _lastAdvancedTimestamp = Stopwatch.GetTimestamp();
        RenderPreferredMotion(restart: true);
        EmitCurrentMotion(restart: false);
        ScheduleNextBoundary();
    }

    private void Overlay_StateChanged(object? sender, EventArgs e)
    {
        if (_disposed || !_waitingForPlaybackReady || !_overlay.IsPlaybackReady)
        {
            return;
        }

        _waitingForPlaybackReady = false;
        _lastAdvancedTimestamp = Stopwatch.GetTimestamp();
        ScheduleNextBoundary();
        StateChanged?.Invoke(this, EventArgs.Empty);
    }

    private void AdvanceTo(long timestamp)
    {
        TimeSpan elapsed = Stopwatch.GetElapsedTime(_lastAdvancedTimestamp, timestamp);
        _lastAdvancedTimestamp = timestamp;
        if (elapsed > TimeSpan.Zero)
        {
            _scheduler.Advance(elapsed);
        }
    }

    private void EmitCurrentMotion(bool restart)
    {
        switch (_scheduler.Status)
        {
            case MotionSchedulerStatus.Playing playing:
                bool changed = playing.Motion != _currentMotion;
                _currentMotion = playing.Motion;
                RenderPreferredMotion(_interactionMotionId is null && (restart || changed));
                _waitingForPlaybackReady =
                    _interactionMotionId is null &&
                    _movementMotionId is null &&
                    !_overlay.IsPlaybackReady;
                Status = _interactionMotionId is { } interaction
                    ? $"쓰다듬기 · {interaction}"
                    : $"{playing.Motion.SequenceId} · 단계 {playing.Motion.StepIndex + 1}" +
                        (playing.Motion.UsesFallback ? " · 기본 모션 대체" : string.Empty);
                break;
            case MotionSchedulerStatus.Completed completed:
                _currentMotion = null;
                RenderPreferredMotion(restart: false);
                Status = $"{completed.SequenceId} · 완료";
                break;
            case MotionSchedulerStatus.Unavailable:
                _currentMotion = null;
                RenderPreferredMotion(restart: false);
                Status = "행동 루틴의 모션을 해석할 수 없습니다";
                break;
            case MotionSchedulerStatus.Stopped:
                _currentMotion = null;
                RenderPreferredMotion(restart: false);
                Status = "행동 대기 중";
                break;
        }
        StateChanged?.Invoke(this, EventArgs.Empty);
    }

    private void RenderPreferredMotion(bool restart)
    {
        string? desired = _interactionMotionId ??
            _movementMotionId ??
            (_scheduler.Status as MotionSchedulerStatus.Playing)?.Motion.ResolvedMotionId;
        if (desired is null)
        {
            _overlay.PausePlayback();
            _displayedMotionId = null;
            return;
        }
        if (restart || !string.Equals(_displayedMotionId, desired, StringComparison.Ordinal))
        {
            _overlay.PlayMotion(desired, restart: true);
            _displayedMotionId = desired;
        }
        _overlay.ResumePlayback();
    }

    private void ScheduleNextBoundary()
    {
        _boundaryTimer.Stop();
        if (_scheduler.IsPaused || _waitingForPlaybackReady ||
            _scheduler.ActiveCycleRemainingDuration is not { } remaining)
        {
            return;
        }

        _boundaryTimer.Interval = remaining > TimeSpan.Zero
            ? remaining
            : TimeSpan.FromMilliseconds(1);
        _boundaryTimer.Start();
    }

    private static BehaviorConfiguration Configuration(BehaviorProfile profile)
    {
        string defaultSequenceId = profile.Sequences.Any(sequence =>
            string.Equals(
                sequence.Id,
                BehaviorMotionReferences.DefaultSequence,
                StringComparison.Ordinal))
            ? BehaviorMotionReferences.DefaultSequence
            : profile.Sequences.FirstOrDefault()?.Id ?? BehaviorMotionReferences.DefaultSequence;
        return new BehaviorConfiguration(
            profile.Mode,
            defaultSequenceId,
            profile.Sequences,
            profile.ManualSequenceId,
            profile.AutomaticRules);
    }

    private static IReadOnlyDictionary<string, TimeSpan> BuildCycleDurations(
        LoadedPetPackage package)
    {
        var durations = new Dictionary<string, TimeSpan>(StringComparer.Ordinal);
        foreach (PetPackageMotion motion in package.Manifest.Motions)
        {
            long milliseconds = 0;
            checked
            {
                foreach (PetPackageFrame frame in motion.Frames)
                {
                    milliseconds += frame.DurationMs;
                }
            }
            durations.Add(motion.Id, TimeSpan.FromMilliseconds(milliseconds));
        }
        return durations;
    }

    private void ThrowIfDisposed() => ObjectDisposedException.ThrowIf(_disposed, this);
}
