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
using MonglePet.Windows.Overlay;
using Windows.Storage;
using Windows.Storage.Pickers;
using Windows.UI;
using Windows.Graphics.Imaging;

namespace MonglePet.Windows;

public sealed partial class MainPage : Page
{
    private readonly ObservableCollection<InstalledPetItem> _installedPets = [];
    private readonly ObservableCollection<PetChoiceItem> _petChoices = [];
    private readonly ObservableCollection<PetAnimationItem> _petAnimations = [];
    private readonly ObservableCollection<BehaviorSequenceItem> _behaviorSequences = [];
    private readonly ObservableCollection<MotionOptionItem> _motionOptions = [];
    private readonly ObservableCollection<MotionOptionItem> _movementMotionOptions = [];
    private readonly ObservableCollection<MonitorOptionItem> _movementScreens = [];
    private readonly ObservableCollection<BehaviorStepEditorItem> _behaviorSteps = [];
    private readonly ObservableCollection<AutomaticRuleEditorItem> _automaticRules = [];
    private readonly ObservableCollection<SpeechPhraseEditorItem> _behaviorSpeechPhrases = [];
    private readonly ObservableCollection<SpeechPhraseEditorItem> _periodicSpeechPhrases = [];
    private readonly WindowsLoginLaunchService _loginLaunchService = new();
    private bool _isLoaded;
    private bool _isRefreshingDisplayControls;
    private bool _isRefreshingBehaviorControls;
    private bool _isRefreshingBehaviorEditor;
    private bool _isRefreshingMovementControls;
    private bool _isRefreshingSpeechControls;
    private bool _isRefreshingPetChoice;
    private bool _isEditingSpeechPhrase;
    private bool _isRefreshingLoginLaunch;
    private string? _selectedRoutineId;
    private Guid? _selectedRuleId;
    private Guid? _selectedSpeechPhraseId;
    private WindowsApplicationChoice? _selectedApplicationChoice;
    private PetOverlayWindow? _subscribedOverlay;
    private DispatcherQueueTimer? _displaySaveTimer;
    private DispatcherQueueTimer? _speechSaveTimer;
    private DispatcherQueueTimer? _petAnimationPreviewTimer;
    private long _petPreviewGeneration;
    private int _petAnimationPreviewFrameIndex;
    private bool _isLoadingPetAnimationPreviewFrame;
    private LoadedPetPackage? _petAnimationPreviewPackage;
    private PetPackageMotion? _petAnimationPreviewMotion;

