using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Runtime.CompilerServices;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Microsoft.UI.Xaml.Input;
using MonglePet.Packages;
using MonglePet.PetLibrary;
using MonglePet.Settings;
using Windows.Foundation;
using Windows.Storage.Pickers;

namespace MonglePet.Windows;

public sealed partial class PetAnimationEditorControl : UserControl
{
    private readonly ObservableCollection<FrameItem> _frames = [];
    private readonly WindowsDecodedImageCache _imageCache = new();
    private bool _isRefreshingPlacement;
    private bool _isDraggingPlacement;
    private UserPetCropHandle _placementDragHandle;
    private Point _placementDragStart;
    private UserPetPixelRect _placementDragOriginal;
    private double _placementDisplayScale = 1;
    private double _placementDisplayX;
    private double _placementDisplayY;
    private bool _isReady;
    private LoadedPetPackage? _sourcePackage;

    public PetAnimationEditorControl()
    {
        InitializeComponent();
        FramesList.ItemsSource = _frames;
        VersionTextBox.Text = "1.0.0";
        AuthorTextBox.Text = "MonglePet 사용자";
        DescriptionTextBox.Text = "MonglePet에서 사용자가 만든 펫입니다.";
        AnimationNameTextBox.Text = "기본";
        BehaviorConnectionModeComboBox.SelectedIndex = 0;
        _isReady = true;
        RefreshFrameEditorVisibility();
    }

    public nint OwnerWindowHandle { get; set; }

    public string? ValidationError(bool requiresPetInformation)
    {
        if (requiresPetInformation && string.IsNullOrWhiteSpace(PetNameTextBox.Text))
        {
            return "펫 이름을 입력해 주세요.";
        }
        if (requiresPetInformation && !UserPetPackageEditor.IsValidEditableVersion(VersionTextBox.Text))
        {
            return "펫 버전은 1.0.0처럼 MAJOR.MINOR.PATCH 형식으로 입력해 주세요.";
        }
        if (requiresPetInformation && string.IsNullOrWhiteSpace(AuthorTextBox.Text))
        {
            return "제작자를 입력해 주세요.";
        }
        if (string.IsNullOrWhiteSpace(AnimationNameTextBox.Text))
        {
            return "애니메이션 이름을 입력해 주세요.";
        }
        if (_frames.Count == 0)
        {
            return "PNG 또는 스프라이트 시트에서 프레임을 하나 이상 추가해 주세요.";
        }
        if (_frames.Any(frame => frame.DurationMilliseconds is < 16 or > 60_000))
        {
            return "프레임 간격은 16~60000ms 사이여야 합니다.";
        }
        if (BehaviorConnectionCard.Visibility == Visibility.Visible &&
            ConnectionMode() == AnimationBehaviorConnectionMode.CreateNew)
        {
            string behaviorName = string.IsNullOrWhiteSpace(NewBehaviorNameTextBox.Text)
                ? AnimationNameTextBox.Text.Trim()
                : NewBehaviorNameTextBox.Text.Trim();
            if (_behaviorProfile?.Sequences.Any(sequence => string.Equals(
                    sequence.DisplayName,
                    behaviorName,
                    StringComparison.OrdinalIgnoreCase)) == true)
            {
                return "같은 이름의 행동이 이미 있습니다.";
            }
        }
        if (BehaviorConnectionCard.Visibility == Visibility.Visible &&
            ConnectionMode() == AnimationBehaviorConnectionMode.AppendExisting &&
            ExistingBehaviorComboBox.SelectedValue is not string)
        {
            return "애니메이션을 추가할 기존 행동을 선택해 주세요.";
        }
        return null;
    }

    private BehaviorProfile? _behaviorProfile;

    public void ConfigureBehaviorConnection(
        BehaviorProfile profile,
        string? currentMotionId = null)
    {
        _behaviorProfile = profile;
        BehaviorConnectionCard.Visibility = Visibility.Visible;
        ExistingBehaviorComboBox.ItemsSource = profile.Sequences;
        ExistingBehaviorComboBox.SelectedIndex = profile.Sequences.Count > 0 ? 0 : -1;
        string[] users = currentMotionId is null
            ? []
            : profile.Sequences
                .Where(sequence => sequence.Steps.Any(step => string.Equals(
                    step.MotionId,
                    currentMotionId,
                    StringComparison.Ordinal)))
                .Select(sequence => sequence.DisplayName)
                .ToArray();
        BehaviorConnectionUsageText.Text = users.Length == 0
            ? "애니메이션 저장과 함께 행동을 연결할 수 있습니다. 저장하기 전에는 행동 설정을 바꾸지 않습니다."
            : $"현재 사용하는 행동: {string.Join(", ", users)}\n저장하면서 다른 행동에도 연결할 수 있습니다.";
    }

