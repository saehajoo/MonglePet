using MonglePet.Activity;
using MonglePet.Core.Behavior;
using MonglePet.Packages;
using MonglePet.Settings;
using MonglePet.Shell;
using MonglePet.Windows.Overlay;

namespace MonglePet.Windows.Runtime;

internal sealed record PetRuntimeSnapshot(
    Guid InstanceId,
    string DisplayName,
    string OriginalName,
    PetPresentation Presentation,
    bool IsVisible,
    bool IsPaused,
    string BehaviorStatus,
    string MovementStatus,
    string SpeechStatus,
    int DisplayOrder);

internal sealed record PetOverlayChangedEventArgs(
    Guid InstanceId,
    OverlaySettings Overlay);

internal sealed class PetRuntimeContext : IDisposable
{
    private readonly WindowsMonitorPlacementService _monitorPlacement;
    private readonly PetBehaviorRuntime _behavior;
    private readonly PetSpeechRuntime _speech;
    private readonly PetMovementRuntime _movement;
    private ActivitySnapshot? _activitySnapshot;
    private bool _isPaused;
    private bool _disposed;

    public PetRuntimeContext(
        ActivePetInstance instance,
        BehaviorProfile profile,
        LoadedPetPackage package,
        WindowsMonitorPlacementService monitorPlacement,
        PetDesktopEnvironment desktopEnvironment,
        IWindowsFrontmostWindowProvider frontmostWindowProvider)
    {
        Instance = instance ?? throw new ArgumentNullException(nameof(instance));
        Profile = profile ?? throw new ArgumentNullException(nameof(profile));
        Package = package ?? throw new ArgumentNullException(nameof(package));
        _monitorPlacement = monitorPlacement ?? throw new ArgumentNullException(nameof(monitorPlacement));
        Overlay = new PetOverlayWindow(package, instance.Overlay);
        _behavior = new PetBehaviorRuntime(package, Overlay);
        _speech = CreateSpeechRuntime(Overlay);
        _movement = new PetMovementRuntime(
            Overlay,
            monitorPlacement,
            package.Manifest.Motions.Select(motion => motion.Id),
            frontmostWindowProvider,
            desktopEnvironment);

        _behavior.StateChanged += Behavior_StateChanged;
        _movement.StateChanged += Runtime_StateChanged;
        _movement.MovementMotionChanged += Movement_MovementMotionChanged;
        _movement.PettingRequested += Movement_PettingRequested;
        _movement.DirectDragCompleted += Movement_DirectDragCompleted;
        Overlay.UserDragStateChanged += Overlay_UserDragStateChanged;
        Overlay.DisplayEnvironmentChanged += Overlay_DisplayEnvironmentChanged;
        RestoreSavedPosition();
        Apply(Instance, profile, null, isPaused: false);
    }

    public ActivePetInstance Instance { get; private set; }

    public BehaviorProfile Profile { get; private set; }

    public LoadedPetPackage Package { get; }

    public PetOverlayWindow Overlay { get; }

    public PetRuntimeSnapshot Snapshot => new(
        Instance.InstanceId,
        DisplayName,
        Package.Manifest.DisplayName,
        Instance.Presentation,
        Overlay.IsVisible,
        _isPaused,
        _behavior.Status,
        $"{_movement.Status} · {_movement.PointerStatus}",
        $"{_speech.Status} · {Overlay.SpeechBubbleStatus}",
        Instance.DisplayOrder);

    public string DisplayName => string.IsNullOrWhiteSpace(Instance.Nickname)
        ? Package.Manifest.DisplayName
        : Instance.Nickname!;

    public event EventHandler? StateChanged;

    public event EventHandler<PetOverlayChangedEventArgs>? OverlayChanged;

