using System.ComponentModel;
using System.Runtime.InteropServices;

namespace MonglePet.Shell;

public sealed class WindowsMonitorPlacementService
{
    private const uint MonitorDefaultToNearest = 2;

    public PetScreenPlacement PlacementForCursor(int petWidth, int petHeight)
    {
        ScreenPoint position = CursorPosition();
        var cursor = new NativePoint(position.X, position.Y);

        nint monitor = MonitorFromPoint(cursor, MonitorDefaultToNearest);
        return PetScreenPlacementCalculator.BottomRight(
            WorkArea(monitor),
            petWidth,
            petHeight);
    }

    public ScreenPoint CursorPosition()
    {
        if (!GetCursorPosition(out NativePoint cursor))
        {
            throw Win32("포인터 위치를 확인하지 못했습니다.");
        }
        return new ScreenPoint(cursor.X, cursor.Y);
    }

    public IReadOnlyList<MonitorWorkArea> AvailableWorkAreas()
    {
        var result = new List<MonitorWorkArea>();
        MonitorEnumeration callback = (monitor, _, _, _) =>
        {
            result.Add(WorkArea(monitor));
            return true;
        };
        if (!EnumDisplayMonitors(0, 0, callback, 0))
        {
            throw Win32("사용 가능한 화면을 열거하지 못했습니다.");
        }
        GC.KeepAlive(callback);
        return result;
    }

    public PetScreenPlacement RestorePlacement(
        string screenIdentifier,
        double originX,
        double originY,
        int petWidth,
        int petHeight)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(screenIdentifier);
        IReadOnlyList<MonitorWorkArea> workAreas = AvailableWorkAreas();
        MonitorWorkArea? target = workAreas.FirstOrDefault(value => string.Equals(
            value.Identifier,
            screenIdentifier,
            StringComparison.OrdinalIgnoreCase));
        target ??= WorkArea(MonitorFromPoint(
            new NativePoint((int)Math.Round(originX), (int)Math.Round(originY)),
            MonitorDefaultToNearest));
        return PetScreenPlacementCalculator.Clamp(
            target,
            (int)Math.Round(originX),
            (int)Math.Round(originY),
            petWidth,
            petHeight);
    }

    public PetScreenPlacement ClampPlacement(
        int originX,
        int originY,
        int petWidth,
        int petHeight)
    {
        nint monitor = MonitorFromPoint(
            new NativePoint(originX, originY),
            MonitorDefaultToNearest);
        return PetScreenPlacementCalculator.Clamp(
            WorkArea(monitor),
            originX,
            originY,
            petWidth,
            petHeight);
    }

    private static MonitorWorkArea WorkArea(nint monitor)
    {
        if (monitor == 0)
        {
            throw new InvalidOperationException("사용 가능한 화면을 찾지 못했습니다.");
        }

        var info = new MonitorInfo
        {
            Size = (uint)Marshal.SizeOf<MonitorInfo>(),
            DeviceName = string.Empty,
        };
        if (!GetMonitorInfo(monitor, ref info))
        {
            throw Win32("화면 작업 영역을 확인하지 못했습니다.");
        }

        return new MonitorWorkArea(
            info.DeviceName,
            info.WorkArea.Left,
            info.WorkArea.Top,
            info.WorkArea.Right,
            info.WorkArea.Bottom);
    }

    private static Win32Exception Win32(string message) =>
        new(Marshal.GetLastWin32Error(), message);

    private delegate bool MonitorEnumeration(
        nint monitor,
        nint deviceContext,
        nint monitorRectangle,
        nint data);

    [StructLayout(LayoutKind.Sequential)]
    private readonly record struct NativePoint(int X, int Y);

    [StructLayout(LayoutKind.Sequential)]
    private struct NativeRectangle
    {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct MonitorInfo
    {
        public uint Size;
        public NativeRectangle MonitorArea;
        public NativeRectangle WorkArea;
        public uint Flags;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string DeviceName;
    }

    [DllImport("user32.dll", EntryPoint = "GetCursorPos", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetCursorPosition(out NativePoint point);

    [DllImport("user32.dll")]
    private static extern nint MonitorFromPoint(NativePoint point, uint flags);

    [DllImport("user32.dll", EntryPoint = "GetMonitorInfoW", CharSet = CharSet.Unicode, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetMonitorInfo(nint monitor, ref MonitorInfo info);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool EnumDisplayMonitors(
        nint deviceContext,
        nint clipRectangle,
        MonitorEnumeration callback,
        nint data);
}
