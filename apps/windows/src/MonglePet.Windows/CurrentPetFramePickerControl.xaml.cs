using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Runtime.CompilerServices;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using MonglePet.Packages;
using MonglePet.PetLibrary;

namespace MonglePet.Windows;

public sealed partial class CurrentPetFramePickerControl : UserControl
{
    private readonly ObservableCollection<FrameChoice> _frames = [];
    private readonly List<FrameChoice> _selection = [];

    public CurrentPetFramePickerControl()
    {
        InitializeComponent();
        FramesList.ItemsSource = _frames;
    }

    public bool HasSelection => _selection.Count > 0;

    public async Task LoadAsync(LoadedPetPackage package)
    {
        ArgumentNullException.ThrowIfNull(package);
        _frames.Clear();
        _selection.Clear();
        var cache = new WindowsDecodedImageCache();
        foreach (PetPackageMotion motion in package.Manifest.Motions)
        {
            LoadedPetAtlas atlas = package.Atlases[motion.Atlas];
            WindowsDecodedImage decoded = await cache.GetAsync(atlas.FilePath);
            for (int index = 0; index < motion.Frames.Count; index++)
            {
                PetPackageFrame frame = motion.Frames[index];
                UserPetProcessedFrame cropped = await Task.Run(() =>
                    UserPetPixelProcessor.Process(
                        decoded.BgraPixels,
                        decoded.Width,
                        decoded.Height,
                        frame));
                ImageSource thumbnail = await WindowsImagePreviewFactory
                    .CreateCheckerboardAsync(cropped);
                _frames.Add(new FrameChoice(
                    motion.Id,
                    index,
                    atlas.FilePath,
                    frame,
                    thumbnail));
            }
        }
        RefreshSelection();
    }

    public IReadOnlyList<UserPetFrameSourceRequest> CreateRequests() => _selection
        .Select(item => new UserPetFrameSourceRequest(
            item.AtlasPath,
            item.Frame.DurationMs,
            item.Frame,
            CanvasPlacement: new UserPetCanvasPlacement(
                item.Frame.Width,
                item.Frame.Height,
                0,
                0,
                item.Frame.Width,
                item.Frame.Height)))
        .ToArray();

    private void FramesList_ItemClick(object sender, ItemClickEventArgs e)
    {
        if (e.ClickedItem is not FrameChoice item)
        {
            return;
        }
        if (!_selection.Remove(item))
        {
            _selection.Add(item);
        }
        RefreshSelection();
    }

    private void RefreshSelection()
    {
        foreach (FrameChoice item in _frames)
        {
            int index = _selection.IndexOf(item);
            item.SelectionOrder = index < 0 ? string.Empty : (index + 1).ToString();
            item.SelectionVisibility = index < 0 ? Visibility.Collapsed : Visibility.Visible;
        }
        SelectionSummaryText.Text = _selection.Count == 0
            ? "선택한 프레임이 없습니다."
            : $"선택 {_selection.Count}개 · 클릭한 순서대로 추가됩니다.";
    }

    public sealed class FrameChoice : INotifyPropertyChanged
    {
        private string _selectionOrder = string.Empty;
        private Visibility _selectionVisibility = Visibility.Collapsed;

        public FrameChoice(
            string motionName,
            int frameIndex,
            string atlasPath,
            PetPackageFrame frame,
            ImageSource thumbnail)
        {
            MotionName = motionName;
            AtlasPath = atlasPath;
            Frame = frame;
            Thumbnail = thumbnail;
            Detail = $"프레임 {frameIndex + 1} · {frame.DurationMs}ms · {frame.Width}×{frame.Height}px";
        }

        public string MotionName { get; }
        public string AtlasPath { get; }
        public PetPackageFrame Frame { get; }
        public ImageSource Thumbnail { get; }
        public string Detail { get; }

        public string SelectionOrder
        {
            get => _selectionOrder;
            set => SetField(ref _selectionOrder, value);
        }

        public Visibility SelectionVisibility
        {
            get => _selectionVisibility;
            set => SetField(ref _selectionVisibility, value);
        }

        public event PropertyChangedEventHandler? PropertyChanged;

        private void SetField<T>(ref T field, T value, [CallerMemberName] string? name = null)
        {
            if (EqualityComparer<T>.Default.Equals(field, value))
            {
                return;
            }
            field = value;
            PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
        }
    }
}
