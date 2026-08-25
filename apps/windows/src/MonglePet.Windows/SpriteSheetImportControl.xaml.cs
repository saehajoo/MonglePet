using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using MonglePet.Packages;
using MonglePet.PetLibrary;
using Windows.Foundation;
using Windows.System;

namespace MonglePet.Windows;

public sealed partial class SpriteSheetImportControl : UserControl
{
    private readonly string _path;
    private readonly int _durationMilliseconds;
    private readonly WindowsDecodedImage _decoded;
    private readonly UserPetSpriteBoundarySuggestion _suggestion;
    private readonly List<SpriteFrameDraft> _frames = [];
    private readonly List<Guid> _clickOrder = [];
    private SpriteFrameDraft? _rangeFrame;
    private SpriteFrameDraft? _previewFrame;
    private bool _isRefreshing;
    private bool _isDragging;
    private UserPetCropHandle _dragHandle;
    private Point _dragStart;
    private UserPetPixelRect _dragOriginal;
    private FrameworkElement? _dragBorder;
    private bool _dragMoved;
    private bool _suppressNextTap;
    private double _zoom = 1;
    private double _baseScale = 1;

    private SpriteSheetImportControl(
        string path,
        int durationMilliseconds,
        WindowsDecodedImage decoded)
    {
        InitializeComponent();
        _path = path;
        _durationMilliseconds = Math.Clamp(durationMilliseconds, 16, 60_000);
        _decoded = decoded;
        _suggestion = UserPetSpriteBoundaryAnalyzer.Analyze(
            decoded.BgraPixels,
            decoded.Width,
            decoded.Height);
        SheetCanvas.AddHandler(
            UIElement.PointerPressedEvent,
            new PointerEventHandler(SheetCanvas_PointerPressed),
            handledEventsToo: true);
        SheetCanvas.AddHandler(
            UIElement.PointerMovedEvent,
            new PointerEventHandler(FrameBorder_PointerMoved),
            handledEventsToo: true);
        SheetCanvas.AddHandler(
            UIElement.PointerReleasedEvent,
            new PointerEventHandler(FrameBorder_PointerReleased),
            handledEventsToo: true);
        SheetCanvas.AddHandler(
            UIElement.PointerCanceledEvent,
            new PointerEventHandler(FrameBorder_PointerCanceled),
            handledEventsToo: true);
    }

    public static async Task<SpriteSheetImportControl> CreateAsync(
        string path,
        int durationMilliseconds)
    {
        var cache = new WindowsDecodedImageCache();
        WindowsDecodedImage decoded = await cache.GetAsync(path);
        var control = new SpriteSheetImportControl(path, durationMilliseconds, decoded);
        await control.InitializeAsync();
        return control;
    }

    public IReadOnlyList<UserPetFrameSourceRequest> CreateRequests() => FinalFrames()
        .Select(frame => new UserPetFrameSourceRequest(
            _path,
            _durationMilliseconds,
            new PetPackageFrame(
                frame.Rect.X,
                frame.Rect.Y,
                frame.Rect.Width,
                frame.Rect.Height,
                _durationMilliseconds),
            frame.FlipsHorizontally,
            frame.FlipsVertically,
            null,
            frame.Id,
            CurrentBackgroundRemoval()))
        .ToArray();

    public bool HasSelectedFrames => FinalFrames().Count > 0;

    private async Task InitializeAsync()
    {
        _isRefreshing = true;
        if (_suggestion.InferredBackground is { } background)
        {
            BackgroundColorTextBox.Text = $"#{background.Red:X2}{background.Green:X2}{background.Blue:X2}";
            BackgroundToleranceNumberBox.Value = background.Tolerance;
        }
        else
        {
            BackgroundColorTextBox.Text = "#FFFFFF";
        }
        _isRefreshing = false;
        await RefreshProcessedSourceAsync();
        ReplaceWithSuggestion();
        await RenderAsync();
    }

