using System.Runtime.InteropServices;
using System.Text;

namespace MonglePet.Activity;

public sealed class WindowsActivityReader : IWindowsActivityReader
{
    private const uint ProcessQueryLimitedInformation = 0x1000;
    private const int ErrorInsufficientBuffer = 122;
    private const int AppModelErrorNoPackage = 15700;

    public TimeSpan ReadIdleDuration()
    {
        var input = new LastInputInfo
        {
            Size = (uint)Marshal.SizeOf<LastInputInfo>(),
        };
        if (!NativeMethods.GetLastInputInfo(ref input))
        {
            return TimeSpan.Zero;
        }

        uint now = unchecked((uint)Environment.TickCount64);
        uint elapsedMilliseconds = unchecked(now - input.TickCount);
        return TimeSpan.FromMilliseconds(elapsedMilliseconds);
    }

    public string? ReadFrontmostApplicationId()
    {
        nint window = NativeMethods.GetForegroundWindow();
        if (window == 0)
        {
            return null;
        }

        _ = NativeMethods.GetWindowThreadProcessId(window, out uint processId);
        if (processId == 0)
        {
            return null;
        }

        nint process = NativeMethods.OpenProcess(
            ProcessQueryLimitedInformation,
            inheritHandle: false,
            processId);
        if (process == 0)
        {
            return null;
        }

        try
        {
            return ReadPackageFamilyName(process) ?? ReadExecutableName(process);
        }
        finally
        {
            _ = NativeMethods.CloseHandle(process);
        }
    }

    private static string? ReadPackageFamilyName(nint process)
    {
        uint length = 0;
        int result = NativeMethods.GetPackageFamilyName(process, ref length, null);
        if (result == AppModelErrorNoPackage ||
            (result != ErrorInsufficientBuffer && result != 0) ||
            length == 0)
        {
            return null;
        }

        var familyName = new StringBuilder(checked((int)length));
        result = NativeMethods.GetPackageFamilyName(process, ref length, familyName);
        return result == 0
            ? WindowsApplicationIdentifier.FromPackageFamilyName(familyName.ToString())
            : null;
    }

    private static string? ReadExecutableName(nint process)
    {
        var path = new StringBuilder(1024);
        int length = path.Capacity;
        return NativeMethods.QueryFullProcessImageName(process, 0, path, ref length)
            ? WindowsApplicationIdentifier.FromExecutablePath(path.ToString(0, length))
            : null;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct LastInputInfo
    {
        public uint Size;
        public uint TickCount;
    }

    private static class NativeMethods
    {
        [DllImport("user32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool GetLastInputInfo(ref LastInputInfo input);

        [DllImport("user32.dll")]
        public static extern nint GetForegroundWindow();

        [DllImport("user32.dll")]
        public static extern uint GetWindowThreadProcessId(nint window, out uint processId);

        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern nint OpenProcess(
            uint desiredAccess,
            [MarshalAs(UnmanagedType.Bool)] bool inheritHandle,
            uint processId);

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
        public static extern int GetPackageFamilyName(
            nint process,
            ref uint packageFamilyNameLength,
            StringBuilder? packageFamilyName);

        [DllImport(
            "kernel32.dll",
            EntryPoint = "QueryFullProcessImageNameW",
            CharSet = CharSet.Unicode,
            SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool QueryFullProcessImageName(
            nint process,
            int flags,
            StringBuilder executableName,
            ref int size);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool CloseHandle(nint handle);
    }
}
