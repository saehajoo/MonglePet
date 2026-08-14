using System.Runtime.InteropServices;
using Microsoft.UI;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Hosting;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Shapes;
using MonglePet.Settings;
using MonglePet.Shell;
using Windows.Foundation;
using Windows.UI;
using Windows.Win32;
using Windows.Win32.Foundation;
using Windows.Win32.UI.WindowsAndMessaging;

namespace MonglePet.Windows.Overlay;

internal sealed unsafe class PetSpeechBubbleWindow : IDisposable
{
    private const string WindowClassName = "MonglePet.PetSpeechBubble.Window";
    private const uint WmNcHitTest = 0x0084;
    private const uint WmMouseActivate = 0x0021;
    private const uint WmEraseBackground = 0x0014;
    private const double MinimumWidth = 72;
    private const double MaximumWidth = 360;
    private const double MaximumHeight = 260;
    private const double TailWidth = 26;
    private const double TailHeight = 13;
    private static readonly WNDPROC WindowProcedure = WindowProc;

    private readonly PetOverlayWindow _parent;
    private readonly WindowsMonitorPlacementService _monitorPlacement = new();
    private readonly DesktopWindowXamlSource _xamlSource;
    private HWND _window;
    private PetSpeechPresentation? _presentation;
    private double _bodyWidthDip;
    private double _bodyHeightDip;
    private double _tailHeightDip;
    private double? _tailAnchorDip;
    private PetSpeechBubbleTailEdge _tailEdge;
    private Microsoft.UI.Xaml.Shapes.Path? _outlinePath;
    private Border? _contentBody;
    private bool _hasRenderedContent;
    private bool _isVisible;
    private bool _disposed;

    public PetSpeechBubbleWindow(PetOverlayWindow parent)
    {
        ArgumentNullException.ThrowIfNull(parent);
        _parent = parent;
        _window = CreateNativeWindow();
        try
        {
            Microsoft.UI.WindowId windowId = Microsoft.UI.Win32Interop.GetWindowIdFromWindow(
                (nint)_window.Value);
            _xamlSource = new DesktopWindowXamlSource();
            _xamlSource.Initialize(windowId);
            _xamlSource.SiteBridge.ResizePolicy = Microsoft.UI.Content.ContentSizePolicy.ResizeContentToParentWindow;
            _parent.PositionChanged += Parent_PositionChanged;
            _parent.DisplayEnvironmentChanged += Parent_DisplayEnvironmentChanged;
        }
        catch
        {
            PInvoke.DestroyWindow(_window);
            _window = default;
            throw;
        }
    }

    public bool IsVisible => _isVisible;

    public string Status => _presentation is null
        ? "말풍선 숨김"
        : $"말풍선 표시 · {_presentation.Text}";

    public nint PlaceZOrderAfter(nint precedingWindow)
    {
        if (_disposed || _window.IsNull || !_isVisible)
        {
            return precedingWindow;
        }
        PInvoke.SetWindowPos(
            _window,
            new HWND(precedingWindow),
            0,
            0,
            0,
            0,
            SET_WINDOW_POS_FLAGS.SWP_NOMOVE |
            SET_WINDOW_POS_FLAGS.SWP_NOSIZE |
            SET_WINDOW_POS_FLAGS.SWP_NOACTIVATE);
        return (nint)_window.Value;
    }

    public void Show(PetSpeechPresentation presentation)
    {
        ArgumentNullException.ThrowIfNull(presentation);
        ThrowIfDisposed();
        bool presentationChanged = presentation != _presentation;
        _presentation = presentation;
        if (!_parent.IsVisible)
        {
            Hide();
            return;
        }
        RenderAndPosition(presentationChanged || !_hasRenderedContent);
    }

    public void Hide()
    {
        if (_disposed || _window.IsNull)
        {
            return;
        }
        _xamlSource.SiteBridge.Hide();
        PInvoke.ShowWindow(_window, SHOW_WINDOW_CMD.SW_HIDE);
        _isVisible = false;
    }

    public void Reposition()
    {
        if (!_disposed && _isVisible && _presentation is not null)
        {
            RenderAndPosition(renderContent: false);
        }
    }

    public void Dispose()
    {
        if (_disposed)
        {
            return;
        }

        _disposed = true;
        _parent.PositionChanged -= Parent_PositionChanged;
        _parent.DisplayEnvironmentChanged -= Parent_DisplayEnvironmentChanged;
        _xamlSource.SiteBridge.Hide();
        _xamlSource.Dispose();
        if (!_window.IsNull)
        {
            PInvoke.DestroyWindow(_window);
            _window = default;
        }
        GC.SuppressFinalize(this);
    }