    private void ReplaceWithSuggestion()
    {
        _frames.Clear();
        _frames.AddRange(_suggestion.Frames.Select(rect => new SpriteFrameDraft(Guid.NewGuid(), rect)));
        (int rows, int columns) = UserPetSpriteSheetGeometry.InferGridCounts(_suggestion.Frames);
        _isRefreshing = true;
        RowsNumberBox.Value = rows;
        ColumnsNumberBox.Value = columns;
        _isRefreshing = false;
        ResetFrameSelection();
    }

    private void ReplaceWithGrid(int rows, int columns)
    {
        IReadOnlyList<UserPetPixelRect> rectangles = UserPetSpriteSheetGeometry.CreateUniformGrid(
            _decoded.Width,
            _decoded.Height,
            rows,
            columns);
        _frames.Clear();
        _frames.AddRange(rectangles.Select(rect => new SpriteFrameDraft(Guid.NewGuid(), rect)));
        ResetFrameSelection();
    }

    private void ResetFrameSelection()
    {
        _clickOrder.Clear();
        _rangeFrame = _frames.FirstOrDefault();
        _previewFrame = _rangeFrame;
        if (ReadingOrderRadio.IsChecked == true)
        {
            foreach (SpriteFrameDraft frame in _frames)
            {
                frame.IsIncluded = true;
            }
        }
    }

    private async Task RenderAsync()
    {
        _isRefreshing = true;
        try
        {
            const double availableWidth = 500;
            double availableHeight = UserPetSpriteSheetGeometry.SuggestedCanvasHeight(
                _decoded.Width,
                _decoded.Height,
                availableWidth,
                500,
                180);
            _baseScale = Math.Min(availableWidth / _decoded.Width, availableHeight / _decoded.Height);
            _baseScale = Math.Min(_baseScale, 1);
            double displayScale = _baseScale * _zoom;
            SheetCanvas.Width = _decoded.Width * displayScale;
            SheetCanvas.Height = _decoded.Height * displayScale;
            SheetImage.Width = SheetCanvas.Width;
            SheetImage.Height = SheetCanvas.Height;
            SheetScrollViewer.HorizontalScrollMode = _zoom > 1 ? ScrollMode.Enabled : ScrollMode.Disabled;
            SheetScrollViewer.VerticalScrollMode = _zoom > 1 ? ScrollMode.Enabled : ScrollMode.Disabled;
            ZoomText.Text = $"{_zoom:0.##}×";
            while (SheetCanvas.Children.Count > 1)
            {
                SheetCanvas.Children.RemoveAt(1);
            }
            IReadOnlyList<SpriteFrameDraft> final = FinalFrames();
            foreach (SpriteFrameDraft frame in _frames)
            {
                int order = final.IndexOf(frame);
                var label = new TextBlock
                {
                    Text = order >= 0 ? (order + 1).ToString() : string.Empty,
                    Foreground = new SolidColorBrush(Microsoft.UI.Colors.White),
                    Margin = new Thickness(3, 0, 0, 0),
                };
                var frameContent = new Grid
                {
                    IsHitTestVisible = false,
                };
                frameContent.Children.Add(label);
                if (RangeModeRadio.IsChecked == true && frame == _rangeFrame)
                {
                    AddResizeHandles(frameContent);
                }
                var border = new ContentControl
                {
                    Tag = frame,
                    Style = (Style)Application.Current.Resources["SpriteFrameBoundaryStyle"],
                    Width = frame.Rect.Width * displayScale,
                    Height = frame.Rect.Height * displayScale,
                    MinWidth = 0,
                    MinHeight = 0,
                    BorderBrush = new SolidColorBrush(
                        frame == _rangeFrame ? Microsoft.UI.Colors.DeepSkyBlue : Microsoft.UI.Colors.DodgerBlue),
                    BorderThickness = new Thickness(frame == _rangeFrame ? 3 : 1),
                    Background = new SolidColorBrush(
                        frame.IsIncluded
                            ? global::Windows.UI.Color.FromArgb(42, 24, 119, 242)
                            : global::Windows.UI.Color.FromArgb(18, 90, 90, 90)),
                    Content = frameContent,
                    Padding = new Thickness(0),
                    HorizontalContentAlignment = HorizontalAlignment.Stretch,
                    VerticalContentAlignment = VerticalAlignment.Stretch,
                    IsTabStop = true,
                    UseSystemFocusVisuals = true,
                };
                AutomationProperties.SetName(
                    border,
                    RangeModeRadio.IsChecked == true
                        ? frame == _rangeFrame
                            ? "편집 중인 스프라이트 프레임 범위"
                            : "스프라이트 프레임 범위"
                        : order >= 0
                            ? $"선택된 스프라이트 프레임 {order + 1}"
                            : "선택되지 않은 스프라이트 프레임");
                ToolTipService.SetToolTip(
                    border,
                    RangeModeRadio.IsChecked == true
                        ? "가운데를 끌어 이동하고 가장자리나 모서리를 끌어 크기를 조절합니다."
                        : "클릭해 가져올 프레임에 포함하거나 제외합니다.");
                border.Tapped += FrameControl_Tapped;
                border.KeyDown += FrameControl_KeyDown;
                Canvas.SetLeft(border, frame.Rect.X * displayScale);
                Canvas.SetTop(border, frame.Rect.Y * displayScale);
                Canvas.SetZIndex(border, frame == _rangeFrame ? 1 : 0);
                SheetCanvas.Children.Add(border);
            }
            SelectionSummaryText.Text = $"선택 {final.Count}개 / 전체 {_frames.Count}개";
            RefreshNumberBoxes();
            await RefreshPreviewAsync(final);
        }
        finally
        {
            _isRefreshing = false;
        }
    }