    internal AnimationBehaviorConnectionRequest BehaviorConnectionRequest()
    {
        AnimationBehaviorConnectionMode mode = ConnectionMode();
        string? name = string.IsNullOrWhiteSpace(NewBehaviorNameTextBox.Text)
            ? AnimationNameTextBox.Text.Trim()
            : NewBehaviorNameTextBox.Text.Trim();
        return new AnimationBehaviorConnectionRequest(
            mode,
            mode == AnimationBehaviorConnectionMode.CreateNew ? name : null,
            mode == AnimationBehaviorConnectionMode.AppendExisting
                ? ExistingBehaviorComboBox.SelectedValue as string
                : null);
    }

    private AnimationBehaviorConnectionMode ConnectionMode() =>
        (BehaviorConnectionModeComboBox.SelectedItem as ComboBoxItem)?.Tag?.ToString() switch
        {
            "new" => AnimationBehaviorConnectionMode.CreateNew,
            "existing" => AnimationBehaviorConnectionMode.AppendExisting,
            _ => AnimationBehaviorConnectionMode.None,
        };

    private void BehaviorConnectionModeComboBox_SelectionChanged(
        object sender,
        SelectionChangedEventArgs e)
    {
        if (NewBehaviorNameTextBox is null || ExistingBehaviorComboBox is null)
        {
            return;
        }
        AnimationBehaviorConnectionMode mode = ConnectionMode();
        NewBehaviorNameTextBox.Visibility = mode == AnimationBehaviorConnectionMode.CreateNew
            ? Visibility.Visible
            : Visibility.Collapsed;
        ExistingBehaviorComboBox.Visibility = mode == AnimationBehaviorConnectionMode.AppendExisting
            ? Visibility.Visible
            : Visibility.Collapsed;
    }

