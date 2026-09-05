using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using MonglePet.Packages;
using MonglePet.PetLibrary;
using Windows.Foundation;
using Windows.Storage.Pickers;

namespace MonglePet.Windows;

public sealed partial class PngFrameImportControl : UserControl
{
    private readonly ObservableCollection<PngDraftItem> _items = [];
    private readonly WindowsDecodedImageCache _imageCache = new();
    private IntPtr _ownerWindow;
    private readonly int _durationMilliseconds;
    private PngDraftItem? _focused;
    private bool _isRefreshing;
    private bool _isDragging;
    private UserPetCropHandle _dragHandle;
    private Point _dragStart;
    private UserPetPixelRect _dragOriginal;
    private double _zoom = 1;
    private double _baseScale = 1;
    private bool _isPopulating;
    private readonly SemaphoreSlim _renderGate = new(1, 1);
    private long _renderRequest;

    public PngFrameImportControl(IntPtr ownerWindow, int durationMilliseconds)
    {
        InitializeComponent();
        _ownerWindow = ownerWindow;
        _durationMilliseconds = Math.Clamp(durationMilliseconds, 16, 60_000);
        PngList.ItemsSource = _items;
    }

    public nint OwnerWindowHandle
    {
        get => _ownerWindow;
        set => _ownerWindow = value;
    }

    public bool HasFrames => _items.Any(item => item.IsIncluded);

    public async Task AddFilesAsync(IEnumerable<string> paths)
    {
        var addedItems = new List<PngDraftItem>();
        _isPopulating = true;
        try
        {
            foreach (string path in paths)
            {
                string fullPath = Path.GetFullPath(path);
                if (_items.Any(item => item.Path.Equals(fullPath, StringComparison.OrdinalIgnoreCase)))
                {
                    continue;
                }
                WindowsDecodedImage image = await _imageCache.GetAsync(fullPath);
                var item = new PngDraftItem(
                    fullPath,
                    image,
                    new UserPetPixelRect(0, 0, image.Width, image.Height),
                    _durationMilliseconds);
                item.SourcePreview = await WindowsImagePreviewFactory.CreateCheckerboardAsync(
                    WindowsImagePreviewFactory.FullImage(image));
                _items.Add(item);
                await RefreshItemPreviewAsync(item);
                addedItems.Add(item);
                _focused ??= item;
            }
        }
        finally
        {
            _isPopulating = false;
        }
        if (addedItems.Count > 0)
        {
            _isPopulating = true;
            try
            {
                PngList.SelectedItems.Clear();
                foreach (PngDraftItem item in addedItems)
                {
                    PngList.SelectedItems.Add(item);
                }
            }
            finally
            {
                _isPopulating = false;
            }
            await FocusAsync(addedItems[0], forceRender: true);
        }
    }

    public IReadOnlyList<UserPetFrameSourceRequest> CreateRequests() => _items
        .Where(item => item.IsIncluded)
        .Select(item => new UserPetFrameSourceRequest(
            item.Path,
            item.DurationMilliseconds,
            new PetPackageFrame(
                item.Crop.X,
                item.Crop.Y,
                item.Crop.Width,
                item.Crop.Height,
                item.DurationMilliseconds),
            item.FlipsHorizontally,
            item.FlipsVertically,
            null,
            item.FrameId))
        .ToArray();

    private async Task FocusAsync(PngDraftItem item, bool forceRender = false)
    {
        if (!forceRender && ReferenceEquals(_focused, item))
        {
            UpdateResultPosition();
            return;
        }
        if (_focused is not null)
        {
            _focused.IsFocused = false;
        }
        _focused = item;
        item.IsFocused = true;
        _zoom = UserPetImageEditingGeometry.ClampZoom(_zoom);
        await RenderFocusedAsync();
    }

