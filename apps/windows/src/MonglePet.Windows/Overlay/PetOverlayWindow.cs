using System.Collections.Concurrent;
using System.Numerics;
using System.Runtime.InteropServices;
using Microsoft.UI.Composition;
using Microsoft.UI.Content;
using MonglePet.Packages;
using MonglePet.Settings;
using Windows.Win32;
using Windows.Win32.Foundation;
using Windows.Win32.UI.WindowsAndMessaging;

namespace MonglePet.Windows.Overlay;

/// <summary>
/// Owns the native pet surface. The HWND is deliberately independent from the
/// WinUI settings window so the overlay lifecycle can later move to a tray host.
/// </summary>
public sealed unsafe class PetOverlayWindow : IDisposable
{
    private const string WindowClassName = "MonglePet.PetOverlay.Window";
    private const uint WmNcHitTest = 0x0084;
    private const uint WmMouseActivate = 0x0021;
    private const uint WmMove = 0x0003;
    private const uint WmEnterSizeMove = 0x0231;
    private const uint WmExitSizeMove = 0x0232;
    private const uint WmDisplayChange = 0x007E;
    private const uint WmSettingChange = 0x001A;
    private const uint WmEraseBackground = 0x0014;
    private const uint WmDestroy = 0x0002;
    private const uint WmPowerBroadcast = 0x0218;
    private const uint WmWtsSessionChange = 0x02B1;
    private const uint NotifyForThisSession = 0;

    private static readonly ConcurrentDictionary<nint, PetOverlayWindow> Instances = new();
    private static readonly WNDPROC WindowProcedure = WindowProc;

    private readonly Compositor _compositor;
    private readonly ContainerVisual _root;
    private readonly PetFrameCompositionPlayer? _framePlayer;
    private readonly PetSpeechBubbleWindow? _speechBubbleWindow;
    private readonly string _packageDisplayName;
    private readonly float _contentAspectRatio;
    private DesktopChildSiteBridge? _siteBridge;
    private ContentIsland? _contentIsland;
    private HWND _window;
    private bool _disposed;
    private bool _isVisible;
    private bool _isClickThrough = true;
    private double _width;
    private double _height;
    private int _originX;
    private int _originY;
    private bool _isUserDragging;
    private double _opacity = 1;
    private double _appliedOpacity = 1;
    private bool _pointerOverlapFadeEnabled;
    private double _pointerOverlapOpacity = 0.2;
    private bool _isPointerOverVisibleContent;
    private bool _pixelArtRendering;
    private bool _isProgrammaticMove;
    private bool _sessionNotificationsRegistered;

    public PetOverlayWindow(LoadedPetPackage package, OverlaySettings settings)
    {
        ArgumentNullException.ThrowIfNull(package);
        ArgumentNullException.ThrowIfNull(settings);
        _packageDisplayName = package.Manifest.DisplayName;
        PetPackageFrame firstFrame = package.DefaultMotion.Frames[0];
        _contentAspectRatio = (float)firstFrame.Height / firstFrame.Width;
        (int width, int height) = CalculateWindowSize(settings.Width);
        _window = CreateNativeWindow(width, height);
        UpdateOriginFromWindow();
        Instances[(nint)_window.Value] = this;

        try
        {
            _sessionNotificationsRegistered =
                PInvoke.WTSRegisterSessionNotification(_window, NotifyForThisSession);

            _compositor = Microsoft.UI.Xaml.Media.CompositionTarget.GetCompositorForCurrentThread();
            _root = CreateRootVisual(width, height, _compositor);
            _framePlayer = new PetFrameCompositionPlayer(
                _compositor,
                package,
                new Vector2(width, height),
                Vector3.Zero);
            _framePlayer.StateChanged += FramePlayer_StateChanged;
            _root.Children.InsertAtTop(_framePlayer.Visual);
            AttachContentIsland(_compositor, _root);
            _speechBubbleWindow = new PetSpeechBubbleWindow(this);
            ApplyDisplaySettings(settings);
        }
        catch
        {
            if (_sessionNotificationsRegistered)
            {
                _ = PInvoke.WTSUnRegisterSessionNotification(_window);
                _sessionNotificationsRegistered = false;
            }
            Instances.TryRemove((nint)_window.Value, out _);
            PInvoke.DestroyWindow(_window);
            _window = default;
            throw;
        }
    }

    public bool IsVisible => _isVisible;

    public bool IsClickThrough => _isClickThrough;

    public double Width => _width;

    public double Height => _height;

    public int OriginX => _originX;