    public async Task ConfigureForAnimationAsync(LoadedPetPackage package, PetPackageMotion? motion)
    {
        _sourcePackage = package;
        PetInformationCard.Visibility = Visibility.Collapsed;
        if (motion is null)
        {
            AnimationNameTextBox.Text = string.Empty;
            RefreshFrameEditorVisibility();
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
        await InitializeUnplacedFramePlacementsAsync();
        await RefreshFrameThumbnailsAsync(_frames);
        if (_frames.Count > 0)
        {
            FramesList.SelectedIndex = 0;
        }
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

    public void SetAnimationName(string value) => AnimationNameTextBox.Text = value;

    public UserPetAnimationUpdateRequest CreateAnimationUpdateRequest(string animationId) => new(
        animationId,
        AnimationNameTextBox.Text,
        LoopsToggle.IsOn,
        FrameRequests());

    private IReadOnlyList<UserPetFrameSourceRequest> FrameRequests()
    {
        NormalizeCommonCanvas();
        return _frames
            .Select(frame => new UserPetFrameSourceRequest(
                frame.ImagePath,
                Math.Clamp(frame.DurationMilliseconds, 16, 60_000),
                frame.SourceFrame,
                frame.FlipsHorizontally,
                frame.FlipsVertically,
                frame.CanvasPlacement,
                frame.FrameId,
                frame.BackgroundRemoval))
            .ToArray();
    }

    private async void ChooseCurrentPetFramesButton_Click(object sender, RoutedEventArgs e)
    {
        nint ownerWindow = EffectiveOwnerWindowHandle();
        if (ownerWindow == nint.Zero || _sourcePackage is not { } package)
        {
            return;
        }
        try
        {
            var picker = new CurrentPetFramePickerControl();
            await picker.LoadAsync(package);
            var window = new EditorWindowHost(
                "현재 펫 프레임에서 추가",
                "이미 저장된 애니메이션 프레임을 클릭한 순서대로 새 애니메이션에 복사합니다.",
                picker,
                "선택 프레임 추가",
                "취소하면 현재 편집 중인 프레임 목록도 바뀌지 않습니다.",
                width: 820,
                height: 720,
                validation: () => picker.HasSelection ? null : "추가할 프레임을 하나 이상 선택해 주세요.");
            if (!await window.ShowAsync(ownerWindow))
            {
                return;
            }
            foreach (UserPetFrameSourceRequest request in picker.CreateRequests())
            {
                _frames.Add(new FrameItem(
                    request.ImagePath,
                    request.DurationMilliseconds,
                    request.SourceFrame,
                    "현재 펫 프레임",
                    request.FlipsHorizontally,
                    request.FlipsVertically,
                    request.CanvasPlacement,
                    request.FrameId,
                    request.BackgroundRemoval));
            }
            RefreshIndexes();
            await InitializeUnplacedFramePlacementsAsync();
            NormalizeCommonCanvas();
            await RefreshFrameThumbnailsAsync(_frames);
            RefreshFrameEditorVisibility();
            FramesList.SelectedIndex = _frames.Count - 1;
            EditorInfoBar.IsOpen = false;
        }
        catch (Exception exception)
        {
            ShowEditorError("현재 펫 프레임을 불러오지 못했습니다", exception);
        }
    }

    private async void ChooseFramesButton_Click(object sender, RoutedEventArgs e)
    {
        nint ownerWindow = EffectiveOwnerWindowHandle();
        if (ownerWindow == nint.Zero)
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
            WinRT.Interop.InitializeWithWindow.Initialize(picker, ownerWindow);
            IReadOnlyList<global::Windows.Storage.StorageFile> files = await picker.PickMultipleFilesAsync();
            if (files.Count == 0)
            {
                return;
            }
            int duration = (int)Math.Clamp(NewFrameDurationNumberBox.Value, 16, 60_000);
            var editor = new PngFrameImportControl(ownerWindow, duration);
            await editor.AddFilesAsync(files.Select(file => file.Path));
            var window = new EditorWindowHost(
                "PNG 프레임 자르기",
                "여러 PNG를 함께 확인하고 프레임마다 사용할 원본 범위를 조정합니다.",
                editor,
                "잘라서 프레임 추가",
                "체크한 PNG만 추가하며 행 선택은 현재 편집 및 일괄 편집 대상을 정합니다.",
                width: 1_040,
                height: 760,
                validation: () => editor.HasFrames ? null : "추가할 PNG가 없습니다.");
            editor.OwnerWindowHandle = window.WindowHandle;
            if (!await window.ShowAsync(ownerWindow))
            {
                return;
            }
            foreach (UserPetFrameSourceRequest request in editor.CreateRequests())
            {
                _frames.Add(new FrameItem(
                    request.ImagePath,
                    request.DurationMilliseconds,
                    request.SourceFrame,
                    "개별 PNG crop",
                    request.FlipsHorizontally,
                    request.FlipsVertically,
                    request.CanvasPlacement,
                    request.FrameId,
                    request.BackgroundRemoval));
            }
            RefreshIndexes();
            await InitializeUnplacedFramePlacementsAsync();
            NormalizeCommonCanvas();
            await RefreshFrameThumbnailsAsync(_frames);
            RefreshFrameEditorVisibility();
            FramesList.SelectedIndex = _frames.Count - 1;
            EditorInfoBar.IsOpen = false;
        }
        catch (Exception exception)
        {
            ShowEditorError("PNG 프레임을 열지 못했습니다", exception);
        }
    }

    private async void ChooseSpriteSheetButton_Click(object sender, RoutedEventArgs e)
    {
        nint ownerWindow = EffectiveOwnerWindowHandle();
        if (ownerWindow == nint.Zero)
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
            picker.FileTypeFilter.Add(".webp");
            WinRT.Interop.InitializeWithWindow.Initialize(picker, ownerWindow);
            global::Windows.Storage.StorageFile? file = await picker.PickSingleFileAsync();
            if (file is null)
            {
                return;
            }
            int duration = (int)Math.Clamp(NewFrameDurationNumberBox.Value, 16, 60_000);
            SpriteSheetImportControl editor = await SpriteSheetImportControl.CreateAsync(
                file.Path,
                duration);
            var window = new EditorWindowHost(
                "스프라이트 시트 가져오기",
                $"{Path.GetFileName(file.Path)} · 프레임 경계와 재생 순서를 확인합니다.",
                editor,
                "프레임 저장 및 추가",
                "정적 PNG·WebP만 지원하며 취소하면 원본과 기존 프레임은 변경되지 않습니다.",
                width: 1_040,
                height: 760,
                validation: () => editor.HasSelectedFrames ? null : "가져올 프레임을 하나 이상 선택해 주세요.");
            if (!await window.ShowAsync(ownerWindow))
            {
                return;
            }
            IReadOnlyList<UserPetFrameSourceRequest> requests = editor.CreateRequests();
            foreach (UserPetFrameSourceRequest request in requests)
            {
                _frames.Add(new FrameItem(
                    request.ImagePath,
                    request.DurationMilliseconds,
                    request.SourceFrame,
                    "스프라이트 시트 프레임",
                    request.FlipsHorizontally,
                    request.FlipsVertically,
                    request.CanvasPlacement,
                    request.FrameId,
                    request.BackgroundRemoval));
            }
            RefreshIndexes();
            await InitializeUnplacedFramePlacementsAsync();
            NormalizeCommonCanvas();
            await RefreshFrameThumbnailsAsync(_frames);
            RefreshFrameEditorVisibility();
            FramesList.SelectedIndex = _frames.Count - 1;
            EditorInfoBar.IsOpen = false;
        }
        catch (Exception exception)
        {
            ShowEditorError("스프라이트 시트를 열지 못했습니다", exception);
        }
    }

    private nint EffectiveOwnerWindowHandle() => OwnerWindowHandle != nint.Zero
        ? OwnerWindowHandle
        : Application.Current is App app
            ? app.MainWindowHandle
            : nint.Zero;

