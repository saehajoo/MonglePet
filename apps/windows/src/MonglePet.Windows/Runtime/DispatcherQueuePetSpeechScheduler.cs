using Microsoft.UI.Dispatching;
using MonglePet.Settings;

namespace MonglePet.Windows.Runtime;

internal sealed class DispatcherQueuePetSpeechScheduler : IPetSpeechScheduler, IDisposable
{
    private readonly object _gate = new();
    private readonly DispatcherQueue _dispatcherQueue;
    private System.Threading.Timer? _timer;
    private Action? _action;
    private long _generation;
    private bool _disposed;

    public DispatcherQueuePetSpeechScheduler(DispatcherQueue dispatcherQueue)
    {
        ArgumentNullException.ThrowIfNull(dispatcherQueue);
        _dispatcherQueue = dispatcherQueue;
    }

    public void Schedule(TimeSpan delay, Action action)
    {
        ArgumentNullException.ThrowIfNull(action);
        long generation;
        lock (_gate)
        {
            ObjectDisposedException.ThrowIf(_disposed, this);
            generation = ++_generation;
            _action = action;
            _timer?.Dispose();
            _timer = new System.Threading.Timer(
                TimerDidFire,
                generation,
                delay > TimeSpan.Zero ? delay : TimeSpan.FromMilliseconds(1),
                System.Threading.Timeout.InfiniteTimeSpan);
        }
    }

    public void Cancel()
    {
        lock (_gate)
        {
            if (_disposed)
            {
                return;
            }
            ++_generation;
            _timer?.Dispose();
            _timer = null;
            _action = null;
        }
    }

    public void Dispose()
    {
        lock (_gate)
        {
            if (_disposed)
            {
                return;
            }
            _disposed = true;
            ++_generation;
            _timer?.Dispose();
            _timer = null;
            _action = null;
        }
        GC.SuppressFinalize(this);
    }

    private void TimerDidFire(object? state)
    {
        if (state is not long generation)
        {
            return;
        }

        Action? action;
        lock (_gate)
        {
            if (_disposed || generation != _generation)
            {
                return;
            }
            action = _action;
            _action = null;
            _timer?.Dispose();
            _timer = null;
        }

        if (action is not null)
        {
            _dispatcherQueue.TryEnqueue(() =>
            {
                lock (_gate)
                {
                    if (_disposed || generation != _generation)
                    {
                        return;
                    }
                }
                action();
            });
        }
    }
}