    public void Apply(
        ActivePetInstance instance,
        BehaviorProfile profile,
        ActivitySnapshot? activitySnapshot,
        bool isPaused,
        bool notifyStateChanged = true)
    {
        ArgumentNullException.ThrowIfNull(instance);
        ArgumentNullException.ThrowIfNull(profile);
        ThrowIfDisposed();
        Instance = instance;
        Profile = profile;
        _activitySnapshot = activitySnapshot;
        _isPaused = isPaused;
        Overlay.ApplyDisplaySettings(instance.Overlay);
        if (instance.Presentation == PetPresentation.Awake)
        {
            Overlay.Show();
        }
        else
        {
            Overlay.Hide();
        }

        bool systemSuspended = isPaused || activitySnapshot is
            { IsScreenLocked: true } or { IsSystemSleeping: true };
        _speech.Update(profile.Speech);
        _speech.SetAwake(instance.Presentation == PetPresentation.Awake);
        _speech.SetSystemSuspended(systemSuspended);
        _behavior.SetUserPaused(isPaused);
        if (activitySnapshot is { } snapshot)
        {
            _behavior.UpdateActivity(snapshot, profile, instance.Presentation);
        }
        else
        {
            _behavior.Update(profile, instance.Presentation);
        }
        _speech.BehaviorSequenceDidChange(_behavior.SequenceId);
        _movement.Update(profile, instance.Overlay, instance.Presentation, systemSuspended);
        if (notifyStateChanged)
        {
            StateChanged?.Invoke(this, EventArgs.Empty);
        }
    }

    public void UpdateActivity(ActivitySnapshot snapshot)
    {
        ArgumentNullException.ThrowIfNull(snapshot);
        Apply(Instance, Profile, snapshot, _isPaused, notifyStateChanged: false);
    }

    public OverlaySettings BringToCurrentScreen()
    {
        ThrowIfDisposed();
        PetScreenPlacement placement = _monitorPlacement.PlacementForCursor(
            Math.Max(1, (int)Math.Round(Overlay.Width)),
            Math.Max(1, (int)Math.Round(Overlay.Height)));
        Overlay.MoveTo(placement.X, placement.Y);
        return Instance.Overlay with
        {
            ScreenIdentifier = placement.ScreenIdentifier,
            OriginX = placement.X,
            OriginY = placement.Y,
        };
    }

    public void InvalidateEnvironment() => _movement.InvalidateEnvironment();

    public void Dispose()
    {
        if (_disposed)
        {
            return;
        }
        _disposed = true;
        Overlay.UserDragStateChanged -= Overlay_UserDragStateChanged;
        Overlay.DisplayEnvironmentChanged -= Overlay_DisplayEnvironmentChanged;
        _movement.StateChanged -= Runtime_StateChanged;
        _movement.MovementMotionChanged -= Movement_MovementMotionChanged;
        _movement.PettingRequested -= Movement_PettingRequested;
        _movement.DirectDragCompleted -= Movement_DirectDragCompleted;
        _behavior.StateChanged -= Behavior_StateChanged;
        _movement.Dispose();
        _speech.Dispose();
        _behavior.Dispose();
        Overlay.Dispose();
        GC.SuppressFinalize(this);
    }

    private void RestoreSavedPosition()
    {
        OverlaySettings settings = Instance.Overlay;
        if (string.IsNullOrWhiteSpace(settings.ScreenIdentifier))
        {
            Overlay.MoveTo((int)Math.Round(settings.OriginX), (int)Math.Round(settings.OriginY));
            return;
        }

        PetScreenPlacement placement = _monitorPlacement.RestorePlacement(
            settings.ScreenIdentifier,
            settings.OriginX,
            settings.OriginY,
            Math.Max(1, (int)Math.Round(Overlay.Width)),
            Math.Max(1, (int)Math.Round(Overlay.Height)));
        Overlay.MoveTo(placement.X, placement.Y);
        if (placement.X != (int)Math.Round(settings.OriginX) ||
            placement.Y != (int)Math.Round(settings.OriginY) ||
            !string.Equals(placement.ScreenIdentifier, settings.ScreenIdentifier, StringComparison.OrdinalIgnoreCase))
        {
            Instance = Instance with
            {
                Overlay = settings with
                {
                    ScreenIdentifier = placement.ScreenIdentifier,
                    OriginX = placement.X,
                    OriginY = placement.Y,
                },
            };
        }
    }

