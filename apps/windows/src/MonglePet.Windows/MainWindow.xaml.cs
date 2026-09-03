using System.Runtime.InteropServices;
using System.Collections.Concurrent;
using Microsoft.UI.Xaml;
using Microsoft.UI.Windowing;

// To learn more about WinUI, the WinUI project structure,
// and more about our project templates, see: http://aka.ms/winui-project-info.

namespace MonglePet.Windows;

/// <summary>
/// The application window. This hosts a Frame that displays pages. Add your
/// UI and logic to MainPage.xaml / MainPage.xaml.cs instead of here so you
/// can use Page features such as navigation events and the Loaded lifecycle.
/// </summary>
public sealed partial class MainWindow : Window
{
    private const int MinimumWidth = 800;
    private const int MinimumHeight = 600;
    private const uint WmGetMinMaxInfo = 0x0024;
    private const nuint MinimumSizeSubclassId = 0x4D504D53;
    private const uint ImageIcon = 1;
    private const uint LoadFromFile = 0x0010;
    private const uint SetIconMessage = 0x0080;
    private const nuint IconSmall = 0;
    private const nuint IconBig = 1;
    private const nuint IconSmall2 = 2;
    private static readonly ConcurrentDictionary<nint, MainWindow> SubclassedWindows = [];
    private static readonly SubclassProcedure MinimumSizeProcedure = MainWindowSubclassProcedure;
    private readonly string _iconPath;
    private nint _largeIcon;
    private nint _smallIcon;
    private bool _contentReady;
    private nint _subclassedWindowHandle;
    private event Action? ContentReady;

    public MainWindow()
    {
        InitializeComponent();

        ExtendsContentIntoTitleBar = true;
        SetTitleBar(AppTitleBar);
        AppWindow.Resize(new global::Windows.Graphics.SizeInt32(1040, 760));

        _iconPath = Path.Combine(
            AppContext.BaseDirectory,
            "Assets",
            "AppIcon.ico");
        ApplyWindowIcons();
        AppWindow.Closing += AppWindow_Closing;

        // Navigate the root frame to the main page on startup.
        RootFrame.Loaded += RootFrame_Loaded;
        RootFrame.Navigate(typeof(MainPage));
    }

    internal void RunWhenContentReady(Action action)
    {
        ArgumentNullException.ThrowIfNull(action);
        if (_contentReady || RootFrame.IsLoaded)
        {
            EnqueueAfterContentLoaded(action);
            return;
        }

        ContentReady += action;
    }

    internal void ApplyWindowIcons()
    {
        AppWindow.SetIcon(_iconPath);
        AppWindow.SetTaskbarIcon(_iconPath);

        nint windowHandle = WinRT.Interop.WindowNative.GetWindowHandle(this);
        _largeIcon = LoadIcon(_largeIcon, 32, 32);
        _smallIcon = LoadIcon(_smallIcon, 16, 16);
        if (_largeIcon != nint.Zero)
        {
            _ = SendMessage(windowHandle, SetIconMessage, IconBig, _largeIcon);
        }
        if (_smallIcon != nint.Zero)
        {
            _ = SendMessage(windowHandle, SetIconMessage, IconSmall, _smallIcon);
            _ = SendMessage(windowHandle, SetIconMessage, IconSmall2, _smallIcon);
        }
    }

    internal void ApplyMinimumSize()
    {
        if (_subclassedWindowHandle != nint.Zero)
        {
            return;
        }

        nint windowHandle = WinRT.Interop.WindowNative.GetWindowHandle(this);
        if (!SetWindowSubclass(
                windowHandle,
                MinimumSizeProcedure,
                MinimumSizeSubclassId,
                nuint.Zero))
        {
            throw new InvalidOperationException("설정 창의 최소 크기를 적용하지 못했습니다.");
        }

        _subclassedWindowHandle = windowHandle;
        SubclassedWindows[windowHandle] = this;

        (int minimumWidth, int minimumHeight) = MinimumTrackSizeForWindow(windowHandle);
        global::Windows.Graphics.SizeInt32 currentSize = AppWindow.Size;
        if (currentSize.Width < minimumWidth || currentSize.Height < minimumHeight)
        {
            AppWindow.Resize(new global::Windows.Graphics.SizeInt32(
                Math.Max(currentSize.Width, minimumWidth),
                Math.Max(currentSize.Height, minimumHeight)));
        }
    }

