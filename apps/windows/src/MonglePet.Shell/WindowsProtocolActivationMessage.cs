using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;

namespace MonglePet.Shell;

public static class WindowsProtocolActivationMessage
{
    internal const string WindowClassName = "MonglePet.NotificationArea.Window";
    internal const string UnpackagedWindowName = "MonglePet Unpackaged Notification Area";
    internal const uint CopyDataMessage = 0x004A;
    internal static readonly nint ProtocolDataIdentifier = new(0x4D504554);
    internal const int MaximumPayloadBytes = 8 * 1024;

    private const uint ProcessQueryLimitedInformation = 0x1000;
    private const uint SendMessageAbortIfHung = 0x0002;

    public static bool TrySend(
        Uri protocolUri,
        string expectedExecutablePath,
        TimeSpan timeout)
    {
        ArgumentNullException.ThrowIfNull(protocolUri);
        if (!WindowsUrlProtocolCommand.TryGetProtocolUri(
                protocolUri.AbsoluteUri,
                out _))
        {
            throw new ArgumentException(
                "The protocol URI is invalid.",
                nameof(protocolUri));
        }
        ArgumentException.ThrowIfNullOrWhiteSpace(expectedExecutablePath);
        if (timeout <= TimeSpan.Zero)
        {
            throw new ArgumentOutOfRangeException(nameof(timeout));
        }

        string expectedPath = Path.GetFullPath(expectedExecutablePath);
        string payload = protocolUri.OriginalString;
        int payloadBytes = checked((payload.Length + 1) * sizeof(char));
        if (payloadBytes > MaximumPayloadBytes)
        {
            throw new ArgumentException(
                "The protocol URI is too long.",
                nameof(protocolUri));
        }

        var stopwatch = Stopwatch.StartNew();
        do
        {
            nint window = FindWindow(WindowClassName, UnpackagedWindowName);
            if (window != 0 && IsExpectedProcess(window, expectedPath))
            {
                nint dataPointer = Marshal.StringToHGlobalUni(payload);
                try
                {
                    var data = new CopyData
                    {
                        Identifier = ProtocolDataIdentifier,
                        DataLength = payloadBytes,
                        Data = dataPointer,
                    };
                    uint remainingMilliseconds = (uint)Math.Clamp(
                        (timeout - stopwatch.Elapsed).TotalMilliseconds,
                        1,
                        5000);
                    nint sent = SendMessageTimeout(
                        window,
                        CopyDataMessage,
                        0,
                        ref data,
                        SendMessageAbortIfHung,
                        remainingMilliseconds,
                        out nuint result);
                    return sent != 0 && result == 1;
                }
                finally
                {
                    Marshal.FreeHGlobal(dataPointer);
                }
            }

            Thread.Sleep(50);
        }
        while (stopwatch.Elapsed < timeout);

        return false;
    }

    internal static bool TryRead(nint copyDataPointer, out Uri? protocolUri)
    {
        protocolUri = null;
        if (copyDataPointer == 0)
        {
            return false;
        }

        CopyData data = Marshal.PtrToStructure<CopyData>(copyDataPointer);
        if (data.Identifier != ProtocolDataIdentifier ||
            data.Data == 0 ||
            data.DataLength < sizeof(char) ||
            data.DataLength > MaximumPayloadBytes ||
            data.DataLength % sizeof(char) != 0)
        {
            return false;
        }

        int characterCount = data.DataLength / sizeof(char);
        string? raw = Marshal.PtrToStringUni(data.Data, characterCount);
        if (string.IsNullOrEmpty(raw) || raw[^1] != '\0')
        {
            return false;
        }

        string value = raw[..^1];
        if (value.Contains('\0', StringComparison.Ordinal))
        {
            return false;
        }
        return WindowsUrlProtocolCommand.TryGetProtocolUri(value, out protocolUri);
    }

    private static bool IsExpectedProcess(nint window, string expectedPath)
    {
        _ = GetWindowThreadProcessId(window, out uint processId);
        if (processId == 0)
        {
            return false;
        }

        nint process = OpenProcess(ProcessQueryLimitedInformation, false, processId);
        if (process == 0)
        {
            return false;
        }

        try
        {
            var path = new StringBuilder(32_768);
            int capacity = path.Capacity;
            return QueryFullProcessImageName(process, 0, path, ref capacity) &&
                string.Equals(
                    Path.GetFullPath(path.ToString()),
                    expectedPath,
                    StringComparison.OrdinalIgnoreCase);
        }
        finally
        {
            _ = CloseHandle(process);
        }
    }

    [StructLayout(LayoutKind.Sequential)]
    internal struct CopyData
    {
        public nint Identifier;
        public int DataLength;
        public nint Data;
    }

    [DllImport("user32.dll", EntryPoint = "FindWindowW", CharSet = CharSet.Unicode)]
    private static extern nint FindWindow(string className, string windowName);

    [DllImport("user32.dll")]
    private static extern uint GetWindowThreadProcessId(nint window, out uint processId);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern nint OpenProcess(uint desiredAccess, bool inheritHandle, uint processId);

    [DllImport("kernel32.dll", EntryPoint = "QueryFullProcessImageNameW", CharSet = CharSet.Unicode, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool QueryFullProcessImageName(
        nint process,
        uint flags,
        StringBuilder executablePath,
        ref int size);

    [DllImport("kernel32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool CloseHandle(nint handle);

    [DllImport("user32.dll", EntryPoint = "SendMessageTimeoutW", SetLastError = true)]
    private static extern nint SendMessageTimeout(
        nint window,
        uint message,
        nuint wParam,
        ref CopyData lParam,
        uint flags,
        uint timeoutMilliseconds,
        out nuint result);
}