    private void RenderAndPosition(bool renderContent)
    {
        if (_presentation is not { } presentation)
        {
            return;
        }

        double scale = Math.Max(1, PInvoke.GetDpiForWindow(new HWND(_parent.Handle)) / 96d);
        PetSpeechBubbleTailMetrics tailMetrics = PetSpeechBubbleTailLayout.Calculate(
            presentation.Theme.ShowsTail,
            TailHeight,
            presentation.Placement.Gap);
        if (renderContent || !_hasRenderedContent)
        {
            Border measurement = BuildBody(presentation, tailMetrics.TailHeight);
            measurement.Measure(new Size(
                MaximumWidth,
                MaximumHeight - tailMetrics.TailHeight));
            Size desired = measurement.DesiredSize;
            Size fallback = EstimateBodySize(presentation, tailMetrics.TailHeight);
            _bodyWidthDip = Math.Clamp(
                Math.Max(desired.Width, fallback.Width),
                MinimumWidth,
                MaximumWidth);
            _bodyHeightDip = Math.Clamp(
                Math.Max(desired.Height, fallback.Height),
                1,
                MaximumHeight - tailMetrics.TailHeight);
        }
        double widthDip = _bodyWidthDip;
        double heightDip = _bodyHeightDip + tailMetrics.TailHeight;
        int width = Math.Max(1, (int)Math.Ceiling(widthDip * scale));
        int height = Math.Max(1, (int)Math.Ceiling(heightDip * scale));

        PetSpeechBubbleRect parentFrame = new(
            _parent.OriginX,
            _parent.OriginY,
            _parent.Width,
            _parent.Height);
        MonitorWorkArea screen = TargetWorkArea(parentFrame);
        PetSpeechBubblePlacementSettings scaledSettings = presentation.Placement with
        {
            HorizontalOffset = presentation.Placement.HorizontalOffset * scale,
            Gap = tailMetrics.PlacementGap * scale,
        };
        PetSpeechBubblePlacementResult placement = PetSpeechBubblePlacement.Calculate(
            parentFrame,
            new PetSpeechBubbleSize(width, height),
            new PetSpeechBubbleRect(
                screen.Left,
                screen.Top,
                screen.Width,
                screen.Height),
            scaledSettings);

        double? tailAnchorDip = placement.TailAnchorX / scale;
        bool tailGeometryChanged = !_hasRenderedContent ||
            placement.TailEdge != _tailEdge ||
            Math.Abs(tailMetrics.TailHeight - _tailHeightDip) > 0.01 ||
            !NearlyEqual(tailAnchorDip, _tailAnchorDip);
        if (renderContent || !_hasRenderedContent)
        {
            FrameworkElement content = BuildContent(
                presentation,
                placement.TailEdge,
                tailAnchorDip,
                tailMetrics.TailHeight,
                _bodyWidthDip,
                _bodyHeightDip);
            content.Width = widthDip;
            content.Height = heightDip;
            _xamlSource.Content = content;
            _hasRenderedContent = true;
        }
        else if (tailGeometryChanged)
        {
            UpdateTailGeometry(
                presentation,
                placement.TailEdge,
                tailAnchorDip,
                tailMetrics.TailHeight);
        }
        _tailEdge = placement.TailEdge;
        _tailAnchorDip = tailAnchorDip;
        _tailHeightDip = tailMetrics.TailHeight;

        SET_WINDOW_POS_FLAGS positionFlags =
            SET_WINDOW_POS_FLAGS.SWP_NOACTIVATE;
        if (_isVisible)
        {
            positionFlags |= SET_WINDOW_POS_FLAGS.SWP_NOZORDER;
        }
        else
        {
            positionFlags |= SET_WINDOW_POS_FLAGS.SWP_SHOWWINDOW;
        }
        PInvoke.SetWindowPos(
            _window,
            _isVisible ? default : new HWND(-1),
            (int)Math.Round(placement.Origin.X),
            (int)Math.Round(placement.Origin.Y),
            width,
            height,
            positionFlags);
        if (!_isVisible)
        {
            _xamlSource.SiteBridge.Show();
        }
        _isVisible = true;
    }

    private static bool NearlyEqual(double? left, double? right)
    {
        if (left is null || right is null)
        {
            return left is null && right is null;
        }
        return Math.Abs(left.Value - right.Value) <= 0.25;
    }