    private void ShowEditorError(string title, Exception exception)
    {
        EditorInfoBar.Title = title;
        EditorInfoBar.Message = exception.Message;
        EditorInfoBar.Severity = InfoBarSeverity.Error;
        EditorInfoBar.IsOpen = true;
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

    private void DuplicateFrameButton_Click(object sender, RoutedEventArgs e)
    {
        int index = FramesList.SelectedIndex;
        if (index < 0)
        {
            return;
        }
        _frames.Insert(index + 1, _frames[index].IndependentCopy());
        RefreshIndexes();
        FramesList.SelectedIndex = index + 1;
    }

    private async void FlipFrameHorizontalButton_Click(object sender, RoutedEventArgs e)
    {
        if (FramesList.SelectedItem is not FrameItem selected)
        {
            return;
        }
        selected.FlipsHorizontally = !selected.FlipsHorizontally;
        await RefreshPlacementEditorAsync();
    }

    private async void FlipFrameVerticalButton_Click(object sender, RoutedEventArgs e)
    {
        if (FramesList.SelectedItem is not FrameItem selected)
        {
            return;
        }
        selected.FlipsVertically = !selected.FlipsVertically;
        await RefreshPlacementEditorAsync();
    }

    private async void ResetFrameDirectionButton_Click(object sender, RoutedEventArgs e)
    {
        if (FramesList.SelectedItem is not FrameItem selected)
        {
            return;
        }
        selected.FlipsHorizontally = false;
        selected.FlipsVertically = false;
        await RefreshPlacementEditorAsync();
    }

    private async void PlacementZoomSlider_ValueChanged(
        object sender,
        RangeBaseValueChangedEventArgs e)
    {
        if (!_isReady || _isRefreshingPlacement ||
            FramesList.SelectedItem is not FrameItem selected ||
            selected.CanvasPlacement is not { } placement)
        {
            return;
        }
        double scalePercent = Math.Clamp(e.NewValue, 25, 400);
        int width = Math.Max(1, (int)Math.Round(selected.BasePlacementWidth * scalePercent / 100));
        int height = Math.Max(1, (int)Math.Round(selected.BasePlacementHeight * scalePercent / 100));
        double centerX = placement.X + (placement.Width / 2.0);
        int bottom = placement.Y + placement.Height;
        selected.CanvasPlacement = placement with
        {
            X = (int)Math.Round(centerX - (width / 2.0)),
            Y = bottom - height,
            Width = width,
            Height = height,
        };
        selected.ScalePercent = scalePercent;
        PlacementScaleText.Text = $"{scalePercent:0}%";
        await RefreshPlacementEditorAsync();
    }

    private void RefreshIndexes()
    {
        for (int index = 0; index < _frames.Count; index++)
        {
            _frames[index].DisplayIndex = $"{index + 1}.";
        }
        RefreshFrameEditorVisibility();
    }

    private void RefreshFrameEditorVisibility()
    {
        bool hasFrames = _frames.Count > 0;
        EmptyFrameState.Visibility = hasFrames ? Visibility.Collapsed : Visibility.Visible;
        FrameEditorGrid.Visibility = hasFrames ? Visibility.Visible : Visibility.Collapsed;
        FrameImportButton.Content = hasFrames ? "프레임 추가" : "프레임 선택";
    }

    private async void FramesList_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        try
        {
            await RefreshPlacementEditorAsync();
        }
        catch (Exception exception)
        {
            ShowEditorError("프레임 미리보기를 표시하지 못했습니다", exception);
        }
    }

    private async Task RefreshPlacementEditorAsync()
    {
        if (FramesList.SelectedItem is not FrameItem selected)
        {
            SelectedFramePlacementImage.Source = null;
            FirstFrameReferenceImage.Source = null;
            SelectedFramePlacementBorder.Visibility = Visibility.Collapsed;
            return;
        }

        NormalizeCommonCanvas();
        UserPetCanvasPlacement placement = selected.CanvasPlacement!;
        _isRefreshingPlacement = true;
        try
        {
            CanvasWidthNumberBox.Value = placement.CanvasWidth;
            CanvasHeightNumberBox.Value = placement.CanvasHeight;
            PlacementXNumberBox.Value = placement.X;
            PlacementYNumberBox.Value = placement.Y;
            PlacementWidthNumberBox.Value = placement.Width;
            PlacementHeightNumberBox.Value = placement.Height;
            PlacementZoomSlider.Value = selected.ScalePercent;
            PlacementScaleText.Text = $"{selected.ScalePercent:0}%";
        }
        finally
        {
            _isRefreshingPlacement = false;
        }

        ConfigurePlacementViewport(placement.CanvasWidth, placement.CanvasHeight);
        var checker = new UserPetProcessedFrame(
            placement.CanvasWidth,
            placement.CanvasHeight,
            new byte[checked(placement.CanvasWidth * placement.CanvasHeight * 4)]);
        FrameCheckerImage.Source = await WindowsImagePreviewFactory.CreateCheckerboardAsync(checker);

        WindowsDecodedImage decoded = await _imageCache.GetAsync(selected.ImagePath);
        if (FramesList.SelectedItem != selected)
        {
            return;
        }
        UserPetProcessedFrame cropped = await Task.Run(() =>
            UserPetPixelProcessor.Process(
                decoded.BgraPixels,
                decoded.Width,
                decoded.Height,
                selected.SourceFrame,
                selected.FlipsHorizontally,
                selected.FlipsVertically,
                backgroundRemoval: selected.BackgroundRemoval));
        selected.Thumbnail = await WindowsImagePreviewFactory.CreateCheckerboardAsync(cropped);
        SelectedFramePlacementImage.Source = await WindowsImagePreviewFactory.CreateTransparentAsync(cropped);
        LayoutPlacementElement(SelectedFramePlacementImage, placement);
        LayoutPlacementElement(SelectedFramePlacementBorder, placement);
        SelectedFramePlacementBorder.Visibility = Visibility.Visible;
        await RefreshFirstFrameReferenceAsync(selected);
    }

