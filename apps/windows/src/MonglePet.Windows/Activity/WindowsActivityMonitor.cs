using System.Diagnostics;
using Microsoft.UI.Dispatching;
using MonglePet.Core.Behavior;
using MonglePet.Windows.Overlay;

namespace MonglePet.Windows.Activity;

internal sealed class WindowsActivityMonitor : IDisposable
{
    private readonly PetOverlayWindow _overlay;
    private readonly global::MonglePet.Activity.ActivitySnapshotFactory _snapshotFactory;
    private readonly DispatcherQueueTimer _pollTimer;
    private readonly long _originTimestamp = Stopwatch.GetTimestamp();
    private global::MonglePet.Activity.WindowsActivitySystemState _systemState =
        global::MonglePet.Activity.WindowsActivitySystemState.Available;
    private PetPresentation _presentation = PetPresentation.TuckedAway;
    private bool _disposed;

    public WindowsActivityMonitor(
        PetOverlayWindow overlay,
        global::MonglePet.Activity.IWindowsActivityReader? reader = null)
    {
        _overlay = overlay ?? throw new ArgumentNullException(nameof(overlay));
        _snapshotFactory = new global::MonglePet.Activity.ActivitySnapshotFactory(
            reader ?? new global::MonglePet.Activity.WindowsActivityReader());
        _pollTimer = DispatcherQueue.GetForCurrentThread().CreateTimer();
        _pollTimer.Interval = TimeSpan.FromSeconds(1);
        _pollTimer.IsRepeating = true;
        _pollTimer.Tick += PollTimer_Tick;
        _overlay.SystemActivityMessageReceived += Overlay_SystemActivityMessageReceived;
    }

    public ActivitySnapshot? LatestSnapshot { get; private set; }

    public event EventHandler<ActivitySnapshotChangedEventArgs>? SnapshotChanged;

    public void SetPresentation(PetPresentation presentation)
    {
        ThrowIfDisposed();
        _presentation = presentation;
        Capture();
        UpdatePolling();
    }

    public void Dispose()
    {
        if (_disposed)
        {
            return;
        }

        _disposed = true;
        _pollTimer.Stop();
        _pollTimer.Tick -= PollTimer_Tick;
        _overlay.SystemActivityMessageReceived -= Overlay_SystemActivityMessageReceived;
        GC.SuppressFinalize(this);
    }

    private void PollTimer_Tick(DispatcherQueueTimer sender, object args) => Capture();

    private void Overlay_SystemActivityMessageReceived(
        object? sender,
        SystemActivityMessageEventArgs e)
    {
        global::MonglePet.Activity.WindowsActivitySystemState next =
            _systemState.ApplyNativeMessage(e.Message, e.Parameter);
        if (next == _systemState)
        {
            return;
        }

        _systemState = next;
        Capture();
        UpdatePolling();
    }

    private void Capture()
    {
        if (_disposed)
        {
            return;
        }

        ActivitySnapshot snapshot = _snapshotFactory.Create(
            Stopwatch.GetElapsedTime(_originTimestamp),
            _systemState);
        LatestSnapshot = snapshot;
        SnapshotChanged?.Invoke(
            this,
            new ActivitySnapshotChangedEventArgs(snapshot));
    }

    private void UpdatePolling()
    {
        bool shouldPoll = _presentation == PetPresentation.Awake &&
            !_systemState.IsScreenLocked &&
            !_systemState.IsSystemSleeping;
        if (shouldPoll)
        {
            if (!_pollTimer.IsRunning)
            {
                _pollTimer.Start();
            }
        }
        else
        {
            _pollTimer.Stop();
        }
    }

    private void ThrowIfDisposed() => ObjectDisposedException.ThrowIf(_disposed, this);
}

internal sealed record ActivitySnapshotChangedEventArgs(ActivitySnapshot Snapshot);