    private FrameworkElement BuildContent(
        PetSpeechPresentation presentation,
        PetSpeechBubbleTailEdge tailEdge,
        double? correctedTailAnchorX,
        double tailHeight,
        double bodyWidth,
        double bodyHeight)
    {
        PetSpeechBubbleTheme theme = presentation.Theme;
        (Color background, Color foreground) = ThemeColors(theme);
        background.A = (byte)Math.Round(theme.BackgroundOpacity * byte.MaxValue);
        Border border = BuildBody(presentation, tailHeight);
        border.Width = bodyWidth;
        border.Height = bodyHeight;
        _contentBody = border;
        _outlinePath = null;

        if (!theme.ShowsTail)
        {
            return border;
        }

        var root = new Canvas
        {
            MinWidth = bodyWidth,
            Width = bodyWidth,
            Height = bodyHeight + tailHeight,
        };
        double bodyTop = tailEdge == PetSpeechBubbleTailEdge.Top ? tailHeight : 0;
        double tailCenter = TailCenterX(
            theme,
            bodyWidth,
            correctedTailAnchorX);
        var outline = new Microsoft.UI.Xaml.Shapes.Path
        {
            Data = BubbleOutlineGeometry(
                bodyWidth,
                bodyHeight,
                tailHeight,
                tailCenter,
                tailEdge,
                theme.CornerRadius),
            Fill = new SolidColorBrush(background),
            Stroke = new SolidColorBrush(
                Color.FromArgb(96, foreground.R, foreground.G, foreground.B)),
            StrokeThickness = 1,
        };
        _outlinePath = outline;
        root.Children.Add(outline);

        border.Background = null;
        border.BorderBrush = null;
        border.BorderThickness = new Thickness(0);
        Canvas.SetTop(border, bodyTop);
        root.Children.Add(border);
        return root;
    }

    private void UpdateTailGeometry(
        PetSpeechPresentation presentation,
        PetSpeechBubbleTailEdge tailEdge,
        double? correctedTailAnchorX,
        double tailHeight)
    {
        if (!presentation.Theme.ShowsTail ||
            _outlinePath is null ||
            _contentBody is null)
        {
            return;
        }

        double tailCenter = TailCenterX(
            presentation.Theme,
            _bodyWidthDip,
            correctedTailAnchorX);
        _outlinePath.Data = BubbleOutlineGeometry(
            _bodyWidthDip,
            _bodyHeightDip,
            tailHeight,
            tailCenter,
            tailEdge,
            presentation.Theme.CornerRadius);
        Canvas.SetTop(
            _contentBody,
            tailEdge == PetSpeechBubbleTailEdge.Top ? tailHeight : 0);
    }

    private static Geometry BubbleOutlineGeometry(
        double bodyWidth,
        double bodyHeight,
        double tailHeight,
        double tailCenter,
        PetSpeechBubbleTailEdge tailEdge,
        double cornerRadius)
    {
        const double inset = 0.5;
        double left = inset;
        double right = Math.Max(left, bodyWidth - inset);
        double bodyTop = (tailEdge == PetSpeechBubbleTailEdge.Top ? tailHeight : 0) + inset;
        double bodyBottom = bodyTop + bodyHeight - (inset * 2);
        double radius = Math.Min(
            Math.Max(cornerRadius, 0),
            Math.Min(
                (right - left) / 2,
                (bodyBottom - bodyTop) / 2));
        double tailHalfWidth = Math.Min(
            TailWidth / 2,
            Math.Max(((right - left) - (radius * 2)) / 2, 0));
        double tailLeft = tailCenter - tailHalfWidth;
        double tailRight = tailCenter + tailHalfWidth;
        double tipY = tailEdge == PetSpeechBubbleTailEdge.Top
            ? inset
            : bodyHeight + tailHeight - inset;

        var figure = new PathFigure
        {
            StartPoint = new Point(left + radius, bodyTop),
            IsClosed = true,
            IsFilled = true,
        };
        if (tailEdge == PetSpeechBubbleTailEdge.Top)
        {
            figure.Segments.Add(new LineSegment { Point = new Point(tailLeft, bodyTop) });
            figure.Segments.Add(new LineSegment { Point = new Point(tailCenter, tipY) });
            figure.Segments.Add(new LineSegment { Point = new Point(tailRight, bodyTop) });
        }
        figure.Segments.Add(new LineSegment
        {
            Point = new Point(right - radius, bodyTop),
        });
        figure.Segments.Add(new QuadraticBezierSegment
        {
            Point1 = new Point(right, bodyTop),
            Point2 = new Point(right, bodyTop + radius),
        });
        figure.Segments.Add(new LineSegment
        {
            Point = new Point(right, bodyBottom - radius),
        });
        figure.Segments.Add(new QuadraticBezierSegment
        {
            Point1 = new Point(right, bodyBottom),
            Point2 = new Point(right - radius, bodyBottom),
        });
        if (tailEdge == PetSpeechBubbleTailEdge.Bottom)
        {
            figure.Segments.Add(new LineSegment { Point = new Point(tailRight, bodyBottom) });
            figure.Segments.Add(new LineSegment { Point = new Point(tailCenter, tipY) });
            figure.Segments.Add(new LineSegment { Point = new Point(tailLeft, bodyBottom) });
        }
        figure.Segments.Add(new LineSegment
        {
            Point = new Point(left + radius, bodyBottom),
        });
        figure.Segments.Add(new QuadraticBezierSegment
        {
            Point1 = new Point(left, bodyBottom),
            Point2 = new Point(left, bodyBottom - radius),
        });
        figure.Segments.Add(new LineSegment
        {
            Point = new Point(left, bodyTop + radius),
        });
        figure.Segments.Add(new QuadraticBezierSegment
        {
            Point1 = new Point(left, bodyTop),
            Point2 = new Point(left + radius, bodyTop),
        });

        var geometry = new PathGeometry();
        geometry.Figures.Add(figure);
        return geometry;
    }