    private async Task RefreshFrameThumbnailsAsync(IEnumerable<FrameItem> frames)
    {
        foreach (FrameItem frame in frames)
        {
            WindowsDecodedImage decoded = await _imageCache.GetAsync(frame.ImagePath);
            UserPetProcessedFrame cropped = await Task.Run(() =>
                UserPetPixelProcessor.Process(
                    decoded.BgraPixels,
                    decoded.Width,
                    decoded.Height,
                    frame.SourceFrame,
                    frame.FlipsHorizontally,
                    frame.FlipsVertically,
                    backgroundRemoval: frame.BackgroundRemoval));
            frame.Thumbnail = await WindowsImagePreviewFactory.CreateCheckerboardAsync(cropped);
        }
    }

    private async Task RefreshFirstFrameReferenceAsync(FrameItem selected)
    {
        if (CompareFirstFrameCheckBox.IsChecked != true ||
            _frames.Count == 0 ||
            _frames[0] == selected)
        {
            FirstFrameReferenceImage.Visibility = Visibility.Collapsed;
            return;
        }
        FrameItem first = _frames[0];
        WindowsDecodedImage decoded = await _imageCache.GetAsync(first.ImagePath);
        UserPetProcessedFrame cropped = await Task.Run(() =>
            UserPetPixelProcessor.Process(
                decoded.BgraPixels,
                decoded.Width,
                decoded.Height,
                first.SourceFrame,
                first.FlipsHorizontally,
                first.FlipsVertically,
                backgroundRemoval: first.BackgroundRemoval));
        FirstFrameReferenceImage.Source = await WindowsImagePreviewFactory.CreateTransparentAsync(cropped);
        LayoutPlacementElement(FirstFrameReferenceImage, first.CanvasPlacement!);
        FirstFrameReferenceImage.Visibility = Visibility.Visible;
    }

    private void ConfigurePlacementViewport(int canvasWidth, int canvasHeight)
    {
        const double availableWidth = 260;
        const double availableHeight = 220;
        double fitScale = Math.Min(availableWidth / canvasWidth, availableHeight / canvasHeight);
        FramePlacementCanvas.Width = availableWidth;
        FramePlacementCanvas.Height = availableHeight;
        _placementDisplayScale = fitScale;
        _placementDisplayX = (availableWidth - (canvasWidth * fitScale)) / 2;
        _placementDisplayY = (availableHeight - (canvasHeight * fitScale)) / 2;
        FrameCheckerImage.Width = canvasWidth * _placementDisplayScale;
        FrameCheckerImage.Height = canvasHeight * _placementDisplayScale;
        Canvas.SetLeft(FrameCheckerImage, _placementDisplayX);
        Canvas.SetTop(FrameCheckerImage, _placementDisplayY);
    }

    private void LayoutPlacementElement(FrameworkElement element, UserPetCanvasPlacement placement)
    {
        element.Width = placement.Width * _placementDisplayScale;
        element.Height = placement.Height * _placementDisplayScale;
        Canvas.SetLeft(element, _placementDisplayX + (placement.X * _placementDisplayScale));
        Canvas.SetTop(element, _placementDisplayY + (placement.Y * _placementDisplayScale));
    }

    private void NormalizeCommonCanvas()
    {
        if (_frames.Count == 0)
        {
            return;
        }
        bool hasUnplacedFrame = _frames.Any(frame => frame.CanvasPlacement is null);
        int canvasWidth = hasUnplacedFrame
            ? _frames.Max(frame => Math.Max(frame.IntrinsicWidth, frame.CanvasPlacement?.CanvasWidth ?? 0))
            : _frames.Max(frame => frame.CanvasPlacement!.CanvasWidth);
        int canvasHeight = hasUnplacedFrame
            ? _frames.Max(frame => Math.Max(frame.IntrinsicHeight, frame.CanvasPlacement?.CanvasHeight ?? 0))
            : _frames.Max(frame => frame.CanvasPlacement!.CanvasHeight);
        foreach (FrameItem frame in _frames)
        {
            UserPetCanvasPlacement current = frame.CanvasPlacement ?? new UserPetCanvasPlacement(
                canvasWidth,
                canvasHeight,
                (canvasWidth - frame.IntrinsicWidth) / 2,
                (canvasHeight - frame.IntrinsicHeight) / 2,
                frame.IntrinsicWidth,
                frame.IntrinsicHeight);
            int width = Math.Clamp(current.Width, 1, 32_768);
            int height = Math.Clamp(current.Height, 1, 32_768);
            frame.CanvasPlacement = current with
            {
                CanvasWidth = canvasWidth,
                CanvasHeight = canvasHeight,
                X = Math.Clamp(current.X, -32_768, 32_768),
                Y = Math.Clamp(current.Y, -32_768, 32_768),
                Width = width,
                Height = height,
            };
            frame.EnsureScaleBaseline();
        }
    }

