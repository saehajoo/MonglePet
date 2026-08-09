using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Runtime.CompilerServices;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using MonglePet.Packages;
using MonglePet.PetLibrary;
using Windows.Storage.Pickers;
using Windows.Graphics.Imaging;

namespace MonglePet.Windows;

public sealed partial class PetAnimationEditorControl : UserControl
{
    private readonly ObservableCollection<FrameItem> _frames = [];

    public PetAnimationEditorControl()
    {
        InitializeComponent();
        FramesList.ItemsSource = _frames;
        VersionTextBox.Text = "1.0.0";
        AuthorTextBox.Text = "MonglePet 사용자";
        DescriptionTextBox.Text = "MonglePet에서 사용자가 만든 펫입니다.";
        AnimationNameTextBox.Text = "기본";
    }

    public void ConfigureForAnimation(LoadedPetPackage package, PetPackageMotion? motion)
    {
        PetInformationCard.Visibility = Visibility.Collapsed;
        if (motion is null)
        {
            AnimationNameTextBox.Text = string.Empty;
            return;
        }

        AnimationNameTextBox.Text = motion.Id;
        LoopsToggle.IsOn = motion.Loop;
        LoadedPetAtlas atlas = package.Atlases[motion.Atlas];
        foreach (PetPackageFrame frame in motion.Frames)
        {
            _frames.Add(new FrameItem(
                atlas.FilePath,
                frame.DurationMs,
                frame,
                "기존 atlas 프레임"));
        }
        RefreshIndexes();
    }

    public UserPetCreationRequest CreatePetRequest() => new(
        PetNameTextBox.Text,
        AnimationNameTextBox.Text,
        LoopsToggle.IsOn,
        FrameRequests(),
        VersionTextBox.Text,
        AuthorTextBox.Text,
        DescriptionTextBox.Text);

    public UserPetAnimationRequest CreateAnimationRequest() => new(
        AnimationNameTextBox.Text,
        LoopsToggle.IsOn,
        FrameRequests());

    public UserPetAnimationUpdateRequest CreateAnimationUpdateRequest(string animationId) => new(
        animationId,
        AnimationNameTextBox.Text,
        LoopsToggle.IsOn,
        FrameRequests());

    private IReadOnlyList<UserPetFrameSourceRequest> FrameRequests() => _frames
        .Select(frame => new UserPetFrameSourceRequest(
            frame.ImagePath,
            Math.Clamp(frame.DurationMilliseconds, 16, 60_000),
            frame.SourceFrame))
        .ToArray();

    private async void ChooseFramesButton_Click(object sender, RoutedEventArgs e)
    {
        if (Application.Current is not App { MainWindowHandle: not 0 } app)
        {
            return;
        }
        var picker = new FileOpenPicker
        {
            SuggestedStartLocation = PickerLocationId.PicturesLibrary,
            ViewMode = PickerViewMode.Thumbnail,
        };
        picker.FileTypeFilter.Add(".png");
        WinRT.Interop.InitializeWithWindow.Initialize(picker, app.MainWindowHandle);
        IReadOnlyList<global::Windows.Storage.StorageFile> files = await picker.PickMultipleFilesAsync();
        int duration = (int)Math.Clamp(NewFrameDurationNumberBox.Value, 16, 60_000);
        foreach (global::Windows.Storage.StorageFile file in files)
        {
            _frames.Add(new FrameItem(file.Path, duration, null, "개별 PNG"));
        }
        RefreshIndexes();
        if (_frames.Count > 0)
        {
            FramesList.SelectedIndex = _frames.Count - 1;
        }
    }