    private static Border BuildBody(
        PetSpeechPresentation presentation,
        double tailHeight)
    {
        PetSpeechBubbleTheme theme = presentation.Theme;
        (Color background, Color foreground) = ThemeColors(theme);
        background.A = (byte)Math.Round(theme.BackgroundOpacity * byte.MaxValue);
        return new Border
        {
            MinWidth = MinimumWidth,
            MaxWidth = MaximumWidth,
            MaxHeight = MaximumHeight - tailHeight,
            Background = new SolidColorBrush(background),
            BorderBrush = new SolidColorBrush(
                Color.FromArgb(96, foreground.R, foreground.G, foreground.B)),
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(theme.CornerRadius),
            Padding = new Thickness(theme.ContentPadding),
            Child = new TextBlock
            {
                Text = presentation.Text,
                FontSize = theme.FontSize,
                Foreground = new SolidColorBrush(foreground),
                TextWrapping = TextWrapping.Wrap,
                MaxWidth = MaximumWidth - (theme.ContentPadding * 2) - 2,
                MaxHeight = MaximumHeight - (theme.ContentPadding * 2) -
                    tailHeight - 2,
                TextTrimming = TextTrimming.CharacterEllipsis,
            },
        };
    }

    private static Size EstimateBodySize(
        PetSpeechPresentation presentation,
        double tailHeight)
    {
        PetSpeechBubbleTheme theme = presentation.Theme;
        double glyphWidth = Math.Max(theme.FontSize * 0.8, 1);
        double chrome = (theme.ContentPadding * 2) + 2;
        double preferredWidth = Math.Clamp(
            (presentation.Text.Length * glyphWidth) + chrome,
            MinimumWidth,
            MaximumWidth);
        double usableWidth = Math.Max(preferredWidth - chrome, glyphWidth);
        int charactersPerLine = Math.Max(1, (int)Math.Floor(usableWidth / glyphWidth));
        int lineCount = Math.Clamp(
            (int)Math.Ceiling((double)Math.Max(presentation.Text.Length, 1) /
                charactersPerLine),
            1,
            6);
        double preferredHeight = (lineCount * theme.FontSize * 1.4) + chrome;
        return new Size(
            preferredWidth,
            Math.Clamp(preferredHeight, 1, MaximumHeight - tailHeight));
    }

    private MonitorWorkArea TargetWorkArea(PetSpeechBubbleRect parentFrame)
    {
        IReadOnlyList<MonitorWorkArea> screens = _monitorPlacement.AvailableWorkAreas();
        if (screens.Count == 0)
        {
            return new MonitorWorkArea(
                "fallback",
                (int)parentFrame.X,
                (int)parentFrame.Y,
                (int)parentFrame.Right,
                (int)parentFrame.Bottom);
        }

        return screens
            .OrderByDescending(screen => IntersectionArea(parentFrame, screen))
            .ThenBy(screen => CenterDistanceSquared(parentFrame, screen))
            .First();
    }

    private static double IntersectionArea(
        PetSpeechBubbleRect parent,
        MonitorWorkArea screen)
    {
        double width = Math.Max(0, Math.Min(parent.Right, screen.Right) - Math.Max(parent.Left, screen.Left));
        double height = Math.Max(0, Math.Min(parent.Bottom, screen.Bottom) - Math.Max(parent.Top, screen.Top));
        return width * height;
    }

