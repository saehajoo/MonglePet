using System.Runtime.InteropServices;

namespace MonglePet.Shell;

public static class WindowsPackageIdentity
{
    private const int ErrorInsufficientBuffer = 122;
    private const int AppModelErrorNoPackage = 15700;

    public static bool IsCurrentProcessPackaged()
    {
        uint length = 0;
        int result = GetCurrentPackageFullName(ref length, null);
        return result switch
        {
            0 => true,
            ErrorInsufficientBuffer => true,
            AppModelErrorNoPackage => false,
            _ => false,
        };
    }

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
    private static extern int GetCurrentPackageFullName(
        ref uint packageFullNameLength,
        char[]? packageFullName);
}