    private async Task InitializeUnplacedFramePlacementsAsync()
    {
        FrameItem[] unplaced = _frames.Where(frame => frame.CanvasPlacement is null).ToArray();
        if (unplaced.Length == 0)
        {
            return;
        }
        var geometries = new List<UserPetVisibleFrameGeometry>(unplaced.Length);
        foreach (FrameItem frame in unplaced)
        {
            WindowsDecodedImage decoded = await _imageCache.GetAsync(frame.ImagePath);
            (UserPetProcessedFrame cropped, UserPetPixelRect visible) = await Task.Run(() =>
            {
                UserPetProcessedFrame result = UserPetPixelProcessor.Process(
                    decoded.BgraPixels,
                    decoded.Width,
                    decoded.Height,
                    frame.SourceFrame,
                    frame.FlipsHorizontally,
                    frame.FlipsVertically,
                    backgroundRemoval: frame.BackgroundRemoval);
                UserPetPixelRect visibleBounds =
                    UserPetImageEditingGeometry.FindVisibleBounds(
                        result.BgraPixels,
                        result.Width,
                        result.Height) ??
                    new UserPetPixelRect(0, 0, result.Width, result.Height);
                return (result, visibleBounds);
            });
            geometries.Add(new UserPetVisibleFrameGeometry(cropped.Width, cropped.Height, visible));
        }
        IReadOnlyList<UserPetCanvasPlacement> placements =
            UserPetImageEditingGeometry.CreateCommonCanvasPlacements(geometries);
        int existingWidth = _frames
            .Where(frame => frame.CanvasPlacement is not null)
            .Select(frame => frame.CanvasPlacement!.CanvasWidth)
            .DefaultIfEmpty(0)
            .Max();
        int existingHeight = _frames
            .Where(frame => frame.CanvasPlacement is not null)
            .Select(frame => frame.CanvasPlacement!.CanvasHeight)
            .DefaultIfEmpty(0)
            .Max();
        int canvasWidth = Math.Max(existingWidth, placements[0].CanvasWidth);
        int canvasHeight = Math.Max(existingHeight, placements[0].CanvasHeight);
        foreach (FrameItem existing in _frames.Where(frame => frame.CanvasPlacement is not null))
        {
            UserPetCanvasPlacement current = existing.CanvasPlacement!;
            existing.CanvasPlacement = current with
            {
                CanvasWidth = canvasWidth,
                CanvasHeight = canvasHeight,
                X = current.X + ((canvasWidth - current.CanvasWidth) / 2),
                Y = current.Y + ((canvasHeight - current.CanvasHeight) / 2),
            };
        }
        int groupOffsetX = (canvasWidth - placements[0].CanvasWidth) / 2;
        int groupOffsetY = (canvasHeight - placements[0].CanvasHeight) / 2;
        for (int index = 0; index < unplaced.Length; index++)
        {
            unplaced[index].CanvasPlacement = placements[index] with
            {
                CanvasWidth = canvasWidth,
                CanvasHeight = canvasHeight,
                X = placements[index].X + groupOffsetX,
                Y = placements[index].Y + groupOffsetY,
            };
        }
    }

    private void PlacementNumberBox_ValueChanged(NumberBox sender, NumberBoxValueChangedEventArgs args)
    {
        if (!_isReady || _isRefreshingPlacement || FramesList.SelectedItem is not FrameItem selected)
        {
            return;
        }
        int canvasWidth = NumberValue(CanvasWidthNumberBox, selected.CanvasPlacement!.CanvasWidth);
        int canvasHeight = NumberValue(CanvasHeightNumberBox, selected.CanvasPlacement.CanvasHeight);
        int width = Math.Clamp(NumberValue(PlacementWidthNumberBox, selected.CanvasPlacement.Width), 1, 32_768);
        int height = Math.Clamp(NumberValue(PlacementHeightNumberBox, selected.CanvasPlacement.Height), 1, 32_768);
        int x = Math.Clamp(NumberValue(PlacementXNumberBox, selected.CanvasPlacement.X), -32_768, 32_768);
        int y = Math.Clamp(NumberValue(PlacementYNumberBox, selected.CanvasPlacement.Y), -32_768, 32_768);
        foreach (FrameItem frame in _frames)
        {
            UserPetCanvasPlacement current = frame.CanvasPlacement!;
            frame.CanvasPlacement = current with
            {
                CanvasWidth = canvasWidth,
                CanvasHeight = canvasHeight,
            };
        }
        selected.CanvasPlacement = new UserPetCanvasPlacement(canvasWidth, canvasHeight, x, y, width, height);
        if (ReferenceEquals(sender, PlacementWidthNumberBox) ||
            ReferenceEquals(sender, PlacementHeightNumberBox))
        {
            selected.ResetScaleBaseline();
        }
        _ = RefreshPlacementEditorAsync();
    }

