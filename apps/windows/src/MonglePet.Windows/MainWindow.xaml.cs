using System.Runtime.InteropServices;
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
    private const uint ImageIcon = 1;
    private const uint LoadFromFile = 0x0010;
    private const uint SetIconMessage = 0x0080;
    private const nuint IconSmall = 0;
    private const nuint IconBig = 1;
    private const nuint IconSmall2 = 2;
    private readonly string _iconPath;
    private nint _largeIcon;
    private nint _smallIcon;

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
        RootFrame.Navigate(typeof(MainPage));
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

    internal void ShowAndActivate()
    {
        AppWindow.Show();
        Activate();
        nint windowHandle = WinRT.Interop.WindowNative.GetWindowHandle(this);
        _ = ShowWindow(windowHandle, 9); // SW_RESTORE
        _ = BringWindowToTop(windowHandle);
        _ = SetForegroundWindow(windowHandle);
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
        if (RootFrame.Content is MainPage page)
        {
            page.PrepareForShutdown();
        }

        ReleaseIcon(ref _largeIcon);
        ReleaseIcon(ref _smallIcon);
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