    private async Task RenderFocusedAsync()
    {
        PngDraftItem? item = _focused;
        if (item is null)
        {
            return;
        }
        long request = Interlocked.Increment(ref _renderRequest);
        await _renderGate.WaitAsync();
        try
        {
            if (request != Volatile.Read(ref _renderRequest) || !ReferenceEquals(item, _focused))
            {
                return;
            }
            _isRefreshing = true;
            WindowsDecodedImage decoded = item.Decoded;
            SourceImage.Source = item.SourcePreview;
            const double availableWidth = 500;
            const double availableHeight = 500;
            _baseScale = Math.Min(
                availableWidth / decoded.Width,
                availableHeight / decoded.Height);
            _baseScale = Math.Min(_baseScale, 1);
            if (!double.IsFinite(_baseScale) || _baseScale <= 0)
            {
                _baseScale = 1;
            }
            double displayScale = _baseScale * _zoom;
            SourceCanvas.Width = decoded.Width * displayScale;
            SourceCanvas.Height = decoded.Height * displayScale;
            SourceImage.Width = SourceCanvas.Width;
            SourceImage.Height = SourceCanvas.Height;
            Canvas.SetLeft(SourceImage, 0);
            Canvas.SetTop(SourceImage, 0);
            UserPetPixelRect crop = item.Crop;
            LayoutCropBorder(crop, displayScale);
            SourceScrollViewer.HorizontalScrollMode = _zoom > 1
                ? ScrollMode.Enabled
                : ScrollMode.Disabled;
            SourceScrollViewer.VerticalScrollMode = _zoom > 1
                ? ScrollMode.Enabled
                : ScrollMode.Disabled;
            UpdateCropNumberBoxes(crop);
            ZoomText.Text = $"{_zoom:0.##}×";
            await RefreshItemPreviewAsync(item);
            UpdateResultPosition();
        }
        catch (COMException exception) when (exception.HResult == unchecked((int)0x80000013))
        {
            item.SourcePreview = await WindowsImagePreviewFactory.CreateCheckerboardAsync(
                WindowsImagePreviewFactory.FullImage(item.Decoded));
            SourceImage.Source = item.SourcePreview;
            await RefreshItemPreviewAsync(item);
            UpdateResultPosition();
        }
        finally
        {
            _isRefreshing = false;
            _renderGate.Release();
        }
    }

    private void UpdateResultPosition()
    {
        IReadOnlyList<PngDraftItem> navigation = NavigationItems();
        int index = _focused is null ? -1 : navigation.IndexOf(_focused);
        ResultPositionText.Text = $"{Math.Max(0, index) + 1} / {Math.Max(1, navigation.Count)}";
    }

    private async Task RefreshItemPreviewAsync(PngDraftItem item)
    {
        var sourceCrop = new PetPackageFrame(
            item.Crop.X,
            item.Crop.Y,
            item.Crop.Width,
            item.Crop.Height,
            item.DurationMilliseconds);
        UserPetProcessedFrame processed = await Task.Run(() =>
            UserPetPixelProcessor.Process(
                item.Decoded.BgraPixels,
                item.Decoded.Width,
                item.Decoded.Height,
                sourceCrop,
                item.FlipsHorizontally,
                item.FlipsVertically));
        item.Thumbnail = await WindowsImagePreviewFactory.CreateCheckerboardAsync(processed);
        item.Detail = $"{item.Crop.Width}×{item.Crop.Height}px" +
            (item.FlipsHorizontally ? " · 좌우" : string.Empty) +
            (item.FlipsVertically ? " · 상하" : string.Empty);
        if (item == _focused)
        {
            IReadOnlyList<PngDraftItem> included = _items
                .Where(candidate => candidate.IsIncluded)
                .ToArray();
            int commonWidth = included.Count == 0
                ? item.Crop.Width
                : included.Max(candidate => candidate.Crop.Width);
            int commonHeight = included.Count == 0
                ? item.Crop.Height
                : included.Max(candidate => candidate.Crop.Height);
            UserPetProcessedFrame commonPreview = await Task.Run(() =>
                WindowsImagePreviewFactory.CenterOnCanvas(
                    processed,
                    commonWidth,
                    commonHeight));
            ResultImage.Source = await WindowsImagePreviewFactory
                .CreateCheckerboardAsync(commonPreview);
            double scale = Math.Min(300d / commonWidth, 190d / commonHeight);
            scale = Math.Min(scale, 1);
            ResultOuterBorder.Width = Math.Max(1, commonWidth * scale + 4);
            ResultOuterBorder.Height = Math.Max(1, commonHeight * scale + 4);
            ResultCanvas.Width = Math.Max(1, commonWidth * scale);
            ResultCanvas.Height = Math.Max(1, commonHeight * scale);
            ResultImage.Width = Math.Max(1, commonWidth * scale);
            ResultImage.Height = Math.Max(1, commonHeight * scale);
            Canvas.SetLeft(ResultImage, 0);
            Canvas.SetTop(ResultImage, 0);
        }
    }