    private static void AddResizeHandles(Grid content)
    {
        AddResizeHandle(content, HorizontalAlignment.Left, VerticalAlignment.Top);
        AddResizeHandle(content, HorizontalAlignment.Center, VerticalAlignment.Top);
        AddResizeHandle(content, HorizontalAlignment.Right, VerticalAlignment.Top);
        AddResizeHandle(content, HorizontalAlignment.Left, VerticalAlignment.Center);
        AddResizeHandle(content, HorizontalAlignment.Right, VerticalAlignment.Center);
        AddResizeHandle(content, HorizontalAlignment.Left, VerticalAlignment.Bottom);
        AddResizeHandle(content, HorizontalAlignment.Center, VerticalAlignment.Bottom);
        AddResizeHandle(content, HorizontalAlignment.Right, VerticalAlignment.Bottom);
    }

    private static void AddResizeHandle(
        Grid content,
        HorizontalAlignment horizontalAlignment,
        VerticalAlignment verticalAlignment)
    {
        content.Children.Add(new Border
        {
            Width = 8,
            Height = 8,
            HorizontalAlignment = horizontalAlignment,
            VerticalAlignment = verticalAlignment,
            Background = new SolidColorBrush(Microsoft.UI.Colors.DeepSkyBlue),
            BorderBrush = new SolidColorBrush(Microsoft.UI.Colors.White),
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(2),
            IsHitTestVisible = false,
        });
    }

    private IReadOnlyList<SpriteFrameDraft> FinalFrames()
    {
        if (ClickOrderRadio.IsChecked == true)
        {
            var byId = _frames.ToDictionary(frame => frame.Id);
            return _clickOrder.Where(byId.ContainsKey).Select(id => byId[id]).ToArray();
        }
        return UserPetSpriteSheetGeometry.ReadingOrder(
                _frames.Where(frame => frame.IsIncluded),
                frame => frame.Rect)
            .ToArray();
    }

