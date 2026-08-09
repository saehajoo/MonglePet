using System.Collections.Concurrent;
using System.ComponentModel;
using System.Runtime.InteropServices;

namespace MonglePet.Shell;

public sealed class NotificationAreaErrorEventArgs(Exception exception) : EventArgs
{
    public Exception Exception { get; } = exception;
}

public sealed class WindowsNotificationAreaIcon : IDisposable
{
    private const string WindowClassName = "MonglePet.NotificationArea.Window";
    private const uint CallbackMessage = WmApp + 17;
    private const uint WmApp = 0x8000;
    private const uint WmContextMenu = 0x007B;
    private const uint WmCommand = 0x0111;
    private const uint WmLButtonDoubleClick = 0x0203;
    private const uint WmRButtonUp = 0x0205;
    private const uint WmNull = 0x0000;
    private const uint NinSelect = 0x0400;
    private const uint NinKeySelect = 0x0401;
    private const uint NimAdd = 0x00000000;
    private const uint NimModify = 0x00000001;
    private const uint NimDelete = 0x00000002;
    private const uint NimSetFocus = 0x00000003;
    private const uint NimSetVersion = 0x00000004;
    private const uint NifMessage = 0x00000001;
    private const uint NifIcon = 0x00000002;
    private const uint NifTip = 0x00000004;
    private const uint NifGuid = 0x00000020;
    private const uint NifShowTip = 0x00000080;
    private const uint NotifyIconVersion4 = 4;
    private const uint ImageIcon = 1;
    private const uint LoadFromFile = 0x00000010;
    private const uint LoadDefaultSize = 0x00000040;
    private const uint WsPopup = 0x80000000;
    private const uint MfGray = 0x00000001;
    private const uint MfChecked = 0x00000008;
    private const uint MfSeparator = 0x00000800;
    private const uint TpmRightButton = 0x0002;
    private const int ErrorClassAlreadyExists = 1410;
    private const uint FirstCommandId = 2000;

    private static readonly Guid IconGuid = new("8A85532B-8E32-4EAF-A968-51B569941277");
    private static readonly ConcurrentDictionary<nint, WindowsNotificationAreaIcon> Instances = new();
    private static readonly WindowProcedure SharedWindowProcedure = WindowProc;

    private readonly Action<NotificationAreaCommand> _onCommand;
    private readonly uint _taskbarCreatedMessage;
    private nint _window;
    private nint _icon;
    private NotificationAreaState _state;
    private bool _disposed;
    private bool _iconAdded;

    public WindowsNotificationAreaIcon(
        NotificationAreaState state,
        string iconPath,
        Action<NotificationAreaCommand> onCommand)
    {
        ArgumentNullException.ThrowIfNull(state);
        ArgumentException.ThrowIfNullOrWhiteSpace(iconPath);
        ArgumentNullException.ThrowIfNull(onCommand);
        if (!File.Exists(iconPath))
        {
            throw new FileNotFoundException("notification area 아이콘을 찾을 수 없습니다.", iconPath);
        }

        _state = state;
        _onCommand = onCommand;
        _taskbarCreatedMessage = RegisterWindowMessage("TaskbarCreated");
        _window = CreateMessageWindow();
        Instances[_window] = this;

        try
        {
            _icon = LoadImage(
                0,
                iconPath,
                ImageIcon,
                0,
                0,
                LoadFromFile | LoadDefaultSize);
            if (_icon == 0)
            {
                throw Win32("notification area 아이콘 파일을 열지 못했습니다.");
            }

            AddIcon();
        }
        catch
        {
            Dispose();
            throw;
        }
    }

    public event EventHandler<NotificationAreaErrorEventArgs>? ErrorOccurred;

    public void Update(NotificationAreaState state)
    {
        ArgumentNullException.ThrowIfNull(state);
        ThrowIfDisposed();
        _state = state;
        if (!_iconAdded)
        {
            return;
        }

        NotifyIconData data = CreateNotifyIconData(NifTip | NifGuid | NifShowTip);
        if (!ShellNotifyIcon(NimModify, ref data))
        {
            throw Win32("notification area 아이콘 상태를 갱신하지 못했습니다.");
        }
    }

    public void Dispose()
    {
        if (_disposed)
        {
            return;
        }

        _disposed = true;
        if (_iconAdded)
        {
            NotifyIconData data = CreateNotifyIconData(NifGuid);
            _ = ShellNotifyIcon(NimDelete, ref data);
            _iconAdded = false;
        }

        if (_window != 0)
        {
            Instances.TryRemove(_window, out _);
            _ = DestroyWindow(_window);
            _window = 0;
        }

        if (_icon != 0)
        {
            _ = DestroyIcon(_icon);
            _icon = 0;
        }

        GC.SuppressFinalize(this);
    }

