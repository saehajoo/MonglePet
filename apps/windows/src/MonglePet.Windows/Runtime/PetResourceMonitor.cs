using System.Diagnostics;
using Microsoft.UI.Dispatching;
using MonglePet.Core.Behavior;
using MonglePet.Settings;
using MonglePet.Shell;

namespace MonglePet.Windows.Runtime;

internal sealed class PetResourceMonitor : IDisposable
{
    private readonly Func<IReadOnlyList<PetRuntimeSnapshot>> _snapshots;
    private readonly PetResourcePressureEvaluator _evaluator = new();
    private readonly DispatcherQueueTimer _timer;
    private readonly Process _process = Process.GetCurrentProcess();
    private TimeSpan _lastCpu;
    private long _lastTimestamp;
    private bool _disposed;

    public PetResourceMonitor(Func<IReadOnlyList<PetRuntimeSnapshot>> snapshots)
    {
        _snapshots = snapshots ?? throw new ArgumentNullException(nameof(snapshots));
        _timer = DispatcherQueue.GetForCurrentThread().CreateTimer();
        _timer.Interval = TimeSpan.FromSeconds(5);
        _timer.IsRepeating = true;
        _timer.Tick += Timer_Tick;
    }

    public PetResourceWarning? Warning { get; private set; }

    public event EventHandler? WarningChanged;

    public void Start()
    {
        _process.Refresh();
        _lastCpu = _process.TotalProcessorTime;
        _lastTimestamp = Stopwatch.GetTimestamp();
        _timer.Start();
    }

    public void Dispose()
    {
        if (_disposed)
        {
            return;
        }
        _disposed = true;
        _timer.Stop();
        _timer.Tick -= Timer_Tick;
        _process.Dispose();
        GC.SuppressFinalize(this);
    }

    private void Timer_Tick(DispatcherQueueTimer sender, object args)
    {
        _process.Refresh();
        long now = Stopwatch.GetTimestamp();
        TimeSpan cpu = _process.TotalProcessorTime;
        double elapsedSeconds = Math.Max(
            0.001,
            Stopwatch.GetElapsedTime(_lastTimestamp, now).TotalSeconds);
        double cpuPercent = Math.Max(
            0,
            (cpu - _lastCpu).TotalSeconds / elapsedSeconds /
                Math.Max(1, Environment.ProcessorCount) * 100);
        _lastCpu = cpu;
        _lastTimestamp = now;
        IReadOnlyList<PetRuntimeSnapshot> snapshots = _snapshots();
        PetResourceWarning? next = _evaluator.Observe(new PetResourceSample(
            cpuPercent,
            _process.PrivateMemorySize64,
            snapshots.Count(snapshot => snapshot.Presentation == PetPresentation.Awake),
            snapshots.Count(snapshot => snapshot.Presentation == PetPresentation.Awake &&
                snapshot.MovementStatus.Contains("이동 중", StringComparison.Ordinal))));
        if (next != Warning)
        {
            Warning = next;
            WarningChanged?.Invoke(this, EventArgs.Empty);
        }
    }
}