    private static int NumberValue(NumberBox numberBox, int fallback) =>
        double.IsFinite(numberBox.Value)
            ? (int)Math.Round(numberBox.Value)
            : fallback;

    private void FramePlacementCanvas_PointerPressed(object sender, PointerRoutedEventArgs e)
    {
        if (FramesList.SelectedItem is not FrameItem selected)
        {
            return;
        }
        Point point = e.GetCurrentPoint(FramePlacementCanvas).Position;
        double left = Canvas.GetLeft(SelectedFramePlacementBorder);
        double top = Canvas.GetTop(SelectedFramePlacementBorder);
        double right = left + SelectedFramePlacementBorder.Width;
        double bottom = top + SelectedFramePlacementBorder.Height;
        const double hit = 8;
        if (point.X < left - hit || point.X > right + hit || point.Y < top - hit || point.Y > bottom + hit)
        {
            return;
        }
        bool nearLeft = Math.Abs(point.X - left) <= hit;
        bool nearRight = Math.Abs(point.X - right) <= hit;
        bool nearTop = Math.Abs(point.Y - top) <= hit;
        bool nearBottom = Math.Abs(point.Y - bottom) <= hit;
        _placementDragHandle = (nearLeft, nearTop, nearRight, nearBottom) switch
        {
            (true, true, _, _) => UserPetCropHandle.TopLeft,
            (_, true, true, _) => UserPetCropHandle.TopRight,
            (true, _, _, true) => UserPetCropHandle.BottomLeft,
            (_, _, true, true) => UserPetCropHandle.BottomRight,
            (true, _, _, _) => UserPetCropHandle.Left,
            (_, true, _, _) => UserPetCropHandle.Top,
            (_, _, true, _) => UserPetCropHandle.Right,
            (_, _, _, true) => UserPetCropHandle.Bottom,
            _ => UserPetCropHandle.Move,
        };
        _placementDragStart = point;
        _placementDragOriginal = new UserPetPixelRect(
            selected.CanvasPlacement!.X,
            selected.CanvasPlacement.Y,
            selected.CanvasPlacement.Width,
            selected.CanvasPlacement.Height);
        _isDraggingPlacement = FramePlacementCanvas.CapturePointer(e.Pointer);
        e.Handled = _isDraggingPlacement;
    }

    private void FramePlacementCanvas_PointerMoved(object sender, PointerRoutedEventArgs e)
    {
        if (!_isDraggingPlacement || FramesList.SelectedItem is not FrameItem selected)
        {
            return;
        }
        Point point = e.GetCurrentPoint(FramePlacementCanvas).Position;
        int deltaX = (int)Math.Round((point.X - _placementDragStart.X) / _placementDisplayScale);
        int deltaY = (int)Math.Round((point.Y - _placementDragStart.Y) / _placementDisplayScale);
        UserPetCanvasPlacement placement = selected.CanvasPlacement!;
        UserPetPixelRect rect = DragPlacement(
            _placementDragOriginal,
            _placementDragHandle,
            deltaX,
            deltaY);
        selected.CanvasPlacement = placement with { X = rect.X, Y = rect.Y, Width = rect.Width, Height = rect.Height };
        if (_placementDragHandle != UserPetCropHandle.Move)
        {
            selected.ResetScaleBaseline();
            _isRefreshingPlacement = true;
            try
            {
                PlacementZoomSlider.Value = selected.ScalePercent;
                PlacementScaleText.Text = $"{selected.ScalePercent:0}%";
            }
            finally
            {
                _isRefreshingPlacement = false;
            }
        }
        LayoutPlacementElement(SelectedFramePlacementImage, selected.CanvasPlacement);
        LayoutPlacementElement(SelectedFramePlacementBorder, selected.CanvasPlacement);
        UpdatePlacementNumbers(selected.CanvasPlacement);
        e.Handled = true;
    }

    private void FramePlacementCanvas_PointerReleased(object sender, PointerRoutedEventArgs e)
    {
        if (!_isDraggingPlacement)
        {
            return;
        }
        _isDraggingPlacement = false;
        FramePlacementCanvas.ReleasePointerCapture(e.Pointer);
        e.Handled = true;
    }

    private void UpdatePlacementNumbers(UserPetCanvasPlacement placement)
    {
        _isRefreshingPlacement = true;
        try
        {
            PlacementXNumberBox.Value = placement.X;
            PlacementYNumberBox.Value = placement.Y;
            PlacementWidthNumberBox.Value = placement.Width;
            PlacementHeightNumberBox.Value = placement.Height;
        }
        finally
        {
            _isRefreshingPlacement = false;
        }
    }