    private void AddIcon()
    {
        NotifyIconData data = CreateNotifyIconData(
            NifMessage | NifIcon | NifTip | NifGuid | NifShowTip);
        if (!ShellNotifyIcon(NimAdd, ref data))
        {
            throw Win32("notification area 아이콘을 등록하지 못했습니다.");
        }

        _iconAdded = true;
        data.VersionOrTimeout = NotifyIconVersion4;
        if (!ShellNotifyIcon(NimSetVersion, ref data))
        {
            NotifyIconData remove = CreateNotifyIconData(NifGuid);
            _ = ShellNotifyIcon(NimDelete, ref remove);
            _iconAdded = false;
            throw Win32("notification area 아이콘 동작 버전을 설정하지 못했습니다.");
        }
    }

    private void ReAddIconAfterExplorerRestart()
    {
        _iconAdded = false;
        AddIcon();
    }

    private NotifyIconData CreateNotifyIconData(uint flags) => new()
    {
        Size = (uint)Marshal.SizeOf<NotifyIconData>(),
        Window = _window,
        Flags = flags,
        CallbackMessage = CallbackMessage,
        Icon = _icon,
        Tip = Tooltip,
        Info = string.Empty,
        InfoTitle = string.Empty,
        IconGuid = IconGuid,
    };

    private string Tooltip
    {
        get
        {
            string name = _state.PetDisplayName.Trim();
            string value = name.Length == 0 ? "MonglePet" : $"MonglePet · {name}";
            return value.Length > 127 ? value[..127] : value;
        }
    }

    private nint CreateMessageWindow()
    {
        nint module = GetModuleHandle(null);
        var windowClass = new WindowClass
        {
            Size = (uint)Marshal.SizeOf<WindowClass>(),
            WindowProcedure = Marshal.GetFunctionPointerForDelegate(SharedWindowProcedure),
            Instance = module,
            ClassName = WindowClassName,
        };
        if (RegisterClassEx(ref windowClass) == 0 &&
            Marshal.GetLastWin32Error() != ErrorClassAlreadyExists)
        {
            throw Win32("notification area 메시지 창 클래스를 등록하지 못했습니다.");
        }

        nint window = CreateWindowEx(
            0,
            WindowClassName,
            "MonglePet Notification Area",
            WsPopup,
            0,
            0,
            1,
            1,
            0,
            0,
            module,
            0);
        return window != 0
            ? window
            : throw Win32("notification area 메시지 창을 만들지 못했습니다.");
    }

    private void ShowContextMenu()
    {
        nint menu = CreatePopupMenu();
        if (menu == 0)
        {
            throw Win32("notification area 메뉴를 만들지 못했습니다.");
        }

        try
        {
            IReadOnlyList<NotificationAreaMenuItem> items = NotificationAreaMenuModel.Build(_state);
            foreach (NotificationAreaMenuItem item in items)
            {
                if (item.Kind == NotificationAreaMenuItemKind.Separator)
                {
                    Append(menu, MfSeparator, 0, null);
                    continue;
                }

                uint flags = item.IsEnabled ? 0 : MfGray;
                if (item.IsChecked)
                {
                    flags |= MfChecked;
                }

                uint id = item.Command is NotificationAreaCommand command
                    ? FirstCommandId + (uint)command
                    : 0;
                Append(menu, flags, id, item.Title);
            }

            if (!GetCursorPosition(out NativePoint cursor))
            {
                throw Win32("notification area 메뉴 위치를 확인하지 못했습니다.");
            }

            _ = SetForegroundWindow(_window);
            _ = TrackPopupMenuEx(
                menu,
                TpmRightButton,
                cursor.X,
                cursor.Y,
                _window,
                0);

            _ = PostMessage(_window, WmNull, 0, 0);
            NotifyIconData focus = CreateNotifyIconData(NifGuid);
            _ = ShellNotifyIcon(NimSetFocus, ref focus);
        }
        finally
        {
            _ = DestroyMenu(menu);
        }
    }

    private static void Append(nint menu, uint flags, uint id, string? text)
    {
        if (!AppendMenu(menu, flags, id, text))
        {
            throw Win32("notification area 메뉴 항목을 추가하지 못했습니다.");
        }
    }

    private void HandleCallback(nint lParam)
    {
        uint notification = unchecked((uint)lParam.ToInt64()) & 0xFFFF;
        if (notification is WmContextMenu or WmRButtonUp)
        {
            ShowContextMenu();
        }
        else if (notification is NinSelect or NinKeySelect or WmLButtonDoubleClick)
        {
            _onCommand(NotificationAreaCommand.OpenSettings);
        }
    }