    private async Task RefreshPreviewAsync(IReadOnlyList<SpriteFrameDraft>? final = null)
    {
        final ??= FinalFrames();
        if (final.Count == 0)
        {
            PreviewImage.Source = null;
            PreviewPositionText.Text = "선택 없음";
            return;
        }
        if (_previewFrame is null || !final.Contains(_previewFrame))
        {
            _previewFrame = final[0];
        }
        SpriteFrameDraft frame = _previewFrame;
        var crop = new PetPackageFrame(
            frame.Rect.X,
            frame.Rect.Y,
            frame.Rect.Width,
            frame.Rect.Height,
            _durationMilliseconds);
        UserPetProcessedFrame processed = UserPetPixelProcessor.Process(
            _decoded.BgraPixels,
            _decoded.Width,
            _decoded.Height,
            crop,
            frame.FlipsHorizontally,
            frame.FlipsVertically,
            backgroundRemoval: CurrentBackgroundRemoval());
        PreviewImage.Source = await WindowsImagePreviewFactory.CreateCheckerboardAsync(processed);
        double scale = Math.Min(300d / processed.Width, 180d / processed.Height);
        scale = Math.Min(scale, 1);
        PreviewImage.Width = Math.Max(1, processed.Width * scale);
        PreviewImage.Height = Math.Max(1, processed.Height * scale);
        PreviewPositionText.Text = $"{final.IndexOf(frame) + 1} / {final.Count}";
    }

    private void RefreshNumberBoxes()
    {
        if (_rangeFrame is null)
        {
            return;
        }
        bool wasRefreshing = _isRefreshing;
        _isRefreshing = true;
        try
        {
            UserPetPixelRect rect = _rangeFrame.Rect;
            FrameXNumberBox.Maximum = _decoded.Width - 1;
            FrameYNumberBox.Maximum = _decoded.Height - 1;
            FrameWidthNumberBox.Maximum = _decoded.Width;
            FrameHeightNumberBox.Maximum = _decoded.Height;
            FrameXNumberBox.Value = rect.X;
            FrameYNumberBox.Value = rect.Y;
            FrameWidthNumberBox.Value = rect.Width;
            FrameHeightNumberBox.Value = rect.Height;
        }
        finally
        {
            _isRefreshing = wasRefreshing;
        }
    }

    private void SheetCanvas_PointerPressed(object sender, PointerRoutedEventArgs e)
    {
        if (SelectionModeRadio.IsChecked == true)
        {
            return;
        }
        double scale = _baseScale * _zoom;
        Point sheetPoint = e.GetCurrentPoint(SheetCanvas).Position;
        bool Contains(SpriteFrameDraft candidate) =>
            sheetPoint.X >= candidate.Rect.X * scale &&
            sheetPoint.X <= candidate.Rect.Right * scale &&
            sheetPoint.Y >= candidate.Rect.Y * scale &&
            sheetPoint.Y <= candidate.Rect.Bottom * scale;
        SpriteFrameDraft? frame = _rangeFrame is not null && Contains(_rangeFrame)
            ? _rangeFrame
            : _frames.LastOrDefault(Contains);
        if (frame is null)
        {
            return;
        }
        ContentControl? border = SheetCanvas.Children
            .OfType<ContentControl>()
            .FirstOrDefault(candidate => ReferenceEquals(candidate.Tag, frame));
        if (border is null)
        {
            return;
        }
        _rangeFrame = frame;
        var point = new Point(
            sheetPoint.X - frame.Rect.X * scale,
            sheetPoint.Y - frame.Rect.Y * scale);
        _dragHandle = HitHandle(point, border.ActualWidth, border.ActualHeight);
        _dragStart = sheetPoint;
        _dragOriginal = frame.Rect;
        _dragBorder = border;
        _dragMoved = false;
        _isDragging = true;
        SheetCanvas.CapturePointer(e.Pointer);
        border.BorderThickness = new Thickness(3);
        RefreshNumberBoxes();
        e.Handled = true;
    }

    private async void FrameControl_Tapped(object sender, TappedRoutedEventArgs e)
    {
        if (_suppressNextTap)
        {
            _suppressNextTap = false;
            e.Handled = true;
            return;
        }
        if (sender is not ContentControl { Tag: SpriteFrameDraft frame })
        {
            return;
        }
        await ActivateFrameAsync(frame);
        e.Handled = true;
    }