    public MainPage()
    {
        InitializeComponent();
        SpeechPeriodicIntervalNumberBox.AddHandler(
            UIElement.KeyUpEvent,
            new Microsoft.UI.Xaml.Input.KeyEventHandler(
                SpeechPeriodicIntervalNumberBox_KeyUp),
            handledEventsToo: true);
        AppVersionText.Text = ApplicationVersionText();
        ShowSettingsSection("pet");
        InstalledPetsList.ItemsSource = _installedPets;
        CurrentPetComboBox.ItemsSource = _petChoices;
        PetAnimationsList.ItemsSource = _petAnimations;
        ManualSequenceComboBox.ItemsSource = _behaviorSequences;
        RoutineEditorComboBox.ItemsSource = _behaviorSequences;
        RuleTargetSequenceComboBox.ItemsSource = _behaviorSequences;
        PettingMotionComboBox.ItemsSource = _movementMotionOptions;
        MovementScreenComboBox.ItemsSource = _movementScreens;
        BehaviorStepsList.ItemsSource = _behaviorSteps;
        AutomaticRulesList.ItemsSource = _automaticRules;
        BehaviorSpeechPhrasesList.ItemsSource = _behaviorSpeechPhrases;
        PeriodicSpeechPhrasesList.ItemsSource = _periodicSpeechPhrases;
        SpeechSequenceComboBox.ItemsSource = _behaviorSequences;
        Loaded += (_, _) =>
        {
            _isLoaded = true;
            _displaySaveTimer ??= CreateDisplaySaveTimer();
            _speechSaveTimer ??= CreateSpeechSaveTimer();
            _petAnimationPreviewTimer ??= CreatePetAnimationPreviewTimer();
            if (Application.Current is App app)
            {
                app.InitializationCompleted += App_InitializationCompleted;
                app.BehaviorStateChanged += App_BehaviorStateChanged;
                app.MovementStateChanged += App_MovementStateChanged;
                app.SettingsStateChanged += App_SettingsStateChanged;
            }
            RefreshOverlayState();
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
        _isLoaded = false;
        _displaySaveTimer?.Stop();
        _speechSaveTimer?.Stop();
        _petAnimationPreviewTimer?.Stop();
        if (Application.Current is App app)
        {
            app.InitializationCompleted -= App_InitializationCompleted;
            app.BehaviorStateChanged -= App_BehaviorStateChanged;
            app.MovementStateChanged -= App_MovementStateChanged;
            app.SettingsStateChanged -= App_SettingsStateChanged;
        }
        if (_subscribedOverlay is not null)
        {
            _subscribedOverlay.StateChanged -= Overlay_StateChanged;
            _subscribedOverlay = null;
        }
    }

    private PetOverlayWindow? Overlay => (Application.Current as App)?.Overlay;

    private void SettingsNavigationView_SelectionChanged(
        NavigationView sender,
        NavigationViewSelectionChangedEventArgs args)
    {
        string section = (args.SelectedItemContainer as NavigationViewItem)?.Tag?.ToString()
            ?? "pet";
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

        bool isPet = section == "pet";
        bool isGeneral = section == "general";
        bool isMovement = section == "movement";
        bool isRoutines = section == "routines";
        bool isSpeech = section == "speech";
        bool isAutomaticRules = section == "automaticRules";

        OverlayInfoBar.Visibility = isPet ? Visibility.Visible : Visibility.Collapsed;
        PetLibraryCard.Visibility = isPet ? Visibility.Visible : Visibility.Collapsed;
        GeneralSettingsCard.Visibility = isGeneral ? Visibility.Visible : Visibility.Collapsed;
        OverlaySettingsCard.Visibility = isGeneral ? Visibility.Visible : Visibility.Collapsed;
        MovementSettingsCard.Visibility = isMovement ? Visibility.Visible : Visibility.Collapsed;
        SpeechSettingsCard.Visibility = isSpeech ? Visibility.Visible : Visibility.Collapsed;

        BehaviorSettingsCard.Visibility = isRoutines || isAutomaticRules
            ? Visibility.Visible
            : Visibility.Collapsed;
        RoutineEditorCard.Visibility = isRoutines ? Visibility.Visible : Visibility.Collapsed;
        AutomaticRulesCard.Visibility = isAutomaticRules ? Visibility.Visible : Visibility.Collapsed;

        (SettingsSectionTitle.Text, SettingsSectionDescription.Text) = section switch
        {
            "general" => (
                "일반",
                "펫 표시, 행동 모드, 화면 표시와 로그인 자동 실행을 설정합니다."),
            "movement" => (
                "이동",
                "현재 펫의 이동 방식, 이동 범위와 쓰다듬기 동작을 설정합니다."),
            "routines" => (
                "행동 루틴",
                "애니메이션 단계를 조합해 현재 펫이 반복할 행동 루틴을 편집합니다."),
            "speech" => (
                "말풍선",
                "행동 대사와 주기 대사, 말풍선 모양 및 표시 위치를 설정합니다."),
            "automaticRules" => (
                "자동 규칙",
                "사용 중인 앱과 입력 없음 시간에 따라 실행할 행동 루틴을 정합니다."),
            _ => (
                "펫",
                "현재 펫을 선택하고 .monglepet 패키지를 가져오거나 내보냅니다."),
        };
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
        if (Application.Current is not App app || Overlay is not { } overlay)
        {
            RefreshOverlayState();
            return;
        }

        try
        {
            app.SetUserPresentation(
                overlay.IsVisible
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
            RefreshOverlayStatusText();
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
        PersistMovementSettingsFromControls();
    }

    private void MovementAnimationEditor_SettingsChanged(object? sender, EventArgs e)
    {
        if (!_isLoaded || _isRefreshingMovementControls)
        {
            return;
        }
        PersistMovementSettingsFromControls();
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

        bool? appliesRecommendedProfile = await ShowImportReview(review);
        if (appliesRecommendedProfile is null)
        {
            return;
        }

        try
        {
            InstalledPetPackage installed = app.ImportReviewedPackage(
                review,
                appliesRecommendedProfile.Value);
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
                appliesRecommendedProfile.Value);
        }
        catch (Exception exception)
        {
            ShowLibraryMessage(InfoBarSeverity.Error, "가져오기 실패", exception.Message);
        }

        RefreshLibraryState();
        RefreshOverlayState();
        RefreshBehaviorState();
    }

    private async Task ResolveDuplicateImport(
        App app,
        PetPackageImportReview review,
        Guid existingInstallationId,
        bool appliesRecommendedProfileToSeparateInstall)
    {
        var replaceProfileCheckBox = new CheckBox
        {
            Content = "교체하면서 권장 설정으로 기존 로컬 설정도 바꾸기",
            IsEnabled = review.CanApplyRecommendedProfile,
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
                    replaceProfileCheckBox.IsChecked == true,
                    PetPackageInstallMode.Replace,
                    existingInstallationId),
                ContentDialogResult.Secondary => app.ImportReviewedPackage(
                    review,
                    appliesRecommendedProfileToSeparateInstall,
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
            ShowLibraryMessage(InfoBarSeverity.Error, "가져오기 실패", exception.Message);
        }
    }

    private async Task<bool?> ShowImportReview(PetPackageImportReview review)
    {
        var content = new StackPanel { Spacing = 10, MaxWidth = 520 };
        content.Children.Add(new TextBlock
        {
            Text = $"{review.Manifest.DisplayName}  v{review.Manifest.Version}\n" +
                   $"제작자: {review.Manifest.Author}\n" +
                   $"모션: {review.Manifest.Motions.Count}개",
            TextWrapping = TextWrapping.Wrap,
        });
        var apply = new CheckBox
        {
            Content = "권장 펫 설정도 적용",
            IsEnabled = review.CanApplyRecommendedProfile,
            IsChecked = false,
        };
        if (review.RecommendedProfile is { } profile)
        {
            content.Children.Add(new TextBlock
            {
                Text = RecommendedProfileSummary(profile),
                TextWrapping = TextWrapping.Wrap,
            });
            content.Children.Add(apply);
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
        return await dialog.ShowAsync() == ContentDialogResult.Primary
            ? apply.IsChecked == true
            : null;
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
                options.Value.IncludesApplicationRules);
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
            IsChecked = false,
        };
        var includeApplicationRules = new CheckBox
        {
            Content = "앱별 자동 규칙도 포함",
            IsChecked = false,
            IsEnabled = false,
            Visibility = hasApplicationRules ? Visibility.Visible : Visibility.Collapsed,
        };
        includeProfile.Checked += (_, _) => includeApplicationRules.IsEnabled = hasApplicationRules;
        includeProfile.Unchecked += (_, _) =>
        {
            includeApplicationRules.IsChecked = false;
            includeApplicationRules.IsEnabled = false;
        };
        var rights = new CheckBox
        {
            Content = "이 이미지 자산을 공유할 권한이 있음을 확인합니다.",
            IsChecked = false,
        };
        var content = new StackPanel { Spacing = 10, MaxWidth = 520 };
        content.Children.Add(new TextBlock
        {
            Text = "manifest, 미리보기와 참조 atlas만 새 패키지에 포함합니다. 로컬 편집 marker와 앱 설정 파일은 제외됩니다.",
            TextWrapping = TextWrapping.Wrap,
        });
        content.Children.Add(includeProfile);
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
            includeProfile.IsChecked == true && includeApplicationRules.IsChecked == true);
    }

