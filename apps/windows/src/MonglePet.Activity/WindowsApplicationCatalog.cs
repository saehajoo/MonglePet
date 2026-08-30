using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;

namespace MonglePet.Activity;

public sealed class WindowsApplicationCatalog : IWindowsApplicationCatalog
{
    private const uint ProcessQueryLimitedInformation = 0x1000;
    private const uint GetWindowOwner = 4;
    private const int ExtendedWindowStyleIndex = -20;
    private const long ToolWindowStyle = 0x00000080L;
    private const int DwmWindowAttributeCloaked = 14;
    private const int ErrorInsufficientBuffer = 122;
    private const int AppModelErrorNoPackage = 15700;
    private readonly HashSet<string> _excludedIdentifiers;
    private readonly uint _currentProcessId;

    public WindowsApplicationCatalog(IEnumerable<string>? excludedIdentifiers = null)
    {
        _currentProcessId = checked((uint)Environment.ProcessId);
        _excludedIdentifiers = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (string identifier in excludedIdentifiers ?? [])
        {
            AddExcluded(identifier);
        }

        AddExcluded(WindowsApplicationIdentifier.FromExecutablePath(Environment.ProcessPath));
        if (TryReadProcess(_currentProcessId) is { } current)
        {
            AddExcluded(current.Identifier);
        }
    }

    public IReadOnlyList<WindowsApplicationChoice> GetRunningApplications()
    {
        var processIds = new HashSet<uint>();
        _ = NativeMethods.EnumWindows((window, parameter) =>
        {
            if (!IsUserFacingWindow(window))
            {
                return true;
            }

            _ = NativeMethods.GetWindowThreadProcessId(window, out uint processId);
            if (processId != 0 && processId != _currentProcessId)
            {
                processIds.Add(processId);
            }
            return true;
        }, 0);

        var candidates = new List<WindowsApplicationCandidate>(processIds.Count);
        foreach (uint processId in processIds)
        {
            if (TryReadProcess(processId) is not { } process)
            {
                continue;
            }

            candidates.Add(new WindowsApplicationCandidate(
                process.Identifier,
                DisplayName(process.ExecutablePath, process.Identifier),
                process.ExecutablePath,
                IsUserFacing: true));
        }

        return WindowsApplicationCatalogNormalizer.Choices(
            candidates,
            _excludedIdentifiers);
    }

    public WindowsApplicationChoice InspectExecutable(string path)
    {
        if (string.IsNullOrWhiteSpace(path) ||
            !string.Equals(Path.GetExtension(path), ".exe", StringComparison.OrdinalIgnoreCase))
        {
            throw new WindowsApplicationCatalogException(
                WindowsApplicationCatalogError.NotExecutable,
                "Windows 실행 파일(.exe)을 선택해 주세요.");
        }

        string fullPath;
        try
        {
            fullPath = Path.GetFullPath(path.Trim());
        }
        catch (Exception exception) when (exception is ArgumentException or NotSupportedException)
        {
            throw new WindowsApplicationCatalogException(
                WindowsApplicationCatalogError.FileUnavailable,
                "선택한 실행 파일 경로를 확인할 수 없습니다.",
                exception);
        }

        if (!File.Exists(fullPath))
        {
            throw new WindowsApplicationCatalogException(
                WindowsApplicationCatalogError.FileUnavailable,
                "선택한 실행 파일을 찾을 수 없습니다.");
        }

        string identifier = WindowsApplicationCatalogNormalizer.NormalizeIdentifier(
            WindowsApplicationIdentifier.FromExecutablePath(fullPath))
            ?? throw new WindowsApplicationCatalogException(
                WindowsApplicationCatalogError.NotExecutable,
                "선택한 실행 파일의 식별자를 만들 수 없습니다.");
        if (_excludedIdentifiers.Contains(identifier))
        {
            throw new WindowsApplicationCatalogException(
                WindowsApplicationCatalogError.MonglePetCannotBeSelected,
                "MonglePet 자체는 앱 사용 규칙 대상으로 선택할 수 없습니다.");
        }

        return new WindowsApplicationChoice(
            identifier,
            DisplayName(fullPath, identifier),
            fullPath);
    }

    private void AddExcluded(string? value)
    {
        if (WindowsApplicationCatalogNormalizer.NormalizeIdentifier(value) is { } normalized)
        {
            _excludedIdentifiers.Add(normalized);
        }
    }

    private static bool IsUserFacingWindow(nint window)
    {
        if (!NativeMethods.IsWindowVisible(window) ||
            NativeMethods.GetWindow(window, GetWindowOwner) != 0 ||
            (NativeMethods.GetWindowLongPtr(window, ExtendedWindowStyleIndex).ToInt64() &
             ToolWindowStyle) != 0)
        {
            return false;
        }

        int cloaked = 0;
        int result = NativeMethods.DwmGetWindowAttribute(
            window,
            DwmWindowAttributeCloaked,
            out cloaked,
            Marshal.SizeOf<int>());
        return result != 0 || cloaked == 0;
    }

    private static ProcessApplication? TryReadProcess(uint processId)
    {
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
            string? executablePath = ReadExecutablePath(process);
            string? identifier = ReadPackageFamilyName(process) ??
                WindowsApplicationIdentifier.FromExecutablePath(executablePath);
            return identifier is null
                ? null
                : new ProcessApplication(identifier, executablePath);
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

    private static string? ReadExecutablePath(nint process)
    {
        var path = new StringBuilder(32768);
        int length = path.Capacity;
        return NativeMethods.QueryFullProcessImageName(process, 0, path, ref length)
            ? path.ToString(0, length)
            : null;
    }

    private static string DisplayName(string? executablePath, string identifier)
    {
        if (executablePath is not null)
        {
            try
            {
                FileVersionInfo version = FileVersionInfo.GetVersionInfo(executablePath);
                foreach (string? candidate in new[] { version.FileDescription, version.ProductName })
                {
                    if (!string.IsNullOrWhiteSpace(candidate))
                    {
                        return candidate.Trim();
                    }
                }

                string fileName = Path.GetFileNameWithoutExtension(executablePath);
                if (!string.IsNullOrWhiteSpace(fileName))
                {
                    return fileName;
                }
            }
            catch (Exception exception) when (
                exception is ArgumentException or IOException or UnauthorizedAccessException)
            {
            }
        }

        return identifier[(identifier.IndexOf(':') + 1)..];
    }

    private sealed record ProcessApplication(string Identifier, string? ExecutablePath);

    private static class NativeMethods
    {
        public delegate bool EnumWindowsCallback(nint window, nint parameter);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool EnumWindows(EnumWindowsCallback callback, nint parameter);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool IsWindowVisible(nint window);

        [DllImport("user32.dll")]
        public static extern nint GetWindow(nint window, uint command);

        [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW")]
        public static extern nint GetWindowLongPtr(nint window, int index);

        [DllImport("user32.dll")]
        public static extern uint GetWindowThreadProcessId(nint window, out uint processId);

        [DllImport("dwmapi.dll")]
        public static extern int DwmGetWindowAttribute(
            nint window,
            int attribute,
            out int value,
            int size);

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