    private async void FrameControl_KeyDown(object sender, KeyRoutedEventArgs e)
    {
        if (e.Key is not (VirtualKey.Enter or VirtualKey.Space) ||
            sender is not ContentControl { Tag: SpriteFrameDraft frame })
        {
            return;
        }
        await ActivateFrameAsync(frame);
        e.Handled = true;
    }

    private async Task ActivateFrameAsync(SpriteFrameDraft frame)
    {
        if (SelectionModeRadio.IsChecked == true)
        {
            if (ClickOrderRadio.IsChecked == true)
            {
                IReadOnlyList<Guid> order = UserPetSpriteSheetGeometry.ToggleClickOrder(_clickOrder, frame.Id);
                _clickOrder.Clear();
                _clickOrder.AddRange(order);
                frame.IsIncluded = _clickOrder.Contains(frame.Id);
            }
            else
            {
                frame.IsIncluded = !frame.IsIncluded;
            }
        }
        else
        {
            _rangeFrame = frame;
        }
        await RenderAsync();
    }

    private void FrameBorder_PointerMoved(object sender, PointerRoutedEventArgs e)
    {
        if (!_isDragging || _rangeFrame is null)
        {
            return;
        }
        Point current = e.GetCurrentPoint(SheetCanvas).Position;
        double scale = _baseScale * _zoom;
        double displayDeltaX = current.X - _dragStart.X;
        double displayDeltaY = current.Y - _dragStart.Y;
        _dragMoved |= Math.Abs(displayDeltaX) >= 2 || Math.Abs(displayDeltaY) >= 2;
        _rangeFrame.Rect = UserPetImageEditingGeometry.DragCrop(
            _dragOriginal,
            _dragHandle,
            (int)Math.Round(displayDeltaX / scale),
            (int)Math.Round(displayDeltaY / scale),
            _decoded.Width,
            _decoded.Height);
        if (_dragBorder is not null)
        {
            double displayScale = _baseScale * _zoom;
            _dragBorder.Width = _rangeFrame.Rect.Width * displayScale;
            _dragBorder.Height = _rangeFrame.Rect.Height * displayScale;
            Canvas.SetLeft(_dragBorder, _rangeFrame.Rect.X * displayScale);
            Canvas.SetTop(_dragBorder, _rangeFrame.Rect.Y * displayScale);
        }
        RefreshNumberBoxes();
        e.Handled = true;
    }

    private async void FrameBorder_PointerReleased(object sender, PointerRoutedEventArgs e)
    {
        if (!_isDragging)
        {
            return;
        }
        _isDragging = false;
        if (sender is UIElement element)
        {
            element.ReleasePointerCapture(e.Pointer);
        }
        _suppressNextTap = _dragMoved;
        _dragBorder = null;
        await RenderAsync();
        e.Handled = true;
    }

    private void FrameBorder_PointerCanceled(object sender, PointerRoutedEventArgs e)
    {
        _isDragging = false;
        _dragBorder = null;
    }

    private static UserPetCropHandle HitHandle(Point point, double width, double height)
    {
        const double tolerance = 10;
        bool left = point.X <= tolerance;
        bool right = point.X >= width - tolerance;
        bool top = point.Y <= tolerance;
        bool bottom = point.Y >= height - tolerance;
        if (left && top) return UserPetCropHandle.TopLeft;
        if (right && top) return UserPetCropHandle.TopRight;
        if (right && bottom) return UserPetCropHandle.BottomRight;
        if (left && bottom) return UserPetCropHandle.BottomLeft;
        if (top) return UserPetCropHandle.Top;
        if (right) return UserPetCropHandle.Right;
        if (bottom) return UserPetCropHandle.Bottom;
        if (left) return UserPetCropHandle.Left;
        return UserPetCropHandle.Move;
    }