    private static string RecommendedProfileSummary(BehaviorProfile profile)
    {
        int stepCount = profile.Sequences.Sum(sequence => sequence.Steps.Count);
        int applicationRules = profile.AutomaticRules.Count(
            rule => rule.Condition is RuleCondition.Application);
        int periodicPhrases = profile.Speech.Phrases.Count(
            phrase => phrase.Trigger is PetSpeechTrigger.Periodic);
        return $"권장 설정: {profile.Mode} · 루틴 {profile.Sequences.Count}개/단계 {stepCount}개 · " +
               $"자동 규칙 {profile.AutomaticRules.Count}개(앱 {applicationRules}개) · 이동 {profile.Movement.Mode} · " +
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
                app.InstallOrActivateBundledSample());
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

        var editor = new PetAnimationEditorControl();
        var dialog = new ContentDialog
        {
            XamlRoot = XamlRoot,
            Title = "새 펫 만들기",
            Content = editor,
            PrimaryButtonText = "펫 만들기",
            CloseButtonText = "취소",
            DefaultButton = ContentDialogButton.Primary,
        };
        if (await dialog.ShowAsync() != ContentDialogResult.Primary)
        {
            return;
        }

        await RunPetEditAsync("새 펫 만들기", async () =>
        {
            InstalledPetPackage installed = await app.PetEditor.CreatePetAsync(editor.CreatePetRequest());
            app.ActivateInstallation(installed.InstallationId);
            return $"'{installed.Package.Manifest.DisplayName}' 펫을 만들었습니다.";
        });
    }

    private async void AddPetAnimationButton_Click(object sender, RoutedEventArgs e)
    {
        if (!TryGetActiveInstalledPet(out App app, out InstalledPetPackage installed) ||
            !app.PetEditor.IsEditable(installed))
        {
            return;
        }

        var editor = new PetAnimationEditorControl();
        editor.ConfigureForAnimation(installed.Package, null);
        var dialog = new ContentDialog
        {
            XamlRoot = XamlRoot,
            Title = "펫 애니메이션 추가",
            Content = editor,
            PrimaryButtonText = "추가",
            CloseButtonText = "취소",
            DefaultButton = ContentDialogButton.Primary,
        };
        if (await dialog.ShowAsync() != ContentDialogResult.Primary)
        {
            return;
        }

        await RunPetEditAsync("애니메이션 추가", async () =>
        {
            InstalledPetPackage updated = await app.PetEditor.AddAnimationAsync(
                installed,
                editor.CreateAnimationRequest());
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

        var editor = new PetAnimationEditorControl();
        editor.ConfigureForAnimation(installed.Package, motion);
        var dialog = new ContentDialog
        {
            XamlRoot = XamlRoot,
            Title = "펫 애니메이션 수정",
            Content = editor,
            PrimaryButtonText = "저장",
            CloseButtonText = "취소",
            DefaultButton = ContentDialogButton.Primary,
        };
        if (await dialog.ShowAsync() != ContentDialogResult.Primary)
        {
            return;
        }

        UserPetAnimationUpdateRequest request = editor.CreateAnimationUpdateRequest(motion.Id);
        await RunPetEditAsync("애니메이션 수정", async () =>
        {
            InstalledPetPackage updated = await app.PetEditor.UpdateAnimationAsync(
                installed,
                request);
            app.ReplaceActiveMotionReferences(motion.Id, request.AnimationName);
            app.ActivateInstallation(updated.InstallationId);
            return $"'{motion.Id}' 애니메이션을 수정했습니다.";
        });
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
        if (!TryGetActiveInstalledPet(out App app, out InstalledPetPackage installed) ||
            app.PetEditor.IsEditable(installed))
        {
            return;
        }

        var name = new TextBox
        {
            Header = "새 펫 이름",
            Text = $"{installed.Package.Manifest.DisplayName} 사본",
            Width = 440,
        };
        var dialog = new ContentDialog
        {
            XamlRoot = XamlRoot,
            Title = "편집 가능한 사본 만들기",
            Content = name,
            PrimaryButtonText = "사본 만들기",
            CloseButtonText = "취소",
            DefaultButton = ContentDialogButton.Primary,
        };
        if (await dialog.ShowAsync() != ContentDialogResult.Primary)
        {
            return;
        }

        await RunPetEditAsync("편집 가능한 사본", () =>
        {
            InstalledPetPackage copied = app.PetEditor.CreateEditableCopy(installed, name.Text);
            app.ActivateInstallation(copied.InstallationId);
            return Task.FromResult($"'{copied.Package.Manifest.DisplayName}' 사본을 만들었습니다.");
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
        App? app = Application.Current as App;
        if (app?.Overlay is not { } overlay)
        {
            OverlayInfoBar.Severity = InfoBarSeverity.Error;
            OverlayInfoBar.Title = "오버레이 초기화 실패";
            OverlayInfoBar.Message = app?.OverlayInitializationError ?? "오버레이를 사용할 수 없습니다.";
            VisibilityButton.IsEnabled = false;
            ClickThroughToggle.IsEnabled = false;
            OverlayWidthSlider.IsEnabled = false;
            OverlayOpacitySlider.IsEnabled = false;
            PointerOverlapFadeToggle.IsEnabled = false;
            PointerOverlapOpacitySlider.IsEnabled = false;
            PixelArtToggle.IsEnabled = false;
            OverlayStatusText.Text = "네이티브 창이 생성되지 않았습니다.";
            return;
        }

        if (!ReferenceEquals(_subscribedOverlay, overlay))
        {
            if (_subscribedOverlay is not null)
            {
                _subscribedOverlay.StateChanged -= Overlay_StateChanged;
            }

            _subscribedOverlay = overlay;
            _subscribedOverlay.StateChanged += Overlay_StateChanged;
        }

        RefreshOverlayPlaybackInfo();
        VisibilityButton.Content = overlay.IsVisible ? "펫 재우기" : "펫 깨우기";
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
        RefreshOverlayStatusText();
    }

    private void Overlay_StateChanged(object? sender, EventArgs e) =>
        DispatcherQueue.TryEnqueue(() =>
        {
            if (!_isLoaded)
            {
                return;
            }
            RefreshOverlayPlaybackInfo();
            RefreshOverlayStatusText();
        });

    private void App_InitializationCompleted(object? sender, EventArgs e) =>
        DispatcherQueue.TryEnqueue(() =>
        {
            if (!_isLoaded)
            {
                return;
            }
            RefreshOverlayState();
            RefreshLibraryState();
            RefreshBehaviorState();
        });

    private void App_BehaviorStateChanged(object? sender, EventArgs e) =>
        DispatcherQueue.TryEnqueue(() =>
        {
            if (_isLoaded)
            {
                RefreshBehaviorRuntimeStatus();
                RefreshSpeechRuntimeStatus();
            }
        });

    private void App_MovementStateChanged(object? sender, EventArgs e) =>
        DispatcherQueue.TryEnqueue(() =>
        {
            if (_isLoaded)
            {
                RefreshMovementRuntimeStatus();
            }
        });

    private void App_SettingsStateChanged(object? sender, EventArgs e) =>
        DispatcherQueue.TryEnqueue(() =>
        {
            if (!_isLoaded)
            {
                return;
            }
            RefreshOverlayState();
            RefreshLibraryState();
            RefreshBehaviorState();
        });

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
            InstallSampleButton.IsEnabled = canManage;
            InstalledPetsList.IsEnabled = canManage;
            CreatePetButton.IsEnabled = canManage;
            EditPetDetailsButton.Visibility = isEditable ? Visibility.Visible : Visibility.Collapsed;
            EditPetDetailsButton.IsEnabled = canManage && isEditable;
            CreateEditablePetCopyButton.Visibility = isInstalled && !isEditable
                ? Visibility.Visible
                : Visibility.Collapsed;
            CreateEditablePetCopyButton.IsEnabled = canManage && isInstalled && !isEditable;
            DeleteCurrentPetButton.Visibility = isInstalled ? Visibility.Visible : Visibility.Collapsed;
            DeleteCurrentPetButton.IsEnabled = canManage && isInstalled;
            AnimationEditingCaptionText.Text = isEditable
                ? "애니메이션을 추가하거나 프레임 순서·간격·반복 여부를 수정할 수 있습니다."
                : isInstalled
                    ? "가져온 패키지는 원본 보존을 위해 읽기 전용입니다. 편집하려면 사본을 만들어 주세요."
                    : "기본 몽글이는 읽기 전용입니다. 새 펫을 만들거나 패키지를 가져와 주세요.";
            PetPackageCaptionText.Text = isInstalled
                ? ".monglepet 형식으로 펫 정보와 애니메이션을 가져오거나 공유합니다."
                : "내장 몽글이는 패키지로 내보낼 수 없습니다.";
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
        DeletePetAnimationButton.Visibility = isEditable ? Visibility.Visible : Visibility.Collapsed;
        AddPetAnimationButton.IsEnabled = canEdit;
        EditPetAnimationButton.IsEnabled = canEdit && selected is not null;
        DeletePetAnimationButton.IsEnabled = canEdit &&
            selected is not null &&
            _petAnimations.Count > 1 &&
            string.IsNullOrEmpty(selected.DefaultBadge);
    }

    private void RefreshCurrentPetSummary(LoadedPetPackage? package)
    {
        long generation = ++_petPreviewGeneration;
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
        _petAnimationPreviewTimer?.Stop();
        _petAnimationPreviewPackage = package;
        _petAnimationPreviewMotion = motion;
        _petAnimationPreviewFrameIndex = 0;
        _ = ShowNextPetAnimationPreviewFrameAsync();
    }

    private async Task ShowNextPetAnimationPreviewFrameAsync()
    {
        if (_isLoadingPetAnimationPreviewFrame || !_isLoaded ||
            _petAnimationPreviewPackage is not { } package ||
            _petAnimationPreviewMotion is not { Frames.Count: > 0 } motion)
        {
            return;
        }
        int frameIndex = Math.Clamp(_petAnimationPreviewFrameIndex, 0, motion.Frames.Count - 1);
        PetPackageFrame frame = motion.Frames[frameIndex];
        LoadedPetAtlas atlas = package.Atlases[motion.Atlas];
        _isLoadingPetAnimationPreviewFrame = true;
        try
        {
            StorageFile file = await StorageFile.GetFileFromPathAsync(atlas.FilePath);
            using global::Windows.Storage.Streams.IRandomAccessStream stream =
                await file.OpenAsync(FileAccessMode.Read);
            BitmapDecoder decoder = await BitmapDecoder.CreateAsync(stream);
            var transform = new BitmapTransform
            {
                Bounds = new BitmapBounds
                {
                    X = (uint)frame.X,
                    Y = (uint)frame.Y,
                    Width = (uint)frame.Width,
                    Height = (uint)frame.Height,
                },
            };
            using SoftwareBitmap bitmap = await decoder.GetSoftwareBitmapAsync(
                BitmapPixelFormat.Bgra8,
                BitmapAlphaMode.Premultiplied,
                transform,
                ExifOrientationMode.IgnoreExifOrientation,
                ColorManagementMode.DoNotColorManage);
            var source = new SoftwareBitmapSource();
            await source.SetBitmapAsync(bitmap);
            if (!ReferenceEquals(package, _petAnimationPreviewPackage) ||
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
            _petAnimationPreviewTimer?.Stop();
        }
        finally
        {
            _isLoadingPetAnimationPreviewFrame = false;
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
                    string.Equals(
                        sequence.Id,
                        BehaviorMotionReferences.DefaultSequence,
                        StringComparison.Ordinal)
                        ? "기본"
                        : sequence.Id));
            }

            BehaviorModeComboBox.SelectedIndex = profile.Mode == BehaviorMode.Manual ? 1 : 0;
            string? selectedId = profile.ManualSequenceId ?? profile.Sequences.FirstOrDefault()?.Id;
            ManualSequenceComboBox.SelectedItem = _behaviorSequences.FirstOrDefault(item =>
                string.Equals(item.Id, selectedId, StringComparison.Ordinal));
            BehaviorModeComboBox.IsEnabled = canEdit;
            ManualSequenceComboBox.IsEnabled =
                canEdit && profile.Mode == BehaviorMode.Manual && _behaviorSequences.Count > 0;
            BehaviorDescriptionText.Text = profile.Mode == BehaviorMode.Manual
                ? "수동 모드는 전면 앱과 입력 없음 상태를 무시하고 선택한 루틴을 반복합니다."
                : "자동 모드는 Windows 전면 앱·입력 없음 규칙을 우선순위 순으로 평가하고 일치하지 않으면 기본 루틴을 재생합니다.";
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

        RefreshBehaviorRuntimeStatus();
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
            foreach (string motionId in app.ActiveMotionIds)
            {
                _movementMotionOptions.Add(new MotionOptionItem(motionId, motionId));
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
            MovementSpeedNumberBox.Value = movement.Speed;
            MovementStopRadiusNumberBox.Value = movement.StopRadius;
            CursorDistanceNumberBox.Value = movement.CursorDistance;
            FreeRoamingDwellNumberBox.Value =
                movement.FreeRoamingDwellMilliseconds / 1000d;
            PrefersFrontmostWindowToggle.IsOn = movement.PrefersFrontmostWindow;
            AvoidingDetectionNumberBox.Value = movement.CursorAvoidingDetectionDistance;
            AvoidingSpeedNumberBox.Value = movement.CursorAvoidingSpeed;
            AvoidingIdleBehaviorComboBox.SelectedIndex =
                movement.CursorAvoidingIdleBehavior == CursorAvoidingIdleBehavior.FreeRoaming
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
                movement.CursorFollowingAnimation,
                app.ActiveMotionIds,
                canEdit);
            FreeRoamingAnimationEditor.SetState(
                movement.Mode == PetMovementMode.CursorAvoiding
                    ? "평상시 자유 이동 애니메이션"
                    : "이동 애니메이션",
                movement.FreeRoamingAnimation,
                app.ActiveMotionIds,
                canEdit);
            CursorAvoidingAnimationEditor.SetState(
                "도망가기 애니메이션",
                movement.CursorAvoidingAnimation,
                app.ActiveMotionIds,
                canEdit);
            SelectMotion(PettingMotionComboBox, profile.PettingMotionId);

            MovementModeComboBox.IsEnabled = canEdit;
            FixedMovementModeRadio.IsEnabled = canEdit;
            CursorFollowingMovementModeRadio.IsEnabled = canEdit;
            FreeRoamingMovementModeRadio.IsEnabled = canEdit;
            CursorAvoidingMovementModeRadio.IsEnabled = canEdit;
            MovementSpeedNumberBox.IsEnabled = canEdit;
            MovementStopRadiusNumberBox.IsEnabled = canEdit;
            CursorDistanceNumberBox.IsEnabled = canEdit;
            FreeRoamingDwellNumberBox.IsEnabled = canEdit;
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
        RefreshMovementRuntimeStatus();
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
        CursorAvoidingOptionsPanel.Visibility = isAvoiding ? Visibility.Visible : Visibility.Collapsed;

        bool clickThrough = Application.Current is App app && app.CurrentSettings.Overlay.ClickThrough;
        FixedMovementHelpText.Text = clickThrough
            ? "클릭 통과가 켜져 있어 펫을 드래그할 수 없습니다. 일반 탭에서 클릭 통과를 끄면 위치를 옮길 수 있습니다."
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
                    step.RepeatCount,
                    _motionOptions,
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
        NewSequenceNameTextBox.IsEnabled = canEdit;
        AddSequenceButton.IsEnabled = canEdit;
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
        _automaticRules.Clear();
        foreach (AutomaticRule rule in profile.AutomaticRules)
        {
            _automaticRules.Add(new AutomaticRuleEditorItem(
                rule.Id,
                RuleSummary(rule),
                $"{(rule.IsEnabled ? "사용" : "중지")} · 우선순위 {rule.Priority} · {rule.SequenceId}"));
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
        NewIdleRuleButton.IsEnabled = canEdit;
        AddRuleButton.IsEnabled = canEdit;
        SaveRuleButton.IsEnabled = canEdit && selected is not null;
        DeleteRuleButton.IsEnabled = canEdit && selected is not null;
        RuleEnabledToggle.IsEnabled = canEdit;
        RulePriorityNumberBox.IsEnabled = canEdit;
        RuleConditionTypeComboBox.IsEnabled = canEdit;
        RuleApplicationIdTextBox.IsEnabled = canEdit;
        ChooseApplicationButton.IsEnabled = canEdit;
        ChooseExecutableButton.IsEnabled = canEdit;
        UseCurrentApplicationButton.IsEnabled = canEdit;
        RuleIdleMinutesNumberBox.IsEnabled = canEdit;
        RuleTargetSequenceComboBox.IsEnabled = canEdit && profile.Sequences.Count > 0;
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
                    SpeechPhraseDetail(phrase));
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
        RefreshSpeechRuntimeStatus();
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

    private static string SpeechPhraseDetail(PetSpeechPhrase phrase)
    {
        string trigger = phrase.Trigger switch
        {
            PetSpeechTrigger.Sequence sequence => $"행동 · {sequence.SequenceId}",
            _ => "주기",
        };
        string display = phrase.DisplayMode == PetSpeechDisplayMode.UntilNextPhrase
            ? "다음 대사까지 유지"
            : $"{phrase.DisplayDurationMilliseconds / 1_000d:0.#}초 표시";
        return $"{trigger} · {display}";
    }

    private void RefreshSpeechRuntimeStatus()
    {
        if (Application.Current is App app && SpeechRuntimeStatusText is not null)
        {
            SpeechRuntimeStatusText.Text = $"실행 상태: {app.SpeechStatus}";
        }
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
            ? idle.Milliseconds / 60_000d
            : 1;
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

    private void AddSequenceButton_Click(object sender, RoutedEventArgs e)
    {
        string requestedId = NewSequenceNameTextBox.Text;
        ApplyBehaviorProfileEdit(
            profile => BehaviorProfileEditor.AddSequence(profile, requestedId),
            onSuccess: profile =>
            {
                _selectedRoutineId = requestedId.Trim();
                NewSequenceNameTextBox.Text = string.Empty;
            });
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

    private void StepMotionComboBox_SelectionChanged(
        object sender,
        SelectionChangedEventArgs e)
    {
        if (!_isLoaded || _isRefreshingBehaviorEditor ||
            _selectedRoutineId is not { } sequenceId ||
            sender is not ComboBox { Tag: int index, SelectedItem: MotionOptionItem motion })
        {
            return;
        }
        ApplyBehaviorProfileEdit(profile =>
        {
            BehaviorStep current = RequiredStep(profile, sequenceId, index);
            return BehaviorProfileEditor.ReplaceStep(
                profile,
                sequenceId,
                index,
                current with { MotionId = motion.Id });
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

    private void NewIdleRuleButton_Click(object sender, RoutedEventArgs e) =>
        PrepareNewRule(conditionIndex: 1);

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
            Title = "자동 규칙 대상 앱 선택",
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
                        RequiredIdleMinutes(),
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
                ? new RuleCondition.IdleAtLeast(checked((long)RequiredIdleMinutes() * 60_000))
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
            app.SaveBehaviorProfile(updated);
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
            RefreshLibraryState();
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
        ?? throw new InvalidOperationException("자동 규칙이 실행할 루틴을 선택해 주세요.");

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

    private int RequiredIdleMinutes()
    {
        double value = RuleIdleMinutesNumberBox.Value;
        if (!double.IsFinite(value) || Math.Truncate(value) != value || value is < 1 or > 1_440)
        {
            throw new InvalidOperationException("입력 없음 시간은 1분에서 1,440분 사이의 정수여야 합니다.");
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
        RuleCondition.IdleAtLeast idle => $"입력 없음 · {idle.Milliseconds / 60_000d:0.##}분",
        RuleCondition.Unsupported unsupported => $"지원하지 않는 조건 · {unsupported.Type}",
        _ => "알 수 없는 조건",
    };

    private void PersistBehaviorSelectionFromControls()
    {
        if (Application.Current is not App app)
        {
            return;
        }

        BehaviorMode mode = BehaviorModeComboBox.SelectedIndex == 1
            ? BehaviorMode.Manual
            : BehaviorMode.Automatic;
        string? sequenceId =
            (ManualSequenceComboBox.SelectedItem as BehaviorSequenceItem)?.Id;
        try
        {
            app.SaveBehaviorSelection(mode, sequenceId);
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
        RefreshLibraryState();
    }

    private void RefreshBehaviorRuntimeStatus()
    {
        if (Application.Current is not App app || BehaviorStatusText is null)
        {
            return;
        }

        BehaviorStatusText.Text = $"실행 상태: {app.BehaviorStatus}";
        ActivityStatusText.Text = $"Windows 활동: {app.ActivityStatus}";
    }

    private void PersistMovementSettingsFromControls()
    {
        if (Application.Current is not App app)
        {
            return;
        }

        try
        {
            BehaviorProfile profile = app.ActiveBehaviorProfile;
            PetMovementSettings current = profile.Movement;
            var movement = current with
            {
                Mode = MovementModeComboBox.SelectedIndex switch
                {
                    1 => PetMovementMode.CursorFollowing,
                    2 => PetMovementMode.FreeRoaming,
                    3 => PetMovementMode.CursorAvoiding,
                    _ => PetMovementMode.Fixed,
                },
                Speed = RequiredFiniteValue(MovementSpeedNumberBox, 20, 1_000, "이동 속도"),
                StopRadius = RequiredFiniteValue(MovementStopRadiusNumberBox, 0, 128, "정지 반경"),
                CursorDistance = RequiredFiniteValue(CursorDistanceNumberBox, 0, 512, "마우스 거리"),
                FreeRoamingDwellMilliseconds = checked((long)Math.Round(
                    RequiredFiniteValue(FreeRoamingDwellNumberBox, 0.5, 300, "머무름 시간") * 1_000)),
                PrefersFrontmostWindow = PrefersFrontmostWindowToggle.IsOn,
                CursorAvoidingDetectionDistance = RequiredFiniteValue(
                    AvoidingDetectionNumberBox,
                    32,
                    1_024,
                    "도망 감지 거리"),
                CursorAvoidingSpeed = RequiredFiniteValue(
                    AvoidingSpeedNumberBox,
                    20,
                    1_000,
                    "도망 속도"),
                CursorAvoidingIdleBehavior = AvoidingIdleBehaviorComboBox.SelectedIndex == 1
                    ? CursorAvoidingIdleBehavior.FreeRoaming
                    : CursorAvoidingIdleBehavior.Stationary,
                CursorFollowingAnimation = CursorFollowingAnimationEditor.Settings,
                FreeRoamingAnimation = FreeRoamingAnimationEditor.Settings,
                CursorAvoidingAnimation = CursorAvoidingAnimationEditor.Settings,
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
                PettingMotionId = SelectedMotionId(PettingMotionComboBox),
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

    private void RefreshMovementRuntimeStatus()
    {
        if (Application.Current is App app && MovementStatusText is not null)
        {
            MovementStatusText.Text = $"실행 상태: {app.MovementStatus}";
        }
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

    private DispatcherQueueTimer CreateDisplaySaveTimer()
    {
        DispatcherQueueTimer timer = DispatcherQueue.CreateTimer();
        timer.Interval = TimeSpan.FromMilliseconds(350);
        timer.IsRepeating = false;
        timer.Tick += (_, _) => PersistCurrentDisplayPreview();
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

        OverlayWidthValueText.Text = $"{OverlayWidthSlider.Value:0} px";
        OverlayOpacityValueText.Text = $"{OverlayOpacitySlider.Value:P0}";
        PointerOverlapOpacityValueText.Text =
            $"{PointerOverlapOpacitySlider.Value:P0}";
    }

    private void RefreshOverlayStatusText()
    {
        if (Overlay is not { } overlay)
        {
            return;
        }

        OverlayStatusText.Text =
            $"HWND 0x{overlay.Handle:X} · {(overlay.IsVisible ? "표시 중" : "숨김")} · " +
            $"{overlay.Width:0}px · 투명도 {overlay.Opacity:P0} · " +
            $"입력 통과 {(overlay.IsClickThrough ? "켜짐" : "꺼짐")} · " +
            $"겹침 {(overlay.IsPointerOverVisibleContent ? $"적용 {overlay.AppliedOpacity:P0}" : "없음")} · " +
            $"픽셀 아트 {(overlay.PixelArtRendering ? "켜짐" : "꺼짐")}";
    }

    private void RefreshOverlayPlaybackInfo()
    {
        if (Overlay is not { } overlay)
        {
            return;
        }

        OverlayInfoBar.Severity = InfoBarSeverity.Success;
        OverlayInfoBar.Title = $"{overlay.PackageDisplayName}이(가) 함께하고 있어요";
        OverlayInfoBar.Message = $"현재 애니메이션: {overlay.MotionId}";
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
        int RepeatCount,
        IReadOnlyList<MotionOptionItem> MotionOptions,
        bool CanMoveUp,
        bool CanMoveDown,
        bool CanDelete);

    public sealed record AutomaticRuleEditorItem(Guid Id, string Summary, string Detail);

    public sealed record SpeechPhraseEditorItem(Guid Id, string Text, string Detail);

    private readonly record struct ExportReviewOptions(
        bool IncludesRecommendedProfile,
        bool IncludesApplicationRules);

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
