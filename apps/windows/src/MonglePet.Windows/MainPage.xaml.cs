using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Reflection;
using System.Runtime.CompilerServices;
using Microsoft.UI;
using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Imaging;
using MonglePet.Activity;
using MonglePet.Core.Behavior;
using MonglePet.Packages;
using MonglePet.PetLibrary;
using MonglePet.Settings;
using MonglePet.Shell;
using MonglePet.Windows.Runtime;
using Windows.Storage;
using Windows.Storage.Pickers;
using Windows.UI;

namespace MonglePet.Windows;

public sealed partial class MainPage : Page
{
    private readonly ObservableCollection<InstalledPetItem> _installedPets = [];
    private readonly ObservableCollection<ActivePetItem> _activePets = [];
    private readonly ObservableCollection<PetChoiceItem> _petChoices = [];
    private readonly ObservableCollection<PetAnimationItem> _petAnimations = [];
    private readonly ObservableCollection<BehaviorSequenceItem> _behaviorSequences = [];
    private readonly ObservableCollection<MotionOptionItem> _motionOptions = [];
    private readonly ObservableCollection<MotionOptionItem> _movementMotionOptions = [];
    private readonly ObservableCollection<MonitorOptionItem> _movementScreens = [];
    private readonly ObservableCollection<BehaviorStepEditorItem> _behaviorSteps = [];
    private readonly ObservableCollection<AutomaticRuleEditorItem> _automaticRules = [];
    private readonly ObservableCollection<RulePriorityKindItem> _rulePriorityKinds = [];
    private readonly ObservableCollection<SpeechPhraseEditorItem> _behaviorSpeechPhrases = [];
    private readonly ObservableCollection<SpeechPhraseEditorItem> _periodicSpeechPhrases = [];
    private readonly WindowsLoginLaunchService _loginLaunchService = new();
    private readonly RemotePetImportService _remotePetImportService = new(
        CurrentAppSemanticVersion());
    private readonly CancellationTokenSource _remotePetImportCancellation = new();
    private RemotePetImportInteractionState _remotePetImportState =
        RemotePetImportInteractionState.Initial;
    private bool _isLoaded;
    private bool _isPreparedForShutdown;
    private bool _isRefreshingDisplayControls;
    private bool _isRefreshingBehaviorControls;
    private bool _isRefreshingBehaviorEditor;
    private bool _isRefreshingMovementControls;
    private bool _isRefreshingSpeechControls;
    private bool _isRefreshingPetChoice;
    private bool _isEditingSpeechPhrase;
    private bool _isRefreshingLoginLaunch;
    private bool _isPersistingMovementControls;
    private bool _isPersistingBehaviorControls;
    private bool _selectedPetDetailsAreStale;
    private string _currentSettingsSection = "activePets";
    private string? _selectedRoutineId;
    private Guid? _selectedRuleId;
    private Guid? _selectedSpeechPhraseId;
    private WindowsApplicationChoice? _selectedApplicationChoice;
    private DispatcherQueueTimer? _displaySaveTimer;
    private DispatcherQueueTimer? _movementSaveTimer;
    private DispatcherQueueTimer? _speechSaveTimer;
    private DispatcherQueueTimer? _petAnimationPreviewTimer;
    private long _petPreviewGeneration;
    private long _petAnimationPreviewGeneration;
    private int _petAnimationPreviewFrameIndex;
    private LoadedPetPackage? _petAnimationPreviewPackage;
    private PetPackageMotion? _petAnimationPreviewMotion;
    private readonly WindowsDecodedImageCache _petAnimationPreviewImageCache = new();

    public MainPage()
    {
        InitializeComponent();
        SpeechPeriodicIntervalNumberBox.AddHandler(
            UIElement.KeyUpEvent,
            new Microsoft.UI.Xaml.Input.KeyEventHandler(
                SpeechPeriodicIntervalNumberBox_KeyUp),
            handledEventsToo: true);
        AppVersionText.Text = ApplicationVersionText();
        ShowSettingsSection("activePets");
        ActivePetsList.ItemsSource = _activePets;
        InstalledPetsList.ItemsSource = _installedPets;
        CurrentPetComboBox.ItemsSource = _petChoices;
        PetAnimationsList.ItemsSource = _petAnimations;
        ManualSequenceComboBox.ItemsSource = _behaviorSequences;
        RandomSequencesList.ItemsSource = _behaviorSequences;
        RoutineEditorComboBox.ItemsSource = _behaviorSequences;
        RuleTargetSequenceComboBox.ItemsSource = _behaviorSequences;
        IdleRuleTargetSequenceComboBox.ItemsSource = _behaviorSequences;
        PettingMotionComboBox.ItemsSource = _movementMotionOptions;
        MovementScreenComboBox.ItemsSource = _movementScreens;
        BehaviorStepsList.ItemsSource = _behaviorSteps;
        AutomaticRulesList.ItemsSource = _automaticRules;
        RulePriorityOrderList.ItemsSource = _rulePriorityKinds;
        BehaviorSpeechPhrasesList.ItemsSource = _behaviorSpeechPhrases;
        PeriodicSpeechPhrasesList.ItemsSource = _periodicSpeechPhrases;
        SpeechSequenceComboBox.ItemsSource = _behaviorSequences;
        Loaded += (_, _) =>
        {
            _isLoaded = true;
            _displaySaveTimer ??= CreateDisplaySaveTimer();
            _movementSaveTimer ??= CreateMovementSaveTimer();
            _speechSaveTimer ??= CreateSpeechSaveTimer();
            _petAnimationPreviewTimer ??= CreatePetAnimationPreviewTimer();
            if (Application.Current is App app)
            {
                app.InitializationCompleted += App_InitializationCompleted;
                app.SettingsStateChanged += App_SettingsStateChanged;
                app.SelectedPetInstanceChanged += App_SelectedPetInstanceChanged;
            }
            RefreshOverlayState();
            RefreshActivePetsState();
            RefreshLibraryState();
            RefreshBehaviorState();
            _ = RefreshLoginLaunchAsync();
            DispatcherQueue.TryEnqueue(RefreshOverlayState);
        };
        Unloaded += (_, _) =>
        {
            PrepareForShutdown();
        };
    }

    internal void PrepareForShutdown()
    {
        if (_isPreparedForShutdown)
        {
            return;
        }

        _isPreparedForShutdown = true;
        FlushMovementSave();
        _isLoaded = false;
        _remotePetImportCancellation.Cancel();
        _remotePetImportCancellation.Dispose();
        _remotePetImportService.Dispose();
        _displaySaveTimer?.Stop();
        _movementSaveTimer?.Stop();
        _speechSaveTimer?.Stop();
        _petAnimationPreviewTimer?.Stop();
        if (Application.Current is App app)
        {
            app.InitializationCompleted -= App_InitializationCompleted;
            app.SettingsStateChanged -= App_SettingsStateChanged;
            app.SelectedPetInstanceChanged -= App_SelectedPetInstanceChanged;
        }
    }

    internal void OpenRemotePetImport(string? canonicalUrl, string? errorMessage)
    {
        NavigationViewItem? libraryItem = SettingsNavigationView.MenuItems
            .OfType<NavigationViewItem>()
            .FirstOrDefault(item => item.Tag?.ToString() == "pet");
        if (libraryItem is not null)
        {
            SettingsNavigationView.SelectedItem = libraryItem;
        }
        ShowSettingsSection("pet");

        if (_remotePetImportState.IsBusy)
        {
            return;
        }

        if (!string.IsNullOrWhiteSpace(canonicalUrl))
        {
            RemotePetUrlTextBox.Text = canonicalUrl;
        }

        if (!string.IsNullOrWhiteSpace(errorMessage))
        {
            _remotePetImportState = _remotePetImportState.Fail(errorMessage);
            RenderRemotePetImportState();
            return;
        }

        if (!string.IsNullOrWhiteSpace(canonicalUrl))
        {
            _ = ImportRemotePetAsync();
        }
    }

    private void SettingsNavigationView_SelectionChanged(
        NavigationView sender,
        NavigationViewSelectionChangedEventArgs args)
    {
        string section = (args.SelectedItemContainer as NavigationViewItem)?.Tag?.ToString()
            ?? "activePets";
        if (_currentSettingsSection == "movement" && section != "movement")
        {
            FlushMovementSave();
        }
        ShowSettingsSection(section);
        if (section == "general" && _isLoaded)
        {
            _ = RefreshLoginLaunchAsync();
        }
    }

    private void ShowSettingsSection(string section)
    {
        if (PetLibraryCard is null)
        {
            return;
        }

        _currentSettingsSection = section;

        bool isActivePets = section == "activePets";
        bool isPet = section == "pet";
        bool isGeneral = section == "general";
        bool isMovement = section == "movement";
        bool isRoutines = section == "routines";
        bool isSpeech = section == "speech";
        bool isAutomaticRules = section == "automaticRules";
        bool isTroubleshooting = section == "troubleshooting";

        ActivePetsCard.Visibility = isActivePets ? Visibility.Visible : Visibility.Collapsed;
        SafeStartInfoBar.Visibility = isTroubleshooting
            ? Visibility.Visible
            : Visibility.Collapsed;
        TroubleshootingCard.Visibility = isTroubleshooting
            ? Visibility.Visible
            : Visibility.Collapsed;
        PetLibraryCard.Visibility = isPet ? Visibility.Visible : Visibility.Collapsed;
        GeneralSettingsCard.Visibility = isMovement
            ? Visibility.Visible
            : Visibility.Collapsed;
        PetPresentationPanel.Visibility = isMovement ? Visibility.Visible : Visibility.Collapsed;
        BehaviorOverviewPanel.Visibility = isMovement
            ? Visibility.Visible
            : Visibility.Collapsed;

        OverlaySettingsCard.Visibility = isGeneral || isMovement
            ? Visibility.Visible
            : Visibility.Collapsed;
        OverlayDisplayPanel.Visibility = isMovement ? Visibility.Visible : Visibility.Collapsed;
        ApplicationSettingsPanel.Visibility = isGeneral ? Visibility.Visible : Visibility.Collapsed;
        AppInformationPanel.Visibility = isGeneral ? Visibility.Visible : Visibility.Collapsed;
        DisplayApplicationDivider.Visibility = Visibility.Collapsed;
        ApplicationInfoDivider.Visibility = isGeneral ? Visibility.Visible : Visibility.Collapsed;
        MovementSettingsCard.Visibility = isMovement ? Visibility.Visible : Visibility.Collapsed;
        SpeechSettingsCard.Visibility = isSpeech ? Visibility.Visible : Visibility.Collapsed;

        BehaviorSettingsCard.Visibility = isRoutines || isAutomaticRules
            ? Visibility.Visible
            : Visibility.Collapsed;
        RoutineEditorCard.Visibility = isRoutines ? Visibility.Visible : Visibility.Collapsed;
        AutomaticRulesCard.Visibility = isAutomaticRules
            ? Visibility.Visible
            : Visibility.Collapsed;

        (SettingsSectionTitle.Text, SettingsSectionDescription.Text) = section switch
        {
            "general" => (
                "일반",
                "로그인 자동 실행과 앱 버전, 로컬 개인정보 보호 정보를 확인합니다."),
            "movement" => (
                "표시 및 이동",
                "선택한 펫의 표시 상태와 화면 모양, 이동 방식과 쓰다듬기를 설정합니다."),
            "routines" => (
                "행동 루틴",
                "애니메이션 단계를 조합해 행동을 만들고 이름과 반복 방식을 편집합니다."),
            "speech" => (
                "말풍선",
                "행동 대사와 주기 대사, 말풍선 모양 및 표시 위치를 설정합니다."),
            "automaticRules" => (
                "규칙 설정",
                "이동·입력 없음·앱 사용 규칙의 우선순위와 조건별 행동을 설정합니다."),
            "pet" => (
                "펫 보관함",
                "펫 패키지를 가져오거나 내보내고 원본 정보와 애니메이션을 관리합니다."),
            "troubleshooting" => (
                "문제 해결",
                "복원 중 문제가 생긴 펫을 안전 모드에서 분리하고 다시 시작합니다."),
            _ => (
                "활성 펫",
                "데스크톱에 함께 표시할 펫을 추가하고 선택, 순서와 실행 상태를 관리합니다."),
        };

        if (_isLoaded && section != "activePets" && _selectedPetDetailsAreStale)
        {
            _selectedPetDetailsAreStale = false;
            RefreshOverlayState();
            RefreshLibraryState();
            RefreshBehaviorState();
        }
    }

    private async void LoginLaunchToggle_Toggled(object sender, RoutedEventArgs e)
    {
        if (!_isLoaded || _isRefreshingLoginLaunch)
        {
            return;
        }
        try
        {
            LoginLaunchStatus status = await _loginLaunchService.SetEnabledAsync(
                LoginLaunchToggle.IsOn);
            ApplyLoginLaunchStatus(status);
        }
        catch (Exception exception)
        {
            await RefreshLoginLaunchAsync();
            ShowLibraryMessage(InfoBarSeverity.Error, "자동 실행 설정 실패", exception.Message);
        }
    }

    private async void OpenStartupAppsSettingsButton_Click(object sender, RoutedEventArgs e)
    {
        await global::Windows.System.Launcher.LaunchUriAsync(
            new Uri("ms-settings:startupapps"));
        await RefreshLoginLaunchAsync();
    }

    private async Task RefreshLoginLaunchAsync()
    {
        ApplyLoginLaunchStatus(await _loginLaunchService.GetStatusAsync());
    }

    private void ApplyLoginLaunchStatus(LoginLaunchStatus status)
    {
        _isRefreshingLoginLaunch = true;
        try
        {
            LoginLaunchToggle.IsOn = status is LoginLaunchStatus.Enabled or
                LoginLaunchStatus.EnabledByPolicy;
            LoginLaunchToggle.IsEnabled = status is not (
                LoginLaunchStatus.DisabledByPolicy or
                LoginLaunchStatus.EnabledByPolicy or
                LoginLaunchStatus.Unavailable);
            OpenStartupAppsSettingsButton.Visibility =
                status == LoginLaunchStatus.DisabledByUser
                    ? Visibility.Visible
                    : Visibility.Collapsed;
            LoginLaunchStatusText.Text = status switch
            {
                LoginLaunchStatus.Enabled => "다음 로그인부터 MonglePet이 자동으로 실행됩니다.",
                LoginLaunchStatus.Disabled => "로그인 시 자동 실행하지 않습니다.",
                LoginLaunchStatus.DisabledByUser => "Windows에서 시작 앱이 꺼져 있습니다. 시작 앱 설정에서 다시 허용해 주세요.",
                LoginLaunchStatus.DisabledByPolicy => "조직 정책에서 자동 실행을 차단했습니다.",
                LoginLaunchStatus.EnabledByPolicy => "조직 정책에서 자동 실행을 사용하도록 설정했습니다.",
                _ => "패키지의 자동 실행 항목을 찾을 수 없습니다. 앱을 다시 설치하거나 개발 패키지를 다시 등록해 주세요.",
            };
        }
        finally
        {
            _isRefreshingLoginLaunch = false;
        }
    }

    private void VisibilityButton_Click(object sender, RoutedEventArgs e)
    {
        if (Application.Current is not App app)
        {
            return;
        }

        try
        {
            app.SetUserPresentation(
                app.CurrentSettings.SelectedPetInstance?.Presentation == PetPresentation.Awake
                    ? PetPresentation.TuckedAway
                    : PetPresentation.Awake);
            DisplaySettingsInfoBar.IsOpen = false;
        }
        catch (Exception exception)
        {
            ShowDisplaySettingsError(exception);
        }

        RefreshOverlayState();
    }

    private void ClickThroughToggle_Toggled(object sender, RoutedEventArgs e)
    {
        if (!_isLoaded || _isRefreshingDisplayControls)
        {
            return;
        }

        PersistDisplaySettingsFromControls();
    }

    private void PixelArtToggle_Toggled(object sender, RoutedEventArgs e)
    {
        if (!_isLoaded || _isRefreshingDisplayControls)
        {
            return;
        }

        PersistDisplaySettingsFromControls();
    }

    private void PointerOverlapFadeToggle_Toggled(object sender, RoutedEventArgs e)
    {
        if (!_isLoaded || _isRefreshingDisplayControls)
        {
            return;
        }

        PersistDisplaySettingsFromControls();
    }

    private void DisplaySlider_ValueChanged(object sender, object e)
    {
        UpdateDisplayValueLabels();
        if (!_isLoaded || _isRefreshingDisplayControls)
        {
            return;
        }

        if (Application.Current is App app)
        {
            app.PreviewOverlaySettings(SettingsFromDisplayControls(app.CurrentSettings.Overlay));
            ScheduleDisplaySettingsSave();
        }
    }

    private void OverlaySizePresetButton_Click(object sender, RoutedEventArgs e)
    {
        if (sender is Button { Tag: not null } button &&
            double.TryParse(button.Tag.ToString(), out double percentage))
        {
            OverlayWidthSlider.Value = Math.Clamp(
                AppSettingsLimits.DefaultOverlayWidth * percentage / 100,
                AppSettingsLimits.MinimumOverlayWidth,
                AppSettingsLimits.MaximumOverlayWidth);
        }
    }