    private static UserPetPixelRect DragPlacement(
        UserPetPixelRect original,
        UserPetCropHandle handle,
        int deltaX,
        int deltaY)
    {
        if (handle == UserPetCropHandle.Move)
        {
            return original with
            {
                X = Math.Clamp(original.X + deltaX, -32_768, 32_768),
                Y = Math.Clamp(original.Y + deltaY, -32_768, 32_768),
            };
        }

        int left = original.X;
        int top = original.Y;
        int right = original.X + original.Width;
        int bottom = original.Y + original.Height;
        if (handle is UserPetCropHandle.Left or UserPetCropHandle.TopLeft or UserPetCropHandle.BottomLeft)
        {
            left = Math.Min(right - 1, left + deltaX);
        }
        if (handle is UserPetCropHandle.Right or UserPetCropHandle.TopRight or UserPetCropHandle.BottomRight)
        {
            right = Math.Max(left + 1, right + deltaX);
        }
        if (handle is UserPetCropHandle.Top or UserPetCropHandle.TopLeft or UserPetCropHandle.TopRight)
        {
            top = Math.Min(bottom - 1, top + deltaY);
        }
        if (handle is UserPetCropHandle.Bottom or UserPetCropHandle.BottomLeft or UserPetCropHandle.BottomRight)
        {
            bottom = Math.Max(top + 1, bottom + deltaY);
        }
        left = Math.Clamp(left, -32_768, 32_768);
        top = Math.Clamp(top, -32_768, 32_768);
        right = Math.Clamp(right, left + 1, left + 32_768);
        bottom = Math.Clamp(bottom, top + 1, top + 32_768);
        return new UserPetPixelRect(left, top, right - left, bottom - top);
    }

    private async void CompareFirstFrameCheckBox_Changed(object sender, RoutedEventArgs e)
    {
        if (_isReady && FramesList.SelectedItem is FrameItem selected)
        {
            await RefreshFirstFrameReferenceAsync(selected);
        }
    }

    public sealed class FrameItem : INotifyPropertyChanged
    {
        private string _displayIndex = string.Empty;
        private int _durationMilliseconds;
        private Microsoft.UI.Xaml.Media.ImageSource? _thumbnail;

        public FrameItem(
            string imagePath,
            int durationMilliseconds,
            PetPackageFrame? sourceFrame,
            string sourceDetail,
            bool flipsHorizontally = false,
            bool flipsVertically = false,
            UserPetCanvasPlacement? canvasPlacement = null,
            Guid? frameId = null,
            UserPetBackgroundRemoval? backgroundRemoval = null)
        {
            ImagePath = imagePath;
            FileName = Path.GetFileName(imagePath);
            _durationMilliseconds = durationMilliseconds;
            SourceFrame = sourceFrame;
            SourceDetail = sourceDetail;
            FlipsHorizontally = flipsHorizontally;
            FlipsVertically = flipsVertically;
            CanvasPlacement = canvasPlacement;
            FrameId = frameId is { } id && id != Guid.Empty ? id : Guid.NewGuid();
            BackgroundRemoval = backgroundRemoval;
        }

        public string ImagePath { get; }
        public string FileName { get; }
        public PetPackageFrame? SourceFrame { get; }
        public string SourceDetail { get; }
        public bool FlipsHorizontally { get; set; }
        public bool FlipsVertically { get; set; }
        public UserPetCanvasPlacement? CanvasPlacement { get; set; }
        public int BasePlacementWidth { get; private set; }
        public int BasePlacementHeight { get; private set; }
        public double ScalePercent { get; set; } = 100;
        public Guid FrameId { get; }
        public UserPetBackgroundRemoval? BackgroundRemoval { get; }

        public Microsoft.UI.Xaml.Media.ImageSource? Thumbnail
        {
            get => _thumbnail;
            set => SetField(ref _thumbnail, value);
        }

        public int IntrinsicWidth => SourceFrame?.Width ?? CanvasPlacement?.Width ?? 1;

        public int IntrinsicHeight => SourceFrame?.Height ?? CanvasPlacement?.Height ?? 1;

        public void EnsureScaleBaseline()
        {
            if (BasePlacementWidth > 0 || CanvasPlacement is not { } placement)
            {
                return;
            }
            BasePlacementWidth = placement.Width;
            BasePlacementHeight = placement.Height;
        }

        public void ResetScaleBaseline()
        {
            if (CanvasPlacement is not { } placement)
            {
                return;
            }
            BasePlacementWidth = placement.Width;
            BasePlacementHeight = placement.Height;
            ScalePercent = 100;
        }

        public FrameItem IndependentCopy()
        {
            var copy = new FrameItem(
                ImagePath,
                DurationMilliseconds,
                SourceFrame,
                SourceDetail + " · 복사본",
                FlipsHorizontally,
                FlipsVertically,
                CanvasPlacement,
                Guid.NewGuid(),
                BackgroundRemoval)
            {
                Thumbnail = Thumbnail,
            };
            return copy;
        }

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

internal enum AnimationBehaviorConnectionMode
{
    None,
    CreateNew,
    AppendExisting,
}

internal sealed record AnimationBehaviorConnectionRequest(
    AnimationBehaviorConnectionMode Mode,
    string? NewBehaviorName,
    string? ExistingBehaviorId);
