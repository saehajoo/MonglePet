using System.Diagnostics;
using System.Runtime.InteropServices;
using MonglePet.Shell;

namespace MonglePet.Windows.Runtime;

internal readonly record struct PetDesktopEnvironmentSnapshot(
    ScreenPoint Pointer,
    bool IsPrimaryButtonPressed,
    IReadOnlyList<MonitorWorkArea> WorkAreas);

internal sealed partial class PetDesktopEnvironment(WindowsMonitorPlacementService monitorService)
{
    private static readonly long MinimumPointerRefreshTicks =
        (long)Math.Ceiling(Stopwatch.Frequency / 120d);

    private readonly WindowsMonitorPlacementService _monitorService =
        monitorService ?? throw new ArgumentNullException(nameof(monitorService));
    private ScreenPoint? _pointer;
    private IReadOnlyList<MonitorWorkArea>? _workAreas;
    private long _pointerCapturedAt;

    public PetDesktopEnvironmentSnapshot Capture()
    {
        long now = Stopwatch.GetTimestamp();
        if (_pointer is null || now - _pointerCapturedAt >= MinimumPointerRefreshTicks)
        {
            _pointer = _monitorService.CursorPosition();
            _pointerCapturedAt = now;
        }
        _workAreas ??= _monitorService.AvailableWorkAreas();
        return new PetDesktopEnvironmentSnapshot(
            _pointer.Value,
            GetAsyncKeyState(0x01) < 0, // VK_LBUTTON
            _workAreas);
    }

    public void InvalidateDisplays() => _workAreas = null;

    [LibraryImport("user32.dll")]
    private static partial short GetAsyncKeyState(int virtualKey);
}