    internal void ShowAndActivate()
    {
        AppWindow.Show();
        Activate();
        nint windowHandle = WinRT.Interop.WindowNative.GetWindowHandle(this);
        _ = ShowWindow(windowHandle, 9); // SW_RESTORE
        _ = BringWindowToTop(windowHandle);
        _ = SetForegroundWindow(windowHandle);
    }

    internal void OpenRemotePetImport(string? canonicalUrl, string? errorMessage)
    {
        ShowAndActivate();
        if (RootFrame.Content is MainPage page)
        {
            page.OpenRemotePetImport(canonicalUrl, errorMessage);
        }
    }

    internal void HideForStartup()
    {
        // AppWindow.Hide can fail with E_NOINTERFACE during the first WinUI
        // activation of an unpackaged process. Hide the initialized desktop
        // HWND directly while keeping the Window alive for tray activation.
        nint windowHandle = WinRT.Interop.WindowNative.GetWindowHandle(this);
        _ = ShowWindow(windowHandle, 0); // SW_HIDE
    }

    private nint LoadIcon(nint current, int width, int height) =>
        current != nint.Zero
            ? current
            : LoadImage(nint.Zero, _iconPath, ImageIcon, width, height, LoadFromFile);

    private void AppWindow_Closing(AppWindow sender, AppWindowClosingEventArgs args)
    {
        if (Application.Current is App app && app.ShouldHideSettingsWindowOnClose)
        {
            args.Cancel = true;
            sender.Hide();
        }
    }

    internal void PrepareForShutdown()
    {
        RootFrame.Loaded -= RootFrame_Loaded;
        ContentReady = null;
        if (_subclassedWindowHandle != nint.Zero)
        {
            _ = RemoveWindowSubclass(
                _subclassedWindowHandle,
                MinimumSizeProcedure,
                MinimumSizeSubclassId);
            SubclassedWindows.TryRemove(_subclassedWindowHandle, out _);
            _subclassedWindowHandle = nint.Zero;
        }
        if (RootFrame.Content is MainPage page)
        {
            page.PrepareForShutdown();
        }

        ReleaseIcon(ref _largeIcon);
        ReleaseIcon(ref _smallIcon);
    }

    private void RootFrame_Loaded(object sender, RoutedEventArgs e)
    {
        if (_contentReady)
        {
            return;
        }

        _contentReady = true;
        RootFrame.Loaded -= RootFrame_Loaded;
        Action? callbacks = ContentReady;
        ContentReady = null;
        if (callbacks is not null)
        {
            EnqueueAfterContentLoaded(callbacks);
        }
    }

    private void EnqueueAfterContentLoaded(Action action)
    {
        // Running on the next dispatcher turn guarantees that the Window,
        // XAML root and compositor have all completed their first activation.
        // This matters for the process launched directly by the installer,
        // where OnLaunched otherwise creates every pet timer too early.
        if (!RootFrame.DispatcherQueue.TryEnqueue(
                Microsoft.UI.Dispatching.DispatcherQueuePriority.Low,
                () => action()))
        {
            action();
        }
    }

    private static void ReleaseIcon(ref nint icon)
    {
        if (icon == nint.Zero)
        {
            return;
        }

        _ = DestroyIcon(icon);
        icon = nint.Zero;
    }

    private static nint MainWindowSubclassProcedure(
        nint window,
        uint message,
        nuint wParam,
        nint lParam,
        nuint subclassId,
        nuint referenceData)
    {
        if (message == WmGetMinMaxInfo &&
            lParam != nint.Zero &&
            SubclassedWindows.ContainsKey(window))
        {
            ApplyMinimumTrackSize(window, lParam);
        }

        return DefSubclassProc(window, message, wParam, lParam);
    }

