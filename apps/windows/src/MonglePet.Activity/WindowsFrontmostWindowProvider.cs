using System.Diagnostics;
using System.Runtime.InteropServices;
using MonglePet.Core.Movement;

namespace MonglePet.Activity;

public sealed class WindowsFrontmostWindowProvider : IWindowsFrontmostWindowProvider
{
    public static readonly TimeSpan DefaultMinimumRefreshInterval = TimeSpan.FromSeconds(1);

    private readonly TimeSpan _minimumRefreshInterval;
    private readonly Func<WindowsForegroundWindow?> _foregroundProvider;
    private readonly Func<IReadOnlyList<WindowsWindowSnapshot>> _snapshotsProvider;
    private readonly Func<TimeSpan> _uptimeProvider;
    private readonly uint _currentProcessId;
    private WindowsForegroundWindow? _cachedForeground;
    private MovementRect? _cachedWindow;
    private TimeSpan _cachedAt;
    private bool _hasCachedValue;

    public WindowsFrontmostWindowProvider(
        TimeSpan? minimumRefreshInterval = null,
        Func<WindowsForegroundWindow?>? foregroundProvider = null,
        Func<IReadOnlyList<WindowsWindowSnapshot>>? snapshotsProvider = null,
        Func<TimeSpan>? uptimeProvider = null,
        uint? currentProcessId = null)
    {
        TimeSpan requested = minimumRefreshInterval ?? DefaultMinimumRefreshInterval;
        _minimumRefreshInterval = requested < TimeSpan.FromMilliseconds(100)
            ? TimeSpan.FromMilliseconds(100)
            : requested;
        _foregroundProvider = foregroundProvider ?? NativeWindowReader.ForegroundWindow;
        _snapshotsProvider = snapshotsProvider ?? NativeWindowReader.Snapshots;
        _uptimeProvider = uptimeProvider ?? (() => Stopwatch.GetElapsedTime(0));
        _currentProcessId = currentProcessId ?? checked((uint)Environment.ProcessId);
    }

    public string Status { get; private set; } = "전면 창: 대기";

    public MovementRect? RepresentativeWindow(IReadOnlyList<MovementScreen> screens)
    {
        ArgumentNullException.ThrowIfNull(screens);
        WindowsForegroundWindow? foreground;
        TimeSpan now;
        try
        {
            foreground = _foregroundProvider();
            now = _uptimeProvider();
        }
        catch (Exception exception)
        {
            Status = $"전면 창: 조회 실패 ({exception.Message})";
            return null;
        }

        if (_hasCachedValue &&
            _cachedForeground == foreground &&
            now >= _cachedAt &&
            now - _cachedAt < _minimumRefreshInterval)
        {
            return _cachedWindow;
        }

        MovementRect? window = null;
        try
        {
            if (foreground is null)
            {
                Status = "전면 창: 없음";
            }
            else if (foreground.ProcessId == _currentProcessId)
            {
                Status = "전면 창: MonglePet 제외";
            }
            else
            {
                window = WindowsFrontmostWindowResolver.RepresentativeWindow(
                    foreground.ProcessId,
                    _snapshotsProvider(),
                    screens);
                Status = window is null
                    ? "전면 창: 대표 창 없음 또는 전체 화면"
                    : $"전면 창: {window.Value.Width:0}×{window.Value.Height:0}";
            }
        }
        catch (Exception exception)
        {
            Status = $"전면 창: 조회 실패 ({exception.Message})";
        }

        _cachedForeground = foreground;
        _cachedWindow = window;
        _cachedAt = now;
        _hasCachedValue = true;
        return window;
    }

    public void Invalidate()
    {
        _cachedForeground = null;
        _cachedWindow = null;
        _cachedAt = default;
        _hasCachedValue = false;
        Status = "전면 창: 대기";
    }

    private static class NativeWindowReader
    {
        private const uint GetWindowOwner = 4;
        private const int ExtendedWindowStyleIndex = -20;
        private const long ToolWindowStyle = 0x00000080L;
        private const int DwmWindowAttributeExtendedFrameBounds = 9;
        private const int DwmWindowAttributeCloaked = 14;

        public static WindowsForegroundWindow? ForegroundWindow()
        {
            nint window = NativeMethods.GetForegroundWindow();
            if (window == 0)
            {
                return null;
            }
            _ = NativeMethods.GetWindowThreadProcessId(window, out uint processId);
            return processId == 0 ? null : new WindowsForegroundWindow(window, processId);
        }

        public static IReadOnlyList<WindowsWindowSnapshot> Snapshots()
        {
            var snapshots = new List<WindowsWindowSnapshot>();
            _ = NativeMethods.EnumWindows((window, parameter) =>
            {
                _ = NativeMethods.GetWindowThreadProcessId(window, out uint processId);
                snapshots.Add(new WindowsWindowSnapshot(
                    processId,
                    NativeMethods.IsWindowVisible(window),
                    NativeMethods.GetWindow(window, GetWindowOwner) != 0,
                    (NativeMethods.GetWindowLongPtr(window, ExtendedWindowStyleIndex)
                        .ToInt64() & ToolWindowStyle) != 0,
                    IsCloaked(window),
                    Bounds(window)));
                return true;
            }, 0);
            return snapshots;
        }

        private static bool IsCloaked(nint window)
        {
            int cloaked = 0;
            int result = NativeMethods.DwmGetWindowAttributeInt(
                window,
                DwmWindowAttributeCloaked,
                out cloaked,
                Marshal.SizeOf<int>());
            return result == 0 && cloaked != 0;
        }

        private static MovementRect Bounds(nint window)
        {
            int result = NativeMethods.DwmGetWindowAttributeRect(
                window,
                DwmWindowAttributeExtendedFrameBounds,
                out NativeRect rectangle,
                Marshal.SizeOf<NativeRect>());
            if (result != 0 && !NativeMethods.GetWindowRect(window, out rectangle))
            {
                return default;
            }
            return new MovementRect(
                rectangle.Left,
                rectangle.Top,
                rectangle.Right - rectangle.Left,
                rectangle.Bottom - rectangle.Top);
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct NativeRect
        {
            public int Left;
            public int Top;
            public int Right;
            public int Bottom;
        }

        private static class NativeMethods
        {
            public delegate bool EnumWindowsCallback(nint window, nint parameter);

            [DllImport("user32.dll")]
            [return: MarshalAs(UnmanagedType.Bool)]
            public static extern bool EnumWindows(
                EnumWindowsCallback callback,
                nint parameter);

            [DllImport("user32.dll")]
            public static extern nint GetForegroundWindow();

            [DllImport("user32.dll")]
            public static extern uint GetWindowThreadProcessId(
                nint window,
                out uint processId);

            [DllImport("user32.dll")]
            [return: MarshalAs(UnmanagedType.Bool)]
            public static extern bool IsWindowVisible(nint window);

            [DllImport("user32.dll")]
            public static extern nint GetWindow(nint window, uint command);

            [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW")]
            public static extern nint GetWindowLongPtr(nint window, int index);

            [DllImport("user32.dll")]
            [return: MarshalAs(UnmanagedType.Bool)]
            public static extern bool GetWindowRect(nint window, out NativeRect rectangle);

            [DllImport("dwmapi.dll", EntryPoint = "DwmGetWindowAttribute")]
            public static extern int DwmGetWindowAttributeInt(
                nint window,
                int attribute,
                out int value,
                int size);

            [DllImport("dwmapi.dll", EntryPoint = "DwmGetWindowAttribute")]
            public static extern int DwmGetWindowAttributeRect(
                nint window,
                int attribute,
                out NativeRect value,
                int size);
        }
    }
}