    public int OriginY => _originY;

    public bool IsUserDragging => _isUserDragging;

    public double Opacity => _opacity;

    public double AppliedOpacity => _appliedOpacity;

    public bool PointerOverlapFadeEnabled => _pointerOverlapFadeEnabled;

    public bool IsPointerOverVisibleContent => _isPointerOverVisibleContent;

    public bool PixelArtRendering => _pixelArtRendering;

    public string PackageDisplayName => _packageDisplayName;

    public string PlaybackStatus => _framePlayer?.Status ?? "재생기 없음";

    public string AlphaMaskStatus => _framePlayer?.AlphaMaskStatus ?? "알파 마스크 없음";

    public bool IsPlaybackReady => _framePlayer?.IsReady ?? false;

    public string MotionId => _framePlayer?.MotionId ?? string.Empty;

    public int CurrentFrameIndex => _framePlayer?.CurrentFrameIndex ?? 0;

    public int FrameCount => _framePlayer?.FrameCount ?? 0;

    public bool IsSpeechBubbleVisible => _speechBubbleWindow?.IsVisible ?? false;

    public string SpeechBubbleStatus => _speechBubbleWindow?.Status ?? "말풍선 없음";

    public nint Handle => (nint)_window.Value;

    public event EventHandler? StateChanged;

    public event EventHandler<SystemActivityMessageEventArgs>? SystemActivityMessageReceived;

    public event EventHandler<PetOverlayDragEventArgs>? UserDragStateChanged;

    public event EventHandler? PositionChanged;

    public event EventHandler? DisplayEnvironmentChanged;

    public event EventHandler? ZOrderInvalidated;

    public void Show()
    {
        ThrowIfDisposed();
        if (_isVisible)
        {
            return;
        }
        PInvoke.ShowWindow(_window, SHOW_WINDOW_CMD.SW_SHOWNOACTIVATE);
        _siteBridge?.Show();
        PInvoke.SetWindowPos(
            _window,
            new HWND(-1),
            0,
            0,
            0,
            0,
            SET_WINDOW_POS_FLAGS.SWP_NOMOVE |
            SET_WINDOW_POS_FLAGS.SWP_NOSIZE |
            SET_WINDOW_POS_FLAGS.SWP_NOACTIVATE |
            SET_WINDOW_POS_FLAGS.SWP_SHOWWINDOW);
        _isVisible = true;
        StateChanged?.Invoke(this, EventArgs.Empty);
    }

    public void Hide()
    {
        ThrowIfDisposed();
        if (!_isVisible)
        {
            return;
        }
        SetPointerOverVisibleContent(false);
        _speechBubbleWindow?.Hide();
        PInvoke.ShowWindow(_window, SHOW_WINDOW_CMD.SW_HIDE);
        _siteBridge?.Hide();
        _isVisible = false;
        StateChanged?.Invoke(this, EventArgs.Empty);
    }

    public void ApplyDisplaySettings(OverlaySettings settings)
    {
        ArgumentNullException.ThrowIfNull(settings);
        ThrowIfDisposed();
        SetSize(settings.Width);
        SetPixelArtRendering(settings.PixelArtRendering);
        SetClickThrough(settings.ClickThrough);
        SetOpacitySettings(
            settings.Opacity,
            settings.PointerOverlapFadeEnabled,
            settings.PointerOverlapOpacity);
        _speechBubbleWindow?.Reposition();
    }

    public void ShowSpeechBubble(PetSpeechPresentation presentation)
    {
        ArgumentNullException.ThrowIfNull(presentation);
        ThrowIfDisposed();
        _speechBubbleWindow?.Show(presentation);
        if (_speechBubbleWindow?.IsVisible == true)
        {
            ZOrderInvalidated?.Invoke(this, EventArgs.Empty);
        }
        StateChanged?.Invoke(this, EventArgs.Empty);
    }

    public void HideSpeechBubble()
    {
        ThrowIfDisposed();
        _speechBubbleWindow?.Hide();
        StateChanged?.Invoke(this, EventArgs.Empty);
    }