    private void HandleMenuCommand(nuint wParam)
    {
        uint selected = unchecked((uint)wParam) & 0xFFFF;
        if (selected < FirstCommandId ||
            !Enum.IsDefined(typeof(NotificationAreaCommand), (int)(selected - FirstCommandId)))
        {
            return;
        }

        _onCommand((NotificationAreaCommand)(selected - FirstCommandId));
    }

    private void Report(Exception exception) =>
        ErrorOccurred?.Invoke(this, new NotificationAreaErrorEventArgs(exception));

    private void ThrowIfDisposed() => ObjectDisposedException.ThrowIf(_disposed, this);

    private static nint WindowProc(nint window, uint message, nuint wParam, nint lParam)
    {
        if (Instances.TryGetValue(window, out WindowsNotificationAreaIcon? owner))
        {
            try
            {
                if (message == CallbackMessage)
                {
                    owner.HandleCallback(lParam);
                    return 0;
                }

                if (message == owner._taskbarCreatedMessage)
                {
                    owner.ReAddIconAfterExplorerRestart();
                    return 0;
                }

                if (message == WmCommand)
                {
                    owner.HandleMenuCommand(wParam);
                    return 0;
                }
            }
            catch (Exception exception)
            {
                owner.Report(exception);
                return 0;
            }
        }

        return DefWindowProc(window, message, wParam, lParam);
    }

    private static Win32Exception Win32(string message) =>
        new(Marshal.GetLastWin32Error(), message);

    [UnmanagedFunctionPointer(CallingConvention.Winapi)]
    private delegate nint WindowProcedure(nint window, uint message, nuint wParam, nint lParam);

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct WindowClass
    {
        public uint Size;
        public uint Style;
        public nint WindowProcedure;
        public int ClassExtra;
        public int WindowExtra;
        public nint Instance;
        public nint Icon;
        public nint Cursor;
        public nint BackgroundBrush;
        [MarshalAs(UnmanagedType.LPWStr)] public string? MenuName;
        [MarshalAs(UnmanagedType.LPWStr)] public string ClassName;
        public nint SmallIcon;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct NotifyIconData
    {
        public uint Size;
        public nint Window;
        public uint Id;
        public uint Flags;
        public uint CallbackMessage;
        public nint Icon;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string Tip;
        public uint State;
        public uint StateMask;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 256)] public string Info;
        public uint VersionOrTimeout;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 64)] public string InfoTitle;
        public uint InfoFlags;
        public Guid IconGuid;
        public nint BalloonIcon;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct NativePoint
    {
        public int X;
        public int Y;
    }

    [DllImport("kernel32.dll", EntryPoint = "GetModuleHandleW", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern nint GetModuleHandle(string? moduleName);

    [DllImport("user32.dll", EntryPoint = "RegisterClassExW", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern ushort RegisterClassEx(ref WindowClass windowClass);

    [DllImport("user32.dll", EntryPoint = "CreateWindowExW", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern nint CreateWindowEx(
        uint extendedStyle,
        string className,
        string windowName,
        uint style,
        int x,
        int y,
        int width,
        int height,
        nint parent,
        nint menu,
        nint instance,
        nint parameter);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool DestroyWindow(nint window);

    [DllImport("user32.dll", EntryPoint = "DefWindowProcW")]
    private static extern nint DefWindowProc(nint window, uint message, nuint wParam, nint lParam);

    [DllImport("user32.dll", EntryPoint = "RegisterWindowMessageW", CharSet = CharSet.Unicode)]
    private static extern uint RegisterWindowMessage(string value);

    [DllImport("user32.dll", EntryPoint = "LoadImageW", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern nint LoadImage(
        nint instance,
        string name,
        uint type,
        int width,
        int height,
        uint loadFlags);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool DestroyIcon(nint icon);

    [DllImport("shell32.dll", EntryPoint = "Shell_NotifyIconW", CharSet = CharSet.Unicode, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool ShellNotifyIcon(uint message, ref NotifyIconData data);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern nint CreatePopupMenu();

    [DllImport("user32.dll", EntryPoint = "AppendMenuW", CharSet = CharSet.Unicode, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool AppendMenu(nint menu, uint flags, nuint id, string? value);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern uint TrackPopupMenuEx(
        nint menu,
        uint flags,
        int x,
        int y,
        nint window,
        nint parameters);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool DestroyMenu(nint menu);

    [DllImport("user32.dll", EntryPoint = "GetCursorPos", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetCursorPosition(out NativePoint point);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetForegroundWindow(nint window);

    [DllImport("user32.dll", EntryPoint = "PostMessageW", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool PostMessage(nint window, uint message, nuint wParam, nint lParam);
}
