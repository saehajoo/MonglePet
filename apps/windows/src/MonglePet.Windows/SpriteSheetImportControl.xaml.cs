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
    private readonly List<Guid> _readingOrder = [];
    private SpriteFrameDraft? _rangeFrame;
    private SpriteFrameDraft? _previewFrame;
    private bool _isRefreshing;
    private bool _isDragging;
    private UserPetCropHandle _dragHandle;
    private Point _dragStart;
    private UserPetPixelRect _dragOriginal;
    private SpriteFrameDraft? _dragFrame;
    private FrameworkElement? _dragBorder;
    private uint _dragPointerId;
    private bool _dragMoved;
    private bool _suppressNextTap;
    private double _zoom = 1;
    private double _baseScale = 1;
    private double _dragDisplayScale = 1;

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
        SheetCanvas.AddHandler(
            UIElement.PointerCaptureLostEvent,
            new PointerEventHandler(FrameBorder_PointerCaptureLost),
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
        CaptureReadingOrder();
        _rangeFrame = _frames.FirstOrDefault();
        _previewFrame = _rangeFrame;
        foreach (SpriteFrameDraft frame in _frames)
        {
            frame.IsIncluded = true;
        }
        _clickOrder.AddRange(_readingOrder);
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
                    IsHitTestVisible = false,
                };
                var frameContent = new Grid
                {
                    Background = new SolidColorBrush(global::Windows.UI.Color.FromArgb(1, 0, 0, 0)),
                };
                frameContent.Children.Add(label);
                double frameDisplayWidth = frame.Rect.Width * displayScale;
                double frameDisplayHeight = frame.Rect.Height * displayScale;
                if (RangeModeRadio.IsChecked == true && frame == _rangeFrame)
                {
                    AddResizeHandles(frameContent, frameDisplayWidth, frameDisplayHeight);
                }
                var border = new ContentControl
                {
                    Tag = frame,
                    Style = (Style)Application.Current.Resources["SpriteFrameBoundaryStyle"],
                    Width = frameDisplayWidth,
                    Height = frameDisplayHeight,
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
                    AllowFocusOnInteraction = false,
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

    private static void AddResizeHandles(
        Grid content,
        double frameDisplayWidth,
        double frameDisplayHeight)
    {
        double minimumDisplayDimension = Math.Min(frameDisplayWidth, frameDisplayHeight);
        if (!double.IsFinite(minimumDisplayDimension) || minimumDisplayDimension < 18)
        {
            return;
        }

        double hitTargetSize = Math.Clamp(Math.Floor(minimumDisplayDimension * 0.2), 6, 10);
        double markerSize = Math.Clamp(hitTargetSize - 2, 4, 6);
        AddResizeHandle(content, UserPetCropHandle.TopLeft, HorizontalAlignment.Left, VerticalAlignment.Top, hitTargetSize, markerSize);
        AddResizeHandle(content, UserPetCropHandle.Top, HorizontalAlignment.Center, VerticalAlignment.Top, hitTargetSize, markerSize);
        AddResizeHandle(content, UserPetCropHandle.TopRight, HorizontalAlignment.Right, VerticalAlignment.Top, hitTargetSize, markerSize);
        AddResizeHandle(content, UserPetCropHandle.Left, HorizontalAlignment.Left, VerticalAlignment.Center, hitTargetSize, markerSize);
        AddResizeHandle(content, UserPetCropHandle.Right, HorizontalAlignment.Right, VerticalAlignment.Center, hitTargetSize, markerSize);
        AddResizeHandle(content, UserPetCropHandle.BottomLeft, HorizontalAlignment.Left, VerticalAlignment.Bottom, hitTargetSize, markerSize);
        AddResizeHandle(content, UserPetCropHandle.Bottom, HorizontalAlignment.Center, VerticalAlignment.Bottom, hitTargetSize, markerSize);
        AddResizeHandle(content, UserPetCropHandle.BottomRight, HorizontalAlignment.Right, VerticalAlignment.Bottom, hitTargetSize, markerSize);
    }

    private static void AddResizeHandle(
        Grid content,
        UserPetCropHandle handle,
        HorizontalAlignment horizontalAlignment,
        VerticalAlignment verticalAlignment,
        double hitTargetSize,
        double markerSize)
    {
        content.Children.Add(new Border
        {
            Tag = handle,
            Width = hitTargetSize,
            Height = hitTargetSize,
            Padding = new Thickness((hitTargetSize - markerSize) / 2),
            HorizontalAlignment = horizontalAlignment,
            VerticalAlignment = verticalAlignment,
            Background = new SolidColorBrush(Microsoft.UI.Colors.Transparent),
            Child = new Border
            {
                Background = new SolidColorBrush(Microsoft.UI.Colors.DeepSkyBlue),
                BorderBrush = new SolidColorBrush(Microsoft.UI.Colors.White),
                BorderThickness = new Thickness(1),
                CornerRadius = new CornerRadius(2),
            },
        });
    }

    private IReadOnlyList<SpriteFrameDraft> FinalFrames()
    {
        if (ClickOrderRadio.IsChecked == true)
        {
            var clickFramesById = _frames.ToDictionary(frame => frame.Id);
            return _clickOrder
                .Where(clickFramesById.ContainsKey)
                .Select(id => clickFramesById[id])
                .Where(frame => frame.IsIncluded)
                .ToArray();
        }
        var readingFramesById = _frames.ToDictionary(frame => frame.Id);
        return _readingOrder
            .Where(readingFramesById.ContainsKey)
            .Select(id => readingFramesById[id])
            .Where(frame => frame.IsIncluded)
            .ToArray();
    }

    private void CaptureReadingOrder()
    {
        _readingOrder.Clear();
        _readingOrder.AddRange(UserPetSpriteSheetGeometry
            .ReadingOrder(_frames, frame => frame.Rect)
            .Select(frame => frame.Id));
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
        UserPetBackgroundRemoval? backgroundRemoval = CurrentBackgroundRemoval();
        UserPetProcessedFrame processed = await Task.Run(() =>
            UserPetPixelProcessor.Process(
                _decoded.BgraPixels,
                _decoded.Width,
                _decoded.Height,
                crop,
                frame.FlipsHorizontally,
                frame.FlipsVertically,
                backgroundRemoval: backgroundRemoval));
        int commonWidth = final.Max(candidate => candidate.Rect.Width);
        int commonHeight = final.Max(candidate => candidate.Rect.Height);
        UserPetProcessedFrame commonPreview = await Task.Run(() =>
            WindowsImagePreviewFactory.CenterOnCanvas(
                processed,
                commonWidth,
                commonHeight));
        PreviewImage.Source = await WindowsImagePreviewFactory
            .CreateCheckerboardAsync(commonPreview);
        double scale = Math.Min(300d / commonWidth, 180d / commonHeight);
        scale = Math.Min(scale, 1);
        PreviewOuterBorder.Width = Math.Max(1, commonWidth * scale + 4);
        PreviewOuterBorder.Height = Math.Max(1, commonHeight * scale + 4);
        PreviewCanvas.Width = Math.Max(1, commonWidth * scale);
        PreviewCanvas.Height = Math.Max(1, commonHeight * scale);
        PreviewImage.Width = Math.Max(1, commonWidth * scale);
        PreviewImage.Height = Math.Max(1, commonHeight * scale);
        Canvas.SetLeft(PreviewImage, 0);
        Canvas.SetTop(PreviewImage, 0);
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
        var canvasPointer = e.GetCurrentPoint(SheetCanvas);
        if (SelectionModeRadio.IsChecked == true ||
            _isDragging ||
            !canvasPointer.Properties.IsLeftButtonPressed)
        {
            return;
        }
        double scale = _baseScale * _zoom;
        Point sheetPoint = canvasPointer.Position;
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
        _dragHandle = FindExplicitHandle(e.OriginalSource) ?? UserPetCropHandle.Move;
        _dragStart = e.GetCurrentPoint(this).Position;
        _dragOriginal = frame.Rect;
        _dragFrame = frame;
        _dragDisplayScale = Math.Max(0.000_1, scale);
        _dragBorder = border;
        _dragPointerId = e.Pointer.PointerId;
        _dragMoved = false;
        _isDragging = SheetCanvas.CapturePointer(e.Pointer);
        if (!_isDragging)
        {
            _dragFrame = null;
            _dragBorder = null;
            return;
        }
        SheetScrollViewer.HorizontalScrollMode = ScrollMode.Disabled;
        SheetScrollViewer.VerticalScrollMode = ScrollMode.Disabled;
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
        if (!_isDragging ||
            e.Pointer.PointerId != _dragPointerId ||
            _dragFrame is null)
        {
            return;
        }
        var currentPointer = e.GetCurrentPoint(this);
        if (!currentPointer.Properties.IsLeftButtonPressed)
        {
            return;
        }
        Point current = currentPointer.Position;
        if (!double.IsFinite(current.X) || !double.IsFinite(current.Y))
        {
            return;
        }
        double displayDeltaX = current.X - _dragStart.X;
        double displayDeltaY = current.Y - _dragStart.Y;
        _dragMoved |= Math.Abs(displayDeltaX) >= 2 || Math.Abs(displayDeltaY) >= 2;
        _dragFrame.Rect = UserPetImageEditingGeometry.DragCrop(
            _dragOriginal,
            _dragHandle,
            (int)Math.Round(displayDeltaX / _dragDisplayScale),
            (int)Math.Round(displayDeltaY / _dragDisplayScale),
            _decoded.Width,
            _decoded.Height);
        if (_dragBorder is not null)
        {
            _dragBorder.Width = _dragFrame.Rect.Width * _dragDisplayScale;
            _dragBorder.Height = _dragFrame.Rect.Height * _dragDisplayScale;
            Canvas.SetLeft(_dragBorder, _dragFrame.Rect.X * _dragDisplayScale);
            Canvas.SetTop(_dragBorder, _dragFrame.Rect.Y * _dragDisplayScale);
        }
        RefreshNumberBoxes();
        e.Handled = true;
    }

    private async void FrameBorder_PointerReleased(object sender, PointerRoutedEventArgs e)
    {
        if (!_isDragging || e.Pointer.PointerId != _dragPointerId)
        {
            return;
        }
        _isDragging = false;
        SheetCanvas.ReleasePointerCapture(e.Pointer);
        _suppressNextTap = _dragMoved;
        _dragFrame = null;
        _dragBorder = null;
        await RenderAsync();
        e.Handled = true;
    }

    private async void FrameBorder_PointerCanceled(object sender, PointerRoutedEventArgs e)
    {
        SpriteFrameDraft? dragFrame = _dragFrame;
        if (!_isDragging || e.Pointer.PointerId != _dragPointerId || dragFrame is null)
        {
            return;
        }
        dragFrame.Rect = _dragOriginal;
        _isDragging = false;
        SheetCanvas.ReleasePointerCapture(e.Pointer);
        _dragFrame = null;
        _dragBorder = null;
        await RenderAsync();
        e.Handled = true;
    }

    private async void FrameBorder_PointerCaptureLost(object sender, PointerRoutedEventArgs e)
    {
        SpriteFrameDraft? dragFrame = _dragFrame;
        if (!_isDragging || e.Pointer.PointerId != _dragPointerId || dragFrame is null)
        {
            return;
        }
        dragFrame.Rect = _dragOriginal;
        _isDragging = false;
        _dragFrame = null;
        _dragBorder = null;
        await RenderAsync();
        e.Handled = true;
    }

    private static UserPetCropHandle? FindExplicitHandle(object source)
    {
        DependencyObject? current = source as DependencyObject;
        while (current is not null)
        {
            if (current is FrameworkElement { Tag: UserPetCropHandle handle })
            {
                return handle;
            }
            current = VisualTreeHelper.GetParent(current);
        }
        return null;
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
            var includedIds = _frames
                .Where(frame => frame.IsIncluded)
                .Select(frame => frame.Id)
                .ToHashSet();
            var nextOrder = _clickOrder
                .Where(includedIds.Contains)
                .Concat(_readingOrder.Where(includedIds.Contains).Where(id => !_clickOrder.Contains(id)))
                .ToArray();
            _clickOrder.Clear();
            _clickOrder.AddRange(nextOrder);
        }
        ApplyReadingOrderButton.IsEnabled = ReadingOrderRadio.IsChecked == true;
        await RenderAsync();
    }

    private async void ApplyReadingOrderButton_Click(object sender, RoutedEventArgs e)
    {
        CaptureReadingOrder();
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
        var byId = _frames.ToDictionary(frame => frame.Id);
        foreach (SpriteFrameDraft frame in _readingOrder.Where(byId.ContainsKey).Select(id => byId[id]))
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
        UserPetBackgroundRemoval? backgroundRemoval = CurrentBackgroundRemoval();
        UserPetProcessedFrame processed = await Task.Run(() =>
            UserPetPixelProcessor.Process(
                _decoded.BgraPixels,
                _decoded.Width,
                _decoded.Height,
                backgroundRemoval: backgroundRemoval));
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