    private async void ChooseSpriteSheetButton_Click(object sender, RoutedEventArgs e)
    {
        if (Application.Current is not App { MainWindowHandle: not 0 } app)
        {
            return;
        }
        var picker = new FileOpenPicker
        {
            SuggestedStartLocation = PickerLocationId.PicturesLibrary,
            ViewMode = PickerViewMode.Thumbnail,
        };
        picker.FileTypeFilter.Add(".png");
        picker.FileTypeFilter.Add(".webp");
        WinRT.Interop.InitializeWithWindow.Initialize(picker, app.MainWindowHandle);
        global::Windows.Storage.StorageFile? file = await picker.PickSingleFileAsync();
        if (file is null)
        {
            return;
        }

        uint pixelWidth;
        uint pixelHeight;
        using (global::Windows.Storage.Streams.IRandomAccessStream stream =
               await file.OpenAsync(global::Windows.Storage.FileAccessMode.Read))
        {
            BitmapDecoder decoder = await BitmapDecoder.CreateAsync(stream);
            pixelWidth = decoder.PixelWidth;
            pixelHeight = decoder.PixelHeight;
        }

        var columns = new NumberBox
        {
            Header = "열 수",
            Minimum = 1,
            Maximum = Math.Max(1, pixelWidth),
            Value = 1,
            SpinButtonPlacementMode = NumberBoxSpinButtonPlacementMode.Compact,
        };
        var rows = new NumberBox
        {
            Header = "행 수",
            Minimum = 1,
            Maximum = Math.Max(1, pixelHeight),
            Value = 1,
            SpinButtonPlacementMode = NumberBoxSpinButtonPlacementMode.Compact,
        };
        var panel = new StackPanel { Width = 440, Spacing = 10 };
        panel.Children.Add(new TextBlock
        {
            Text = $"{file.Name} · {pixelWidth}×{pixelHeight}px\n왼쪽 위부터 행 순서로 동일한 크기의 프레임을 나눕니다.",
            TextWrapping = TextWrapping.Wrap,
        });
        panel.Children.Add(columns);
        panel.Children.Add(rows);
        var dialog = new ContentDialog
        {
            XamlRoot = XamlRoot,
            Title = "스프라이트 시트 프레임 확인",
            Content = panel,
            PrimaryButtonText = "프레임 추가",
            CloseButtonText = "취소",
            DefaultButton = ContentDialogButton.Primary,
        };
        if (await dialog.ShowAsync() != ContentDialogResult.Primary)
        {
            return;
        }

        int columnCount = (int)columns.Value;
        int rowCount = (int)rows.Value;
        if (columnCount <= 0 || rowCount <= 0 ||
            pixelWidth % (uint)columnCount != 0 || pixelHeight % (uint)rowCount != 0)
        {
            await new ContentDialog
            {
                XamlRoot = XamlRoot,
                Title = "프레임을 나눌 수 없습니다",
                Content = "이미지 너비와 높이가 입력한 열·행 수로 정확히 나누어져야 합니다.",
                CloseButtonText = "확인",
            }.ShowAsync();
            return;
        }

        int frameWidth = checked((int)pixelWidth / columnCount);
        int frameHeight = checked((int)pixelHeight / rowCount);
        int duration = (int)Math.Clamp(NewFrameDurationNumberBox.Value, 16, 60_000);
        for (int row = 0; row < rowCount; row++)
        {
            for (int column = 0; column < columnCount; column++)
            {
                var source = new PetPackageFrame(
                    column * frameWidth,
                    row * frameHeight,
                    frameWidth,
                    frameHeight,
                    duration);
                _frames.Add(new FrameItem(file.Path, duration, source, "스프라이트 시트 프레임"));
            }
        }
        RefreshIndexes();
        FramesList.SelectedIndex = _frames.Count - 1;
    }

    private void MoveFrameUpButton_Click(object sender, RoutedEventArgs e) => MoveSelected(-1);

    private void MoveFrameDownButton_Click(object sender, RoutedEventArgs e) => MoveSelected(1);

    private void MoveSelected(int offset)
    {
        int source = FramesList.SelectedIndex;
        int destination = source + offset;
        if (source < 0 || destination < 0 || destination >= _frames.Count)
        {
            return;
        }
        _frames.Move(source, destination);
        RefreshIndexes();
        FramesList.SelectedIndex = destination;
    }

    private void RemoveFrameButton_Click(object sender, RoutedEventArgs e)
    {
        int index = FramesList.SelectedIndex;
        if (index < 0)
        {
            return;
        }
        _frames.RemoveAt(index);
        RefreshIndexes();
        if (_frames.Count > 0)
        {
            FramesList.SelectedIndex = Math.Min(index, _frames.Count - 1);
        }
    }

    private void RefreshIndexes()
    {
        for (int index = 0; index < _frames.Count; index++)
        {
            _frames[index].DisplayIndex = $"{index + 1}.";
        }
    }

    public sealed class FrameItem : INotifyPropertyChanged
    {
        private string _displayIndex = string.Empty;
        private int _durationMilliseconds;

        public FrameItem(
            string imagePath,
            int durationMilliseconds,
            PetPackageFrame? sourceFrame,
            string sourceDetail)
        {
            ImagePath = imagePath;
            FileName = Path.GetFileName(imagePath);
            _durationMilliseconds = durationMilliseconds;
            SourceFrame = sourceFrame;
            SourceDetail = sourceDetail;
        }

        public string ImagePath { get; }
        public string FileName { get; }
        public PetPackageFrame? SourceFrame { get; }
        public string SourceDetail { get; }

        public string DisplayIndex
        {
            get => _displayIndex;
            set => SetField(ref _displayIndex, value);
        }

        public int DurationMilliseconds
        {
            get => _durationMilliseconds;
            set => SetField(ref _durationMilliseconds, value);
        }

        public event PropertyChangedEventHandler? PropertyChanged;

        private void SetField<T>(ref T field, T value, [CallerMemberName] string? propertyName = null)
        {
            if (EqualityComparer<T>.Default.Equals(field, value))
            {
                return;
            }
            field = value;
            PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
        }
    }
}