    private IReadOnlyList<PngDraftItem> SelectedItems() => PngList.SelectedItems
        .OfType<PngDraftItem>()
        .ToArray();

    private IReadOnlyList<PngDraftItem> NavigationItems()
    {
        PngDraftItem[] selected = SelectedItems().ToArray();
        return selected.Length > 0
            ? selected
            : _items.Where(item => item.IsIncluded).ToArray();
    }

    private async void PngList_ItemClick(object sender, ItemClickEventArgs e)
    {
        try
        {
            if (e.ClickedItem is PngDraftItem item)
            {
                await FocusAsync(item);
            }
        }
        catch (Exception exception)
        {
            ShowImportError("선택한 PNG를 표시하지 못했습니다", exception);
        }
    }

    private async void PngList_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_isPopulating)
        {
            return;
        }
        try
        {
            PngDraftItem? added = e.AddedItems.OfType<PngDraftItem>().LastOrDefault();
            if (added is not null)
            {
                await FocusAsync(added);
            }
            else
            {
                UpdateResultPosition();
            }
        }
        catch (Exception exception)
        {
            ShowImportError("PNG 선택을 변경하지 못했습니다", exception);
        }
    }

    private void SourceCanvas_PointerPressed(object sender, PointerRoutedEventArgs e)
    {
        if (_focused is null)
        {
            return;
        }
        Point point = e.GetCurrentPoint(SourceCanvas).Position;
        _dragHandle = HitHandle(point);
        _dragStart = point;
        _dragOriginal = _focused.Crop;
        _isDragging = SourceCanvas.CapturePointer(e.Pointer);
        e.Handled = _isDragging;
    }

    private void SourceCanvas_PointerMoved(object sender, PointerRoutedEventArgs e)
    {
        if (!_isDragging || _focused is null)
        {
            return;
        }
        Point current = e.GetCurrentPoint(SourceCanvas).Position;
        double scale = _baseScale * _zoom;
        int deltaX = (int)Math.Round((current.X - _dragStart.X) / scale);
        int deltaY = (int)Math.Round((current.Y - _dragStart.Y) / scale);
        _focused.Crop = UserPetImageEditingGeometry.DragCrop(
            _dragOriginal,
            _dragHandle,
            deltaX,
            deltaY,
            _focused.Decoded.Width,
            _focused.Decoded.Height);
        LayoutCropBorder(_focused.Crop, scale);
        UpdateCropNumberBoxes(_focused.Crop);
        e.Handled = true;
    }

    private async void SourceCanvas_PointerReleased(object sender, PointerRoutedEventArgs e)
    {
        if (!_isDragging)
        {
            return;
        }
        _isDragging = false;
        SourceCanvas.ReleasePointerCapture(e.Pointer);
        if (_focused is not null)
        {
            await RenderFocusedAsync();
        }
        e.Handled = true;
    }

    private UserPetCropHandle HitHandle(Point point)
    {
        double scale = _baseScale * _zoom;
        UserPetPixelRect crop = _focused!.Crop;
        double left = crop.X * scale;
        double top = crop.Y * scale;
        double right = crop.Right * scale;
        double bottom = crop.Bottom * scale;
        const double tolerance = 10;
        bool nearLeft = Math.Abs(point.X - left) <= tolerance;
        bool nearRight = Math.Abs(point.X - right) <= tolerance;
        bool nearTop = Math.Abs(point.Y - top) <= tolerance;
        bool nearBottom = Math.Abs(point.Y - bottom) <= tolerance;
        if (nearLeft && nearTop) return UserPetCropHandle.TopLeft;
        if (nearRight && nearTop) return UserPetCropHandle.TopRight;
        if (nearRight && nearBottom) return UserPetCropHandle.BottomRight;
        if (nearLeft && nearBottom) return UserPetCropHandle.BottomLeft;
        if (nearTop) return UserPetCropHandle.Top;
        if (nearRight) return UserPetCropHandle.Right;
        if (nearBottom) return UserPetCropHandle.Bottom;
        if (nearLeft) return UserPetCropHandle.Left;
        return UserPetCropHandle.Move;
    }

    private void LayoutCropBorder(UserPetPixelRect crop, double displayScale)
    {
        CropBorder.Width = crop.Width * displayScale;
        CropBorder.Height = crop.Height * displayScale;
        Canvas.SetLeft(CropBorder, crop.X * displayScale);
        Canvas.SetTop(CropBorder, crop.Y * displayScale);
    }

    private void UpdateCropNumberBoxes(UserPetPixelRect crop)
    {
        if (_focused is null)
        {
            return;
        }
        bool wasRefreshing = _isRefreshing;
        _isRefreshing = true;
        try
        {
            CropXNumberBox.Maximum = _focused.Decoded.Width - 1;
            CropYNumberBox.Maximum = _focused.Decoded.Height - 1;
            CropWidthNumberBox.Maximum = _focused.Decoded.Width;
            CropHeightNumberBox.Maximum = _focused.Decoded.Height;
            CropXNumberBox.Value = crop.X;
            CropYNumberBox.Value = crop.Y;
            CropWidthNumberBox.Value = crop.Width;
            CropHeightNumberBox.Value = crop.Height;
        }
        finally
        {
            _isRefreshing = wasRefreshing;
        }
    }

    private async void CropNumberBox_ValueChanged(NumberBox sender, NumberBoxValueChangedEventArgs args)
    {
        if (_isRefreshing || _focused is null || double.IsNaN(sender.Value))
        {
            return;
        }
        var requested = new UserPetPixelRect(
            (int)CropXNumberBox.Value,
            (int)CropYNumberBox.Value,
            Math.Max(1, (int)CropWidthNumberBox.Value),
            Math.Max(1, (int)CropHeightNumberBox.Value));
        _focused.Crop = UserPetImageEditingGeometry.ClampCrop(
            requested,
            _focused.Decoded.Width,
            _focused.Decoded.Height);
        await RenderFocusedAsync();
    }

    private async void FitVisiblePixelsButton_Click(object sender, RoutedEventArgs e)
    {
        foreach (PngDraftItem item in SelectedItems().DefaultIfEmpty(_focused).OfType<PngDraftItem>())
        {
            item.Crop = item.VisibleBounds;
            await RefreshItemPreviewAsync(item);
        }
        await RenderFocusedAsync();
    }

    private async void RestoreFullImageButton_Click(object sender, RoutedEventArgs e)
    {
        foreach (PngDraftItem item in SelectedItems().DefaultIfEmpty(_focused).OfType<PngDraftItem>())
        {
            item.Crop = new UserPetPixelRect(0, 0, item.Decoded.Width, item.Decoded.Height);
            await RefreshItemPreviewAsync(item);
        }
        await RenderFocusedAsync();
    }

    private async void FlipHorizontalButton_Click(object sender, RoutedEventArgs e)
    {
        foreach (PngDraftItem item in SelectedItems().DefaultIfEmpty(_focused).OfType<PngDraftItem>())
        {
            item.FlipsHorizontally = !item.FlipsHorizontally;
            await RefreshItemPreviewAsync(item);
        }
        await RenderFocusedAsync();
    }

    private async void FlipVerticalButton_Click(object sender, RoutedEventArgs e)
    {
        foreach (PngDraftItem item in SelectedItems().DefaultIfEmpty(_focused).OfType<PngDraftItem>())
        {
            item.FlipsVertically = !item.FlipsVertically;
            await RefreshItemPreviewAsync(item);
        }
        await RenderFocusedAsync();
    }

    private async void ApplyCurrentSizeButton_Click(object sender, RoutedEventArgs e)
    {
        if (_focused is null)
        {
            return;
        }
        foreach (PngDraftItem item in SelectedItems().Where(item => item != _focused))
        {
            item.Crop = UserPetImageEditingGeometry.ClampCrop(
                item.Crop with
                {
                    Width = Math.Min(_focused.Crop.Width, item.Decoded.Width),
                    Height = Math.Min(_focused.Crop.Height, item.Decoded.Height),
                },
                item.Decoded.Width,
                item.Decoded.Height);
            await RefreshItemPreviewAsync(item);
        }
        await RenderFocusedAsync();
    }

    private async void AddMorePngButton_Click(object sender, RoutedEventArgs e)
    {
        if (_ownerWindow == nint.Zero)
        {
            return;
        }
        try
        {
            var picker = new FileOpenPicker
            {
                SuggestedStartLocation = PickerLocationId.PicturesLibrary,
                ViewMode = PickerViewMode.Thumbnail,
            };
            picker.FileTypeFilter.Add(".png");
            WinRT.Interop.InitializeWithWindow.Initialize(picker, _ownerWindow);
            IReadOnlyList<global::Windows.Storage.StorageFile> files = await picker.PickMultipleFilesAsync();
            await AddFilesAsync(files.Select(file => file.Path));
            ImportInfoBar.IsOpen = false;
        }
        catch (Exception exception)
        {
            ShowImportError("PNG를 더 추가하지 못했습니다", exception);
        }
    }

    private async void PngIncludedCheckBox_Changed(object sender, RoutedEventArgs e)
    {
        if (_isPopulating || sender is not CheckBox { DataContext: PngDraftItem item } checkBox)
        {
            return;
        }
        item.IsIncluded = checkBox.IsChecked == true;
        if (_focused is not null)
        {
            await RenderFocusedAsync();
        }
    }

    private async void RemovePngButton_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not Button { DataContext: PngDraftItem item })
        {
            return;
        }
        int index = _items.IndexOf(item);
        bool wasFocused = ReferenceEquals(item, _focused);
        _items.Remove(item);
        if (!wasFocused)
        {
            if (_focused is not null)
            {
                await RenderFocusedAsync();
            }
            return;
        }
        _focused = null;
        if (_items.Count == 0)
        {
            SourceImage.Source = null;
            ResultImage.Source = null;
            ResultPositionText.Text = "선택 없음";
            return;
        }
        await FocusAsync(_items[Math.Min(index, _items.Count - 1)], forceRender: true);
    }

    private void ShowImportError(string title, Exception exception)
    {
        ImportInfoBar.Title = title;
        ImportInfoBar.Message = exception.Message;
        ImportInfoBar.Severity = InfoBarSeverity.Error;
        ImportInfoBar.IsOpen = true;
    }

    private void SelectAllButton_Click(object sender, RoutedEventArgs e)
    {
        _isPopulating = true;
        try
        {
            foreach (PngDraftItem item in _items)
            {
                item.IsIncluded = true;
            }
        }
        finally
        {
            _isPopulating = false;
        }
        _focused ??= _items.FirstOrDefault();
        if (_focused is not null)
        {
            _ = RenderFocusedAsync();
        }
    }

    private void DeselectAllButton_Click(object sender, RoutedEventArgs e)
    {
        _isPopulating = true;
        try
        {
            foreach (PngDraftItem item in _items)
            {
                item.IsIncluded = false;
            }
        }
        finally
        {
            _isPopulating = false;
        }
        if (_focused is not null)
        {
            _ = RenderFocusedAsync();
        }
    }

    private async void PreviousResultButton_Click(object sender, RoutedEventArgs e) =>
        await NavigateAsync(-1);

    private async void NextResultButton_Click(object sender, RoutedEventArgs e) =>
        await NavigateAsync(1);

    private async Task NavigateAsync(int offset)
    {
        IReadOnlyList<PngDraftItem> items = NavigationItems();
        if (items.Count == 0)
        {
            return;
        }
        int index = _focused is null ? 0 : items.IndexOf(_focused);
        index = (index + offset + items.Count) % items.Count;
        await FocusAsync(items[index]);
    }

    private async void ZoomOutButton_Click(object sender, RoutedEventArgs e)
    {
        _zoom = UserPetImageEditingGeometry.ClampZoom(_zoom - 0.5);
        await RenderFocusedAsync();
    }

    private async void ZoomInButton_Click(object sender, RoutedEventArgs e)
    {
        _zoom = UserPetImageEditingGeometry.ClampZoom(_zoom + 0.5);
        await RenderFocusedAsync();
    }

    private async void FitButton_Click(object sender, RoutedEventArgs e)
    {
        _zoom = 1;
        await RenderFocusedAsync();
    }

    private sealed class PngDraftItem : INotifyPropertyChanged
    {
        private ImageSource? _thumbnail;
        private string _detail = string.Empty;
        private bool _isFocused;
        private bool _isIncluded = true;

        public PngDraftItem(
            string path,
            WindowsDecodedImage decoded,
            UserPetPixelRect crop,
            int durationMilliseconds)
        {
            Path = path;
            Decoded = decoded;
            Crop = crop;
            VisibleBounds = UserPetImageEditingGeometry.FindVisibleBounds(
                decoded.BgraPixels,
                decoded.Width,
                decoded.Height) ?? crop;
            DurationMilliseconds = durationMilliseconds;
            FrameId = Guid.NewGuid();
        }

        public string Path { get; }
        public string FileName => System.IO.Path.GetFileName(Path);
        public WindowsDecodedImage Decoded { get; }
        public int DurationMilliseconds { get; }
        public Guid FrameId { get; }
        public UserPetPixelRect Crop { get; set; }
        public UserPetPixelRect VisibleBounds { get; }
        public bool FlipsHorizontally { get; set; }
        public bool FlipsVertically { get; set; }

        public bool IsIncluded
        {
            get => _isIncluded;
            set => SetField(ref _isIncluded, value);
        }

        public ImageSource? Thumbnail
        {
            get => _thumbnail;
            set => SetField(ref _thumbnail, value);
        }

        public ImageSource? SourcePreview { get; set; }

        public string Detail
        {
            get => _detail;
            set => SetField(ref _detail, value);
        }

        public bool IsFocused
        {
            get => _isFocused;
            set
            {
                if (SetField(ref _isFocused, value))
                {
                    PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(FocusBorderThickness)));
                }
            }
        }

        public Thickness FocusBorderThickness => IsFocused ? new Thickness(2) : new Thickness(0);

        public event PropertyChangedEventHandler? PropertyChanged;

        private bool SetField<T>(ref T field, T value, [CallerMemberName] string? name = null)
        {
            if (EqualityComparer<T>.Default.Equals(field, value))
            {
                return false;
            }
            field = value;
            PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
            return true;
        }
    }
}

internal static class PngDraftItemListExtensions
{
    public static int IndexOf<T>(this IReadOnlyList<T> values, T value)
    {
        for (int index = 0; index < values.Count; index++)
        {
            if (EqualityComparer<T>.Default.Equals(values[index], value))
            {
                return index;
            }
        }
        return -1;
    }
}