    private async void ApplyGridButton_Click(object sender, RoutedEventArgs e)
    {
        int rows = Math.Clamp((int)RowsNumberBox.Value, 1, Math.Min(32, _decoded.Height));
        int columns = Math.Clamp((int)ColumnsNumberBox.Value, 1, Math.Min(32, _decoded.Width));
        ReplaceWithGrid(rows, columns);
        await RenderAsync();
    }

    private async void ApplySuggestionButton_Click(object sender, RoutedEventArgs e)
    {
        ReplaceWithSuggestion();
        await RenderAsync();
    }

    private async void FrameNumberBox_ValueChanged(NumberBox sender, NumberBoxValueChangedEventArgs args)
    {
        if (_isRefreshing || _rangeFrame is null || double.IsNaN(sender.Value))
        {
            return;
        }
        _rangeFrame.Rect = UserPetImageEditingGeometry.ClampCrop(
            new UserPetPixelRect(
                (int)FrameXNumberBox.Value,
                (int)FrameYNumberBox.Value,
                Math.Max(1, (int)FrameWidthNumberBox.Value),
                Math.Max(1, (int)FrameHeightNumberBox.Value)),
            _decoded.Width,
            _decoded.Height);
        await RenderAsync();
    }

    private async void ApplyFrameSizeToAllButton_Click(object sender, RoutedEventArgs e)
    {
        if (_rangeFrame is null) return;
        foreach (SpriteFrameDraft frame in _frames.Where(frame => frame != _rangeFrame))
        {
            frame.Rect = UserPetImageEditingGeometry.ClampCrop(
                frame.Rect with
                {
                    Width = Math.Min(_rangeFrame.Rect.Width, _decoded.Width),
                    Height = Math.Min(_rangeFrame.Rect.Height, _decoded.Height),
                },
                _decoded.Width,
                _decoded.Height);
        }
        await RenderAsync();
    }

    private async void OrderingRadio_Checked(object sender, RoutedEventArgs e)
    {
        if (!IsLoaded) return;
        if (ClickOrderRadio.IsChecked == true)
        {
            _clickOrder.Clear();
            foreach (SpriteFrameDraft frame in _frames) frame.IsIncluded = false;
        }
        else
        {
            foreach (SpriteFrameDraft frame in _frames) frame.IsIncluded = true;
        }
        await RenderAsync();
    }

    private async void EditModeRadio_Checked(object sender, RoutedEventArgs e)
    {
        if (!IsLoaded || _isRefreshing)
        {
            return;
        }
        _rangeFrame ??= _frames.FirstOrDefault();
        await RenderAsync();
    }

    private async void SelectAllButton_Click(object sender, RoutedEventArgs e)
    {
        _clickOrder.Clear();
        foreach (SpriteFrameDraft frame in UserPetSpriteSheetGeometry.ReadingOrder(_frames, value => value.Rect))
        {
            frame.IsIncluded = true;
            if (ClickOrderRadio.IsChecked == true) _clickOrder.Add(frame.Id);
        }
        await RenderAsync();
    }

    private async void ClearSelectionButton_Click(object sender, RoutedEventArgs e)
    {
        _clickOrder.Clear();
        foreach (SpriteFrameDraft frame in _frames) frame.IsIncluded = false;
        await RenderAsync();
    }

    private async void FlipHorizontalButton_Click(object sender, RoutedEventArgs e)
    {
        if (_previewFrame is null) return;
        _previewFrame.FlipsHorizontally = !_previewFrame.FlipsHorizontally;
        await RefreshPreviewAsync();
    }

    private async void FlipVerticalButton_Click(object sender, RoutedEventArgs e)
    {
        if (_previewFrame is null) return;
        _previewFrame.FlipsVertically = !_previewFrame.FlipsVertically;
        await RefreshPreviewAsync();
    }