    public bool PlayMotion(
        string motionId,
        bool restart = false,
        TimeSpan? cycleElapsed = null)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(motionId);
        ThrowIfDisposed();
        return _framePlayer?.PlayMotion(motionId, restart, cycleElapsed) ?? false;
    }

    public void PausePlayback()
    {
        ThrowIfDisposed();
        _framePlayer?.Pause();
    }

    public void ResumePlayback()
    {
        ThrowIfDisposed();
        _framePlayer?.Resume();
    }

    public bool ContainsVisibleContent(double pointX, double pointY)
    {
        ThrowIfDisposed();
        return _framePlayer?.ContainsVisibleContent(pointX, pointY) ?? false;
    }

    public bool IsTopmostWindowAt(int screenX, int screenY)
    {
        ThrowIfDisposed();
        nint hitWindow = WindowFromPoint(new NativePoint(screenX, screenY));
        if (hitWindow == nint.Zero)
        {
            return false;
        }
        return GetAncestor(hitWindow, 2) == Handle; // GA_ROOT
    }

    public void SetAlphaMaskObservationEnabled(bool enabled)
    {
        ThrowIfDisposed();
        _framePlayer?.SetAlphaMaskObservationEnabled(enabled);
    }

    public void SetPointerOverVisibleContent(bool isOverVisibleContent)
    {
        ThrowIfDisposed();
        if (isOverVisibleContent == _isPointerOverVisibleContent)
        {
            return;
        }
        _isPointerOverVisibleContent = isOverVisibleContent;
        ApplyPointerOpacity();
        StateChanged?.Invoke(this, EventArgs.Empty);
    }

    public void SetClickThrough(bool enabled)
    {
        ThrowIfDisposed();

        nint style = PInvoke.GetWindowLongPtr(_window, WINDOW_LONG_PTR_INDEX.GWL_EXSTYLE);
        nint transparentStyle = (nint)WINDOW_EX_STYLE.WS_EX_TRANSPARENT;
        nint nextStyle = enabled ? style | transparentStyle : style & ~transparentStyle;

        if (nextStyle != style)
        {
            PInvoke.SetWindowLongPtr(_window, WINDOW_LONG_PTR_INDEX.GWL_EXSTYLE, nextStyle);
            PInvoke.SetWindowPos(
                _window,
                default,
                0,
                0,
                0,
                0,
                SET_WINDOW_POS_FLAGS.SWP_NOMOVE |
                SET_WINDOW_POS_FLAGS.SWP_NOSIZE |
                SET_WINDOW_POS_FLAGS.SWP_NOZORDER |
                SET_WINDOW_POS_FLAGS.SWP_NOACTIVATE |
                SET_WINDOW_POS_FLAGS.SWP_FRAMECHANGED);
        }

        _isClickThrough = enabled;
        // The ContentIsland is a composition surface only. Keeping its child
        // site input-disabled lets the parent overlay HWND own hit testing in
        // both modes: WS_EX_TRANSPARENT passes clicks through, while
        // HTCAPTION moves the pet when interaction is enabled.
        _contentIsland!.IsIslandEnabled = false;
        _siteBridge!.Disable();
        ApplyPointerOpacity();
    }

    public void MoveTo(int x, int y)
    {
        ThrowIfDisposed();
        if (x == _originX && y == _originY)
        {
            return;
        }
        bool moved;
        _isProgrammaticMove = true;
        try
        {
            moved = PInvoke.SetWindowPos(
                _window,
                default,
                x,
                y,
                0,
                0,
                SET_WINDOW_POS_FLAGS.SWP_NOSIZE |
                SET_WINDOW_POS_FLAGS.SWP_NOZORDER |
                SET_WINDOW_POS_FLAGS.SWP_NOACTIVATE);
        }
        finally
        {
            _isProgrammaticMove = false;
        }
        if (moved)
        {
            _originX = x;
            _originY = y;
            PositionChanged?.Invoke(this, EventArgs.Empty);
        }
    }

    public nint PlaceZOrderGroupAfter(nint precedingWindow)
    {
        ThrowIfDisposed();
        nint preceding = _speechBubbleWindow?.PlaceZOrderAfter(precedingWindow)
            ?? precedingWindow;
        PInvoke.SetWindowPos(
            _window,
            new HWND(preceding),
            0,
            0,
            0,
            0,
            SET_WINDOW_POS_FLAGS.SWP_NOMOVE |
            SET_WINDOW_POS_FLAGS.SWP_NOSIZE |
            SET_WINDOW_POS_FLAGS.SWP_NOACTIVATE);
        return Handle;
    }

    private void SetSize(double width)
    {
        (int pixelWidth, int pixelHeight) = CalculateWindowSize(width);
        PInvoke.SetWindowPos(
            _window,
            default,
            0,
            0,
            pixelWidth,
            pixelHeight,
            SET_WINDOW_POS_FLAGS.SWP_NOMOVE |
            SET_WINDOW_POS_FLAGS.SWP_NOZORDER |
            SET_WINDOW_POS_FLAGS.SWP_NOACTIVATE);
        _root.Size = new Vector2(pixelWidth, pixelHeight);
        _root.CenterPoint = new Vector3(pixelWidth / 2f, pixelHeight / 2f, 0);
        _framePlayer?.Resize(new Vector2(pixelWidth, pixelHeight), Vector3.Zero);
        _width = width;
        _height = pixelHeight;
    }

    private void SetOpacitySettings(
        double opacity,
        bool pointerOverlapFadeEnabled,
        double pointerOverlapOpacity)
    {
        _opacity = opacity;
        _pointerOverlapFadeEnabled = pointerOverlapFadeEnabled;
        _pointerOverlapOpacity = pointerOverlapOpacity;
        ApplyPointerOpacity();
    }

    private void ApplyPointerOpacity()
    {
        double target = _isClickThrough &&
            _pointerOverlapFadeEnabled &&
            _isPointerOverVisibleContent
                ? Math.Min(_opacity, _pointerOverlapOpacity)
                : _opacity;
        if (target == _appliedOpacity)
        {
            return;
        }
        _root.Opacity = (float)target;
        _appliedOpacity = target;
    }

    private void SetPixelArtRendering(bool enabled)
    {
        _framePlayer?.SetPixelArtRendering(enabled);
        _pixelArtRendering = enabled;
    }

    public void Dispose()
    {
        if (_disposed)
        {
            return;
        }

        _disposed = true;
        _speechBubbleWindow?.Dispose();
        if (_framePlayer is not null)
        {
            _framePlayer.StateChanged -= FramePlayer_StateChanged;
            _framePlayer.Dispose();
        }

        _contentIsland?.Dispose();
        _contentIsland = null;
        _siteBridge?.Dispose();
        _siteBridge = null;

        if (!_window.IsNull)
        {
            if (_sessionNotificationsRegistered)
            {
                _ = PInvoke.WTSUnRegisterSessionNotification(_window);
                _sessionNotificationsRegistered = false;
            }
            Instances.TryRemove((nint)_window.Value, out _);
            PInvoke.DestroyWindow(_window);
            _window = default;
        }

        _root.Dispose();
        GC.SuppressFinalize(this);
    }

    private HWND CreateNativeWindow(int width, int height)
    {
        HMODULE module = PInvoke.GetModuleHandle((PCWSTR)null);
        HINSTANCE instance = new(module.Value);

        fixed (char* className = WindowClassName)
        fixed (char* title = "MonglePet Pet Overlay")
        {
            WNDCLASSEXW windowClass = new()
            {
                cbSize = (uint)Marshal.SizeOf<WNDCLASSEXW>(),
                lpfnWndProc = WindowProcedure,
                hInstance = instance,
                lpszClassName = className,
            };

            if (PInvoke.RegisterClassEx(windowClass) == 0 && Marshal.GetLastPInvokeError() != 1410)
            {
                throw new InvalidOperationException("펫 오버레이용 Win32 창 클래스를 등록하지 못했습니다.");
            }

            int screenWidth = PInvoke.GetSystemMetrics(SYSTEM_METRICS_INDEX.SM_CXSCREEN);
            int screenHeight = PInvoke.GetSystemMetrics(SYSTEM_METRICS_INDEX.SM_CYSCREEN);
            int x = Math.Max(0, screenWidth - width - 48);
            int y = Math.Max(0, screenHeight - height - 88);

            WINDOW_EX_STYLE extendedStyle =
                WINDOW_EX_STYLE.WS_EX_TOOLWINDOW |
                WINDOW_EX_STYLE.WS_EX_TOPMOST |
                WINDOW_EX_STYLE.WS_EX_NOACTIVATE |
                WINDOW_EX_STYLE.WS_EX_NOREDIRECTIONBITMAP;

            HWND window = PInvoke.CreateWindowEx(
                extendedStyle,
                className,
                title,
                WINDOW_STYLE.WS_POPUP,
                x,
                y,
                width,
                height,
                default,
                default,
                instance,
                null);

            if (window.IsNull)
            {
                throw new InvalidOperationException("펫 오버레이용 Win32 창을 만들지 못했습니다.");
            }

            return window;
        }
    }

    private static ContainerVisual CreateRootVisual(
        int width,
        int height,
        Compositor compositor)
    {
        ContainerVisual root = compositor.CreateContainerVisual();
        root.Size = new Vector2(width, height);
        root.CenterPoint = new Vector3(width / 2f, height / 2f, 0);

        return root;
    }

    private (int Width, int Height) CalculateWindowSize(double width)
    {
        int roundedWidth = Math.Max(1, (int)Math.Round(width));
        int roundedHeight = Math.Max(1, (int)Math.Round(width * _contentAspectRatio));
        return (roundedWidth, roundedHeight);
    }

    private void AttachContentIsland(Compositor compositor, ContainerVisual root)
    {
        Microsoft.UI.WindowId windowId = Microsoft.UI.Win32Interop.GetWindowIdFromWindow((nint)_window.Value);
        _siteBridge = DesktopChildSiteBridge.Create(compositor, windowId);
        _siteBridge.ResizePolicy = ContentSizePolicy.ResizeContentToParentWindow;
        _contentIsland = ContentIsland.Create(root);
        _contentIsland.IsHitTestVisibleWhenTransparent = false;
        _siteBridge.Connect(_contentIsland);
        _siteBridge.Show();
    }

    private void ThrowIfDisposed()
    {
        ObjectDisposedException.ThrowIf(_disposed, this);
    }

    private void UpdateOriginFromWindow()
    {
        if (_window.IsNull || !PInvoke.GetWindowRect(_window, out RECT rectangle))
        {
            return;
        }

        int x = rectangle.left;
        int y = rectangle.top;
        if (x == _originX && y == _originY)
        {
            return;
        }
        _originX = x;
        _originY = y;
        PositionChanged?.Invoke(this, EventArgs.Empty);
    }

    private bool ContainsVisibleContentAtScreenPoint(LPARAM packedPoint)
    {
        long value = packedPoint.Value;
        int screenX = unchecked((short)(value & 0xffff));
        int screenY = unchecked((short)((value >> 16) & 0xffff));
        return ContainsVisibleContent(screenX - _originX, screenY - _originY);
    }

    private void FramePlayer_StateChanged(object? sender, EventArgs e)
    {
        StateChanged?.Invoke(this, EventArgs.Empty);
    }

    private static LRESULT WindowProc(HWND window, uint message, WPARAM wParam, LPARAM lParam)
    {
        if (Instances.TryGetValue((nint)window.Value, out PetOverlayWindow? owner))
        {
            if (message == WmNcHitTest)
            {
                return new LRESULT(
                    owner._isClickThrough ||
                    !owner.ContainsVisibleContentAtScreenPoint(lParam)
                        ? -1 // HTTRANSPARENT
                        : 2); // HTCAPTION
            }

            if (message == WmMouseActivate)
            {
                return new LRESULT(3);
            }

            if (message == WmEraseBackground)
            {
                return new LRESULT(1);
            }

            if (message == WmMove && !owner._isProgrammaticMove)
            {
                owner.UpdateOriginFromWindow();
            }

            if (message == WmEnterSizeMove && !owner._isUserDragging)
            {
                owner._isUserDragging = true;
                owner.UserDragStateChanged?.Invoke(
                    owner,
                    new PetOverlayDragEventArgs(true, owner._originX, owner._originY));
            }

            if (message == WmExitSizeMove && owner._isUserDragging)
            {
                owner.UpdateOriginFromWindow();
                owner._isUserDragging = false;
                owner.UserDragStateChanged?.Invoke(
                    owner,
                    new PetOverlayDragEventArgs(false, owner._originX, owner._originY));
            }

            if (message == WmDestroy)
            {
                owner._isVisible = false;
                Instances.TryRemove((nint)window.Value, out _);
            }

            if (message is WmPowerBroadcast or WmWtsSessionChange)
            {
                owner.SystemActivityMessageReceived?.Invoke(
                    owner,
                    new SystemActivityMessageEventArgs(message, wParam.Value));
            }

            if (message is WmDisplayChange or WmSettingChange)
            {
                owner.DisplayEnvironmentChanged?.Invoke(owner, EventArgs.Empty);
            }
        }

        return PInvoke.DefWindowProc(window, message, wParam, lParam);
    }

    [StructLayout(LayoutKind.Sequential)]
    private readonly struct NativePoint(int x, int y)
    {
        public readonly int X = x;
        public readonly int Y = y;
    }

    [DllImport("user32.dll")]
    private static extern nint WindowFromPoint(NativePoint point);

    [DllImport("user32.dll")]
    private static extern nint GetAncestor(nint window, uint flags);

}

public sealed record SystemActivityMessageEventArgs(uint Message, nuint Parameter);

public sealed record PetOverlayDragEventArgs(bool IsDragging, int X, int Y);