    private static void ApplyMinimumTrackSize(nint window, nint minMaxInfoPointer)
    {
        (int minimumWidth, int minimumHeight) = MinimumTrackSizeForWindow(window);

        MinMaxInfo minMaxInfo = Marshal.PtrToStructure<MinMaxInfo>(minMaxInfoPointer);
        minMaxInfo.MinimumTrackSize.X = Math.Max(minMaxInfo.MinimumTrackSize.X, minimumWidth);
        minMaxInfo.MinimumTrackSize.Y = Math.Max(minMaxInfo.MinimumTrackSize.Y, minimumHeight);
        Marshal.StructureToPtr(minMaxInfo, minMaxInfoPointer, false);
    }

    private static (int Width, int Height) MinimumTrackSizeForWindow(nint window)
    {
        uint dpi = GetDpiForWindow(window);
        double scale = dpi == 0 ? 1 : dpi / 96d;
        int minimumWidth = (int)Math.Ceiling(MinimumWidth * scale);
        int minimumHeight = (int)Math.Ceiling(MinimumHeight * scale);

        nint monitor = MonitorFromWindow(window, 2); // MONITOR_DEFAULTTONEAREST
        var monitorInfo = new MonitorInfo
        {
            Size = (uint)Marshal.SizeOf<MonitorInfo>(),
        };
        if (monitor != nint.Zero && GetMonitorInfo(monitor, ref monitorInfo))
        {
            minimumWidth = Math.Min(minimumWidth, monitorInfo.WorkArea.Right - monitorInfo.WorkArea.Left);
            minimumHeight = Math.Min(minimumHeight, monitorInfo.WorkArea.Bottom - monitorInfo.WorkArea.Top);
        }

        return (minimumWidth, minimumHeight);
    }

    private delegate nint SubclassProcedure(
        nint window,
        uint message,
        nuint wParam,
        nint lParam,
        nuint subclassId,
        nuint referenceData);

    [StructLayout(LayoutKind.Sequential)]
    private struct NativePoint
    {
        public int X;
        public int Y;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct NativeRectangle
    {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct MinMaxInfo
    {
        public NativePoint Reserved;
        public NativePoint MaximumSize;
        public NativePoint MaximumPosition;
        public NativePoint MinimumTrackSize;
        public NativePoint MaximumTrackSize;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct MonitorInfo
    {
        public uint Size;
        public NativeRectangle MonitorArea;
        public NativeRectangle WorkArea;
        public uint Flags;
    }

    [LibraryImport("user32.dll", EntryPoint = "LoadImageW", SetLastError = true, StringMarshalling = StringMarshalling.Utf16)]
    private static partial nint LoadImage(
        nint instance,
        string name,
        uint type,
        int width,
        int height,
        uint loadFlags);

    [LibraryImport("user32.dll", EntryPoint = "SendMessageW")]
    private static partial nint SendMessage(
        nint window,
        uint message,
        nuint wParam,
        nint lParam);

    [DllImport("comctl32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetWindowSubclass(
        nint window,
        SubclassProcedure procedure,
        nuint subclassId,
        nuint referenceData);

    [DllImport("comctl32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool RemoveWindowSubclass(
        nint window,
        SubclassProcedure procedure,
        nuint subclassId);

    [DllImport("comctl32.dll")]
    private static extern nint DefSubclassProc(
        nint window,
        uint message,
        nuint wParam,
        nint lParam);

    [DllImport("user32.dll")]
    private static extern uint GetDpiForWindow(nint window);

    [DllImport("user32.dll")]
    private static extern nint MonitorFromWindow(nint window, uint flags);

    [DllImport("user32.dll", EntryPoint = "GetMonitorInfoW", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetMonitorInfo(nint monitor, ref MonitorInfo info);

    [LibraryImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool ShowWindow(nint window, int command);

    [LibraryImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool BringWindowToTop(nint window);

    [LibraryImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool SetForegroundWindow(nint window);

    [LibraryImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool DestroyIcon(nint icon);
}