    private async void PreviousPreviewButton_Click(object sender, RoutedEventArgs e) => await NavigatePreviewAsync(-1);
    private async void NextPreviewButton_Click(object sender, RoutedEventArgs e) => await NavigatePreviewAsync(1);

    private async Task NavigatePreviewAsync(int offset)
    {
        IReadOnlyList<SpriteFrameDraft> frames = FinalFrames();
        if (frames.Count == 0) return;
        int index = _previewFrame is null ? 0 : frames.IndexOf(_previewFrame);
        _previewFrame = frames[(index + offset + frames.Count) % frames.Count];
        await RefreshPreviewAsync(frames);
    }

    private UserPetBackgroundRemoval? CurrentBackgroundRemoval()
    {
        if (RemoveBackgroundToggle.IsOn != true ||
            !TryParseRgb(BackgroundColorTextBox.Text, out byte red, out byte green, out byte blue))
        {
            return null;
        }
        int tolerance = double.IsFinite(BackgroundToleranceNumberBox.Value)
            ? (int)Math.Round(BackgroundToleranceNumberBox.Value)
            : 0;
        return new UserPetBackgroundRemoval(red, green, blue, (byte)Math.Clamp(tolerance, 0, 255));
    }

    private async Task RefreshProcessedSourceAsync()
    {
        UserPetProcessedFrame processed = UserPetPixelProcessor.Process(
            _decoded.BgraPixels,
            _decoded.Width,
            _decoded.Height,
            backgroundRemoval: CurrentBackgroundRemoval());
        SheetImage.Source = await WindowsImagePreviewFactory.CreateCheckerboardAsync(processed);
    }

    private async void RemoveBackgroundToggle_Toggled(object sender, RoutedEventArgs e) =>
        await RefreshBackgroundPreviewAsync();

    private async void BackgroundToleranceNumberBox_ValueChanged(
        NumberBox sender,
        NumberBoxValueChangedEventArgs args) => await RefreshBackgroundPreviewAsync();

    private async void BackgroundColorTextBox_TextChanged(object sender, TextChangedEventArgs e)
    {
        if (RemoveBackgroundToggle.IsOn && TryParseRgb(BackgroundColorTextBox.Text, out _, out _, out _))
        {
            await RefreshBackgroundPreviewAsync();
        }
    }

    private async Task RefreshBackgroundPreviewAsync()
    {
        if (_isRefreshing || !IsLoaded)
        {
            return;
        }
        await RefreshProcessedSourceAsync();
        await RefreshPreviewAsync();
    }

    private static bool TryParseRgb(string? value, out byte red, out byte green, out byte blue)
    {
        red = green = blue = 0;
        string text = value?.Trim() ?? string.Empty;
        if (text.StartsWith('#'))
        {
            text = text[1..];
        }
        if (text.Length != 6 || !int.TryParse(
            text,
            System.Globalization.NumberStyles.HexNumber,
            System.Globalization.CultureInfo.InvariantCulture,
            out int rgb))
        {
            return false;
        }
        red = (byte)((rgb >> 16) & 0xff);
        green = (byte)((rgb >> 8) & 0xff);
        blue = (byte)(rgb & 0xff);
        return true;
    }

    private async void ZoomOutButton_Click(object sender, RoutedEventArgs e) { _zoom = UserPetImageEditingGeometry.ClampZoom(_zoom - 0.5); await RenderAsync(); }
    private async void ZoomInButton_Click(object sender, RoutedEventArgs e) { _zoom = UserPetImageEditingGeometry.ClampZoom(_zoom + 0.5); await RenderAsync(); }
    private async void FitButton_Click(object sender, RoutedEventArgs e) { _zoom = 1; await RenderAsync(); }

    private sealed class SpriteFrameDraft(Guid id, UserPetPixelRect rect)
    {
        public Guid Id { get; } = id;
        public UserPetPixelRect Rect { get; set; } = rect;
        public bool IsIncluded { get; set; }
        public bool FlipsHorizontally { get; set; }
        public bool FlipsVertically { get; set; }
    }
}