    private void BringPetToCurrentScreenButton_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            (Application.Current as App)?.BringPetToCurrentScreen();
            RefreshOverlayState();
        }
        catch (Exception exception)
        {
            DisplaySettingsInfoBar.Severity = InfoBarSeverity.Error;
            DisplaySettingsInfoBar.Title = "펫을 가져오지 못했습니다";
            DisplaySettingsInfoBar.Message = exception.Message;
            DisplaySettingsInfoBar.IsOpen = true;
        }
    }

    private void BehaviorModeComboBox_SelectionChanged(
        object sender,
        SelectionChangedEventArgs e)
    {
        if (!_isLoaded || _isRefreshingBehaviorControls)
        {
            return;
        }

        PersistBehaviorSelectionFromControls();
    }

    private void ManualSequenceComboBox_SelectionChanged(
        object sender,
        SelectionChangedEventArgs e)
    {
        if (!_isLoaded || _isRefreshingBehaviorControls ||
            BehaviorModeComboBox.SelectedIndex != 0)
        {
            return;
        }

        PersistBehaviorSelectionFromControls();
    }

    private void RandomSequencesList_SelectionChanged(
        object sender,
        SelectionChangedEventArgs e)
    {
        if (!_isLoaded || _isRefreshingBehaviorControls ||
            BehaviorModeComboBox.SelectedIndex != 1)
        {
            return;
        }
        PersistBehaviorSelectionFromControls();
    }

    private void MovementControls_Changed(object sender, object e)
    {
        if (!_isLoaded || _isRefreshingMovementControls)
        {
            return;
        }
        bool canEdit = Application.Current is App app && app.SettingsStore.IsWritingEnabled;
        RefreshMovementControlVisibility(canEdit);
        ScheduleMovementSave();
    }

    private void MovementAnimationEditor_SettingsChanged(object? sender, EventArgs e)
    {
        if (!_isLoaded || _isRefreshingMovementControls)
        {
            return;
        }
        ScheduleMovementSave();
    }

    private void MovementModeRadioButton_Checked(object sender, RoutedEventArgs e)
    {
        if (_isRefreshingMovementControls || sender is not RadioButton radioButton ||
            !int.TryParse(radioButton.Tag?.ToString(), out int selectedIndex))
        {
            return;
        }

        MovementModeComboBox.SelectedIndex = selectedIndex;
    }

    private async void BrowseWebPetsButton_Click(object sender, RoutedEventArgs e)
    {
#if DEBUG
        var catalogUri = new Uri("https://dev.mapleroom.kr/monglepet/pets");
#else
        var catalogUri = new Uri("https://mapleroom.kr/monglepet/pets");
#endif
        bool opened = await global::Windows.System.Launcher.LaunchUriAsync(catalogUri);
        if (!opened)
        {
            _remotePetImportState = _remotePetImportState.Fail(
                "MonglePet 웹페이지를 열 수 없습니다. 잠시 뒤 다시 시도해 주세요.");
            RenderRemotePetImportState();
        }
    }

    private void RemotePetUrlTextBox_TextChanged(object sender, TextChangedEventArgs e)
    {
        _remotePetImportState = _remotePetImportState.WithInput(RemotePetUrlTextBox.Text);
        RenderRemotePetImportState();
    }

    private void RemotePetUrlTextBox_KeyDown(
        object sender,
        Microsoft.UI.Xaml.Input.KeyRoutedEventArgs e)
    {
        if (e.Key != global::Windows.System.VirtualKey.Enter)
        {
            return;
        }

        e.Handled = true;
        _ = ImportRemotePetAsync();
    }

    private void ImportRemotePetButton_Click(object sender, RoutedEventArgs e) =>
        _ = ImportRemotePetAsync();

    private async Task ImportRemotePetAsync()
    {
        if (Application.Current is not App app)
        {
            return;
        }

        _remotePetImportState = _remotePetImportState.WithInput(RemotePetUrlTextBox.Text);
        if (!_remotePetImportState.TryBegin(out _remotePetImportState))
        {
            return;
        }
        RenderRemotePetImportState();

        try
        {
            using RemotePetPreparedPackage prepared =
                await _remotePetImportService.PreparePackageAsync(
                    _remotePetImportState.UserInput,
                    _remotePetImportCancellation.Token);
            PetPackageImportReview review = app.ReviewPackage(
                prepared.PackagePath,
                prepared.PublishedMinimumAppVersion);
            await ReviewAndImportPackageAsync(
                app,
                review,
                usesRemoteErrorSurface: true);
            if (_remotePetImportState.IsBusy)
            {
                _remotePetImportState = _remotePetImportState.Complete();
                RenderRemotePetImportState();
            }
        }
        catch (OperationCanceledException)
            when (_remotePetImportCancellation.IsCancellationRequested)
        {
            _remotePetImportState = _remotePetImportState.Complete();
        }
        catch (Exception exception)
        {
            _remotePetImportState = _remotePetImportState.Fail(exception.Message);
            RenderRemotePetImportState();
        }
    }

    private void RenderRemotePetImportState()
    {
        if (ImportRemotePetButton is null)
        {
            return;
        }

        bool canInstall = (Application.Current as App)?.SettingsStore.IsWritingEnabled == true;
        ImportRemotePetButton.Content = _remotePetImportState.ActionText;
        ImportRemotePetButton.IsEnabled = canInstall && !_remotePetImportState.IsBusy;
        BrowseWebPetsButton.IsEnabled = !_remotePetImportState.IsBusy;
        RemotePetUrlTextBox.IsEnabled = !_remotePetImportState.IsBusy;
        RemotePetImportProgressRing.IsActive = _remotePetImportState.IsBusy;
        RemotePetImportProgressRing.Visibility = _remotePetImportState.IsBusy
            ? Visibility.Visible
            : Visibility.Collapsed;
        RemotePetImportStatusText.Visibility = _remotePetImportState.IsBusy
            ? Visibility.Visible
            : Visibility.Collapsed;
        RemotePetImportInfoBar.Message = _remotePetImportState.ErrorMessage ?? string.Empty;
        RemotePetImportInfoBar.Title = "웹에서 펫을 가져오지 못했습니다";
        RemotePetImportInfoBar.IsOpen = !string.IsNullOrWhiteSpace(
            _remotePetImportState.ErrorMessage);
    }

    private async void ImportPackageButton_Click(object sender, RoutedEventArgs e)
    {
        if (Application.Current is not App app || app.MainWindowHandle == IntPtr.Zero)
        {
            return;
        }

        var picker = new FileOpenPicker
        {
            SuggestedStartLocation = PickerLocationId.Downloads,
            ViewMode = PickerViewMode.List,
        };
        picker.FileTypeFilter.Add(".monglepet");
        WinRT.Interop.InitializeWithWindow.Initialize(picker, app.MainWindowHandle);
        global::Windows.Storage.StorageFile? file = await picker.PickSingleFileAsync();
        if (file is null)
        {
            return;
        }

        PetPackageImportReview review;
        try
        {
            review = app.ReviewPackage(file.Path);
        }
        catch (Exception exception)
        {
            ShowLibraryMessage(InfoBarSeverity.Error, "가져오기 실패", exception.Message);
            return;
        }

        await ReviewAndImportPackageAsync(app, review, usesRemoteErrorSurface: false);
    }

    private async Task ReviewAndImportPackageAsync(
        App app,
        PetPackageImportReview review,
        bool usesRemoteErrorSurface)
    {
        PetRecommendedProfileApplyOptions? options = await ShowImportReview(review);
        if (options is null)
        {
            return;
        }

        try
        {
            InstalledPetPackage installed = app.ImportReviewedPackage(
                review,
                options);
            ShowLibraryMessage(
                InfoBarSeverity.Success,
                "가져오기 완료",
                $"'{installed.Package.Manifest.DisplayName}'을(를) 설치하고 현재 펫으로 전환했습니다.");
        }
        catch (PetLibraryException exception)
            when (exception.Error == PetLibraryError.DuplicatePackage &&
                  exception.MatchingInstallationIds.Count > 0)
        {
            await ResolveDuplicateImport(
                app,
                review,
                exception.MatchingInstallationIds[0],
                options,
                usesRemoteErrorSurface);
        }
        catch (Exception exception)
        {
            ShowImportFailure(usesRemoteErrorSurface, exception.Message);
        }

        RefreshLibraryState();
        RefreshOverlayState();
        RefreshBehaviorState();
    }

    private async Task ResolveDuplicateImport(
        App app,
        PetPackageImportReview review,
        Guid existingInstallationId,
        PetRecommendedProfileApplyOptions optionsForSeparateInstall,
        bool usesRemoteErrorSurface)
    {
        var replaceProfileCheckBox = new CheckBox
        {
            Content = "교체하면서 권장 설정으로 기존 로컬 설정도 바꾸기",
            IsEnabled = review.CanApplyRecommendedProfile &&
                optionsForSeparateInstall.AppliesProfile,
            IsChecked = false,
        };
        var content = new StackPanel { Spacing = 10 };
        content.Children.Add(new TextBlock
        {
            Text = "기존 설치 UUID를 유지해 교체하거나, 편집 가능한 별도 사본으로 설치할 수 있습니다. 교체 시 로컬 설정은 기본적으로 보존됩니다.",
            TextWrapping = TextWrapping.Wrap,
        });
        content.Children.Add(replaceProfileCheckBox);
        var dialog = new ContentDialog
        {
            XamlRoot = XamlRoot,
            Title = "같은 펫 패키지가 이미 설치되어 있습니다",
            Content = content,
            PrimaryButtonText = "기존 설치 교체",
            SecondaryButtonText = "별도 설치",
            CloseButtonText = "취소",
            DefaultButton = ContentDialogButton.Close,
        };
        ContentDialogResult result = await dialog.ShowAsync();
        try
        {
            InstalledPetPackage? installed = result switch
            {
                ContentDialogResult.Primary => app.ImportReviewedPackage(
                    review,
                    replaceProfileCheckBox.IsChecked == true
                        ? optionsForSeparateInstall
                        : PetRecommendedProfileApplyOptions.None,
                    PetPackageInstallMode.Replace,
                    existingInstallationId),
                ContentDialogResult.Secondary => app.ImportReviewedPackage(
                    review,
                    optionsForSeparateInstall,
                    PetPackageInstallMode.InstallSeparately),
                _ => null,
            };
            if (installed is not null)
            {
                ShowLibraryMessage(
                    InfoBarSeverity.Success,
                    "가져오기 완료",
                    $"'{installed.Package.Manifest.DisplayName}'을 설치하고 전환했습니다.");
            }
        }
        catch (Exception exception)
        {
            ShowImportFailure(usesRemoteErrorSurface, exception.Message);
        }
    }

    private void ShowImportFailure(bool usesRemoteErrorSurface, string message)
    {
        if (usesRemoteErrorSurface)
        {
            _remotePetImportState = _remotePetImportState.Fail(message);
            RenderRemotePetImportState();
            return;
        }

        ShowLibraryMessage(InfoBarSeverity.Error, "가져오기 실패", message);
    }

    private async Task<PetRecommendedProfileApplyOptions?> ShowImportReview(
        PetPackageImportReview review)
    {
        var content = new StackPanel { Spacing = 10, MaxWidth = 520 };
        content.Children.Add(new TextBlock
        {
            Text = $"{review.Manifest.DisplayName}  v{review.Manifest.Version}\n" +
                   $"제작자: {review.Manifest.Author}\n" +
                   $"모션: {review.Manifest.Motions.Count}개",
            TextWrapping = TextWrapping.Wrap,
        });
        if (review.CompatibilityAdvisory is { HasWarning: true } advisory)
        {
            string versionLine = advisory.RecommendsUpdate &&
                advisory.RequiredMinimumAppVersion is { } required
                    ? $"이 펫은 MonglePet {required} 이상을 권장합니다. 현재 앱은 {advisory.CurrentAppVersion}입니다."
                    : $"이 펫은 현재 앱보다 새로운 MonglePet {advisory.CreatedWithAppVersion}에서 제작되었습니다.";
            var warning = new InfoBar
            {
                IsOpen = true,
                IsClosable = false,
                Severity = InfoBarSeverity.Warning,
                Title = "MonglePet 업데이트를 권장합니다",
                Message = versionLine + " 일부 기능이 적용되지 않거나 다르게 보일 수 있지만 설치는 계속할 수 있습니다.",
            };
            var downloadButton = new Button
            {
                Content = "MonglePet 다운로드 페이지 열기",
                HorizontalAlignment = HorizontalAlignment.Left,
            };
            downloadButton.Click += async (_, _) => await global::Windows.System.Launcher.LaunchUriAsync(
                new Uri(PetCompatibilityAdvisory.DownloadPageUrl));
            content.Children.Add(warning);
            content.Children.Add(downloadButton);
        }
        var apply = new CheckBox
        {
            Content = "권장 펫 설정도 적용",
            IsEnabled = review.CanApplyRecommendedProfile,
            IsChecked = false,
        };
        CheckBox Option(string text, bool defaultValue = true) => new()
        {
            Content = text,
            IsChecked = defaultValue,
            IsEnabled = false,
            Margin = new Thickness(20, 0, 0, 0),
        };
        CheckBox behavior = Option("평상시 행동과 조건 규칙");
        CheckBox applicationRules = Option("앱 사용 규칙", defaultValue: false);
        CheckBox movement = Option("이동 설정");
        CheckBox petting = Option("쓰다듬기 행동");
        CheckBox speech = Option("말풍선 설정");
        CheckBox display = Option("크기·투명도·클릭 통과 표시 설정");
        CheckBox[] options = [behavior, applicationRules, movement, petting, speech, display];
        apply.Checked += (_, _) =>
        {
            foreach (CheckBox option in options) option.IsEnabled = true;
        };
        apply.Unchecked += (_, _) =>
        {
            foreach (CheckBox option in options) option.IsEnabled = false;
        };
        behavior.Unchecked += (_, _) =>
        {
            movement.IsChecked = false;
            petting.IsChecked = false;
            applicationRules.IsChecked = false;
            movement.IsEnabled = false;
            petting.IsEnabled = false;
            applicationRules.IsEnabled = false;
        };
        behavior.Checked += (_, _) =>
        {
            bool enabled = apply.IsChecked == true;
            movement.IsEnabled = enabled;
            petting.IsEnabled = enabled;
            applicationRules.IsEnabled = enabled;
        };
        if (review.RecommendedProfile is { } profile)
        {
            content.Children.Add(new TextBlock
            {
                Text = RecommendedProfileSummary(profile),
                TextWrapping = TextWrapping.Wrap,
            });
            content.Children.Add(apply);
            foreach (CheckBox option in options) content.Children.Add(option);
        }
        else if (review.ContainsRecommendedProfile)
        {
            content.Children.Add(new TextBlock
            {
                Text = $"권장 설정은 적용할 수 없습니다. 펫만 설치할 수 있습니다.\n{review.RecommendedProfileIssueDetail}",
                TextWrapping = TextWrapping.Wrap,
            });
        }
        else
        {
            content.Children.Add(new TextBlock { Text = "권장 설정이 포함되지 않았습니다." });
        }

        var dialog = new ContentDialog
        {
            XamlRoot = XamlRoot,
            Title = "가져오기 검토",
            Content = content,
            PrimaryButtonText = "설치",
            CloseButtonText = "취소",
            DefaultButton = ContentDialogButton.Primary,
        };
        if (await dialog.ShowAsync() != ContentDialogResult.Primary)
        {
            return null;
        }
        bool applies = apply.IsChecked == true;
        return new PetRecommendedProfileApplyOptions(
            applies,
            applies && behavior.IsChecked == true,
            applies && applicationRules.IsChecked == true,
            applies && movement.IsChecked == true,
            applies && petting.IsChecked == true,
            applies && speech.IsChecked == true,
            applies && display.IsChecked == true);
    }

    private async void ExportPackageButton_Click(object sender, RoutedEventArgs e)
    {
        if (Application.Current is not App app ||
            app.MainWindowHandle == IntPtr.Zero ||
            app.ActiveInstallationId is null)
        {
            return;
        }

        ExportReviewOptions? options = await ShowExportReview(app.ActiveBehaviorProfile);
        if (options is null)
        {
            return;
        }

        var picker = new FileSavePicker
        {
            SuggestedStartLocation = PickerLocationId.Downloads,
            SuggestedFileName = SafeFileName(
                app.PetLibrary.GetInstallation(app.ActiveInstallationId.Value)
                    .Package.Manifest.DisplayName),
        };
        picker.FileTypeChoices.Add("MonglePet package", [".monglepet"]);
        WinRT.Interop.InitializeWithWindow.Initialize(picker, app.MainWindowHandle);
        global::Windows.Storage.StorageFile? file = await picker.PickSaveFileAsync();
        if (file is null)
        {
            return;
        }

        try
        {
            app.ExportActivePackage(
                file.Path,
                options.Value.IncludesRecommendedProfile,
                options.Value.IncludesApplicationRules,
                options.Value.IncludesBehavior,
                options.Value.IncludesMovement,
                options.Value.IncludesPetting,
                options.Value.IncludesSpeech,
                options.Value.IncludesDisplay);
            ShowLibraryMessage(
                InfoBarSeverity.Success,
                "내보내기 완료",
                $"'{file.Name}' 파일을 만들었습니다.");
        }
        catch (Exception exception)
        {
            ShowLibraryMessage(InfoBarSeverity.Error, "내보내기 실패", exception.Message);
        }
    }

    private async Task<ExportReviewOptions?> ShowExportReview(BehaviorProfile profile)
    {
        bool hasApplicationRules = profile.AutomaticRules.Any(
            rule => rule.Condition is RuleCondition.Application);
        var includeProfile = new CheckBox
        {
            Content = "펫 설정도 함께 공유",
            IsChecked = true,
            Visibility = Visibility.Collapsed,
        };
        var includeApplicationRules = new CheckBox
        {
            Content = "앱 사용 규칙도 포함",
            IsChecked = false,
            IsEnabled = hasApplicationRules,
            Visibility = hasApplicationRules ? Visibility.Visible : Visibility.Collapsed,
        };
        CheckBox Option(string text) => new()
        {
            Content = text,
            IsChecked = true,
            IsEnabled = false,
            Margin = new Thickness(20, 0, 0, 0),
        };
        CheckBox includeBehavior = Option("평상시 행동과 조건 규칙");
        CheckBox includeMovement = Option("이동 설정");
        CheckBox includePetting = Option("쓰다듬기 행동");
        CheckBox includeSpeech = Option("말풍선 설정");
        CheckBox includeDisplay = Option("크기·투명도·클릭 통과 표시 설정");
        CheckBox[] portableOptions =
            [includeBehavior, includeMovement, includePetting, includeSpeech, includeDisplay];
        includeProfile.Checked += (_, _) =>
        {
            includeApplicationRules.IsEnabled = hasApplicationRules;
            foreach (CheckBox option in portableOptions) option.IsEnabled = true;
        };
        includeProfile.Unchecked += (_, _) =>
        {
            includeApplicationRules.IsChecked = false;
            includeApplicationRules.IsEnabled = false;
            foreach (CheckBox option in portableOptions)
            {
                option.IsChecked = true;
                option.IsEnabled = false;
            }
        };
        includeBehavior.Unchecked += (_, _) =>
        {
            includeMovement.IsChecked = false;
            includePetting.IsChecked = false;
            includeMovement.IsEnabled = false;
            includePetting.IsEnabled = false;
        };
        includeBehavior.Checked += (_, _) =>
        {
            bool enabled = includeProfile.IsChecked == true;
            includeMovement.IsEnabled = enabled;
            includePetting.IsEnabled = enabled;
        };
        var rights = new CheckBox
        {
            Content = "이 이미지 자산을 공유할 권한이 있음을 확인합니다.",
            IsChecked = false,
        };
        var content = new StackPanel { Spacing = 10, MaxWidth = 520 };
        content.Children.Add(new TextBlock
        {
            Text = "평상시 행동, 조건 규칙 순서, 각 이동 방식, 쓰다듬기, 말풍선과 휴대 가능한 표시 설정을 함께 저장합니다. 화면 위치·모니터·활성 인스턴스 같은 기기 전용 값은 제외됩니다.",
            TextWrapping = TextWrapping.Wrap,
        });
        content.Children.Add(includeApplicationRules);
        content.Children.Add(new TextBlock
        {
            Text = RecommendedProfileSummary(profile),
            TextWrapping = TextWrapping.Wrap,
        });
        content.Children.Add(rights);
        var dialog = new ContentDialog
        {
            XamlRoot = XamlRoot,
            Title = "현재 펫 내보내기",
            Content = content,
            PrimaryButtonText = "저장 위치 선택",
            CloseButtonText = "취소",
            IsPrimaryButtonEnabled = false,
            DefaultButton = ContentDialogButton.Primary,
        };
        rights.Checked += (_, _) => dialog.IsPrimaryButtonEnabled = true;
        rights.Unchecked += (_, _) => dialog.IsPrimaryButtonEnabled = false;
        if (await dialog.ShowAsync() != ContentDialogResult.Primary)
        {
            return null;
        }
        return new ExportReviewOptions(
            includeProfile.IsChecked == true,
            includeProfile.IsChecked == true && includeApplicationRules.IsChecked == true,
            includeProfile.IsChecked == true && includeBehavior.IsChecked == true,
            includeProfile.IsChecked == true && includeMovement.IsChecked == true,
            includeProfile.IsChecked == true && includePetting.IsChecked == true,
            includeProfile.IsChecked == true && includeSpeech.IsChecked == true,
            includeProfile.IsChecked == true && includeDisplay.IsChecked == true);
    }

    private static string RecommendedProfileSummary(BehaviorProfile profile)
    {
        int stepCount = profile.Sequences.Sum(sequence => sequence.Steps.Count);
        int enabledRules = profile.AutomaticRules.Count(rule => rule.IsEnabled);
        int periodicPhrases = profile.Speech.Phrases.Count(
            phrase => phrase.Trigger is PetSpeechTrigger.Periodic);
        string mode = profile.StationaryBehaviorMode switch
        {
            StationaryBehaviorMode.Random => "랜덤 선택",
            _ => "하나 선택",
        };
        string movement = profile.Movement.Mode switch
        {
            PetMovementMode.Fixed => "위치 고정",
            PetMovementMode.CursorFollowing => "마우스 따라가기",
            PetMovementMode.FreeRoaming => "자유 이동",
            PetMovementMode.CursorAvoiding => "마우스 도망가기",
            _ => "위치 고정",
        };
        IReadOnlyDictionary<string, string> names = profile.Sequences
            .ToDictionary(sequence => sequence.Id, sequence => sequence.DisplayName, StringComparer.Ordinal);
        IEnumerable<string> selectedIds = profile.StationaryBehaviorMode == StationaryBehaviorMode.Random
            ? profile.RandomSequences
            : profile.StationarySequenceId is { } stationary ? [stationary] : [];
        string selected = string.Join(", ", selectedIds
            .Select(id => names.GetValueOrDefault(id))
            .Where(name => !string.IsNullOrWhiteSpace(name))
            .Take(3));
        string selectedDetail = selected.Length == 0
            ? profile.StationaryBehaviorMode == StationaryBehaviorMode.Fixed
                ? " · 선택 기본 행동"
                : string.Empty
            : $" · 선택 {selected}";
        string priority = string.Join(" → ", profile.RulePriorityOrder.Select(kind => kind switch
        {
            AutomaticRuleKind.Movement => "이동",
            AutomaticRuleKind.Idle => "입력 없음",
            AutomaticRuleKind.Application => "앱 사용",
            _ => "알 수 없음",
        }));
        return $"권장 설정: {mode}{selectedDetail} · 행동 {profile.Sequences.Count}개/단계 {stepCount}개 · " +
               $"조건 규칙 {profile.AutomaticRules.Count}개/사용 {enabledRules}개 · 우선순위 {priority} · 이동 {movement} · " +
               $"말풍선 {(profile.Speech.IsEnabled ? "사용" : "사용 안 함")}, 주기 대사 {periodicPhrases}개";
    }

    private static string SafeFileName(string value)
    {
        char[] invalid = Path.GetInvalidFileNameChars();
        string safe = string.Concat(value.Select(character =>
            invalid.Contains(character) ? '_' : character)).Trim();
        return string.IsNullOrWhiteSpace(safe) ? "MonglePet" : safe;
    }

    private void InstallSampleButton_Click(object sender, RoutedEventArgs e)
    {
        if (Application.Current is not App app)
        {
            return;
        }

        try
        {
            ShowLibraryMessage(
                InfoBarSeverity.Success,
                "펫 라이브러리",
                app.ActivateBuiltInMongle());
        }
        catch (Exception exception)
        {
            ShowLibraryMessage(InfoBarSeverity.Error, "설치 실패", exception.Message);
        }

        RefreshLibraryState();
        RefreshOverlayState();
        RefreshBehaviorState();
    }

    private void ActivatePetButton_Click(object sender, RoutedEventArgs e)
    {
        if (Application.Current is not App app ||
            sender is not Button { Tag: string idText } ||
            !Guid.TryParse(idText, out Guid installationId))
        {
            return;
        }

        try
        {
            InstalledPetPackage installed = app.ActivateInstallation(installationId);
            ShowLibraryMessage(
                InfoBarSeverity.Success,
                "현재 펫 변경",
                $"'{installed.Package.Manifest.DisplayName}'로 전환했습니다.");
        }
        catch (Exception exception)
        {
            ShowLibraryMessage(InfoBarSeverity.Error, "전환 실패", exception.Message);
        }

        RefreshLibraryState();
        RefreshOverlayState();
        RefreshBehaviorState();
    }

    private void CurrentPetComboBox_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_isRefreshingPetChoice || !_isLoaded ||
            Application.Current is not App app ||
            CurrentPetComboBox.SelectedItem is not PetChoiceItem selected)
        {
            return;
        }
        try
        {
            if (selected.InstallationId is Guid installationId)
            {
                app.ActivateInstallation(installationId);
            }
            else
            {
                app.ActivateBundledPet();
            }
            ShowLibraryMessage(
                InfoBarSeverity.Success,
                "현재 펫 변경",
                $"'{selected.DisplayName}' 펫으로 전환했습니다.");
        }
        catch (Exception exception)
        {
            ShowLibraryMessage(InfoBarSeverity.Error, "펫 전환 실패", exception.Message);
        }
        RefreshLibraryState();
        RefreshOverlayState();
        RefreshBehaviorState();
    }

    private async void RemovePetButton_Click(object sender, RoutedEventArgs e)
    {
        if (Application.Current is not App app ||
            sender is not Button { Tag: string idText } ||
            !Guid.TryParse(idText, out Guid installationId))
        {
            return;
        }

        InstalledPetPackage removing;
        try
        {
            removing = app.PetLibrary.GetInstallation(installationId);
        }
        catch (Exception exception)
        {
            ShowLibraryMessage(InfoBarSeverity.Error, "삭제 실패", exception.Message);
            return;
        }

        var dialog = new ContentDialog
        {
            XamlRoot = XamlRoot,
            Title = $"'{removing.Package.Manifest.DisplayName}' 설치를 삭제할까요?",
            Content = "라이브러리의 이 설치 사본이 삭제됩니다. 원본 .monglepet 파일은 삭제하지 않습니다.",
            PrimaryButtonText = "삭제",
            CloseButtonText = "취소",
            DefaultButton = ContentDialogButton.Close,
        };
        if (await dialog.ShowAsync() != ContentDialogResult.Primary)
        {
            return;
        }

        try
        {
            ShowLibraryMessage(
                InfoBarSeverity.Success,
                "설치 삭제",
                app.RemoveInstallation(installationId));
        }
        catch (Exception exception)
        {
            ShowLibraryMessage(InfoBarSeverity.Error, "삭제 실패", exception.Message);
        }

        RefreshLibraryState();
        RefreshOverlayState();
        RefreshBehaviorState();
    }

    private void PetAnimationsList_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        RefreshPetEditorButtonState();
        if (Application.Current is App app &&
            app.ActivePackage is { } package &&
            PetAnimationsList.SelectedItem is PetAnimationItem selected)
        {
            PetPackageMotion? motion = package.Manifest.Motions.FirstOrDefault(value =>
                value.Id == selected.Id);
            if (motion is not null)
            {
                CurrentPetMotionText.Text =
                    $"선택한 애니메이션: {motion.Id} · {motion.Frames.Count}프레임 · " +
                    (motion.Loop ? "반복 재생" : "한 번 재생");
            }
            StartPetAnimationPreview(package, selected.Id);
        }
    }

    private async void CreatePetButton_Click(object sender, RoutedEventArgs e)
    {
        if (Application.Current is not App app)
        {
            return;
        }

        PetAnimationEditorControl? editor = await ShowPetAnimationEditorAsync(
            "새 펫 만들기",
            "펫 만들기");
        if (editor is null)
        {
            return;
        }

        await RunPetEditAsync("새 펫 만들기", async () =>
        {
            InstalledPetPackage installed = await app.PetEditor.CreatePetAsync(editor.CreatePetRequest());
            app.AddInstallationAsNewInstance(installed.InstallationId);
            return $"'{installed.Package.Manifest.DisplayName}' 펫을 새 활성 펫으로 추가했습니다.";
        });
    }

    private async void AddPetAnimationButton_Click(object sender, RoutedEventArgs e)
    {
        if (!TryGetActiveInstalledPet(out App app, out InstalledPetPackage installed) ||
            !app.PetEditor.IsEditable(installed))
        {
            return;
        }

        PetAnimationEditorControl? editor = await ShowPetAnimationEditorAsync(
            "펫 애니메이션 추가",
            "추가",
            installed.Package);
        if (editor is null)
        {
            return;
        }
        UserPetAnimationRequest animationRequest = editor.CreateAnimationRequest();
        BehaviorProfile connectedProfile = ApplyAnimationBehaviorConnection(
            app.ActiveBehaviorProfile,
            editor.BehaviorConnectionRequest(),
            animationRequest.AnimationName);

        await RunPetEditAsync("애니메이션 추가", async () =>
        {
            InstalledPetPackage updated = await app.PetEditor.AddAnimationAsync(
                installed,
                animationRequest);
            try
            {
                app.SaveBehaviorProfile(connectedProfile);
            }
            catch
            {
                _ = app.PetEditor.RemoveAnimation(updated, animationRequest.AnimationName);
                throw;
            }
            app.ActivateInstallation(updated.InstallationId);
            return $"'{updated.Package.Manifest.DisplayName}'에 애니메이션을 추가했습니다.";
        });
    }

    private async void EditPetAnimationButton_Click(object sender, RoutedEventArgs e)
    {
        if (!TryGetSelectedEditableAnimation(
                out App app,
                out InstalledPetPackage installed,
                out PetPackageMotion motion))
        {
            return;
        }

        PetAnimationEditorControl? editor = await ShowPetAnimationEditorAsync(
            "펫 애니메이션 수정",
            "저장",
            installed.Package,
            motion);
        if (editor is null)
        {
            return;
        }

        UserPetAnimationUpdateRequest request = editor.CreateAnimationUpdateRequest(motion.Id);
        BehaviorProfile renamedProfile = BehaviorProfileMotionReferences.Replacing(
            app.ActiveBehaviorProfile,
            motion.Id,
            request.AnimationName);
        BehaviorProfile connectedProfile = ApplyAnimationBehaviorConnection(
            renamedProfile,
            editor.BehaviorConnectionRequest(),
            request.AnimationName);
        await RunPetEditAsync("애니메이션 수정", async () =>
        {
            InstalledPetPackage updated = await app.PetEditor.UpdateAnimationAsync(
                installed,
                request);
            app.SaveBehaviorProfile(connectedProfile);
            app.ActivateInstallation(updated.InstallationId);
            return $"'{motion.Id}' 애니메이션을 수정했습니다.";
        });
    }

    private async void DuplicatePetAnimationButton_Click(object sender, RoutedEventArgs e)
    {
        if (!TryGetSelectedEditableAnimation(
                out App app,
                out InstalledPetPackage installed,
                out PetPackageMotion motion))
        {
            return;
        }

        PetAnimationEditorControl? editor = await ShowPetAnimationEditorAsync(
            "애니메이션 복제",
            "복제본 저장",
            installed.Package,
            motion,
            AvailableAnimationCopyName(installed.Package.Manifest, motion.Id));
        if (editor is null)
        {
            return;
        }
        UserPetAnimationRequest animationRequest = editor.CreateAnimationRequest();
        BehaviorProfile connectedProfile = ApplyAnimationBehaviorConnection(
            app.ActiveBehaviorProfile,
            editor.BehaviorConnectionRequest(),
            animationRequest.AnimationName);
        await RunPetEditAsync("애니메이션 복제", async () =>
        {
            InstalledPetPackage updated = await app.PetEditor.AddAnimationAsync(
                installed,
                animationRequest);
            try
            {
                app.SaveBehaviorProfile(connectedProfile);
            }
            catch
            {
                _ = app.PetEditor.RemoveAnimation(updated, animationRequest.AnimationName);
                throw;
            }
            app.ActivateInstallation(updated.InstallationId);
            return $"'{motion.Id}' 애니메이션 복제본을 만들었습니다.";
        });
    }

    private static string AvailableAnimationCopyName(
        PetPackageManifest manifest,
        string sourceName)
    {
        string first = $"{sourceName} 복사본";
        if (!manifest.Motions.Any(motion => string.Equals(
                motion.Id,
                first,
                StringComparison.OrdinalIgnoreCase)))
        {
            return first;
        }
        for (int suffix = 2; suffix < 10_000; suffix++)
        {
            string candidate = $"{sourceName} 복사본 {suffix}";
            if (!manifest.Motions.Any(motion => string.Equals(
                    motion.Id,
                    candidate,
                    StringComparison.OrdinalIgnoreCase)))
            {
                return candidate;
            }
        }
        return $"{sourceName} 복사본 {Guid.NewGuid():N}";
    }

    private static BehaviorProfile ApplyAnimationBehaviorConnection(
        BehaviorProfile profile,
        AnimationBehaviorConnectionRequest request,
        string motionId) => request.Mode switch
    {
        AnimationBehaviorConnectionMode.CreateNew =>
            BehaviorProfileEditor.AddSequenceForMotion(
                profile,
                request.NewBehaviorName ?? motionId,
                motionId),
        AnimationBehaviorConnectionMode.AppendExisting
            when request.ExistingBehaviorId is { } sequenceId =>
                BehaviorProfileEditor.AppendMotionStep(profile, sequenceId, motionId),
        _ => profile,
    };

    private async Task<PetAnimationEditorControl?> ShowPetAnimationEditorAsync(
        string title,
        string primaryButtonText,
        LoadedPetPackage? package = null,
        PetPackageMotion? motion = null,
        string? suggestedAnimationName = null)
    {
        try
        {
            var editor = new PetAnimationEditorControl();
            if (package is not null)
            {
                await editor.ConfigureForAnimationAsync(package, motion);
                if (Application.Current is App app)
                {
                    editor.ConfigureBehaviorConnection(app.ActiveBehaviorProfile, motion?.Id);
                }
            }
            if (!string.IsNullOrWhiteSpace(suggestedAnimationName))
            {
                editor.SetAnimationName(suggestedAnimationName);
            }
            string description = package is null
                ? "펫 정보와 첫 애니메이션을 설정하고 PNG 또는 스프라이트 프레임을 추가합니다."
                : motion is null
                    ? "애니메이션 이름과 재생 방식을 정한 뒤 사용할 프레임을 추가합니다."
                    : "애니메이션 미리보기와 프레임 순서, 위치 및 재생 간격을 편집합니다.";
            var window = new EditorWindowHost(
                title,
                description,
                editor,
                primaryButtonText,
                "프레임은 16~60000ms 간격을 사용하며 취소하면 기존 펫은 변경되지 않습니다.",
                width: 900,
                height: 760,
                validation: () => editor.ValidationError(package is null));
            editor.OwnerWindowHandle = window.WindowHandle;
            nint ownerWindow = Application.Current is App currentApp
                ? currentApp.MainWindowHandle
                : nint.Zero;
            return await window.ShowAsync(ownerWindow)
                ? editor
                : null;
        }
        catch (Exception exception)
        {
            ShowLibraryMessage(
                InfoBarSeverity.Error,
                $"{title} 열기 실패",
                exception.Message);
            return null;
        }
    }

    private async void DeletePetAnimationButton_Click(object sender, RoutedEventArgs e)
    {
        if (!TryGetSelectedEditableAnimation(
                out App app,
                out InstalledPetPackage installed,
                out PetPackageMotion motion))
        {
            return;
        }

        var dialog = new ContentDialog
        {
            XamlRoot = XamlRoot,
            Title = $"'{motion.Id}' 애니메이션을 삭제할까요?",
            Content = "이 작업은 현재 편집 가능한 펫 패키지에서 애니메이션과 더 이상 사용하지 않는 atlas 이미지를 제거합니다.",
            PrimaryButtonText = "삭제",
            CloseButtonText = "취소",
            DefaultButton = ContentDialogButton.Close,
        };
        if (await dialog.ShowAsync() != ContentDialogResult.Primary)
        {
            return;
        }

        await RunPetEditAsync("애니메이션 삭제", () =>
        {
            InstalledPetPackage updated = app.PetEditor.RemoveAnimation(installed, motion.Id);
            app.ReplaceActiveMotionReferences(motion.Id, replacementMotionId: null);
            app.ActivateInstallation(updated.InstallationId);
            return Task.FromResult($"'{motion.Id}' 애니메이션을 삭제했습니다.");
        });
    }

    private async void EditPetDetailsButton_Click(object sender, RoutedEventArgs e)
    {
        if (!TryGetActiveInstalledPet(out App app, out InstalledPetPackage installed) ||
            !app.PetEditor.IsEditable(installed))
        {
            return;
        }

        PetPackageManifest manifest = installed.Package.Manifest;
        var name = new TextBox { Header = "펫 이름", Text = manifest.DisplayName };
        var author = new TextBox { Header = "제작자", Text = manifest.Author };
        var version = new TextBox { Header = "버전", Text = manifest.Version };
        var versionError = new TextBlock
        {
            Text = "버전은 1.0.0처럼 MAJOR.MINOR.PATCH 형식으로 입력해 주세요.",
            Foreground = new SolidColorBrush(Microsoft.UI.Colors.IndianRed),
            TextWrapping = TextWrapping.Wrap,
            Visibility = Visibility.Collapsed,
        };
        var description = new TextBox
        {
            Header = "설명",
            Text = manifest.Description ?? string.Empty,
            AcceptsReturn = true,
            TextWrapping = TextWrapping.Wrap,
        };
        var defaultMotion = new ComboBox
        {
            Header = "기본 애니메이션",
            ItemsSource = manifest.Motions.Select(value => value.Id).ToArray(),
            SelectedItem = installed.Package.DefaultMotionId,
        };
        var content = new StackPanel { Width = 520, Spacing = 10 };
        content.Children.Add(name);
        content.Children.Add(author);
        content.Children.Add(version);
        content.Children.Add(versionError);
        content.Children.Add(description);
        content.Children.Add(defaultMotion);
        var dialog = new ContentDialog
        {
            XamlRoot = XamlRoot,
            Title = "펫 정보 수정",
            Content = content,
            PrimaryButtonText = "저장",
            CloseButtonText = "취소",
            DefaultButton = ContentDialogButton.Primary,
        };
        dialog.Closing += (_, args) =>
        {
            if (args.Result != ContentDialogResult.Primary ||
                UserPetPackageEditor.IsValidEditableVersion(version.Text))
            {
                return;
            }
            args.Cancel = true;
            versionError.Visibility = Visibility.Visible;
            version.Focus(FocusState.Programmatic);
            version.SelectAll();
        };
        if (await dialog.ShowAsync() != ContentDialogResult.Primary)
        {
            return;
        }

        await RunPetEditAsync("펫 정보 수정", () =>
        {
            InstalledPetPackage updated = app.PetEditor.UpdateDetails(
                installed,
                new UserPetDetailsRequest(
                    name.Text,
                    version.Text,
                    author.Text,
                    description.Text,
                    defaultMotion.SelectedItem?.ToString() ?? installed.Package.DefaultMotionId));
            app.ActivateInstallation(updated.InstallationId);
            return Task.FromResult($"'{updated.Package.Manifest.DisplayName}' 정보를 수정했습니다.");
        });
    }

    private async void CreateEditablePetCopyButton_Click(object sender, RoutedEventArgs e)
    {
        if (Application.Current is not App app || app.ActivePackage is not { } package)
        {
            return;
        }

        var name = new TextBox
        {
            Header = "사본 이름",
            Text = $"{package.Manifest.DisplayName} 사본",
            MinWidth = 360,
        };
        var content = new StackPanel
        {
            Spacing = 12,
            MaxWidth = 520,
        };
        content.Children.Add(new TextBlock
        {
            Text = "현재 펫은 그대로 보존됩니다. 사본은 새 패키지 ID를 가진 독립된 사용자 펫으로 설치되어 정보와 애니메이션을 수정할 수 있습니다.",
            TextWrapping = TextWrapping.Wrap,
        });
        content.Children.Add(name);
        content.Children.Add(new TextBlock
        {
            Text = $"원본 펫: {package.Manifest.DisplayName}\n" +
                   $"제작자: {package.Manifest.Author}\n" +
                   $"버전: {package.Manifest.Version}\n" +
                   $"원본 패키지 ID: {package.Manifest.Id}",
            TextWrapping = TextWrapping.Wrap,
            Opacity = 0.72,
            IsTextSelectionEnabled = true,
        });
        content.Children.Add(new TextBlock
        {
            Text = "애니메이션과 미리보기 자산을 복사하고, 현재 행동·자동 동작·이동·쓰다듬기·말풍선 설정도 새 펫에 복사합니다.",
            TextWrapping = TextWrapping.Wrap,
            Opacity = 0.72,
        });
        var dialog = new ContentDialog
        {
            XamlRoot = XamlRoot,
            Title = "펫 사본 새로 만들기",
            Content = content,
            PrimaryButtonText = "사본 만들기",
            CloseButtonText = "취소",
            DefaultButton = ContentDialogButton.Primary,
        };
        if (await dialog.ShowAsync() != ContentDialogResult.Primary)
        {
            return;
        }

        BehaviorProfile sourceProfile = app.ActiveBehaviorProfile;
        OverlaySettings sourceOverlay = app.CurrentSettings.SelectedPetInstance?.Overlay
            ?? OverlaySettings.Default;
        await RunPetEditAsync("편집 가능한 사본", () =>
        {
            InstalledPetPackage copied = app.PetEditor.CreateEditableCopy(
                package,
                package.PackageRootPath,
                name.Text);
            app.AddInstallationCopyAsNewInstance(
                copied.InstallationId,
                sourceProfile,
                sourceOverlay);
            return Task.FromResult($"'{copied.Package.Manifest.DisplayName}' 사본을 새 활성 펫으로 추가했습니다.");
        });
    }

    private async void DeleteCurrentPetButton_Click(object sender, RoutedEventArgs e)
    {
        if (!TryGetActiveInstalledPet(out App app, out InstalledPetPackage installed))
        {
            return;
        }

        var dialog = new ContentDialog
        {
            XamlRoot = XamlRoot,
            Title = $"'{installed.Package.Manifest.DisplayName}' 펫을 삭제할까요?",
            Content = "MonglePet 라이브러리의 설치 사본과 이 펫의 로컬 설정이 삭제됩니다. 원본 .monglepet 파일은 삭제하지 않습니다.",
            PrimaryButtonText = "펫 삭제",
            CloseButtonText = "취소",
            DefaultButton = ContentDialogButton.Close,
        };
        if (await dialog.ShowAsync() != ContentDialogResult.Primary)
        {
            return;
        }

        await RunPetEditAsync("펫 삭제", () => Task.FromResult(
            app.RemoveInstallation(installed.InstallationId)));
    }

    private bool TryGetActiveInstalledPet(out App app, out InstalledPetPackage installed)
    {
        app = (Application.Current as App)!;
        installed = null!;
        if (app is null || app.ActiveInstallationId is not Guid installationId)
        {
            return false;
        }
        try
        {
            installed = app.PetLibrary.GetInstallation(installationId);
            return true;
        }
        catch (Exception exception)
        {
            ShowLibraryMessage(InfoBarSeverity.Error, "펫을 열 수 없음", exception.Message);
            return false;
        }
    }

    private bool TryGetSelectedEditableAnimation(
        out App app,
        out InstalledPetPackage installed,
        out PetPackageMotion motion)
    {
        motion = null!;
        if (!TryGetActiveInstalledPet(out app, out installed) ||
            !app.PetEditor.IsEditable(installed) ||
            PetAnimationsList.SelectedItem is not PetAnimationItem selected)
        {
            return false;
        }
        motion = installed.Package.Manifest.Motions.First(value => value.Id == selected.Id);
        return true;
    }

    private async Task RunPetEditAsync(string title, Func<Task<string>> operation)
    {
        try
        {
            string message = await operation();
            ShowLibraryMessage(InfoBarSeverity.Success, title, message);
        }
        catch (Exception exception)
        {
            ShowLibraryMessage(InfoBarSeverity.Error, $"{title} 실패", exception.Message);
        }
        RefreshLibraryState();
        RefreshOverlayState();
        RefreshBehaviorState();
    }

    private void RefreshOverlayState()
    {
        if (Application.Current is not App app)
        {
            VisibilityButton.IsEnabled = false;
            ClickThroughToggle.IsEnabled = false;
            OverlayWidthSlider.IsEnabled = false;
            OverlayOpacitySlider.IsEnabled = false;
            PointerOverlapFadeToggle.IsEnabled = false;
            PointerOverlapOpacitySlider.IsEnabled = false;
            PixelArtToggle.IsEnabled = false;
            return;
        }

        VisibilityButton.Content =
            app.CurrentSettings.SelectedPetInstance?.Presentation == PetPresentation.Awake
                ? "펫 재우기"
                : "펫 깨우기";
        bool canEdit = app.SettingsStore.IsWritingEnabled;
        VisibilityButton.IsEnabled = canEdit;
        ClickThroughToggle.IsEnabled = canEdit;
        OverlayWidthSlider.IsEnabled = canEdit;
        OverlayOpacitySlider.IsEnabled = canEdit;
        PointerOverlapFadeToggle.IsEnabled = canEdit;
        PixelArtToggle.IsEnabled = canEdit;
        _isRefreshingDisplayControls = true;
        try
        {
            OverlaySettings settings = app.CurrentSettings.Overlay;
            ClickThroughToggle.IsOn = settings.ClickThrough;
            OverlayWidthSlider.Value = settings.Width;
            OverlayOpacitySlider.Value = settings.Opacity;
            PointerOverlapFadeToggle.IsOn = settings.PointerOverlapFadeEnabled;
            PointerOverlapOpacitySlider.Value = settings.PointerOverlapOpacity;
            PointerOverlapOpacitySlider.IsEnabled = canEdit &&
                settings.PointerOverlapFadeEnabled;
            PixelArtToggle.IsOn = settings.PixelArtRendering;
            UpdateDisplayValueLabels();
        }
        finally
        {
            _isRefreshingDisplayControls = false;
        }
    }

    private void App_InitializationCompleted(object? sender, EventArgs e) =>
        DispatcherQueue.TryEnqueue(() =>
        {
            if (!_isLoaded)
            {
                return;
            }
            RefreshOverlayState();
            RefreshActivePetsState();
            RefreshLibraryState();
            RefreshBehaviorState();
        });

    private void App_SettingsStateChanged(object? sender, EventArgs e)
    {
        bool preservesMovementEditor = _isPersistingMovementControls;
        bool preservesBehaviorEditor = _isPersistingBehaviorControls;
        DispatcherQueue.TryEnqueue(() =>
        {
            if (!_isLoaded)
            {
                return;
            }
            if (preservesMovementEditor)
            {
                // The controls already contain the values that were just
                // persisted. Rebuilding unrelated display controls and active
                // pet cards here makes WinUI recalculate pointer hit testing,
                // which can replace the NumberBox I-beam cursor and disrupt
                // continued editing.
                return;
            }
            if (preservesBehaviorEditor)
            {
                return;
            }
            RefreshOverlayState();
            RefreshActivePetsState();
            RefreshLibraryState();
            RefreshBehaviorState();
        });
    }

    private void App_SelectedPetInstanceChanged(object? sender, EventArgs e) =>
        DispatcherQueue.TryEnqueue(() =>
        {
            if (!_isLoaded)
            {
                return;
            }

            RefreshActivePetsState();
            if (_currentSettingsSection == "activePets")
            {
                _selectedPetDetailsAreStale = true;
                return;
            }

            _selectedPetDetailsAreStale = false;
            RefreshOverlayState();
            RefreshLibraryState();
            RefreshBehaviorState();
        });

    private void RefreshActivePetsState()
    {
        if (Application.Current is not App app || ActivePetsList is null)
        {
            return;
        }

        List<ActivePetInstance> orderedInstances = app.CurrentSettings.ActivePetInstances
            .OrderBy(value => value.DisplayOrder)
            .ToList();
        HashSet<Guid> currentInstanceIds = orderedInstances
            .Select(value => value.InstanceId)
            .ToHashSet();

        for (int index = _activePets.Count - 1; index >= 0; index--)
        {
            if (!currentInstanceIds.Contains(_activePets[index].InstanceId))
            {
                _activePets.RemoveAt(index);
            }
        }

        for (int targetIndex = 0; targetIndex < orderedInstances.Count; targetIndex++)
        {
            ActivePetInstance instance = orderedInstances[targetIndex];
            string originalName;
            try
            {
                originalName = app.PetDisplayName(instance.PetKey);
            }
            catch (Exception)
            {
                originalName = "찾을 수 없는 펫";
            }
            string nickname = instance.Nickname ?? originalName;
            PetMovementMode movementMode = app.CurrentSettings.BehaviorProfiles
                .FirstOrDefault(value => value.ProfileId == instance.BehaviorProfileId)?
                .Movement.Mode ?? PetMovementMode.Fixed;
            string detail =
                $"{originalName} · {MovementModeTitle(movementMode)} · " +
                $"{(instance.Overlay.ClickThrough ? "클릭 통과" : "상호작용")} · " +
                $"{(instance.Presentation == PetPresentation.Awake ? "표시" : "숨김")}";
            string presentationCommand = instance.Presentation == PetPresentation.Awake
                ? "재우기"
                : "깨우기";

            int currentIndex = IndexOfActivePet(instance.InstanceId);
            ActivePetItem item;
            if (currentIndex < 0)
            {
                item = new ActivePetItem(instance.InstanceId);
                _activePets.Insert(targetIndex, item);
            }
            else
            {
                if (currentIndex != targetIndex)
                {
                    _activePets.Move(currentIndex, targetIndex);
                }
                item = _activePets[targetIndex];
            }

            item.Update(
                nickname,
                detail,
                presentationCommand,
                instance.DisplayOrder,
                instance.InstanceId == app.CurrentSettings.SelectedPetInstanceId);
            if (item.NeedsPreview(instance.PetKey))
            {
                string? previewPath = null;
                try
                {
                    previewPath = app.PetPackage(instance.InstanceId, instance.PetKey).PreviewFilePath;
                }
                catch
                {
                    // Keep the neutral pet placeholder when the package is unavailable.
                }
                if (item.BeginPreviewLoad(instance.PetKey, previewPath, out long previewGeneration))
                {
                    _ = LoadActivePetPreviewAsync(item, previewPath, previewGeneration);
                }
            }
        }
        SafeStartInfoBar.IsOpen = app.SafeStartRecovery is not null;
        ResumeWithoutLastSafeStartButton.Visibility = app.SafeStartRecovery is not null
            ? Visibility.Visible
            : Visibility.Collapsed;
    }

    private async Task LoadActivePetPreviewAsync(
        ActivePetItem item,
        string? previewPath,
        long generation)
    {
        if (string.IsNullOrWhiteSpace(previewPath))
        {
            item.CompletePreviewLoad(generation, null);
            return;
        }

        BitmapImage? bitmap = null;
        try
        {
            StorageFile file = await StorageFile.GetFileFromPathAsync(previewPath);
            using var stream = await file.OpenReadAsync();
            bitmap = new BitmapImage { DecodePixelWidth = 168 };
            await bitmap.SetSourceAsync(stream);
        }
        catch
        {
            // Keep the neutral pet placeholder for a missing or invalid preview.
        }

        if (_isLoaded)
        {
            item.CompletePreviewLoad(generation, bitmap);
        }
    }

    private int IndexOfActivePet(Guid instanceId)
    {
        for (int index = 0; index < _activePets.Count; index++)
        {
            if (_activePets[index].InstanceId == instanceId)
            {
                return index;
            }
        }

        return -1;
    }

    private async void AddActivePetButton_Click(object sender, RoutedEventArgs e)
    {
        if (Application.Current is not App app)
        {
            return;
        }
        var dialog = new ContentDialog
        {
            XamlRoot = XamlRoot,
            Title = "같은 펫 추가",
            Content = "현재 펫의 설정을 복사할까요? 어느 쪽이든 이후에는 독립적으로 저장됩니다.",
            PrimaryButtonText = "설정 복사",
            SecondaryButtonText = "기본 설정",
            CloseButtonText = "취소",
            DefaultButton = ContentDialogButton.Primary,
        };
        ContentDialogResult result = await dialog.ShowAsync();
        if (result is ContentDialogResult.Primary or ContentDialogResult.Secondary)
        {
            app.AddSamePetInstance(result == ContentDialogResult.Primary);
        }
    }

    private void ActivePetsList_ItemClick(object sender, ItemClickEventArgs e)
    {
        if (Application.Current is App app && e.ClickedItem is ActivePetItem item)
        {
            app.SelectPetInstance(item.InstanceId);
        }
    }

    private void ActivePetNicknameTextBox_LostFocus(object sender, RoutedEventArgs e)
    {
        if (Application.Current is App app && sender is TextBox { Tag: Guid instanceId } textBox)
        {
            app.RenamePetInstance(instanceId, textBox.Text);
        }
    }

    private void WakeAllPetsButton_Click(object sender, RoutedEventArgs e) =>
        (Application.Current as App)?.SetAllPetPresentations(PetPresentation.Awake);

    private void TuckAwayAllPetsButton_Click(object sender, RoutedEventArgs e) =>
        (Application.Current as App)?.SetAllPetPresentations(PetPresentation.TuckedAway);

    private void PauseAllPetsButton_Click(object sender, RoutedEventArgs e) =>
        (Application.Current as App)?.ToggleAllPetsPaused();

    private void ToggleActivePetButton_Click(object sender, RoutedEventArgs e)
    {
        if (Application.Current is not App app || sender is not Button { Tag: Guid instanceId })
        {
            return;
        }
        ActivePetInstance instance = app.CurrentSettings.ActivePetInstances.Single(value =>
            value.InstanceId == instanceId);
        app.SelectPetInstance(instanceId);
        app.SetUserPresentation(instance.Presentation == PetPresentation.Awake
            ? PetPresentation.TuckedAway
            : PetPresentation.Awake);
    }

    private async void RemoveActivePetButton_Click(object sender, RoutedEventArgs e)
    {
        if (Application.Current is not App app || sender is not Button { Tag: Guid instanceId })
        {
            return;
        }
        if (app.CurrentSettings.ActivePetInstances.Count <= 1)
        {
            ShowLibraryMessage(InfoBarSeverity.Warning, "활성 펫 제거", "최소 한 마리의 활성 펫은 남겨야 합니다.");
            return;
        }
        var dialog = new ContentDialog
        {
            XamlRoot = XamlRoot,
            Title = "활성 펫 제거",
            Content = "데스크톱 배치와 이 펫만의 설정을 제거합니다. 펫 보관함의 원본은 유지됩니다.",
            PrimaryButtonText = "제거",
            CloseButtonText = "취소",
            DefaultButton = ContentDialogButton.Close,
        };
        if (await dialog.ShowAsync() == ContentDialogResult.Primary)
        {
            app.RemovePetInstance(instanceId);
        }
    }

    private void MoveActivePetUpButton_Click(object sender, RoutedEventArgs e) =>
        MoveActivePet(sender, -1);

    private void MoveActivePetDownButton_Click(object sender, RoutedEventArgs e) =>
        MoveActivePet(sender, 1);

    private void MoveActivePet(object sender, int offset)
    {
        if (Application.Current is not App app || sender is not Button { Tag: Guid instanceId })
        {
            return;
        }
        List<ActivePetInstance> ordered = app.CurrentSettings.ActivePetInstances
            .OrderBy(value => value.DisplayOrder)
            .ToList();
        int index = ordered.FindIndex(value => value.InstanceId == instanceId);
        int target = Math.Clamp(index + offset, 0, ordered.Count - 1);
        if (target != index)
        {
            app.MovePetInstance(instanceId, target);
        }
    }

    private void ResumeAllSafeStartButton_Click(object sender, RoutedEventArgs e) =>
        (Application.Current as App)?.ResumeSafeStart(excludesLastRestoredInstance: false);

    private void ResumeWithoutLastSafeStartButton_Click(object sender, RoutedEventArgs e) =>
        (Application.Current as App)?.ResumeSafeStart(excludesLastRestoredInstance: true);

    private static string MovementModeTitle(PetMovementMode mode) => mode switch
    {
        PetMovementMode.Fixed => "위치 고정",
        PetMovementMode.CursorFollowing => "마우스 따라가기",
        PetMovementMode.FreeRoaming => "자유 이동",
        PetMovementMode.CursorAvoiding => "마우스 도망가기",
        _ => "이동",
    };

    private void RefreshLibraryState()
    {
        if (Application.Current is not App app)
        {
            return;
        }

        try
        {
            RefreshCurrentPetSummary(app.ActivePackage);
            string? selectedAnimationId = (PetAnimationsList.SelectedItem as PetAnimationItem)?.Id;
            _petAnimations.Clear();
            if (app.ActivePackage is { } activePackage)
            {
                foreach (PetPackageMotion motion in activePackage.Manifest.Motions)
                {
                    _petAnimations.Add(new PetAnimationItem(
                        motion.Id,
                        motion.Id,
                        $"{motion.Frames.Count}프레임 · {(motion.Loop ? "반복 재생" : "한 번 재생")}",
                        motion.Id == activePackage.DefaultMotionId ? "기본" : string.Empty));
                }
            }
            PetAnimationsList.SelectedItem = _petAnimations.FirstOrDefault(value =>
                value.Id == selectedAnimationId) ?? _petAnimations.FirstOrDefault();

            IReadOnlyList<InstalledPetPackage> installed =
                app.PetLibrary.GetInstalledPackages();
            _isRefreshingPetChoice = true;
            _petChoices.Clear();
            _petChoices.Add(new PetChoiceItem(null, "몽글이 (내장)"));
            foreach (InstalledPetPackage package in installed)
            {
                _petChoices.Add(new PetChoiceItem(
                    package.InstallationId,
                    package.Package.Manifest.DisplayName));
            }
            CurrentPetComboBox.SelectedItem = _petChoices.FirstOrDefault(value =>
                value.InstallationId == app.ActiveInstallationId) ?? _petChoices[0];
            _isRefreshingPetChoice = false;
            _installedPets.Clear();
            foreach (InstalledPetPackage package in installed)
            {
                bool isActive = package.InstallationId == app.ActiveInstallationId;
                _installedPets.Add(new InstalledPetItem(
                    package.InstallationId.ToString("D"),
                    isActive
                        ? $"{package.Package.Manifest.DisplayName} · 사용 중"
                        : package.Package.Manifest.DisplayName,
                    $"{package.Package.Manifest.Id} · v{package.Package.Manifest.Version} · {package.InstallationId:D}",
                    !isActive && app.SettingsStore.IsWritingEnabled));
            }

            string active = app.ActiveInstallationId is Guid activeId
                ? $" · 현재 설치 {activeId:D}"
                : " · 현재 bundled 샘플";
            LibraryStatusText.Text =
                $"설치 {installed.Count}개{active}\n{app.PetLibrary.LibraryRootPath}";
            SettingsStatusText.Text =
                $"설정: {app.SettingsStore.SettingsPath}" +
                (string.IsNullOrWhiteSpace(app.SettingsStatusMessage)
                    ? string.Empty
                    : $"\n{app.SettingsStatusMessage}");
            bool canManage = app.SettingsStore.IsWritingEnabled;
            bool isInstalled = app.ActiveInstallationId is Guid;
            bool isEditable = isInstalled && TryGetActiveInstalledPet(
                out _,
                out InstalledPetPackage activeInstalled) &&
                app.PetEditor.IsEditable(activeInstalled);
            ImportPackageButton.IsEnabled = canManage;
            ExportPackageButton.IsEnabled = canManage && isInstalled;
            ExportPackageButton.Visibility = isInstalled ? Visibility.Visible : Visibility.Collapsed;
            BuiltInPetExportLockPanel.Visibility = isInstalled
                ? Visibility.Collapsed
                : Visibility.Visible;
            RenderRemotePetImportState();
            InstallSampleButton.IsEnabled = canManage;
            InstalledPetsList.IsEnabled = canManage;
            CreatePetButton.IsEnabled = canManage;
            EditPetDetailsButton.Visibility = isEditable ? Visibility.Visible : Visibility.Collapsed;
            EditPetDetailsButton.IsEnabled = canManage && isEditable;
            CreateEditablePetCopyButton.Visibility = app.ActivePackage is not null
                ? Visibility.Visible
                : Visibility.Collapsed;
            CreateEditablePetCopyButton.IsEnabled = canManage && app.ActivePackage is not null;
            DeleteCurrentPetButton.Visibility = isInstalled ? Visibility.Visible : Visibility.Collapsed;
            DeleteCurrentPetButton.IsEnabled = canManage && isInstalled;
            AnimationEditingCaptionText.Text = isEditable
                ? "애니메이션을 추가하거나 프레임 순서·간격·반복 여부를 수정할 수 있습니다."
                : isInstalled
                    ? "가져온 패키지는 원본 보존을 위해 읽기 전용입니다. 편집하려면 사본을 만들어 주세요."
                    : "기본 몽글이는 읽기 전용입니다. 새 펫을 만들거나 패키지를 가져와 주세요.";
            PetManagementCaptionText.Text = isEditable
                ? "MonglePet에서 만든 펫입니다. 정보와 애니메이션을 직접 수정할 수 있습니다."
                : isInstalled
                    ? "가져온 펫은 편집 가능한 사본을 만든 뒤 수정할 수 있습니다."
                    : "기본 몽글이는 삭제하거나 내보낼 수 없습니다.";
            RefreshPetEditorButtonState();
        }
        catch (Exception exception)
        {
            _isRefreshingPetChoice = false;
            LibraryStatusText.Text = $"라이브러리를 읽을 수 없습니다: {exception.Message}";
        }
    }

    private void RefreshPetEditorButtonState()
    {
        if (Application.Current is not App app)
        {
            return;
        }
        bool isEditable = TryGetActiveInstalledPet(out _, out InstalledPetPackage installed) &&
            app.PetEditor.IsEditable(installed);
        bool canEdit = app.SettingsStore.IsWritingEnabled && isEditable;
        PetAnimationItem? selected = PetAnimationsList.SelectedItem as PetAnimationItem;
        AddPetAnimationButton.Visibility = isEditable ? Visibility.Visible : Visibility.Collapsed;
        EditPetAnimationButton.Visibility = isEditable ? Visibility.Visible : Visibility.Collapsed;
        DuplicatePetAnimationButton.Visibility = isEditable
            ? Visibility.Visible
            : Visibility.Collapsed;
        DeletePetAnimationButton.Visibility = isEditable ? Visibility.Visible : Visibility.Collapsed;
        AddPetAnimationButton.IsEnabled = canEdit;
        EditPetAnimationButton.IsEnabled = canEdit && selected is not null;
        DuplicatePetAnimationButton.IsEnabled = canEdit && selected is not null;
        DeletePetAnimationButton.IsEnabled = canEdit &&
            selected is not null &&
            _petAnimations.Count > 1 &&
            string.IsNullOrEmpty(selected.DefaultBadge);
    }

    private void RefreshCurrentPetSummary(LoadedPetPackage? package)
    {
        long generation = ++_petPreviewGeneration;
        _petAnimationPreviewGeneration++;
        _petAnimationPreviewTimer?.Stop();
        _petAnimationPreviewPackage = null;
        _petAnimationPreviewMotion = null;
        CurrentPetPreviewImage.Source = null;
        SpeechPetPreviewImage.Source = null;
        CurrentPetPreviewPlaceholder.Visibility = Visibility.Visible;
        SpeechPetPreviewPlaceholder.Visibility = Visibility.Visible;

        if (package is null)
        {
            CurrentPetNameText.Text = "현재 펫을 불러오는 중입니다.";
            CurrentPetAuthorVersionText.Text = string.Empty;
            CurrentPetDescriptionText.Text = "잠시 후 현재 펫 정보가 표시됩니다.";
            CurrentPetMotionText.Text = string.Empty;
            return;
        }

        PetPackageManifest manifest = package.Manifest;
        CurrentPetNameText.Text = manifest.DisplayName;
        CurrentPetAuthorVersionText.Text = $"{manifest.Author} · 버전 {manifest.Version}";
        CurrentPetDescriptionText.Text = string.IsNullOrWhiteSpace(manifest.Description)
            ? "이 펫에는 소개가 등록되어 있지 않습니다."
            : manifest.Description;
        CurrentPetMotionText.Text =
            $"기본 애니메이션: {package.DefaultMotionId} · 전체 {manifest.Motions.Count}개";
        _ = LoadCurrentPetPreviewAsync(package.PreviewFilePath, generation);
    }

    private async Task LoadCurrentPetPreviewAsync(string previewPath, long generation)
    {
        try
        {
            StorageFile file = await StorageFile.GetFileFromPathAsync(previewPath);
            using var stream = await file.OpenReadAsync();
            var bitmap = new BitmapImage();
            await bitmap.SetSourceAsync(stream);
            if (generation != _petPreviewGeneration || !_isLoaded)
            {
                return;
            }
            if (_petAnimationPreviewMotion is null)
            {
                CurrentPetPreviewImage.Source = bitmap;
            }
            SpeechPetPreviewImage.Source = bitmap;
            CurrentPetPreviewPlaceholder.Visibility = Visibility.Collapsed;
            SpeechPetPreviewPlaceholder.Visibility = Visibility.Collapsed;
        }
        catch
        {
            if (generation == _petPreviewGeneration)
            {
                CurrentPetPreviewPlaceholder.Visibility = Visibility.Visible;
                SpeechPetPreviewPlaceholder.Visibility = Visibility.Visible;
            }
        }
    }

    private void StartPetAnimationPreview(LoadedPetPackage package, string motionId)
    {
        PetPackageMotion? motion = package.Manifest.Motions.FirstOrDefault(value =>
            string.Equals(value.Id, motionId, StringComparison.Ordinal));
        if (motion is null || motion.Frames.Count == 0)
        {
            return;
        }
        _petAnimationPreviewGeneration++;
        _petAnimationPreviewTimer?.Stop();
        _petAnimationPreviewPackage = package;
        _petAnimationPreviewMotion = motion;
        _petAnimationPreviewFrameIndex = 0;
        _ = ShowNextPetAnimationPreviewFrameAsync();
    }

    private async Task ShowNextPetAnimationPreviewFrameAsync()
    {
        if (!_isLoaded ||
            _petAnimationPreviewPackage is not { } package ||
            _petAnimationPreviewMotion is not { Frames.Count: > 0 } motion)
        {
            return;
        }
        long generation = _petAnimationPreviewGeneration;
        int frameIndex = Math.Clamp(_petAnimationPreviewFrameIndex, 0, motion.Frames.Count - 1);
        PetPackageFrame frame = motion.Frames[frameIndex];
        LoadedPetAtlas atlas = package.Atlases[motion.Atlas];
        try
        {
            WindowsDecodedImage decoded = await _petAnimationPreviewImageCache.GetAsync(
                atlas.FilePath);
            UserPetProcessedFrame processed = UserPetPixelProcessor.Process(
                decoded.BgraPixels,
                decoded.Width,
                decoded.Height,
                frame);
            ImageSource source = await WindowsImagePreviewFactory.CreateTransparentAsync(
                processed);
            if (generation != _petAnimationPreviewGeneration ||
                !ReferenceEquals(package, _petAnimationPreviewPackage) ||
                !ReferenceEquals(motion, _petAnimationPreviewMotion) || !_isLoaded)
            {
                return;
            }
            CurrentPetPreviewImage.Source = source;
            CurrentPetPreviewPlaceholder.Visibility = Visibility.Collapsed;

            bool hasNext = frameIndex + 1 < motion.Frames.Count;
            if (hasNext)
            {
                _petAnimationPreviewFrameIndex = frameIndex + 1;
            }
            else if (motion.Loop)
            {
                _petAnimationPreviewFrameIndex = 0;
            }
            else
            {
                return;
            }
            if (_petAnimationPreviewTimer is not null)
            {
                _petAnimationPreviewTimer.Interval = TimeSpan.FromMilliseconds(
                    Math.Clamp(frame.DurationMs, 16, 60_000));
                _petAnimationPreviewTimer.Start();
            }
        }
        catch
        {
            if (generation == _petAnimationPreviewGeneration)
            {
                _petAnimationPreviewTimer?.Stop();
            }
        }
    }

    private static string ApplicationVersionText()
    {
        if (!WindowsPackageIdentity.IsCurrentProcessPackaged())
        {
            Version? unpackagedVersion = Assembly.GetEntryAssembly()?.GetName().Version;
            return unpackagedVersion is null
                ? "MonglePet 개발 빌드"
                : $"MonglePet {unpackagedVersion.Major}.{unpackagedVersion.Minor}." +
                  $"{unpackagedVersion.Build}";
        }

        try
        {
            global::Windows.ApplicationModel.PackageVersion version =
                global::Windows.ApplicationModel.Package.Current.Id.Version;
            return $"MonglePet {version.Major}.{version.Minor}.{version.Build}";
        }
        catch
        {
            return "MonglePet 개발 빌드";
        }
    }

    private static RemotePetSemanticVersion CurrentAppSemanticVersion()
    {
        Version? version = Assembly.GetEntryAssembly()?.GetName().Version;
        return version is null
            ? new RemotePetSemanticVersion(1, 5, 0)
            : new RemotePetSemanticVersion(
                Math.Max(version.Major, 0),
                Math.Max(version.Minor, 0),
                Math.Max(version.Build, 0));
    }

    private void ShowLibraryMessage(InfoBarSeverity severity, string title, string message)
    {
        LibraryInfoBar.Severity = severity;
        LibraryInfoBar.Title = title;
        LibraryInfoBar.Message = message;
        LibraryInfoBar.IsOpen = true;
    }

    private void RefreshBehaviorState()
    {
        if (Application.Current is not App app)
        {
            return;
        }

        BehaviorProfile profile = app.ActiveBehaviorProfile;
        bool canEdit = app.SettingsStore.IsWritingEnabled;
        _isRefreshingBehaviorControls = true;
        _isRefreshingBehaviorEditor = true;
        try
        {
            BehaviorTargetPetText.Text = app.ActivePackage?.Manifest.DisplayName ?? "몽글이";
            _behaviorSequences.Clear();
            foreach (BehaviorSequence sequence in profile.Sequences)
            {
                _behaviorSequences.Add(new BehaviorSequenceItem(
                    sequence.Id,
                    sequence.DisplayName));
            }

            BehaviorModeComboBox.SelectedIndex = profile.StationaryBehaviorMode switch
            {
                StationaryBehaviorMode.Random => 1,
                _ => 0,
            };
            string? selectedId = profile.StationarySequenceId ??
                profile.Sequences.FirstOrDefault()?.Id;
            ManualSequenceComboBox.SelectedItem = _behaviorSequences.FirstOrDefault(item =>
                string.Equals(item.Id, selectedId, StringComparison.Ordinal));
            RandomSequencesList.SelectedItems.Clear();
            foreach (BehaviorSequenceItem item in _behaviorSequences.Where(item =>
                profile.RandomSequences.Contains(item.Id, StringComparer.Ordinal)))
            {
                RandomSequencesList.SelectedItems.Add(item);
            }
            BehaviorModeComboBox.IsEnabled = canEdit;
            ManualSequenceComboBox.IsEnabled =
                canEdit && profile.StationaryBehaviorMode == StationaryBehaviorMode.Fixed &&
                _behaviorSequences.Count > 0;
            ManualSequenceComboBox.Visibility =
                profile.StationaryBehaviorMode == StationaryBehaviorMode.Fixed
                ? Visibility.Visible
                : Visibility.Collapsed;
            RandomSequencesList.IsEnabled = canEdit &&
                profile.StationaryBehaviorMode == StationaryBehaviorMode.Random;
            RandomSequencesList.Visibility =
                profile.StationaryBehaviorMode == StationaryBehaviorMode.Random
                ? Visibility.Visible
                : Visibility.Collapsed;
            BehaviorDescriptionText.Text = profile.StationaryBehaviorMode switch
            {
                StationaryBehaviorMode.Random when profile.RandomSequences.Count == 0 =>
                    "행동을 하나 이상 선택해 주세요. 선택 전에는 기본 행동을 표시합니다.",
                StationaryBehaviorMode.Random =>
                    "선택한 행동을 모두 한 번씩 섞어 재생한 뒤 새 순서로 반복합니다. 같은 행동은 연속해서 나오지 않습니다.",
                _ => "선택한 행동을 평상시에 반복해서 재생합니다. 선택하지 않으면 현재 펫의 기본 행동을 사용합니다.",
            };
            AutomaticRulesCard.Visibility =
                _currentSettingsSection == "automaticRules"
                    ? Visibility.Visible
                    : Visibility.Collapsed;
            RefreshMotionOptions(app);
            RefreshMovementControls(app, profile, canEdit);
            RefreshRoutineEditor(profile, canEdit);
            RefreshRulesEditor(profile, canEdit);
            RefreshSpeechControls(app, profile, canEdit);
        }
        finally
        {
            _isRefreshingBehaviorControls = false;
            _isRefreshingBehaviorEditor = false;
        }

    }

    private void RefreshMotionOptions(App app)
    {
        _motionOptions.Clear();
        _motionOptions.Add(new MotionOptionItem(
            BehaviorMotionReferences.CurrentPetDefault,
            "현재 펫 기본 모션"));
        foreach (string motionId in app.ActiveMotionIds)
        {
            _motionOptions.Add(new MotionOptionItem(motionId, motionId));
        }
    }

    private void RefreshMovementControls(App app, BehaviorProfile profile, bool canEdit)
    {
        _isRefreshingMovementControls = true;
        try
        {
            _movementMotionOptions.Clear();
            _movementMotionOptions.Add(new MotionOptionItem(string.Empty, "사용 안 함"));
            foreach (BehaviorSequence behavior in profile.Sequences)
            {
                _movementMotionOptions.Add(new MotionOptionItem(
                    behavior.Id,
                    behavior.DisplayName));
            }

            _movementScreens.Clear();
            foreach (MonitorWorkArea screen in app.AvailableMonitorWorkAreas())
            {
                _movementScreens.Add(new MonitorOptionItem(
                    screen.Identifier,
                    $"{screen.Identifier} · {screen.Width}×{screen.Height}"));
            }

            PetMovementSettings movement = profile.Movement;
            MovementTargetPetText.Text = app.ActivePackage?.Manifest.DisplayName ?? "몽글이";
            MovementModeComboBox.SelectedIndex = movement.Mode switch
            {
                PetMovementMode.Fixed => 0,
                PetMovementMode.CursorFollowing => 1,
                PetMovementMode.FreeRoaming => 2,
                PetMovementMode.CursorAvoiding => 3,
                _ => 0,
            };
            FixedMovementModeRadio.IsChecked = MovementModeComboBox.SelectedIndex == 0;
            CursorFollowingMovementModeRadio.IsChecked = MovementModeComboBox.SelectedIndex == 1;
            FreeRoamingMovementModeRadio.IsChecked = MovementModeComboBox.SelectedIndex == 2;
            CursorAvoidingMovementModeRadio.IsChecked = MovementModeComboBox.SelectedIndex == 3;
            CursorFollowingMovementSettings following = movement.CursorFollowing;
            FreeRoamingMovementSettings roaming = movement.Mode == PetMovementMode.CursorAvoiding
                ? movement.CursorAvoiding.IdleFreeRoaming
                : movement.FreeRoaming;
            MovementSpeedNumberBox.Value = movement.Mode switch
            {
                PetMovementMode.CursorFollowing => following.Speed,
                PetMovementMode.CursorAvoiding => roaming.Speed,
                _ => movement.FreeRoaming.Speed,
            };
            MovementStopRadiusNumberBox.Value = movement.Mode switch
            {
                PetMovementMode.CursorFollowing => following.StopRadius,
                PetMovementMode.CursorAvoiding => movement.CursorAvoiding.StopRadius,
                _ => movement.FreeRoaming.StopRadius,
            };
            CursorDistanceNumberBox.Value = following.CursorDistance;
            FreeRoamingDwellNumberBox.Value =
                roaming.DwellMilliseconds / 1000d;
            RandomizesDwellToggle.IsOn = roaming.RandomizesDwell;
            FreeRoamingDwellMinimumNumberBox.Value =
                roaming.DwellMinimumMilliseconds / 1000d;
            PrefersFrontmostWindowToggle.IsOn = roaming.PrefersFrontmostWindow;
            AvoidingDetectionNumberBox.Value = movement.CursorAvoiding.DetectionDistance;
            AvoidingSpeedNumberBox.Value = movement.CursorAvoiding.Speed;
            AvoidingIdleBehaviorComboBox.SelectedIndex =
                movement.CursorAvoiding.IdleBehavior == CursorAvoidingIdleBehavior.FreeRoaming
                    ? 1
                    : 0;

            MovementBoundarySettings boundary = app.CurrentSettings.Overlay.MovementBoundary;
            MovementBoundaryModeComboBox.SelectedIndex = boundary.Mode switch
            {
                MovementBoundaryMode.AllDisplays => 0,
                MovementBoundaryMode.SelectedDisplay => 1,
                MovementBoundaryMode.CustomArea => 2,
                _ => 0,
            };
            MovementScreenComboBox.SelectedItem = _movementScreens.FirstOrDefault(item =>
                string.Equals(
                    item.Identifier,
                    boundary.ScreenIdentifier,
                    StringComparison.OrdinalIgnoreCase)) ?? _movementScreens.FirstOrDefault();
            MovementScreenComboBox.IsEnabled = canEdit &&
                MovementBoundaryModeComboBox.SelectedIndex != 0;

            NormalizedMovementRect normalized = boundary.NormalizedRect is { IsValid: true } value
                ? value
                : new NormalizedMovementRect(0, 0, 1, 1);
            MovementAreaXNumberBox.Value = normalized.X * 100;
            MovementAreaYNumberBox.Value = Math.Max(
                0,
                1 - normalized.Y - normalized.Height) * 100;
            MovementAreaWidthNumberBox.Value = normalized.Width * 100;
            MovementAreaHeightNumberBox.Value = normalized.Height * 100;

            CursorFollowingAnimationEditor.SetState(
                "이동 애니메이션",
                following.Behavior,
                profile.Sequences,
                canEdit);
            FreeRoamingAnimationEditor.SetState(
                movement.Mode == PetMovementMode.CursorAvoiding
                    ? "평상시 자유 이동 애니메이션"
                    : "이동 애니메이션",
                roaming.Behavior,
                profile.Sequences,
                canEdit);
            CursorAvoidingAnimationEditor.SetState(
                "도망가기 애니메이션",
                movement.CursorAvoiding.Behavior,
                profile.Sequences,
                canEdit);
            SelectMotion(PettingMotionComboBox, profile.PettingBehaviorId);

            MovementModeComboBox.IsEnabled = canEdit;
            FixedMovementModeRadio.IsEnabled = canEdit;
            CursorFollowingMovementModeRadio.IsEnabled = canEdit;
            FreeRoamingMovementModeRadio.IsEnabled = canEdit;
            CursorAvoidingMovementModeRadio.IsEnabled = canEdit;
            MovementSpeedNumberBox.IsEnabled = canEdit;
            MovementStopRadiusNumberBox.IsEnabled = canEdit;
            CursorDistanceNumberBox.IsEnabled = canEdit;
            FreeRoamingDwellNumberBox.IsEnabled = canEdit;
            RandomizesDwellToggle.IsEnabled = canEdit;
            FreeRoamingDwellMinimumNumberBox.IsEnabled = canEdit;
            PrefersFrontmostWindowToggle.IsEnabled = canEdit;
            AvoidingDetectionNumberBox.IsEnabled = canEdit;
            AvoidingSpeedNumberBox.IsEnabled = canEdit;
            AvoidingIdleBehaviorComboBox.IsEnabled = canEdit;
            MovementBoundaryModeComboBox.IsEnabled = canEdit;
            MovementAreaXNumberBox.IsEnabled = canEdit;
            MovementAreaYNumberBox.IsEnabled = canEdit;
            MovementAreaWidthNumberBox.IsEnabled = canEdit;
            MovementAreaHeightNumberBox.IsEnabled = canEdit;
            RefreshMovementControlVisibility(canEdit);
        }
        catch (Exception exception)
        {
            ShowMovementError(exception);
        }
        finally
        {
            _isRefreshingMovementControls = false;
        }
    }

    private void RefreshMovementControlVisibility(bool canEdit)
    {
        int mode = MovementModeComboBox.SelectedIndex;
        bool isFixed = mode == 0;
        bool isFollowing = mode == 1;
        bool isFreeRoaming = mode == 2;
        bool isAvoiding = mode == 3;
        bool avoidingRoams = isAvoiding && AvoidingIdleBehaviorComboBox.SelectedIndex == 1;

        FixedMovementHelpPanel.Visibility = isFixed ? Visibility.Visible : Visibility.Collapsed;
        MovementSensePanel.Visibility = isFixed ? Visibility.Collapsed : Visibility.Visible;
        MovementSpeedNumberBox.Visibility = !isAvoiding || avoidingRoams
            ? Visibility.Visible
            : Visibility.Collapsed;
        MovementSpeedNumberBox.Header = isAvoiding ? "평상시 이동 속도 (px/s)" : "이동 속도 (px/s)";
        MovementBoundaryPanel.Visibility = isFixed ? Visibility.Collapsed : Visibility.Visible;
        MovementScreenComboBox.IsEnabled = canEdit &&
            MovementBoundaryModeComboBox.SelectedIndex != 0;
        MovementCustomAreaPanel.Visibility = !isFixed && MovementBoundaryModeComboBox.SelectedIndex == 2
            ? Visibility.Visible
            : Visibility.Collapsed;
        CursorFollowingOptionsPanel.Visibility = isFollowing ? Visibility.Visible : Visibility.Collapsed;
        FreeRoamingOptionsPanel.Visibility = isFreeRoaming || avoidingRoams
            ? Visibility.Visible
            : Visibility.Collapsed;
        FreeRoamingSectionTitle.Text = avoidingRoams ? "평상시 자유 이동" : "자유 이동";
        FreeRoamingDwellMinimumNumberBox.Visibility =
            RandomizesDwellToggle.IsOn ? Visibility.Visible : Visibility.Collapsed;
        CursorAvoidingOptionsPanel.Visibility = isAvoiding ? Visibility.Visible : Visibility.Collapsed;

        bool clickThrough = Application.Current is App app && app.CurrentSettings.Overlay.ClickThrough;
        FixedMovementHelpText.Text = clickThrough
            ? "클릭 통과가 켜져 있어 펫을 드래그할 수 없습니다. 위 화면 표시에서 클릭 통과를 끄면 위치를 옮길 수 있습니다."
            : "펫을 직접 드래그한 위치에 그대로 둡니다.";
        PettingMotionComboBox.IsEnabled = canEdit && !isAvoiding;
        PettingDescriptionText.Text = isAvoiding
            ? "마우스 도망가기 모드에서는 접근 반응과 충돌하지 않도록 쓰다듬기를 실행하지 않습니다. 다른 이동 모드의 선택은 유지됩니다."
            : "펫의 보이는 부분에 마우스를 잠시 올리면 선택한 애니메이션을 한 번 재생한 뒤 기존 행동으로 돌아갑니다. 클릭 통과 중에도 사용할 수 있습니다.";
    }

    private static void SelectMotion(ComboBox comboBox, string? motionId)
    {
        string selected = motionId ?? string.Empty;
        comboBox.SelectedItem = ((IEnumerable<MotionOptionItem>)comboBox.ItemsSource)
            .FirstOrDefault(item => string.Equals(item.Id, selected, StringComparison.Ordinal));
    }

    private void RefreshRoutineEditor(BehaviorProfile profile, bool canEdit)
    {
        _selectedRoutineId = profile.Sequences.Any(sequence => string.Equals(
                sequence.Id,
                _selectedRoutineId,
                StringComparison.Ordinal))
            ? _selectedRoutineId
            : profile.Sequences.FirstOrDefault()?.Id;
        RoutineEditorComboBox.SelectedItem = _behaviorSequences.FirstOrDefault(item =>
            string.Equals(item.Id, _selectedRoutineId, StringComparison.Ordinal));
        BehaviorSequence? sequence = SelectedRoutine(profile);
        _behaviorSteps.Clear();
        if (sequence is not null)
        {
            for (int index = 0; index < sequence.Steps.Count; index++)
            {
                BehaviorStep step = sequence.Steps[index];
                _behaviorSteps.Add(new BehaviorStepEditorItem(
                    index,
                    index + 1,
                    step.MotionId,
                    _motionOptions.FirstOrDefault(option => string.Equals(
                        option.Id,
                        step.MotionId,
                        StringComparison.Ordinal))?.DisplayName ?? step.MotionId,
                    step.RepeatCount,
                    index > 0,
                    index < sequence.Steps.Count - 1,
                    sequence.Steps.Count > 1));
            }
            SequenceRepeatsToggle.IsOn = sequence.Repeats;
        }
        else
        {
            SequenceRepeatsToggle.IsOn = false;
        }

        RoutineEditorComboBox.IsEnabled = canEdit && profile.Sequences.Count > 0;
        AddSequenceButton.IsEnabled = canEdit;
        RenameSequenceButton.IsEnabled = canEdit && sequence is not null;
        DeleteSequenceButton.IsEnabled = canEdit && sequence is not null && !string.Equals(
            sequence.Id,
            BehaviorMotionReferences.DefaultSequence,
            StringComparison.Ordinal);
        SequenceRepeatsToggle.IsEnabled = canEdit && sequence is not null;
        BehaviorStepsList.IsEnabled = canEdit && sequence is not null;
        AddStepButton.IsEnabled = canEdit && sequence is not null;
    }

    private void RefreshRulesEditor(BehaviorProfile profile, bool canEdit)
    {
        _rulePriorityKinds.Clear();
        foreach ((AutomaticRuleKind kind, int index) in profile.RulePriorityOrder
                     .Select((kind, index) => (kind, index)))
        {
            _rulePriorityKinds.Add(new RulePriorityKindItem(
                kind,
                kind switch
                {
                    AutomaticRuleKind.Movement => "표시 및 이동",
                    AutomaticRuleKind.Idle => "입력 없음 규칙",
                    _ => "앱 사용 규칙",
                },
                kind switch
                {
                    AutomaticRuleKind.Movement => "펫이 움직이는 동안 설정한 이동 행동",
                    AutomaticRuleKind.Idle => "설정한 시간 동안 입력이 없을 때의 행동",
                    _ => "현재 사용 중인 앱에 등록된 행동",
                },
                $"{index + 1}순위"));
        }
        _automaticRules.Clear();
        foreach (AutomaticRule rule in profile.AutomaticRules.Where(rule =>
            rule.Condition is not RuleCondition.IdleAtLeast))
        {
            _automaticRules.Add(new AutomaticRuleEditorItem(
                rule.Id,
                RuleSummary(rule),
                $"{(rule.IsEnabled ? "사용" : "중지")} · " +
                (profile.Sequences.FirstOrDefault(sequence =>
                    sequence.Id == rule.SequenceId)?.DisplayName ?? "찾을 수 없는 행동")));
        }

        AutomaticRuleEditorItem? selected = _automaticRules.FirstOrDefault(item =>
            item.Id == _selectedRuleId);
        _selectedRuleId = selected?.Id;
        AutomaticRulesList.SelectedItem = selected;
        RefreshRuleForm(profile, selected is null
            ? null
            : profile.AutomaticRules.First(rule => rule.Id == selected.Id));
        AutomaticRulesList.IsEnabled = canEdit;
        NewApplicationRuleButton.IsEnabled = canEdit;
        NewIdleRuleButton.IsEnabled = canEdit && !profile.AutomaticRules.Any(rule =>
            rule.Condition is RuleCondition.IdleAtLeast);
        AddRuleButton.IsEnabled = canEdit;
        SaveRuleButton.IsEnabled = canEdit && selected is not null;
        DeleteRuleButton.IsEnabled = canEdit && selected is not null;
        RuleEnabledToggle.IsEnabled = canEdit;
        RulePriorityNumberBox.IsEnabled = canEdit;
        RulePriorityOrderList.IsEnabled = canEdit;
        RuleConditionTypeComboBox.IsEnabled = canEdit;
        RuleApplicationIdTextBox.IsEnabled = canEdit;
        ChooseApplicationButton.IsEnabled = canEdit;
        ChooseExecutableButton.IsEnabled = canEdit;
        UseCurrentApplicationButton.IsEnabled = canEdit;
        RuleIdleMinutesNumberBox.IsEnabled = canEdit;
        RuleTargetSequenceComboBox.IsEnabled = canEdit && profile.Sequences.Count > 0;
        AutomaticRule? idleRule = profile.AutomaticRules.FirstOrDefault(rule =>
            rule.Condition is RuleCondition.IdleAtLeast);
        IdleRuleEnabledToggle.IsOn = idleRule?.IsEnabled ?? false;
        IdleRuleSecondsNumberBox.Value = idleRule?.Condition is RuleCondition.IdleAtLeast idle
            ? idle.Milliseconds / 1_000d
            : 60;
        IdleRuleTargetSequenceComboBox.SelectedValue = idleRule?.SequenceId ??
            profile.Sequences.FirstOrDefault()?.Id;
        IdleRuleEnabledToggle.IsEnabled = canEdit;
        IdleRuleSecondsNumberBox.IsEnabled = canEdit;
        IdleRuleTargetSequenceComboBox.IsEnabled = canEdit && profile.Sequences.Count > 0;
        SaveIdleRuleSettingsButton.IsEnabled = canEdit && profile.Sequences.Count > 0;
    }

    private void RefreshSpeechControls(App app, BehaviorProfile profile, bool canEdit)
    {
        _isRefreshingSpeechControls = true;
        try
        {
            PetSpeechSettings speech = profile.Speech;
            SpeechTargetPetText.Text = app.ActivePackage?.Manifest.DisplayName ?? "몽글이";
            _behaviorSpeechPhrases.Clear();
            _periodicSpeechPhrases.Clear();
            foreach (PetSpeechPhrase phrase in speech.Phrases)
            {
                var item = new SpeechPhraseEditorItem(
                    phrase.Id,
                    phrase.Text,
                    SpeechPhraseDetail(phrase, profile));
                if (phrase.Trigger is PetSpeechTrigger.Sequence)
                {
                    _behaviorSpeechPhrases.Add(item);
                }
                else
                {
                    _periodicSpeechPhrases.Add(item);
                }
            }

            SpeechPhraseEditorItem? selected = _behaviorSpeechPhrases
                .Concat(_periodicSpeechPhrases)
                .FirstOrDefault(item => item.Id == _selectedSpeechPhraseId);
            _selectedSpeechPhraseId = selected?.Id;
            BehaviorSpeechPhrasesList.SelectedItem = _behaviorSpeechPhrases.FirstOrDefault(item =>
                item.Id == _selectedSpeechPhraseId);
            PeriodicSpeechPhrasesList.SelectedItem = _periodicSpeechPhrases.FirstOrDefault(item =>
                item.Id == _selectedSpeechPhraseId);

            SpeechEnabledToggle.IsOn = speech.IsEnabled;
            SpeechPeriodicEnabledToggle.IsOn = speech.PeriodicIsEnabled;
            SpeechPeriodicIntervalNumberBox.Value =
                speech.PeriodicIntervalMilliseconds / 1_000d;
            SpeechPeriodicOrderComboBox.SelectedIndex =
                speech.PeriodicOrder == PetSpeechPeriodicOrder.Sequential ? 1 : 0;
            SpeechBehaviorChangePolicyComboBox.SelectedIndex =
                speech.BehaviorChangePolicy == PetSpeechBehaviorChangePolicy.Keep ? 1 : 0;

            SpeechThemeStyleComboBox.SelectedIndex = speech.Theme.ColorStyle switch
            {
                PetSpeechBubbleColorStyle.Cream => 1,
                PetSpeechBubbleColorStyle.Midnight => 2,
                PetSpeechBubbleColorStyle.Mint => 3,
                PetSpeechBubbleColorStyle.Peach => 4,
                PetSpeechBubbleColorStyle.Custom => 5,
                _ => 0,
            };
            SpeechBackgroundColorPicker.Color = ColorValue(speech.Theme.CustomBackgroundColor);
            SpeechTextColorPicker.Color = ColorValue(speech.Theme.CustomTextColor);
            SpeechBackgroundOpacityNumberBox.Value = speech.Theme.BackgroundOpacity * 100;
            SpeechFontSizeNumberBox.Value = speech.Theme.FontSize;
            SpeechPaddingNumberBox.Value = speech.Theme.ContentPadding;
            SpeechCornerRadiusNumberBox.Value = speech.Theme.CornerRadius;
            SpeechTailToggle.IsOn = speech.Theme.ShowsTail;
            SpeechTailAlignmentComboBox.SelectedIndex = speech.Theme.TailAlignment switch
            {
                PetSpeechBubbleTailAlignment.Leading => 0,
                PetSpeechBubbleTailAlignment.Trailing => 2,
                _ => 1,
            };

            SpeechPreferredPositionComboBox.SelectedIndex = speech.Placement.PreferredPosition switch
            {
                PetSpeechBubblePreferredPosition.Above => 1,
                PetSpeechBubblePreferredPosition.Below => 2,
                _ => 0,
            };
            SpeechHorizontalOffsetNumberBox.Value = speech.Placement.HorizontalOffset;
            SpeechGapNumberBox.Value = speech.Placement.Gap;

            if (!_isEditingSpeechPhrase)
            {
                SpeechPhraseEditorPanel.Visibility = Visibility.Collapsed;
                PetSpeechPhrase? selectedPhrase = selected is null
                    ? null
                    : speech.Phrases.First(phrase => phrase.Id == selected.Id);
                RefreshSpeechPhraseForm(profile, selectedPhrase);
            }

            SpeechEnabledToggle.IsEnabled = canEdit;
            SpeechPeriodicEnabledToggle.IsEnabled = canEdit && speech.IsEnabled;
            SpeechBehaviorChangePolicyComboBox.IsEnabled = canEdit && speech.IsEnabled;
            BehaviorSpeechPhrasesList.IsEnabled = canEdit && speech.IsEnabled;
            PeriodicSpeechPhrasesList.IsEnabled = canEdit && speech.IsEnabled && speech.PeriodicIsEnabled;
            AddBehaviorSpeechPhraseButton.IsEnabled = canEdit && speech.IsEnabled &&
                profile.Sequences.Count > 0 && speech.Phrases.Count < AppSettingsLimits.MaximumSpeechPhrases;
            AddPeriodicSpeechPhraseButton.IsEnabled = canEdit && speech.IsEnabled &&
                speech.PeriodicIsEnabled && speech.Phrases.Count < AppSettingsLimits.MaximumSpeechPhrases;
            RefreshSpeechPhraseActionButtons(canEdit, speech);
            SpeechPhraseTextBox.IsEnabled = canEdit;
            SpeechTriggerComboBox.IsEnabled = canEdit;
            SpeechDisplayModeComboBox.IsEnabled = canEdit;
            SaveSpeechPhraseButton.IsEnabled = canEdit;
            CancelSpeechPhraseButton.IsEnabled = canEdit;
            SpeechThemeStyleComboBox.IsEnabled = canEdit;
            SpeechBackgroundColorPicker.IsEnabled = canEdit;
            SpeechTextColorPicker.IsEnabled = canEdit;
            SpeechBackgroundOpacityNumberBox.IsEnabled = canEdit;
            SpeechFontSizeNumberBox.IsEnabled = canEdit;
            SpeechPaddingNumberBox.IsEnabled = canEdit;
            SpeechCornerRadiusNumberBox.IsEnabled = canEdit;
            SpeechTailToggle.IsEnabled = canEdit;
            SpeechPreferredPositionComboBox.IsEnabled = canEdit;
            SpeechHorizontalOffsetNumberBox.IsEnabled = canEdit;
            SpeechGapNumberBox.IsEnabled = canEdit;
            SaveSpeechSettingsButton.IsEnabled = canEdit;
            RefreshSpeechControlVisibility(canEdit);
            UpdateSpeechThemePreview();
        }
        finally
        {
            _isRefreshingSpeechControls = false;
        }
    }

    private void RefreshSpeechPhraseForm(
        BehaviorProfile profile,
        PetSpeechPhrase? phrase)
    {
        SpeechPhraseTextBox.Text = phrase?.Text ?? string.Empty;
        SpeechTriggerComboBox.SelectedIndex = phrase?.Trigger is PetSpeechTrigger.Sequence ? 1 : 0;
        string? sequenceId = (phrase?.Trigger as PetSpeechTrigger.Sequence)?.SequenceId
            ?? profile.Sequences.FirstOrDefault()?.Id;
        SpeechSequenceComboBox.SelectedItem = _behaviorSequences.FirstOrDefault(item =>
            string.Equals(item.Id, sequenceId, StringComparison.Ordinal));
        SpeechDisplayModeComboBox.SelectedIndex =
            phrase?.DisplayMode == PetSpeechDisplayMode.UntilNextPhrase ? 1 : 0;
        SpeechDisplayDurationNumberBox.Value =
            (phrase?.DisplayDurationMilliseconds ??
                AppSettingsLimits.DefaultSpeechDisplayDurationMilliseconds) / 1_000d;
        SaveSpeechPhraseButton.Content = phrase is null ? "새 대사 추가" : "선택 대사 저장";
        RefreshSpeechPhraseFormVisibility();
    }

    private void BehaviorSpeechPhrasesList_SelectionChanged(
        object sender,
        SelectionChangedEventArgs e) => SpeechPhraseSelectionChanged(isBehavior: true);

    private void PeriodicSpeechPhrasesList_SelectionChanged(
        object sender,
        SelectionChangedEventArgs e) => SpeechPhraseSelectionChanged(isBehavior: false);

    private void SpeechPhraseSelectionChanged(bool isBehavior)
    {
        if (!_isLoaded || _isRefreshingSpeechControls || Application.Current is not App app)
        {
            return;
        }
        _isRefreshingSpeechControls = true;
        try
        {
            if (isBehavior)
            {
                PeriodicSpeechPhrasesList.SelectedItem = null;
                _selectedSpeechPhraseId =
                    (BehaviorSpeechPhrasesList.SelectedItem as SpeechPhraseEditorItem)?.Id;
            }
            else
            {
                BehaviorSpeechPhrasesList.SelectedItem = null;
                _selectedSpeechPhraseId =
                    (PeriodicSpeechPhrasesList.SelectedItem as SpeechPhraseEditorItem)?.Id;
            }
            RefreshSpeechPhraseActionButtons(
                app.SettingsStore.IsWritingEnabled,
                app.ActiveBehaviorProfile.Speech);
        }
        finally
        {
            _isRefreshingSpeechControls = false;
        }
    }

    private void AddBehaviorSpeechPhraseButton_Click(object sender, RoutedEventArgs e) =>
        BeginSpeechPhraseEdit(isBehavior: true, phraseId: null);

    private void AddPeriodicSpeechPhraseButton_Click(object sender, RoutedEventArgs e) =>
        BeginSpeechPhraseEdit(isBehavior: false, phraseId: null);

    private void EditBehaviorSpeechPhraseButton_Click(object sender, RoutedEventArgs e) =>
        BeginSpeechPhraseEdit(
            isBehavior: true,
            (BehaviorSpeechPhrasesList.SelectedItem as SpeechPhraseEditorItem)?.Id);

    private void EditPeriodicSpeechPhraseButton_Click(object sender, RoutedEventArgs e) =>
        BeginSpeechPhraseEdit(
            isBehavior: false,
            (PeriodicSpeechPhrasesList.SelectedItem as SpeechPhraseEditorItem)?.Id);

    private void BeginSpeechPhraseEdit(bool isBehavior, Guid? phraseId)
    {
        if (Application.Current is not App app || (phraseId is null &&
            app.ActiveBehaviorProfile.Speech.Phrases.Count >= AppSettingsLimits.MaximumSpeechPhrases))
        {
            return;
        }
        PetSpeechPhrase? phrase = phraseId is Guid id
            ? app.ActiveBehaviorProfile.Speech.Phrases.FirstOrDefault(value => value.Id == id)
            : null;
        _selectedSpeechPhraseId = phrase?.Id;
        _isEditingSpeechPhrase = true;
        _isRefreshingSpeechControls = true;
        try
        {
            RefreshSpeechPhraseForm(app.ActiveBehaviorProfile, phrase);
            SpeechTriggerComboBox.SelectedIndex = isBehavior ? 1 : 0;
            SpeechPhraseEditorTitleText.Text = phrase is null
                ? (isBehavior ? "행동 대사 추가" : "주기 대사 추가")
                : (isBehavior ? "행동 대사 수정" : "주기 대사 수정");
            SaveSpeechPhraseButton.Content = phrase is null ? "추가" : "저장";
            SpeechPhraseEditorPanel.Visibility = Visibility.Visible;
            SpeechPhraseTextBox.Focus(FocusState.Programmatic);
        }
        finally
        {
            _isRefreshingSpeechControls = false;
        }
    }

    private async void DeleteBehaviorSpeechPhraseButton_Click(object sender, RoutedEventArgs e) =>
        await DeleteSpeechPhraseAsync(
            (BehaviorSpeechPhrasesList.SelectedItem as SpeechPhraseEditorItem)?.Id);

    private async void DeletePeriodicSpeechPhraseButton_Click(object sender, RoutedEventArgs e) =>
        await DeleteSpeechPhraseAsync(
            (PeriodicSpeechPhrasesList.SelectedItem as SpeechPhraseEditorItem)?.Id);

    private async Task DeleteSpeechPhraseAsync(Guid? phraseId)
    {
        if (phraseId is not Guid id || Application.Current is not App app)
        {
            return;
        }
        var dialog = new ContentDialog
        {
            XamlRoot = XamlRoot,
            Title = "선택한 대사를 삭제할까요?",
            PrimaryButtonText = "삭제",
            CloseButtonText = "취소",
            DefaultButton = ContentDialogButton.Close,
        };
        if (await dialog.ShowAsync() != ContentDialogResult.Primary)
        {
            return;
        }
        try
        {
            BehaviorProfile profile = app.ActiveBehaviorProfile;
            PetSpeechSettings speech = profile.Speech with
            {
                Phrases = profile.Speech.Phrases.Where(phrase => phrase.Id != id).ToList(),
            };
            _selectedSpeechPhraseId = null;
            _isEditingSpeechPhrase = false;
            app.SaveBehaviorProfile(profile with { Speech = speech });
            SpeechSettingsInfoBar.IsOpen = false;
        }
        catch (Exception exception)
        {
            ShowSpeechError("대사를 삭제하지 못했습니다", exception);
        }
    }

    private void CancelSpeechPhraseButton_Click(object sender, RoutedEventArgs e)
    {
        _isEditingSpeechPhrase = false;
        _selectedSpeechPhraseId = null;
        SpeechPhraseEditorPanel.Visibility = Visibility.Collapsed;
        if (Application.Current is App app)
        {
            RefreshSpeechControls(app, app.ActiveBehaviorProfile, app.SettingsStore.IsWritingEnabled);
        }
    }

    private void RefreshSpeechPhraseActionButtons(bool canEdit, PetSpeechSettings speech)
    {
        bool behaviorSelected = BehaviorSpeechPhrasesList.SelectedItem is SpeechPhraseEditorItem;
        bool periodicSelected = PeriodicSpeechPhrasesList.SelectedItem is SpeechPhraseEditorItem;
        EditBehaviorSpeechPhraseButton.IsEnabled = canEdit && speech.IsEnabled && behaviorSelected;
        DeleteBehaviorSpeechPhraseButton.IsEnabled = canEdit && speech.IsEnabled && behaviorSelected;
        EditPeriodicSpeechPhraseButton.IsEnabled = canEdit && speech.IsEnabled &&
            speech.PeriodicIsEnabled && periodicSelected;
        DeletePeriodicSpeechPhraseButton.IsEnabled = canEdit && speech.IsEnabled &&
            speech.PeriodicIsEnabled && periodicSelected;
    }

    private void SaveSpeechPhraseButton_Click(object sender, RoutedEventArgs e)
    {
        if (Application.Current is not App app)
        {
            return;
        }

        try
        {
            BehaviorProfile profile = app.ActiveBehaviorProfile;
            string text = SpeechPhraseTextBox.Text.Trim();
            if (text.Length == 0)
            {
                throw new InvalidOperationException("대사를 입력해 주세요.");
            }
            Guid id = _selectedSpeechPhraseId ?? Guid.NewGuid();
            PetSpeechTrigger trigger = SpeechTriggerComboBox.SelectedIndex == 1
                ? new PetSpeechTrigger.Sequence(
                    (SpeechSequenceComboBox.SelectedItem as BehaviorSequenceItem)?.Id
                        ?? throw new InvalidOperationException("행동 루틴을 선택해 주세요."))
                : new PetSpeechTrigger.Periodic();
            long duration = checked((long)Math.Round(
                RequiredFiniteValue(
                    SpeechDisplayDurationNumberBox,
                    1,
                    30,
                    "표시 시간") * 1_000));
            var phrase = new PetSpeechPhrase(
                id,
                text,
                duration,
                trigger,
                SpeechDisplayModeComboBox.SelectedIndex == 1
                    ? PetSpeechDisplayMode.UntilNextPhrase
                    : PetSpeechDisplayMode.Timed);
            var phrases = profile.Speech.Phrases.ToList();
            int index = phrases.FindIndex(value => value.Id == id);
            if (index >= 0)
            {
                phrases[index] = phrase;
            }
            else
            {
                if (phrases.Count >= AppSettingsLimits.MaximumSpeechPhrases)
                {
                    throw new InvalidOperationException("대사는 최대 100개까지 등록할 수 있습니다.");
                }
                phrases.Add(phrase);
            }
            _selectedSpeechPhraseId = id;
            _isEditingSpeechPhrase = false;
            SpeechPhraseEditorPanel.Visibility = Visibility.Collapsed;
            app.SaveBehaviorProfile(profile with
            {
                Speech = profile.Speech with { Phrases = phrases },
            });
            SpeechSettingsInfoBar.IsOpen = false;
        }
        catch (Exception exception)
        {
            ShowSpeechError("대사를 저장하지 못했습니다", exception);
        }
    }

    private void SpeechPhraseForm_Changed(object sender, object e)
    {
        if (!_isRefreshingSpeechControls)
        {
            RefreshSpeechPhraseFormVisibility();
        }
    }

    private void SpeechPhraseTextBox_TextChanged(object sender, TextChangedEventArgs e)
    {
        if (!_isRefreshingSpeechControls)
        {
            UpdateSpeechThemePreview();
        }
    }

    private void RefreshSpeechPhraseFormVisibility()
    {
        if (SpeechSequenceComboBox is null || SpeechDisplayDurationNumberBox is null)
        {
            return;
        }
        bool canEdit = Application.Current is App app && app.SettingsStore.IsWritingEnabled;
        SpeechSequenceComboBox.IsEnabled =
            canEdit && SpeechTriggerComboBox.SelectedIndex == 1 && _behaviorSequences.Count > 0;
        SpeechDisplayDurationNumberBox.IsEnabled =
            canEdit && SpeechDisplayModeComboBox.SelectedIndex != 1;
    }

    private void SpeechSettings_Changed(object sender, object e)
    {
        if (_isRefreshingSpeechControls)
        {
            return;
        }
        bool canEdit = Application.Current is App app && app.SettingsStore.IsWritingEnabled;
        RefreshSpeechControlVisibility(canEdit);
        UpdateSpeechThemePreview();
        if (!_isLoaded)
        {
            return;
        }
        if (sender is ColorPicker)
        {
            _speechSaveTimer?.Stop();
            _speechSaveTimer?.Start();
        }
        else
        {
            PersistSpeechSettingsFromControls(showConfirmation: false);
        }
    }

    private void SpeechPeriodicIntervalNumberBox_KeyUp(
        object sender,
        Microsoft.UI.Xaml.Input.KeyRoutedEventArgs e)
    {
        if (e.Key != global::Windows.System.VirtualKey.Enter)
        {
            return;
        }

        e.Handled = true;
        DispatcherQueue.TryEnqueue(() =>
        {
            // NumberBox commits its edited text before KeyUp. Moving focus makes
            // the commit visible immediately and ValueChanged persists the new
            // interval, which resets the runtime's previous reservation.
            SpeechPeriodicOrderComboBox.Focus(FocusState.Programmatic);
        });
    }

    private void RefreshSpeechControlVisibility(bool canEdit)
    {
        if (SpeechCustomColorsGrid is null)
        {
            return;
        }
        bool speechEnabled = SpeechEnabledToggle.IsOn;
        bool periodicEnabled = speechEnabled && SpeechPeriodicEnabledToggle.IsOn;
        SpeechPeriodicEnabledToggle.IsEnabled = canEdit && speechEnabled;
        SpeechBehaviorChangePolicyComboBox.IsEnabled = canEdit && speechEnabled;
        SpeechPeriodicIntervalNumberBox.IsEnabled = canEdit && periodicEnabled;
        SpeechPeriodicOrderComboBox.IsEnabled =
            canEdit && periodicEnabled;
        BehaviorSpeechPhrasesList.IsEnabled = canEdit && speechEnabled;
        PeriodicSpeechPhrasesList.IsEnabled = canEdit && periodicEnabled;
        if (Application.Current is App app)
        {
            PetSpeechSettings speech = app.ActiveBehaviorProfile.Speech with
            {
                IsEnabled = speechEnabled,
                PeriodicIsEnabled = SpeechPeriodicEnabledToggle.IsOn,
            };
            AddBehaviorSpeechPhraseButton.IsEnabled = canEdit && speechEnabled &&
                _behaviorSequences.Count > 0 &&
                speech.Phrases.Count < AppSettingsLimits.MaximumSpeechPhrases;
            AddPeriodicSpeechPhraseButton.IsEnabled = canEdit && periodicEnabled &&
                speech.Phrases.Count < AppSettingsLimits.MaximumSpeechPhrases;
            RefreshSpeechPhraseActionButtons(canEdit, speech);
        }
        SpeechCustomColorsGrid.Visibility =
            SpeechThemeStyleComboBox.SelectedIndex == 5
                ? Visibility.Visible
                : Visibility.Collapsed;
        SpeechTailAlignmentComboBox.IsEnabled = canEdit && SpeechTailToggle.IsOn;
        RefreshSpeechPhraseFormVisibility();
    }

    private void SaveSpeechSettingsButton_Click(object sender, RoutedEventArgs e)
    {
        _speechSaveTimer?.Stop();
        PersistSpeechSettingsFromControls(showConfirmation: true);
    }

    private void PersistSpeechSettingsFromControls(bool showConfirmation)
    {
        if (Application.Current is not App app)
        {
            return;
        }
        try
        {
            BehaviorProfile profile = app.ActiveBehaviorProfile;
            PetSpeechBubbleTheme theme = SpeechThemeFromControls();
            if (theme.ColorStyle == PetSpeechBubbleColorStyle.Custom &&
                theme.CustomBackgroundColor.ContrastRatio(theme.CustomTextColor) <
                    AppSettingsLimits.MinimumSpeechBubbleTextContrastRatio)
            {
                throw new InvalidOperationException(
                    "사용자 지정 배경과 글자는 읽기 쉬운 대비(4.5:1 이상)가 필요합니다.");
            }

            PetSpeechSettings speech = profile.Speech with
            {
                IsEnabled = SpeechEnabledToggle.IsOn,
                PeriodicIsEnabled = SpeechPeriodicEnabledToggle.IsOn,
                PeriodicIntervalMilliseconds = checked((long)Math.Round(
                    RequiredFiniteValue(
                        SpeechPeriodicIntervalNumberBox,
                        5,
                        3_600,
                        "주기 대사 간격") * 1_000)),
                PeriodicOrder = SpeechPeriodicOrderComboBox.SelectedIndex == 1
                    ? PetSpeechPeriodicOrder.Sequential
                    : PetSpeechPeriodicOrder.Random,
                BehaviorChangePolicy = SpeechBehaviorChangePolicyComboBox.SelectedIndex == 1
                    ? PetSpeechBehaviorChangePolicy.Keep
                    : PetSpeechBehaviorChangePolicy.Dismiss,
                Theme = theme,
                Placement = new PetSpeechBubblePlacementSettings(
                    SpeechPreferredPositionComboBox.SelectedIndex switch
                    {
                        1 => PetSpeechBubblePreferredPosition.Above,
                        2 => PetSpeechBubblePreferredPosition.Below,
                        _ => PetSpeechBubblePreferredPosition.Automatic,
                    },
                    RequiredFiniteValue(
                        SpeechHorizontalOffsetNumberBox,
                        -160,
                        160,
                        "좌우 오프셋"),
                    RequiredFiniteValue(
                        SpeechGapNumberBox,
                        0,
                        64,
                        "펫 사이 간격")),
            };
            app.SaveBehaviorProfile(profile with { Speech = speech });
            if (showConfirmation)
            {
                SpeechSettingsInfoBar.Severity = InfoBarSeverity.Success;
                SpeechSettingsInfoBar.Title = "말풍선 설정을 저장했습니다";
                SpeechSettingsInfoBar.Message = "현재 펫의 다음 대사부터 적용됩니다.";
                SpeechSettingsInfoBar.IsOpen = true;
            }
            else
            {
                SpeechSettingsInfoBar.IsOpen = false;
            }
        }
        catch (Exception exception)
        {
            ShowSpeechError("말풍선 설정을 저장하지 못했습니다", exception);
        }
    }

    private PetSpeechBubbleTheme SpeechThemeFromControls() => new(
        SpeechThemeStyleComboBox.SelectedIndex switch
        {
            1 => PetSpeechBubbleColorStyle.Cream,
            2 => PetSpeechBubbleColorStyle.Midnight,
            3 => PetSpeechBubbleColorStyle.Mint,
            4 => PetSpeechBubbleColorStyle.Peach,
            5 => PetSpeechBubbleColorStyle.Custom,
            _ => PetSpeechBubbleColorStyle.System,
        },
        SpeechColor(SpeechBackgroundColorPicker.Color),
        SpeechColor(SpeechTextColorPicker.Color),
        RequiredFiniteValue(
            SpeechBackgroundOpacityNumberBox,
            65,
            100,
            "배경 불투명도") / 100,
        RequiredFiniteValue(SpeechFontSizeNumberBox, 11, 24, "글자 크기"),
        RequiredFiniteValue(SpeechPaddingNumberBox, 6, 24, "안쪽 여백"),
        RequiredFiniteValue(SpeechCornerRadiusNumberBox, 0, 28, "모서리 반경"),
        SpeechTailToggle.IsOn,
        SpeechTailAlignmentComboBox.SelectedIndex switch
        {
            0 => PetSpeechBubbleTailAlignment.Leading,
            2 => PetSpeechBubbleTailAlignment.Trailing,
            _ => PetSpeechBubbleTailAlignment.Center,
        });

    private void UpdateSpeechThemePreview()
    {
        if (SpeechThemePreviewBorder is null || SpeechThemePreviewText is null)
        {
            return;
        }
        PetSpeechBubbleColorStyle style = SpeechThemeStyleComboBox.SelectedIndex switch
        {
            1 => PetSpeechBubbleColorStyle.Cream,
            2 => PetSpeechBubbleColorStyle.Midnight,
            3 => PetSpeechBubbleColorStyle.Mint,
            4 => PetSpeechBubbleColorStyle.Peach,
            5 => PetSpeechBubbleColorStyle.Custom,
            _ => PetSpeechBubbleColorStyle.System,
        };
        (Color background, Color foreground) = PreviewThemeColors(style);
        var backgroundBrush = new SolidColorBrush(background)
        {
            Opacity = FiniteOr(
                SpeechBackgroundOpacityNumberBox.Value / 100,
                AppSettingsLimits.DefaultSpeechBubbleBackgroundOpacity),
        };
        SpeechThemePreviewBorder.Background = backgroundBrush;
        SpeechThemePreviewTail.Fill = backgroundBrush;
        bool showsTail = SpeechTailToggle.IsOn;
        SpeechThemePreviewTail.Visibility = showsTail
            ? Visibility.Visible
            : Visibility.Collapsed;
        SpeechThemePreviewTail.HorizontalAlignment = SpeechTailAlignmentComboBox.SelectedIndex switch
        {
            0 => HorizontalAlignment.Left,
            2 => HorizontalAlignment.Right,
            _ => HorizontalAlignment.Center,
        };
        SpeechThemePreviewTail.Margin = SpeechTailAlignmentComboBox.SelectedIndex switch
        {
            0 => new Thickness(36, 0, 0, 0),
            2 => new Thickness(0, 0, 36, 0),
            _ => new Thickness(0),
        };
        bool placesBelow = SpeechPreferredPositionComboBox.SelectedIndex == 2;
        double gap = Math.Max(0, FiniteOr(SpeechGapNumberBox.Value, 0));
        double connectorHeight = showsTail ? 10 + gap : gap;
        SpeechPlacementPreviewGrid.RowDefinitions[1].Height = new GridLength(
            placesBelow ? 0 : connectorHeight);
        SpeechPlacementPreviewGrid.RowDefinitions[3].Height = new GridLength(
            placesBelow ? connectorHeight : 0);
        SpeechThemePreviewTail.Height = 10;
        SpeechThemePreviewTail.VerticalAlignment = placesBelow
            ? VerticalAlignment.Bottom
            : VerticalAlignment.Top;
        Grid.SetRow(SpeechThemePreviewBorder, placesBelow ? 4 : 0);
        Grid.SetRow(SpeechThemePreviewTail, placesBelow ? 3 : 1);
        SpeechThemePreviewTail.Points.Clear();
        if (placesBelow)
        {
            SpeechThemePreviewTail.Points.Add(new global::Windows.Foundation.Point(9, 0));
            SpeechThemePreviewTail.Points.Add(new global::Windows.Foundation.Point(18, 10));
            SpeechThemePreviewTail.Points.Add(new global::Windows.Foundation.Point(0, 10));
        }
        else
        {
            SpeechThemePreviewTail.Points.Add(new global::Windows.Foundation.Point(0, 0));
            SpeechThemePreviewTail.Points.Add(new global::Windows.Foundation.Point(18, 0));
            SpeechThemePreviewTail.Points.Add(new global::Windows.Foundation.Point(9, 10));
        }
        double horizontalOffset = FiniteOr(SpeechHorizontalOffsetNumberBox.Value, 0);
        SpeechThemePreviewBorder.RenderTransform = new TranslateTransform { X = horizontalOffset };
        if (Math.Abs(horizontalOffset) > 0.001)
        {
            // The real bubble corrects the tail anchor back toward the pet when
            // the body is offset. Keep the preview tip over the pet as well.
            SpeechThemePreviewTail.HorizontalAlignment = HorizontalAlignment.Center;
            SpeechThemePreviewTail.Margin = new Thickness(0);
        }
        SpeechThemePreviewTail.RenderTransform = new TranslateTransform();
        SpeechThemePreviewBorder.Margin = new Thickness(0);
        SpeechThemePreviewBorder.Padding = new Thickness(FiniteOr(
            SpeechPaddingNumberBox.Value,
            AppSettingsLimits.DefaultSpeechBubbleContentPadding));
        SpeechThemePreviewBorder.CornerRadius = new CornerRadius(FiniteOr(
            SpeechCornerRadiusNumberBox.Value,
            AppSettingsLimits.DefaultSpeechBubbleCornerRadius));
        SpeechThemePreviewText.Foreground = new SolidColorBrush(foreground);
        SpeechThemePreviewText.FontSize = FiniteOr(
            SpeechFontSizeNumberBox.Value,
            AppSettingsLimits.DefaultSpeechBubbleFontSize);
        SpeechThemePreviewText.Text = string.IsNullOrWhiteSpace(SpeechPhraseTextBox?.Text)
            ? "오늘도 같이 있어요!"
            : SpeechPhraseTextBox.Text.Trim();
    }

    private (Color Background, Color Foreground) PreviewThemeColors(
        PetSpeechBubbleColorStyle style)
    {
        bool dark = Application.Current.RequestedTheme == ApplicationTheme.Dark;
        return style switch
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
                (SpeechBackgroundColorPicker.Color, SpeechTextColorPicker.Color),
            _ when dark =>
                (Color.FromArgb(255, 43, 43, 43), Colors.White),
            _ =>
                (Colors.White, Colors.Black),
        };
    }

    private static double FiniteOr(double value, double fallback) =>
        double.IsFinite(value) ? value : fallback;

    private static PetSpeechColor SpeechColor(Color color) => new(
        color.R / 255d,
        color.G / 255d,
        color.B / 255d);

    private static Color ColorValue(PetSpeechColor color) => Color.FromArgb(
        255,
        (byte)Math.Round(color.Red * 255),
        (byte)Math.Round(color.Green * 255),
        (byte)Math.Round(color.Blue * 255));

    private static string SpeechPhraseDetail(PetSpeechPhrase phrase, BehaviorProfile profile)
    {
        string trigger = phrase.Trigger switch
        {
            PetSpeechTrigger.Sequence sequence =>
                $"행동 · {profile.Sequences.FirstOrDefault(candidate => string.Equals(
                    candidate.Id,
                    sequence.SequenceId,
                    StringComparison.Ordinal))?.DisplayName ?? "찾을 수 없는 행동"}",
            _ => "주기",
        };
        string display = phrase.DisplayMode == PetSpeechDisplayMode.UntilNextPhrase
            ? "다음 대사까지 유지"
            : $"{phrase.DisplayDurationMilliseconds / 1_000d:0.#}초 표시";
        return $"{trigger} · {display}";
    }

    private void ShowSpeechError(string title, Exception exception)
    {
        SpeechSettingsInfoBar.Severity = InfoBarSeverity.Error;
        SpeechSettingsInfoBar.Title = title;
        SpeechSettingsInfoBar.Message = exception.Message;
        SpeechSettingsInfoBar.IsOpen = true;
    }

    private void RefreshRuleForm(BehaviorProfile profile, AutomaticRule? rule)
    {
        RuleEnabledToggle.IsOn = rule?.IsEnabled ?? true;
        RulePriorityNumberBox.Value = rule?.Priority ?? NextRulePriority(profile);
        RuleConditionTypeComboBox.SelectedIndex = rule?.Condition is RuleCondition.IdleAtLeast ? 1 : 0;
        string applicationId =
            (rule?.Condition as RuleCondition.Application)?.ApplicationId ?? string.Empty;
        if (!string.Equals(
                _selectedApplicationChoice?.Identifier,
                WindowsApplicationCatalogNormalizer.NormalizeIdentifier(applicationId),
                StringComparison.OrdinalIgnoreCase))
        {
            _selectedApplicationChoice = null;
        }
        RuleApplicationIdTextBox.Text = applicationId;
        RuleIdleMinutesNumberBox.Value = rule?.Condition is RuleCondition.IdleAtLeast idle
            ? idle.Milliseconds / 1_000d
            : 60;
        string? targetId = rule?.SequenceId ?? profile.Sequences.FirstOrDefault()?.Id;
        RuleTargetSequenceComboBox.SelectedItem = _behaviorSequences.FirstOrDefault(item =>
            string.Equals(item.Id, targetId, StringComparison.Ordinal));
        RefreshRuleConditionVisibility();
        RefreshApplicationSelectionSummary();
    }

    private void RoutineEditorComboBox_SelectionChanged(
        object sender,
        SelectionChangedEventArgs e)
    {
        if (!_isLoaded || _isRefreshingBehaviorEditor ||
            Application.Current is not App app)
        {
            return;
        }

        _selectedRoutineId = (RoutineEditorComboBox.SelectedItem as BehaviorSequenceItem)?.Id;
        _isRefreshingBehaviorEditor = true;
        try
        {
            RefreshRoutineEditor(app.ActiveBehaviorProfile, app.SettingsStore.IsWritingEnabled);
        }
        finally
        {
            _isRefreshingBehaviorEditor = false;
        }
    }

    private async void AddSequenceButton_Click(object sender, RoutedEventArgs e)
    {
        string? requestedName = await ShowRoutineNameDialogAsync(
            "새 행동 루틴 만들기",
            "새 루틴 이름",
            string.Empty,
            "만들기");
        if (requestedName is null)
        {
            return;
        }

        ApplyBehaviorProfileEdit(
            profile => BehaviorProfileEditor.AddSequence(profile, requestedName),
            onSuccess: profile =>
            {
                _selectedRoutineId = profile.Sequences.Last().Id;
            });
    }

    private async void RenameSequenceButton_Click(object sender, RoutedEventArgs e)
    {
        if (_selectedRoutineId is not { } sequenceId ||
            Application.Current is not App app ||
            app.ActiveBehaviorProfile.Sequences.FirstOrDefault(sequence =>
                string.Equals(sequence.Id, sequenceId, StringComparison.Ordinal)) is not { } sequence)
        {
            return;
        }

        string? requestedName = await ShowRoutineNameDialogAsync(
            "행동 루틴 이름 변경",
            "행동 루틴 이름",
            sequence.DisplayName,
            "변경");
        if (requestedName is null)
        {
            return;
        }

        ApplyBehaviorProfileEdit(
            profile => BehaviorProfileEditor.RenameSequence(
                profile,
                sequenceId,
                requestedName));
    }

    private async Task<string?> ShowRoutineNameDialogAsync(
        string title,
        string inputHeader,
        string initialValue,
        string primaryButtonText)
    {
        var nameTextBox = new TextBox
        {
            Header = inputHeader,
            MaxLength = 80,
            PlaceholderText = "예: 집중하기",
            Text = initialValue,
        };
        var dialog = new ContentDialog
        {
            XamlRoot = XamlRoot,
            Title = title,
            Content = nameTextBox,
            PrimaryButtonText = primaryButtonText,
            CloseButtonText = "취소",
            DefaultButton = ContentDialogButton.Primary,
        };
        dialog.Opened += (_, _) =>
        {
            nameTextBox.Focus(FocusState.Programmatic);
            nameTextBox.SelectAll();
        };
        return await dialog.ShowAsync() == ContentDialogResult.Primary
            ? nameTextBox.Text
            : null;
    }

    private void DeleteSequenceButton_Click(object sender, RoutedEventArgs e)
    {
        if (_selectedRoutineId is not { } sequenceId)
        {
            return;
        }
        ApplyBehaviorProfileEdit(
            profile => BehaviorProfileEditor.RemoveSequence(profile, sequenceId),
            onSuccess: profile =>
            {
                _selectedRoutineId = profile.Sequences.FirstOrDefault()?.Id;
                _selectedRuleId = null;
            });
    }

    private void SequenceRepeatsToggle_Toggled(object sender, RoutedEventArgs e)
    {
        if (!_isLoaded || _isRefreshingBehaviorEditor ||
            _selectedRoutineId is not { } sequenceId)
        {
            return;
        }
        ApplyBehaviorProfileEdit(profile => BehaviorProfileEditor.SetSequenceRepeats(
            profile,
            sequenceId,
            SequenceRepeatsToggle.IsOn));
    }

    private void AddStepButton_Click(object sender, RoutedEventArgs e)
    {
        if (_selectedRoutineId is not { } sequenceId)
        {
            return;
        }
        ApplyBehaviorProfileEdit(profile => BehaviorProfileEditor.AddStep(profile, sequenceId));
    }

    private async void ChooseStepMotionButton_Click(object sender, RoutedEventArgs e)
    {
        if (!_isLoaded || _isRefreshingBehaviorEditor ||
            _selectedRoutineId is not { } sequenceId ||
            sender is not Button { Tag: int index } ||
            Application.Current is not App app)
        {
            return;
        }

        BehaviorStep current = RequiredStep(app.ActiveBehaviorProfile, sequenceId, index);
        var picker = new ListView
        {
            DisplayMemberPath = nameof(MotionOptionItem.DisplayName),
            ItemsSource = _motionOptions,
            MaxHeight = 360,
            MinWidth = 320,
            SelectionMode = ListViewSelectionMode.Single,
            SelectedItem = _motionOptions.FirstOrDefault(option => string.Equals(
                option.Id,
                current.MotionId,
                StringComparison.Ordinal)),
        };
        var dialog = new ContentDialog
        {
            XamlRoot = XamlRoot,
            Title = $"{index + 1}단계 애니메이션",
            Content = picker,
            PrimaryButtonText = "선택",
            CloseButtonText = "취소",
            DefaultButton = ContentDialogButton.Primary,
        };
        if (await dialog.ShowAsync() != ContentDialogResult.Primary ||
            picker.SelectedItem is not MotionOptionItem motion)
        {
            return;
        }

        ApplyBehaviorProfileEdit(profile =>
        {
            BehaviorStep latest = RequiredStep(profile, sequenceId, index);
            return BehaviorProfileEditor.ReplaceStep(
                profile,
                sequenceId,
                index,
                latest with { MotionId = motion.Id });
        });
    }

    private void StepRepeatCountNumberBox_ValueChanged(
        NumberBox sender,
        NumberBoxValueChangedEventArgs args)
    {
        if (!_isLoaded || _isRefreshingBehaviorEditor ||
            _selectedRoutineId is not { } sequenceId ||
            sender.Tag is not int index ||
            !double.IsFinite(args.NewValue) ||
            Math.Truncate(args.NewValue) != args.NewValue)
        {
            return;
        }
        int repeatCount = checked((int)args.NewValue);
        ApplyBehaviorProfileEdit(profile =>
        {
            BehaviorStep current = RequiredStep(profile, sequenceId, index);
            return BehaviorProfileEditor.ReplaceStep(
                profile,
                sequenceId,
                index,
                current with { RepeatCount = repeatCount });
        });
    }

    private void MoveStepUpButton_Click(object sender, RoutedEventArgs e) =>
        MoveStep(sender, -1);

    private void MoveStepDownButton_Click(object sender, RoutedEventArgs e) =>
        MoveStep(sender, 1);

    private void MoveStep(object sender, int offset)
    {
        if (_selectedRoutineId is not { } sequenceId ||
            sender is not Button { Tag: int index })
        {
            return;
        }
        int destination = index + offset;
        if (destination < 0 || destination >= _behaviorSteps.Count)
        {
            return;
        }
        ApplyBehaviorProfileEdit(profile => BehaviorProfileEditor.MoveStep(
            profile,
            sequenceId,
            index,
            destination));
    }

    private void RemoveStepButton_Click(object sender, RoutedEventArgs e)
    {
        if (_selectedRoutineId is not { } sequenceId ||
            sender is not Button { Tag: int index })
        {
            return;
        }
        ApplyBehaviorProfileEdit(profile => BehaviorProfileEditor.RemoveStep(
            profile,
            sequenceId,
            index));
    }

    private void AutomaticRulesList_SelectionChanged(
        object sender,
        SelectionChangedEventArgs e)
    {
        if (!_isLoaded || _isRefreshingBehaviorEditor ||
            Application.Current is not App app)
        {
            return;
        }
        _selectedRuleId = (AutomaticRulesList.SelectedItem as AutomaticRuleEditorItem)?.Id;
        AutomaticRule? rule = app.ActiveBehaviorProfile.AutomaticRules.FirstOrDefault(value =>
            value.Id == _selectedRuleId);
        _isRefreshingBehaviorEditor = true;
        try
        {
            RefreshRuleForm(app.ActiveBehaviorProfile, rule);
            SaveRuleButton.IsEnabled = rule is not null && app.SettingsStore.IsWritingEnabled;
            DeleteRuleButton.IsEnabled = rule is not null && app.SettingsStore.IsWritingEnabled;
        }
        finally
        {
            _isRefreshingBehaviorEditor = false;
        }
    }

    private void NewApplicationRuleButton_Click(object sender, RoutedEventArgs e) =>
        PrepareNewRule(conditionIndex: 0);

    private void MoveRulePriorityUpButton_Click(object sender, RoutedEventArgs e) =>
        MoveRulePriority(-1);

    private void MoveRulePriorityDownButton_Click(object sender, RoutedEventArgs e) =>
        MoveRulePriority(1);

    private void MoveRulePriority(int delta)
    {
        int source = RulePriorityOrderList.SelectedIndex;
        int destination = source + delta;
        if (source < 0 || destination < 0 || destination >= _rulePriorityKinds.Count)
        {
            return;
        }
        RulePriorityKindItem item = _rulePriorityKinds[source];
        _rulePriorityKinds.Move(source, destination);
        RulePriorityOrderList.SelectedItem = item;
        ApplyBehaviorProfileEdit(profile => profile with
        {
            AutomaticRulePriorityOrder = _rulePriorityKinds
                .Select(value => value.Kind)
                .ToArray(),
        });
    }

    private void NewIdleRuleButton_Click(object sender, RoutedEventArgs e) =>
        PrepareNewRule(conditionIndex: 1);

    private void IdleRuleEnabledToggle_Toggled(object sender, RoutedEventArgs e)
    {
        if (!_isLoaded || _isRefreshingBehaviorEditor)
        {
            return;
        }
        SaveIdleRuleSettings();
    }

    private void SaveIdleRuleSettingsButton_Click(object sender, RoutedEventArgs e)
    {
        SaveIdleRuleSettings();
    }

    private void SaveIdleRuleSettings()
    {
        if (Application.Current is not App app)
        {
            return;
        }
        try
        {
            BehaviorProfile profile = app.ActiveBehaviorProfile;
            AutomaticRule? existing = profile.AutomaticRules.FirstOrDefault(rule =>
                rule.Condition is RuleCondition.IdleAtLeast);
            if (IdleRuleTargetSequenceComboBox.SelectedValue is not string sequenceId)
            {
                throw new InvalidOperationException("입력 없음 때 실행할 행동을 선택해 주세요.");
            }
            double rawSeconds = IdleRuleSecondsNumberBox.Value;
            if (!double.IsFinite(rawSeconds) || rawSeconds != Math.Truncate(rawSeconds) ||
                rawSeconds is < 1 or > 86_400)
            {
                throw new InvalidOperationException("입력 없음 시간은 1초에서 86,400초 사이의 정수여야 합니다.");
            }
            int seconds = (int)rawSeconds;
            BehaviorProfile updated;
            if (existing is null)
            {
                if (!IdleRuleEnabledToggle.IsOn)
                {
                    BehaviorSettingsInfoBar.IsOpen = false;
                    return;
                }
                updated = BehaviorProfileEditor.AddIdleRule(profile, seconds, sequenceId);
            }
            else
            {
                updated = BehaviorProfileEditor.ReplaceRule(profile, existing with
                {
                    IsEnabled = IdleRuleEnabledToggle.IsOn,
                    Condition = new RuleCondition.IdleAtLeast(checked((long)seconds * 1_000)),
                    SequenceId = sequenceId,
                });
            }
            _isPersistingBehaviorControls = true;
            try
            {
                app.SaveBehaviorProfile(updated);
            }
            finally
            {
                _isPersistingBehaviorControls = false;
            }
            BehaviorSettingsInfoBar.IsOpen = false;
            RefreshBehaviorState();
        }
        catch (Exception exception)
        {
            ShowBehaviorError(exception);
        }
    }

    private void PrepareNewRule(int conditionIndex)
    {
        if (Application.Current is not App app)
        {
            return;
        }
        _selectedRuleId = null;
        _isRefreshingBehaviorEditor = true;
        try
        {
            AutomaticRulesList.SelectedItem = null;
            RefreshRuleForm(app.ActiveBehaviorProfile, null);
            RuleConditionTypeComboBox.SelectedIndex = conditionIndex;
            AddRuleButton.Content = conditionIndex == 1
                ? "입력 없음 규칙 추가"
                : "앱 규칙 추가";
            SaveRuleButton.IsEnabled = false;
            DeleteRuleButton.IsEnabled = false;
        }
        finally
        {
            _isRefreshingBehaviorEditor = false;
        }
    }

    private void RuleConditionTypeComboBox_SelectionChanged(
        object sender,
        SelectionChangedEventArgs e) => RefreshRuleConditionVisibility();

    private void RefreshRuleConditionVisibility()
    {
        if (ApplicationRuleEditorGrid is null || RuleIdleMinutesNumberBox is null)
        {
            return;
        }
        bool isIdle = RuleConditionTypeComboBox.SelectedIndex == 1;
        ApplicationRuleEditorGrid.Visibility = isIdle ? Visibility.Collapsed : Visibility.Visible;
        RuleIdleMinutesNumberBox.Visibility = isIdle ? Visibility.Visible : Visibility.Collapsed;
        AddRuleButton.Content = isIdle ? "입력 없음 규칙 추가" : "앱 규칙 추가";
    }

    private void RuleApplicationIdTextBox_TextChanged(
        object sender,
        TextChangedEventArgs e)
    {
        if (_isRefreshingBehaviorEditor)
        {
            return;
        }

        string? normalized = WindowsApplicationCatalogNormalizer.NormalizeIdentifier(
            RuleApplicationIdTextBox.Text);
        if (!string.Equals(
                normalized,
                _selectedApplicationChoice?.Identifier,
                StringComparison.OrdinalIgnoreCase))
        {
            _selectedApplicationChoice = null;
        }
        RefreshApplicationSelectionSummary();
    }

    private async void ChooseApplicationButton_Click(object sender, RoutedEventArgs e)
    {
        if (Application.Current is not App app)
        {
            return;
        }

        var items = new ObservableCollection<ApplicationPickerItem>();
        var list = new ListView
        {
            ItemsSource = items,
            ItemTemplate = (DataTemplate)Resources["ApplicationPickerItemTemplate"],
            SelectionMode = ListViewSelectionMode.Single,
            MinWidth = 520,
            MaxHeight = 360,
        };
        AutomationProperties.SetAutomationId(list, "ApplicationPickerList");
        var status = new TextBlock
        {
            Text = "실행 중 앱을 확인하는 중입니다.",
            TextWrapping = TextWrapping.Wrap,
        };
        AutomationProperties.SetAutomationId(status, "ApplicationPickerStatusText");
        var refresh = new Button { Content = "새로 고침" };
        AutomationProperties.SetAutomationId(refresh, "RefreshApplicationPickerButton");
        var panel = new StackPanel { Spacing = 12 };
        panel.Children.Add(new TextBlock
        {
            Text = "일반 창이 열려 있는 앱만 표시합니다. 이름·아이콘·경로는 저장하지 않습니다.",
            TextWrapping = TextWrapping.Wrap,
        });
        panel.Children.Add(status);
        panel.Children.Add(refresh);
        panel.Children.Add(list);
        var dialog = new ContentDialog
        {
            XamlRoot = XamlRoot,
            Title = "앱 사용 규칙 대상 앱 선택",
            Content = panel,
            PrimaryButtonText = "선택",
            CloseButtonText = "취소",
            DefaultButton = ContentDialogButton.Primary,
            IsPrimaryButtonEnabled = false,
        };
        AutomationProperties.SetAutomationId(dialog, "ApplicationPickerDialog");
        list.SelectionChanged += (_, _) =>
            dialog.IsPrimaryButtonEnabled = list.SelectedItem is ApplicationPickerItem;

        async Task RefreshChoices()
        {
            refresh.IsEnabled = false;
            status.Text = "실행 중 앱을 확인하는 중입니다.";
            try
            {
                IReadOnlyList<WindowsApplicationChoice> choices = await Task.Run(
                    app.ApplicationCatalog.GetRunningApplications);
                items.Clear();
                foreach (WindowsApplicationChoice choice in choices)
                {
                    items.Add(new ApplicationPickerItem(choice));
                }

                list.SelectedItem = items.FirstOrDefault(item => string.Equals(
                    item.Identifier,
                    WindowsApplicationCatalogNormalizer.NormalizeIdentifier(
                        RuleApplicationIdTextBox.Text),
                    StringComparison.OrdinalIgnoreCase));
                status.Text = items.Count == 0
                    ? "선택할 수 있는 실행 중 앱이 없습니다. 앱을 연 뒤 새로 고치거나 실행 파일을 선택하세요."
                    : $"실행 중 앱 {items.Count}개";
                _ = PopulateApplicationIcons(items.ToList());
            }
            catch (Exception exception)
            {
                status.Text = $"실행 중 앱 목록을 가져오지 못했습니다: {exception.Message}";
            }
            finally
            {
                refresh.IsEnabled = true;
            }
        }

        refresh.Click += async (_, _) => await RefreshChoices();
        await RefreshChoices();
        ContentDialogResult result = await dialog.ShowAsync();
        if (result == ContentDialogResult.Primary &&
            list.SelectedItem is ApplicationPickerItem selected)
        {
            ApplyApplicationChoice(selected.Choice);
        }
    }

    private async void ChooseExecutableButton_Click(object sender, RoutedEventArgs e)
    {
        if (Application.Current is App app)
        {
            await ChooseExecutableApplication(app);
        }
    }

    private async Task ChooseExecutableApplication(App app)
    {
        if (app.MainWindowHandle == IntPtr.Zero)
        {
            return;
        }

        var picker = new FileOpenPicker
        {
            SuggestedStartLocation = PickerLocationId.Downloads,
            ViewMode = PickerViewMode.List,
        };
        picker.FileTypeFilter.Add(".exe");
        WinRT.Interop.InitializeWithWindow.Initialize(picker, app.MainWindowHandle);
        global::Windows.Storage.StorageFile? file;
        try
        {
            file = await picker.PickSingleFileAsync();
        }
        catch (Exception exception)
        {
            ShowBehaviorError(exception);
            return;
        }
        if (file is null)
        {
            return;
        }

        try
        {
            WindowsApplicationChoice choice = await Task.Run(
                () => app.ApplicationCatalog.InspectExecutable(file.Path));
            ApplyApplicationChoice(choice);
            BehaviorSettingsInfoBar.IsOpen = false;
        }
        catch (Exception exception)
        {
            ShowBehaviorError(exception);
        }
    }

    private static async Task PopulateApplicationIcons(
        IEnumerable<ApplicationPickerItem> items)
    {
        foreach (ApplicationPickerItem item in items)
        {
            item.Icon = await LoadApplicationIcon(item.ExecutablePath);
        }
    }

    private static async Task<BitmapImage?> LoadApplicationIcon(string? executablePath)
    {
        if (executablePath is null)
        {
            return null;
        }

        try
        {
            global::Windows.Storage.StorageFile file =
                await global::Windows.Storage.StorageFile.GetFileFromPathAsync(executablePath);
            using global::Windows.Storage.FileProperties.StorageItemThumbnail thumbnail =
                await file.GetThumbnailAsync(
                    global::Windows.Storage.FileProperties.ThumbnailMode.SingleItem,
                    32,
                    global::Windows.Storage.FileProperties.ThumbnailOptions.UseCurrentScale);
            var image = new BitmapImage { DecodePixelWidth = 32 };
            await image.SetSourceAsync(thumbnail);
            return image;
        }
        catch
        {
            return null;
        }
    }

    private void ApplyApplicationChoice(WindowsApplicationChoice choice)
    {
        _selectedApplicationChoice = choice;
        RuleApplicationIdTextBox.Text = choice.Identifier;
        RefreshApplicationSelectionSummary();
    }

    private void RefreshApplicationSelectionSummary()
    {
        if (RuleApplicationSelectionText is null || RuleApplicationIdTextBox is null)
        {
            return;
        }

        string? normalized = WindowsApplicationCatalogNormalizer.NormalizeIdentifier(
            RuleApplicationIdTextBox.Text);
        RuleApplicationSelectionText.Text =
            _selectedApplicationChoice is { } selected &&
            string.Equals(selected.Identifier, normalized, StringComparison.OrdinalIgnoreCase)
                ? $"{selected.DisplayName} · {selected.Identifier}"
                : normalized ?? "선택되지 않음";
    }

    private void UseCurrentApplicationButton_Click(object sender, RoutedEventArgs e)
    {
        if (Application.Current is App app &&
            app.LatestActivitySnapshot?.FrontmostApplicationId is { } applicationId)
        {
            ApplyApplicationChoice(new WindowsApplicationChoice(
                applicationId,
                "현재 전면 앱",
                null));
        }
        else
        {
            ShowBehaviorError(new InvalidOperationException("현재 전면 앱 식별자를 확인할 수 없습니다."));
        }
    }

    private void AddRuleButton_Click(object sender, RoutedEventArgs e)
    {
        Guid ruleId = Guid.NewGuid();
        ApplyBehaviorProfileEdit(
            profile =>
            {
                string targetId = RequiredRuleTargetId();
                BehaviorProfile added = RuleConditionTypeComboBox.SelectedIndex == 1
                    ? BehaviorProfileEditor.AddIdleRule(
                        profile,
                        RequiredIdleSeconds(),
                        targetId,
                        ruleId)
                    : BehaviorProfileEditor.AddApplicationRule(
                        profile,
                        RequiredWindowsApplicationId(),
                        targetId,
                        ruleId);
                AutomaticRule generated = added.AutomaticRules.First(rule => rule.Id == ruleId);
                return BehaviorProfileEditor.ReplaceRule(
                    added,
                    generated with
                    {
                        IsEnabled = RuleEnabledToggle.IsOn,
                        Priority = RequiredRulePriority(),
                    });
            },
            onSuccess: profile => _selectedRuleId = ruleId);
    }

    private void SaveRuleButton_Click(object sender, RoutedEventArgs e)
    {
        if (_selectedRuleId is not Guid ruleId)
        {
            return;
        }
        ApplyBehaviorProfileEdit(profile =>
        {
            AutomaticRule current = profile.AutomaticRules.First(rule => rule.Id == ruleId);
            RuleCondition condition = RuleConditionTypeComboBox.SelectedIndex == 1
                ? new RuleCondition.IdleAtLeast(checked((long)RequiredIdleSeconds() * 1_000))
                : new RuleCondition.Application(RequiredWindowsApplicationId());
            return BehaviorProfileEditor.ReplaceRule(
                profile,
                current with
                {
                    IsEnabled = RuleEnabledToggle.IsOn,
                    Priority = RequiredRulePriority(),
                    Condition = condition,
                    SequenceId = RequiredRuleTargetId(),
                });
        });
    }

    private void DeleteRuleButton_Click(object sender, RoutedEventArgs e)
    {
        if (_selectedRuleId is not Guid ruleId)
        {
            return;
        }
        ApplyBehaviorProfileEdit(
            profile => BehaviorProfileEditor.RemoveRule(profile, ruleId),
            onSuccess: profile => _selectedRuleId = null);
    }

    private void ApplyBehaviorProfileEdit(
        Func<BehaviorProfile, BehaviorProfile> edit,
        Action<BehaviorProfile>? onSuccess = null)
    {
        if (Application.Current is not App app)
        {
            return;
        }
        try
        {
            BehaviorProfile updated = edit(app.ActiveBehaviorProfile);
            _isPersistingBehaviorControls = true;
            try
            {
                app.SaveBehaviorProfile(updated);
            }
            finally
            {
                _isPersistingBehaviorControls = false;
            }
            onSuccess?.Invoke(updated);
            BehaviorSettingsInfoBar.IsOpen = false;
        }
        catch (Exception exception)
        {
            ShowBehaviorError(exception);
        }
        DispatcherQueue.TryEnqueue(() =>
        {
            if (!_isLoaded)
            {
                return;
            }

            RefreshBehaviorState();
        });
    }

    private void ShowBehaviorError(Exception exception)
    {
        BehaviorSettingsInfoBar.Severity = InfoBarSeverity.Error;
        BehaviorSettingsInfoBar.Title = "행동 설정을 저장하지 못했습니다";
        BehaviorSettingsInfoBar.Message = exception.Message;
        BehaviorSettingsInfoBar.IsOpen = true;
    }

    private BehaviorSequence? SelectedRoutine(BehaviorProfile profile) =>
        profile.Sequences.FirstOrDefault(sequence => string.Equals(
            sequence.Id,
            _selectedRoutineId,
            StringComparison.Ordinal));

    private static BehaviorStep RequiredStep(
        BehaviorProfile profile,
        string sequenceId,
        int index) =>
        profile.Sequences.First(sequence => string.Equals(
            sequence.Id,
            sequenceId,
            StringComparison.Ordinal)).Steps[index];

    private string RequiredRuleTargetId() =>
        (RuleTargetSequenceComboBox.SelectedItem as BehaviorSequenceItem)?.Id
        ?? throw new InvalidOperationException("조건 규칙이 실행할 행동을 선택해 주세요.");

    private string RequiredWindowsApplicationId()
    {
        string value = RuleApplicationIdTextBox.Text.Trim().ToLowerInvariant();
        if ((!value.StartsWith("pfn:", StringComparison.Ordinal) &&
             !value.StartsWith("exe:", StringComparison.Ordinal)) ||
            value.Any(char.IsWhiteSpace) || value.Length is <= 4)
        {
            throw new InvalidOperationException("앱 식별자는 공백 없는 pfn: 또는 exe: 형식이어야 합니다.");
        }
        return value;
    }

    private int RequiredIdleSeconds()
    {
        double value = RuleIdleMinutesNumberBox.Value;
        if (!double.IsFinite(value) || Math.Truncate(value) != value || value is < 1 or > 86_400)
        {
            throw new InvalidOperationException("입력 없음 시간은 1초에서 86,400초 사이의 정수여야 합니다.");
        }
        return checked((int)value);
    }

    private int RequiredRulePriority()
    {
        double value = RulePriorityNumberBox.Value;
        if (!double.IsFinite(value) || Math.Truncate(value) != value ||
            value < int.MinValue || value > int.MaxValue)
        {
            throw new InvalidOperationException("우선순위는 32비트 정수여야 합니다.");
        }
        return checked((int)value);
    }

    private static int NextRulePriority(BehaviorProfile profile)
    {
        if (profile.AutomaticRules.Count == 0)
        {
            return 0;
        }
        int maximum = profile.AutomaticRules.Max(rule => rule.Priority);
        return maximum == int.MaxValue ? int.MaxValue : maximum + 1;
    }

    private static string RuleSummary(AutomaticRule rule) => rule.Condition switch
    {
        RuleCondition.Application application => $"전면 앱 · {application.ApplicationId}",
        RuleCondition.IdleAtLeast idle => $"입력 없음 · {idle.Milliseconds / 1_000d:0.###}초",
        RuleCondition.Unsupported unsupported => $"지원하지 않는 조건 · {unsupported.Type}",
        _ => "알 수 없는 조건",
    };

    private void PersistBehaviorSelectionFromControls()
    {
        if (Application.Current is not App app)
        {
            return;
        }

        StationaryBehaviorMode mode = BehaviorModeComboBox.SelectedIndex switch
        {
            1 => StationaryBehaviorMode.Random,
            _ => StationaryBehaviorMode.Fixed,
        };
        string? sequenceId =
            (ManualSequenceComboBox.SelectedItem as BehaviorSequenceItem)?.Id;
        try
        {
            string[] randomIds = RandomSequencesList.SelectedItems
                .OfType<BehaviorSequenceItem>()
                .Select(item => item.Id)
                .ToArray();
            _isPersistingBehaviorControls = true;
            try
            {
                app.SaveBehaviorSelection(mode, sequenceId, randomIds);
            }
            finally
            {
                _isPersistingBehaviorControls = false;
            }
            BehaviorSettingsInfoBar.IsOpen = false;
        }
        catch (Exception exception)
        {
            BehaviorSettingsInfoBar.Severity = InfoBarSeverity.Error;
            BehaviorSettingsInfoBar.Title = "행동 설정을 저장하지 못했습니다";
            BehaviorSettingsInfoBar.Message = exception.Message;
            BehaviorSettingsInfoBar.IsOpen = true;
        }

        RefreshBehaviorState();
    }

    private void PersistMovementSettingsFromControls()
    {
        if (Application.Current is not App app)
        {
            return;
        }

        _isPersistingMovementControls = true;
        try
        {
            BehaviorProfile profile = app.ActiveBehaviorProfile;
            PetMovementSettings current = profile.Movement;
            PetMovementMode selectedMode = MovementModeComboBox.SelectedIndex switch
            {
                1 => PetMovementMode.CursorFollowing,
                2 => PetMovementMode.FreeRoaming,
                3 => PetMovementMode.CursorAvoiding,
                _ => PetMovementMode.Fixed,
            };
            double sharedSpeed = RequiredFiniteValue(
                MovementSpeedNumberBox, 20, 1_000, "이동 속도");
            double sharedStopRadius = RequiredFiniteValue(
                MovementStopRadiusNumberBox, 0, 128, "정지 반경");
            long dwellMilliseconds = checked((long)Math.Round(
                RequiredFiniteValue(
                    FreeRoamingDwellNumberBox, 0.5, 300, "머무름 시간") * 1_000));
            long minimumDwellMilliseconds = checked((long)Math.Round(
                RequiredFiniteValue(
                    FreeRoamingDwellMinimumNumberBox, 0.5, 300, "최소 머무름 시간") * 1_000));
            if (minimumDwellMilliseconds > dwellMilliseconds)
            {
                throw new InvalidOperationException(
                    "최소 머무는 시간은 최대 머무는 시간보다 길 수 없습니다.");
            }
            CursorFollowingMovementSettings following = current.CursorFollowing with
            {
                Speed = selectedMode == PetMovementMode.CursorFollowing
                    ? sharedSpeed
                    : current.CursorFollowing.Speed,
                StopRadius = selectedMode == PetMovementMode.CursorFollowing
                    ? sharedStopRadius
                    : current.CursorFollowing.StopRadius,
                CursorDistance = RequiredFiniteValue(
                    CursorDistanceNumberBox, 0, 512, "마우스 거리"),
                Behavior = CursorFollowingAnimationEditor.Settings,
            };
            FreeRoamingMovementSettings roaming = current.FreeRoaming with
            {
                Speed = selectedMode == PetMovementMode.FreeRoaming
                    ? sharedSpeed
                    : current.FreeRoaming.Speed,
                StopRadius = selectedMode == PetMovementMode.FreeRoaming
                    ? sharedStopRadius
                    : current.FreeRoaming.StopRadius,
                DwellMilliseconds = dwellMilliseconds,
                RandomizesDwell = RandomizesDwellToggle.IsOn,
                DwellMinimumMilliseconds = minimumDwellMilliseconds,
                PrefersFrontmostWindow = PrefersFrontmostWindowToggle.IsOn,
                Behavior = FreeRoamingAnimationEditor.Settings,
            };
            FreeRoamingMovementSettings avoidingIdleRoaming =
                current.CursorAvoiding.IdleFreeRoaming with
                {
                    Speed = selectedMode == PetMovementMode.CursorAvoiding
                        ? sharedSpeed
                        : current.CursorAvoiding.IdleFreeRoaming.Speed,
                    DwellMilliseconds = dwellMilliseconds,
                    RandomizesDwell = RandomizesDwellToggle.IsOn,
                    DwellMinimumMilliseconds = minimumDwellMilliseconds,
                    PrefersFrontmostWindow = PrefersFrontmostWindowToggle.IsOn,
                    Behavior = FreeRoamingAnimationEditor.Settings,
                };
            CursorAvoidingMovementSettings avoiding = current.CursorAvoiding with
            {
                IdleBehavior = AvoidingIdleBehaviorComboBox.SelectedIndex == 1
                    ? CursorAvoidingIdleBehavior.FreeRoaming
                    : CursorAvoidingIdleBehavior.Stationary,
                DetectionDistance = RequiredFiniteValue(
                    AvoidingDetectionNumberBox, 32, 1_024, "도망 감지 거리"),
                Speed = RequiredFiniteValue(
                    AvoidingSpeedNumberBox, 20, 1_000, "도망 속도"),
                StopRadius = selectedMode == PetMovementMode.CursorAvoiding
                    ? sharedStopRadius
                    : current.CursorAvoiding.StopRadius,
                Behavior = CursorAvoidingAnimationEditor.Settings,
                IdleFreeRoaming = avoidingIdleRoaming,
            };
            var movement = current with
            {
                Mode = selectedMode,
                CursorFollowingSettings = following,
                FreeRoamingSettings = roaming,
                CursorAvoidingSettings = avoiding,
            };

            MovementBoundaryMode boundaryMode = MovementBoundaryModeComboBox.SelectedIndex switch
            {
                1 => MovementBoundaryMode.SelectedDisplay,
                2 => MovementBoundaryMode.CustomArea,
                _ => MovementBoundaryMode.AllDisplays,
            };
            string? screenIdentifier = boundaryMode == MovementBoundaryMode.AllDisplays
                ? null
                : (MovementScreenComboBox.SelectedItem as MonitorOptionItem)?.Identifier
                    ?? throw new InvalidOperationException("이동할 화면을 선택해 주세요.");
            NormalizedMovementRect? normalized = boundaryMode == MovementBoundaryMode.CustomArea
                ? RequiredMovementArea()
                : null;
            var boundary = new MovementBoundarySettings(
                boundaryMode,
                screenIdentifier,
                normalized);

            app.SaveBehaviorProfile(profile with
            {
                Movement = movement,
                PettingMotionId = null,
                PettingBehaviorId = SelectedMotionId(PettingMotionComboBox),
            });
            if (boundary != app.CurrentSettings.Overlay.MovementBoundary)
            {
                app.SaveOverlaySettings(app.CurrentSettings.Overlay with
                {
                    MovementBoundary = boundary,
                });
            }
            MovementSettingsInfoBar.IsOpen = false;
        }
        catch (Exception exception)
        {
            ShowMovementError(exception);
        }
        finally
        {
            _isPersistingMovementControls = false;
        }
    }

    private NormalizedMovementRect RequiredMovementArea()
    {
        double x = RequiredFiniteValue(MovementAreaXNumberBox, 0, 99, "왼쪽 여백") / 100;
        double bottom = RequiredFiniteValue(MovementAreaYNumberBox, 0, 99, "아래쪽 여백") / 100;
        double width = RequiredFiniteValue(MovementAreaWidthNumberBox, 1, 100, "영역 너비") / 100;
        double height = RequiredFiniteValue(MovementAreaHeightNumberBox, 1, 100, "영역 높이") / 100;
        double y = 1 - bottom - height;
        var value = new NormalizedMovementRect(x, y, width, height);
        if (!value.IsValid)
        {
            throw new InvalidOperationException("사용자 지정 이동 영역이 모니터 범위를 벗어납니다. 여백과 크기를 조정해 주세요.");
        }
        return value;
    }

    private void ShowMovementError(Exception exception)
    {
        MovementSettingsInfoBar.Severity = InfoBarSeverity.Error;
        MovementSettingsInfoBar.Title = "이동 설정을 저장하지 못했습니다";
        MovementSettingsInfoBar.Message = exception.Message;
        MovementSettingsInfoBar.IsOpen = true;
    }

    private static double RequiredFiniteValue(
        NumberBox numberBox,
        double minimum,
        double maximum,
        string name)
    {
        double value = numberBox.Value;
        if (!double.IsFinite(value) || value < minimum || value > maximum)
        {
            throw new InvalidOperationException(
                $"{name}은(는) {minimum:0.##}에서 {maximum:0.##} 사이여야 합니다.");
        }
        return value;
    }

    private static string? SelectedMotionId(ComboBox comboBox) =>
        (comboBox.SelectedItem as MotionOptionItem)?.Id is { Length: > 0 } id
            ? id
            : null;

    private void ScheduleMovementSave()
    {
        if (_movementSaveTimer is null)
        {
            return;
        }
        _movementSaveTimer.Stop();
        _movementSaveTimer.Start();
    }

    private void FlushMovementSave()
    {
        if (_movementSaveTimer?.IsRunning != true)
        {
            return;
        }
        _movementSaveTimer.Stop();
        PersistMovementSettingsFromControls();
    }

    private DispatcherQueueTimer CreateDisplaySaveTimer()
    {
        DispatcherQueueTimer timer = DispatcherQueue.CreateTimer();
        timer.Interval = TimeSpan.FromMilliseconds(350);
        timer.IsRepeating = false;
        timer.Tick += (_, _) => PersistCurrentDisplayPreview();
        return timer;
    }

    private DispatcherQueueTimer CreateMovementSaveTimer()
    {
        DispatcherQueueTimer timer = DispatcherQueue.CreateTimer();
        timer.Interval = TimeSpan.FromMilliseconds(350);
        timer.IsRepeating = false;
        timer.Tick += (_, _) =>
        {
            timer.Stop();
            if (_isLoaded && !_isRefreshingMovementControls)
            {
                PersistMovementSettingsFromControls();
            }
        };
        return timer;
    }

    private DispatcherQueueTimer CreateSpeechSaveTimer()
    {
        DispatcherQueueTimer timer = DispatcherQueue.CreateTimer();
        timer.Interval = TimeSpan.FromMilliseconds(350);
        timer.IsRepeating = false;
        timer.Tick += (_, _) =>
        {
            if (_isLoaded && !_isRefreshingSpeechControls)
            {
                PersistSpeechSettingsFromControls(showConfirmation: false);
            }
        };
        return timer;
    }

    private DispatcherQueueTimer CreatePetAnimationPreviewTimer()
    {
        DispatcherQueueTimer timer = DispatcherQueue.CreateTimer();
        timer.Interval = TimeSpan.FromMilliseconds(120);
        timer.IsRepeating = false;
        timer.Tick += async (_, _) => await ShowNextPetAnimationPreviewFrameAsync();
        return timer;
    }

    private void ScheduleDisplaySettingsSave()
    {
        _displaySaveTimer?.Stop();
        _displaySaveTimer?.Start();
    }

    private void PersistCurrentDisplayPreview()
    {
        if (!_isLoaded || Application.Current is not App app)
        {
            return;
        }

        try
        {
            app.PersistCurrentSettings();
            DisplaySettingsInfoBar.IsOpen = false;
            RefreshLibraryState();
        }
        catch (Exception exception)
        {
            ShowDisplaySettingsError(exception);
        }
    }

    private void PersistDisplaySettingsFromControls()
    {
        if (Application.Current is not App app)
        {
            return;
        }

        _displaySaveTimer?.Stop();
        try
        {
            app.SaveOverlaySettings(SettingsFromDisplayControls(app.CurrentSettings.Overlay));
            DisplaySettingsInfoBar.IsOpen = false;
        }
        catch (Exception exception)
        {
            ShowDisplaySettingsError(exception);
        }

        RefreshOverlayState();
        RefreshLibraryState();
    }

    private OverlaySettings SettingsFromDisplayControls(OverlaySettings current) =>
        current with
        {
            Width = OverlayWidthSlider.Value,
            ClickThrough = ClickThroughToggle.IsOn,
            Opacity = OverlayOpacitySlider.Value,
            PointerOverlapFadeEnabled = PointerOverlapFadeToggle.IsOn,
            PointerOverlapOpacity = PointerOverlapOpacitySlider.Value,
            PixelArtRendering = PixelArtToggle.IsOn,
        };

    private void UpdateDisplayValueLabels()
    {
        if (OverlayWidthSlider is null || OverlayOpacitySlider is null ||
            PointerOverlapOpacitySlider is null ||
            OverlayWidthValueText is null || OverlayOpacityValueText is null ||
            PointerOverlapOpacityValueText is null)
        {
            return;
        }

        OverlayWidthValueText.Text =
            $"{OverlayWidthSlider.Value / AppSettingsLimits.DefaultOverlayWidth * 100:0}%";
        if (TinyPetInfoBar is not null)
        {
            TinyPetInfoBar.IsOpen = OverlayWidthSlider.Value <
                AppSettingsLimits.DefaultOverlayWidth * 0.25;
        }
        OverlayOpacityValueText.Text = $"{OverlayOpacitySlider.Value:P0}";
        PointerOverlapOpacityValueText.Text =
            $"{PointerOverlapOpacitySlider.Value:P0}";
    }

    private void ShowDisplaySettingsError(Exception exception)
    {
        DisplaySettingsInfoBar.Severity = InfoBarSeverity.Error;
        DisplaySettingsInfoBar.Title = "화면 표시 설정을 저장하지 못했습니다";
        DisplaySettingsInfoBar.Message = exception.Message;
        DisplaySettingsInfoBar.IsOpen = true;
    }

    public sealed record InstalledPetItem(
        string InstallationId,
        string DisplayName,
        string Detail,
        bool CanActivate);

    public sealed record PetAnimationItem(
        string Id,
        string DisplayName,
        string Detail,
        string DefaultBadge);

    public sealed record PetChoiceItem(Guid? InstallationId, string DisplayName);

    public sealed record BehaviorSequenceItem(string Id, string DisplayName);

    public sealed record MotionOptionItem(string Id, string DisplayName);

    public sealed record MonitorOptionItem(string Identifier, string DisplayName);

    public sealed record BehaviorStepEditorItem(
        int Index,
        int DisplayIndex,
        string MotionId,
        string MotionDisplayName,
        int RepeatCount,
        bool CanMoveUp,
        bool CanMoveDown,
        bool CanDelete);

    public sealed record AutomaticRuleEditorItem(Guid Id, string Summary, string Detail);

    public sealed class ActivePetItem : INotifyPropertyChanged
    {
        private string _nickname = string.Empty;
        private string _detail = string.Empty;
        private string _presentationCommand = string.Empty;
        private int _displayOrder;
        private bool _isSelected;
        private BitmapImage? _preview;
        private PetBehaviorKey? _previewPetKey;
        private string? _previewPath;
        private long _previewGeneration;

        public ActivePetItem(Guid instanceId)
        {
            InstanceId = instanceId;
        }

        public event PropertyChangedEventHandler? PropertyChanged;

        public Guid InstanceId { get; }

        public string DisplayName => string.IsNullOrWhiteSpace(Nickname)
            ? "이름 없는 펫"
            : Nickname;

        public string Nickname
        {
            get => _nickname;
            private set => SetProperty(ref _nickname, value);
        }

        public string Detail
        {
            get => _detail;
            private set => SetProperty(ref _detail, value);
        }

        public string PresentationCommand
        {
            get => _presentationCommand;
            private set => SetProperty(ref _presentationCommand, value);
        }

        public int DisplayOrder
        {
            get => _displayOrder;
            private set => SetProperty(ref _displayOrder, value);
        }

        public BitmapImage? Preview
        {
            get => _preview;
            private set => SetProperty(ref _preview, value);
        }

        public Visibility SelectionVisibility => _isSelected
            ? Visibility.Visible
            : Visibility.Collapsed;

        public void Update(
            string nickname,
            string detail,
            string presentationCommand,
            int displayOrder,
            bool isSelected)
        {
            Nickname = nickname;
            Detail = detail;
            PresentationCommand = presentationCommand;
            DisplayOrder = displayOrder;
            if (_isSelected != isSelected)
            {
                _isSelected = isSelected;
                PropertyChanged?.Invoke(
                    this,
                    new PropertyChangedEventArgs(nameof(SelectionVisibility)));
            }
        }

        public bool BeginPreviewLoad(
            PetBehaviorKey petKey,
            string? previewPath,
            out long generation)
        {
            if (_previewPetKey == petKey &&
                string.Equals(_previewPath, previewPath, StringComparison.OrdinalIgnoreCase))
            {
                generation = _previewGeneration;
                return false;
            }

            _previewPetKey = petKey;
            _previewPath = previewPath;
            Preview = null;
            generation = ++_previewGeneration;
            return true;
        }

        public bool NeedsPreview(PetBehaviorKey petKey) => _previewPetKey != petKey;

        public void CompletePreviewLoad(long generation, BitmapImage? preview)
        {
            if (generation == _previewGeneration)
            {
                Preview = preview;
            }
        }

        private void SetProperty<T>(ref T field, T value, [CallerMemberName] string? name = null)
        {
            if (EqualityComparer<T>.Default.Equals(field, value))
            {
                return;
            }

            field = value;
            PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
            if (name == nameof(Nickname))
            {
                PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(DisplayName)));
            }
        }
    }

    public sealed record SpeechPhraseEditorItem(Guid Id, string Text, string Detail);

    public sealed record RulePriorityKindItem(
        AutomaticRuleKind Kind,
        string DisplayName,
        string Subtitle,
        string Rank);

    private readonly record struct ExportReviewOptions(
        bool IncludesRecommendedProfile,
        bool IncludesApplicationRules,
        bool IncludesBehavior,
        bool IncludesMovement,
        bool IncludesPetting,
        bool IncludesSpeech,
        bool IncludesDisplay);

    public sealed class ApplicationPickerItem : INotifyPropertyChanged
    {
        private BitmapImage? _icon;

        public ApplicationPickerItem(WindowsApplicationChoice choice)
        {
            Choice = choice;
        }

        public WindowsApplicationChoice Choice { get; }

        public string Identifier => Choice.Identifier;

        public string DisplayName => Choice.DisplayName;

        public string? ExecutablePath => Choice.ExecutablePath;

        public BitmapImage? Icon
        {
            get => _icon;
            set
            {
                if (ReferenceEquals(_icon, value))
                {
                    return;
                }
                _icon = value;
                OnPropertyChanged();
            }
        }

        public event PropertyChangedEventHandler? PropertyChanged;

        private void OnPropertyChanged([CallerMemberName] string? propertyName = null) =>
            PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
    }
}