    private void Behavior_StateChanged(object? sender, EventArgs e)
    {
        _speech.BehaviorSequenceDidChange(_behavior.SequenceId);
        StateChanged?.Invoke(this, EventArgs.Empty);
    }

    private void Runtime_StateChanged(object? sender, EventArgs e) =>
        StateChanged?.Invoke(this, EventArgs.Empty);

    private void Movement_MovementMotionChanged(
        object? sender,
        MovementMotionChangedEventArgs e) =>
        _behavior.SetMovementMotion(e.MotionId);

    private void Movement_PettingRequested(
        object? sender,
        PettingRequestedEventArgs e) =>
        _behavior.PlayInteraction(e.MotionId);

    private void Movement_DirectDragCompleted(
        object? sender,
        DirectDragCompletedEventArgs e) =>
        PersistDraggedPosition(e.X, e.Y);

    private void Overlay_UserDragStateChanged(
        object? sender,
        PetOverlayDragEventArgs e)
    {
        if (e.IsDragging)
        {
            _movement.SetUserDragging(true);
            return;
        }

        try
        {
            PersistDraggedPosition(e.X, e.Y);
        }
        finally
        {
            _movement.SetUserDragging(false);
        }
    }

    private void PersistDraggedPosition(int x, int y)
    {
        PetScreenPlacement placement = _monitorPlacement.ClampPlacement(
            x,
            y,
            Math.Max(1, (int)Math.Round(Overlay.Width)),
            Math.Max(1, (int)Math.Round(Overlay.Height)));
        Overlay.MoveTo(placement.X, placement.Y);
        OverlaySettings overlay = Instance.Overlay with
        {
            ScreenIdentifier = placement.ScreenIdentifier,
            OriginX = placement.X,
            OriginY = placement.Y,
        };
        Instance = Instance with { Overlay = overlay };
        OverlayChanged?.Invoke(
            this,
            new PetOverlayChangedEventArgs(Instance.InstanceId, overlay));
    }

    private void Overlay_DisplayEnvironmentChanged(object? sender, EventArgs e)
    {
        _movement.InvalidateEnvironment();
        if (Profile.Movement.Mode != PetMovementMode.Fixed)
        {
            return;
        }
        PetScreenPlacement placement = _monitorPlacement.ClampPlacement(
            Overlay.OriginX,
            Overlay.OriginY,
            Math.Max(1, (int)Math.Round(Overlay.Width)),
            Math.Max(1, (int)Math.Round(Overlay.Height)));
        Overlay.MoveTo(placement.X, placement.Y);
        OverlaySettings overlay = Instance.Overlay with
        {
            ScreenIdentifier = placement.ScreenIdentifier,
            OriginX = placement.X,
            OriginY = placement.Y,
        };
        if (overlay != Instance.Overlay)
        {
            Instance = Instance with { Overlay = overlay };
            OverlayChanged?.Invoke(
                this,
                new PetOverlayChangedEventArgs(Instance.InstanceId, overlay));
        }
    }

    private static PetSpeechRuntime CreateSpeechRuntime(PetOverlayWindow overlay)
    {
        Microsoft.UI.Dispatching.DispatcherQueue dispatcher =
            Microsoft.UI.Dispatching.DispatcherQueue.GetForCurrentThread();
        return new PetSpeechRuntime(
            new DispatcherQueuePetSpeechScheduler(dispatcher),
            new DispatcherQueuePetSpeechScheduler(dispatcher),
            presentation =>
            {
                if (presentation is null)
                {
                    overlay.HideSpeechBubble();
                }
                else
                {
                    overlay.ShowSpeechBubble(presentation);
                }
            });
    }

    private void ThrowIfDisposed() => ObjectDisposedException.ThrowIf(_disposed, this);
}