    private static double CenterDistanceSquared(
        PetSpeechBubbleRect parent,
        MonitorWorkArea screen)
    {
        double dx = parent.MidX - (screen.Left + (screen.Width / 2d));
        double dy = parent.MidY - (screen.Top + (screen.Height / 2d));
        return (dx * dx) + (dy * dy);
    }

    private static double TailCenterX(
        PetSpeechBubbleTheme theme,
        double width,
        double? correctedAnchor)
    {
        double requested = correctedAnchor ?? theme.TailAlignment switch
        {
            PetSpeechBubbleTailAlignment.Leading => width * 0.25,
            PetSpeechBubbleTailAlignment.Trailing => width * 0.75,
            _ => width * 0.5,
        };
        double inset = Math.Max(TailWidth / 2, theme.CornerRadius + 2);
        return Math.Clamp(requested, inset, Math.Max(inset, width - inset));
    }

    private static (Color Background, Color Foreground) ThemeColors(
        PetSpeechBubbleTheme theme)
    {
        bool dark = Application.Current.RequestedTheme == ApplicationTheme.Dark;
        return theme.ColorStyle switch
        {
            PetSpeechBubbleColorStyle.Cream =>
                (Color.FromArgb(255, 255, 243, 214), Color.FromArgb(255, 58, 43, 31)),
            PetSpeechBubbleColorStyle.Midnight =>
                (Color.FromArgb(255, 37, 48, 74), Colors.White),
            PetSpeechBubbleColorStyle.Mint =>
                (Color.FromArgb(255, 221, 245, 230), Color.FromArgb(255, 23, 58, 42)),
            PetSpeechBubbleColorStyle.Peach =>
                (Color.FromArgb(255, 255, 224, 210), Color.FromArgb(255, 74, 38, 29)),
            PetSpeechBubbleColorStyle.Custom =>
                (ColorValue(theme.CustomBackgroundColor), ColorValue(theme.CustomTextColor)),
            _ when dark =>
                (Color.FromArgb(255, 43, 43, 43), Colors.White),
            _ =>
                (Colors.White, Colors.Black),
        };
    }

    private static Color ColorValue(PetSpeechColor value) => Color.FromArgb(
        255,
        (byte)Math.Round(value.Red * byte.MaxValue),
        (byte)Math.Round(value.Green * byte.MaxValue),
        (byte)Math.Round(value.Blue * byte.MaxValue));

    private static HWND CreateNativeWindow()
    {
        HMODULE module = PInvoke.GetModuleHandle((PCWSTR)null);
        HINSTANCE instance = new(module.Value);
        fixed (char* className = WindowClassName)
        fixed (char* title = "MonglePet Speech Bubble")
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
                throw new InvalidOperationException("말풍선용 Win32 창 클래스를 등록하지 못했습니다.");
            }

            WINDOW_EX_STYLE style =
                WINDOW_EX_STYLE.WS_EX_TOOLWINDOW |
                WINDOW_EX_STYLE.WS_EX_TOPMOST |
                WINDOW_EX_STYLE.WS_EX_NOACTIVATE |
                WINDOW_EX_STYLE.WS_EX_TRANSPARENT |
                WINDOW_EX_STYLE.WS_EX_NOREDIRECTIONBITMAP;
            HWND window = PInvoke.CreateWindowEx(
                style,
                className,
                title,
                WINDOW_STYLE.WS_POPUP,
                0,
                0,
                1,
                1,
                // Keep the bubble unowned so PetInstanceManager can order each
                // bubble/pet pair relative to the other topmost pet groups.
                default,
                default,
                instance,
                null);
            if (window.IsNull)
            {
                throw new InvalidOperationException("말풍선용 Win32 창을 만들지 못했습니다.");
            }
            return window;
        }
    }

    private static LRESULT WindowProc(HWND window, uint message, WPARAM wParam, LPARAM lParam)
    {
        if (message == WmNcHitTest)
        {
            return new LRESULT(-1);
        }
        if (message == WmMouseActivate)
        {
            return new LRESULT(3);
        }
        if (message == WmEraseBackground)
        {
            return new LRESULT(1);
        }
        return PInvoke.DefWindowProc(window, message, wParam, lParam);
    }

    private void Parent_PositionChanged(object? sender, EventArgs e) => Reposition();

    private void Parent_DisplayEnvironmentChanged(object? sender, EventArgs e) => Reposition();

    private void ThrowIfDisposed() => ObjectDisposedException.ThrowIf(_disposed, this);
}
