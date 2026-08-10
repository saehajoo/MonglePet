using Microsoft.UI.Xaml;
using MonglePet.Activity;
using MonglePet.Core.Behavior;
using MonglePet.Packages;
using MonglePet.PetLibrary;
using MonglePet.Settings;
using MonglePet.Shell;
using MonglePet.Windows.Activity;
using MonglePet.Windows.Runtime;

namespace MonglePet.Windows;

public partial class App : Application
{
    private const string DevelopmentPackageFamilyName =
        "4B7E245F-A59A-4E0F-84D7-52B511356256_1z32rh13vfry6";
    private Window? _window;
    private PetBehaviorRuntime? _behaviorRuntime;
    private PetSpeechRuntime? _speechRuntime;
    private PetMovementRuntime? _movementRuntime;
    private WindowsActivityMonitor? _activityMonitor;
    private LoadedPetPackage? _activePackage;
    private readonly WindowsMonitorPlacementService _monitorPlacement = new();
    private WindowsNotificationAreaIcon? _notificationArea;
    private bool _isQuitting;

    public App()
    {
        InitializeComponent();
        IsPackaged = WindowsPackageIdentity.IsCurrentProcessPackaged();
        string appLocalDataRoot;
        if (IsPackaged)
        {
            appLocalDataRoot =
                global::Windows.Storage.ApplicationData.Current.LocalFolder.Path;
        }
        else
        {
            appLocalDataRoot = Environment.GetFolderPath(
                Environment.SpecialFolder.LocalApplicationData,
                Environment.SpecialFolderOption.Create);
            DataMigrationResult =
                WindowsAppDataMigration.TryMigrateFromPackageLocalState(
                    appLocalDataRoot,
                    [DevelopmentPackageFamilyName]);
        }
        PetLibrary = new PetLibraryStore(
            PetLibraryPaths.FromAppLocalDataRoot(appLocalDataRoot));
        PetImporter = new PetPackageImporter(PetLibrary);
        PetExporter = new PetPackageExporter();
        PetEditor = new UserPetPackageEditor(PetLibrary, new WindowsUserPetAtlasBuilder());
        SettingsStore = new AppSettingsStore(
            AppSettingsPaths.FromAppLocalDataRoot(appLocalDataRoot),
            legacyMotionCycleMillisecondsResolver:
                ResolveLegacyMotionCycleMilliseconds,
            legacyPetDefinitionAvailabilityResolver:
                CanResolveLegacyPetDefinition);
        ApplicationCatalog = new WindowsApplicationCatalog();
    }

    public PetLibraryStore PetLibrary { get; }

    public bool IsPackaged { get; }

    public WindowsAppDataMigrationResult? DataMigrationResult { get; }

    public PetPackageImporter PetImporter { get; }

    public PetPackageExporter PetExporter { get; }

    public UserPetPackageEditor PetEditor { get; }

    public AppSettingsStore SettingsStore { get; }

    public IWindowsApplicationCatalog ApplicationCatalog { get; }

    public AppSettingsLoadResult? SettingsLoadResult { get; private set; }

    public AppSettings CurrentSettings { get; private set; } = AppSettings.Default;

    public Guid? ActiveInstallationId { get; private set; }

    public LoadedPetPackage? ActivePackage => _activePackage;

    public Overlay.PetOverlayWindow? Overlay { get; private set; }

    public string? OverlayInitializationError { get; private set; }

    public string? SettingsStatusMessage { get; private set; }

    public string? NotificationAreaInitializationError { get; private set; }

    public BehaviorProfile ActiveBehaviorProfile =>
        ProfileFor(CurrentSettings, ActiveInstallationId);

    public IReadOnlyList<string> ActiveMotionIds =>
        _activePackage?.Manifest.Motions.Select(motion => motion.Id).ToList() ?? [];

    public IReadOnlyList<MonitorWorkArea> AvailableMonitorWorkAreas() =>
        _monitorPlacement.AvailableWorkAreas();

    public string BehaviorStatus => _behaviorRuntime?.Status ?? "행동 런타임 없음";

    public string SpeechStatus => _speechRuntime is null
        ? "말풍선 런타임 없음"
        : $"{_speechRuntime.Status} · {Overlay?.SpeechBubbleStatus ?? "표시 창 없음"}";

    public string MovementStatus => _movementRuntime is { } runtime
        ? $"{runtime.Status} · {runtime.PointerStatus} · {runtime.WindowPreferenceStatus}"
        : "이동 런타임 없음";

    public ActivitySnapshot? LatestActivitySnapshot => _activityMonitor?.LatestSnapshot;

    public string ActivityStatus => LatestActivitySnapshot switch
    {
        null => "활동 감지 준비 중",
        { IsSystemSleeping: true } => "시스템 절전 중",
        { IsScreenLocked: true } => "Windows 세션 잠금 중",
        { } snapshot =>
            $"{snapshot.FrontmostApplicationId ?? "전면 앱 식별 불가"} · " +
            $"입력 없음 {snapshot.IdleDuration.TotalSeconds:0}초",
    };

    public event EventHandler? InitializationCompleted;

    public event EventHandler? BehaviorStateChanged;

    public event EventHandler? MovementStateChanged;

    public event EventHandler? SettingsStateChanged;

    public IntPtr MainWindowHandle => _window is null
        ? IntPtr.Zero
        : WinRT.Interop.WindowNative.GetWindowHandle(_window);

    public bool ShouldHideSettingsWindowOnClose => !_isQuitting && _notificationArea is not null;

    public bool IsQuitting => _isQuitting;

    protected override void OnLaunched(Microsoft.UI.Xaml.LaunchActivatedEventArgs args)
    {
        bool isStartupLaunch = WindowsRunAtLoginCommand.IsStartupLaunch(
            Environment.GetCommandLineArgs().Skip(1));
        var mainWindow = new MainWindow();
        _window = mainWindow;
        if (!isStartupLaunch)
        {
            mainWindow.Activate();
        }
        mainWindow.ApplyWindowIcons();
        InitializeOverlay();
        InitializeNotificationArea();
        InitializationCompleted?.Invoke(this, EventArgs.Empty);
        if (isStartupLaunch)
        {
            mainWindow.AppWindow.Hide();
            Microsoft.UI.Dispatching.DispatcherQueue.GetForCurrentThread().TryEnqueue(
                Microsoft.UI.Dispatching.DispatcherQueuePriority.Low,
                mainWindow.AppWindow.Hide);
        }
    }

    public string InstallOrActivateBundledSample()
    {
        EnsureSettingsWritingEnabled();
        InstalledPetPackage installed;
        try
        {
            installed = PetLibrary.InstallFromDirectory(BundledSamplePath);
        }
        catch (PetLibraryException exception)
            when (exception.Error == PetLibraryError.DuplicatePackage &&
                  exception.MatchingInstallationIds.Count > 0)
        {
            installed = PetLibrary.GetInstallation(exception.MatchingInstallationIds[0]);
            ActivateInstalledPackage(installed);
            return $"기존 설치 '{installed.Package.Manifest.DisplayName}'로 전환했습니다.";
        }

        ActivateInstalledPackage(installed);
        return $"'{installed.Package.Manifest.DisplayName}' 패키지를 라이브러리에 설치했습니다.";
    }

    public InstalledPetPackage ImportPackage(
        string sourcePath,
        PetPackageInstallMode mode = PetPackageInstallMode.RejectDuplicate,
        Guid? replacementInstallationId = null)
    {
        EnsureSettingsWritingEnabled();
        InstalledPetPackage installed = PetImporter.Import(
            sourcePath,
            mode,
            replacementInstallationId);
        try
        {
            ActivateInstalledPackage(installed);
            return installed;
        }
        catch
        {
            if (mode != PetPackageInstallMode.Replace)
            {
                TryRemoveInstallation(installed.InstallationId);
            }

            throw;
        }
    }

    public PetPackageImportReview ReviewPackage(string sourcePath) =>
        PetImporter.Review(sourcePath);

    public InstalledPetPackage ImportReviewedPackage(
        PetPackageImportReview review,
        bool appliesRecommendedProfile,
        PetPackageInstallMode mode = PetPackageInstallMode.RejectDuplicate,
        Guid? replacementInstallationId = null)
    {
        EnsureSettingsWritingEnabled();
        if (appliesRecommendedProfile && review.RecommendedProfile is null)
        {
            throw new PetLibraryException(
                PetLibraryError.PackageValidationFailed,
                "이 패키지의 권장 설정은 적용할 수 없습니다.");
        }

        InstalledPetPackage installed = PetImporter.ImportReviewed(
            review,
            mode,
            replacementInstallationId);
        try
        {
            ActivateInstalledPackage(installed);
            if (appliesRecommendedProfile && review.RecommendedProfile is { } recommended)
            {
                SaveBehaviorProfile(recommended with
                {
                    PetKey = new PetBehaviorKey.Installed(installed.InstallationId),
                });
            }
            return installed;
        }
        catch
        {
            if (mode != PetPackageInstallMode.Replace)
            {
                TryRemoveInstallation(installed.InstallationId);
            }
            throw;
        }
    }

    public string ExportActivePackage(
        string destinationPath,
        bool includesRecommendedProfile,
        bool includesApplicationRules)
    {
        if (ActiveInstallationId is not Guid installationId)
        {
            throw new PetPackageExportException(
                PetPackageExportError.InvalidDestination,
                "내장 펫은 내보낼 수 없습니다.");
        }
        InstalledPetPackage installed = PetLibrary.GetInstallation(installationId);
        BehaviorProfile? profile = includesRecommendedProfile
            ? ActiveBehaviorProfile
            : null;
        return PetExporter.Export(
            installed,
            destinationPath,
            profile,
            includesApplicationRules);
    }

    public InstalledPetPackage ActivateInstallation(Guid installationId)
    {
        EnsureSettingsWritingEnabled();
        InstalledPetPackage installed = PetLibrary.GetInstallation(installationId);
        ActivateInstalledPackage(installed);
        return installed;
    }

    public void ActivateBundledPet()
    {
        EnsureSettingsWritingEnabled();
        ActivateBundledSample();
    }

    public void PreviewOverlaySettings(OverlaySettings settings)
    {
        ArgumentNullException.ThrowIfNull(settings);
        CurrentSettings = CurrentSettings with { Overlay = settings };
        Overlay?.ApplyDisplaySettings(settings);
        UpdateMovementRuntime();
    }

    public void SaveOverlaySettings(OverlaySettings settings)
    {
        ArgumentNullException.ThrowIfNull(settings);
        EnsureSettingsWritingEnabled();
        AppSettings next = CurrentSettings with { Overlay = settings };
        SettingsStore.Save(next);
        CurrentSettings = next;
        Overlay?.ApplyDisplaySettings(settings);
        UpdateMovementRuntime();
        RefreshNotificationArea();
        SettingsStateChanged?.Invoke(this, EventArgs.Empty);
    }

    public void PersistCurrentSettings()
    {
        EnsureSettingsWritingEnabled();
        SettingsStore.Save(CurrentSettings);
    }

    public void SetUserPresentation(PetPresentation presentation)
    {
        EnsureSettingsWritingEnabled();
        AppSettings next = CurrentSettings with { LastUserPresentation = presentation };
        SettingsStore.Save(next);
        CurrentSettings = next;
        ApplyPresentation(presentation);
        RefreshNotificationArea();
        SettingsStateChanged?.Invoke(this, EventArgs.Empty);
    }

    public void ShowSettings()
    {
        if (_window is not MainWindow mainWindow)
        {
            return;
        }

        mainWindow.ShowAndActivate();
    }

    public void BringPetToCurrentScreen()
    {
        EnsureSettingsWritingEnabled();
        if (Overlay is not { } overlay)
        {
            throw new InvalidOperationException("이동할 펫 오버레이가 없습니다.");
        }

        PetScreenPlacement placement = _monitorPlacement.PlacementForCursor(
            Math.Max(1, (int)Math.Round(overlay.Width)),
            Math.Max(1, (int)Math.Round(overlay.Height)));
        overlay.MoveTo(placement.X, placement.Y);
        OverlaySettings nextOverlay = CurrentSettings.Overlay with
        {
            ScreenIdentifier = placement.ScreenIdentifier,
            OriginX = placement.X,
            OriginY = placement.Y,
        };
        AppSettings next = CurrentSettings with { Overlay = nextOverlay };
        SettingsStore.Save(next);
        CurrentSettings = next;
        _movementRuntime?.InvalidateEnvironment();
        SettingsStateChanged?.Invoke(this, EventArgs.Empty);
    }

    public void QuitApplication()
    {
        if (_isQuitting)
        {
            return;
        }

        _isQuitting = true;
        if (_window is MainWindow mainWindow)
        {
            mainWindow.PrepareForShutdown();
        }
        if (_notificationArea is not null)
        {
            _notificationArea.ErrorOccurred -= NotificationArea_ErrorOccurred;
            _notificationArea.Dispose();
            _notificationArea = null;
        }
        if (_activityMonitor is not null)
        {
            _activityMonitor.SnapshotChanged -= ActivityMonitor_SnapshotChanged;
            _activityMonitor.Dispose();
            _activityMonitor = null;
        }
        if (_behaviorRuntime is not null)
        {
            _behaviorRuntime.StateChanged -= BehaviorRuntime_StateChanged;
            _behaviorRuntime.Dispose();
            _behaviorRuntime = null;
        }
        if (_speechRuntime is not null)
        {
            _speechRuntime.Dispose();
            _speechRuntime = null;
        }
        if (_movementRuntime is not null)
        {
            _movementRuntime.StateChanged -= MovementRuntime_StateChanged;
            _movementRuntime.MovementMotionChanged -= MovementRuntime_MovementMotionChanged;
            _movementRuntime.PettingRequested -= MovementRuntime_PettingRequested;
            _movementRuntime.Dispose();
            _movementRuntime = null;
        }
        if (Overlay is not null)
        {
            Overlay.UserDragStateChanged -= Overlay_UserDragStateChanged;
            Overlay.DisplayEnvironmentChanged -= Overlay_DisplayEnvironmentChanged;
        }
        Overlay?.Dispose();
        Overlay = null;
        Window? window = _window;
        _window = null;
        if (window is not null)
        {
            // Closing the last WinUI window owns application shutdown. Calling
            // Application.Exit immediately afterwards can race pending XAML input
            // and value-change work during rapid settings edits.
            window.Close();
        }
        else
        {
            Exit();
        }
    }

    public void SaveBehaviorSelection(BehaviorMode mode, string? manualSequenceId)
    {
        EnsureSettingsWritingEnabled();
        BehaviorProfile current = ActiveBehaviorProfile;
        string? resolvedManual = manualSequenceId;
        if (mode == BehaviorMode.Manual &&
            (resolvedManual is null || !current.Sequences.Any(sequence =>
                string.Equals(sequence.Id, resolvedManual, StringComparison.Ordinal))))
        {
            resolvedManual = current.Sequences.FirstOrDefault()?.Id;
        }

        BehaviorProfile updated = current with
        {
            Mode = mode,
            ManualSequenceId = resolvedManual,
        };
        SaveBehaviorProfile(updated);
    }

    public void SaveBehaviorProfile(BehaviorProfile profile)
    {
        ArgumentNullException.ThrowIfNull(profile);
        EnsureSettingsWritingEnabled();
        if (profile.PetKey != BehaviorProfileDefaults.KeyForInstallation(ActiveInstallationId))
        {
            throw new AppSettingsException(
                AppSettingsError.InvalidSettings,
                "현재 펫과 다른 행동 프로필은 편집할 수 없습니다.");
        }

        var profiles = CurrentSettings.BehaviorProfiles.ToList();
        int index = profiles.FindIndex(value => value.PetKey == profile.PetKey);
        if (index >= 0)
        {
            profiles[index] = profile;
        }
        else
        {
            profiles.Add(profile);
        }

        AppSettings next = CurrentSettings with { BehaviorProfiles = profiles };
        SettingsStore.Save(next);
        CurrentSettings = next;
        _speechRuntime?.Update(profile.Speech);
        _behaviorRuntime?.Update(profile, next.LastUserPresentation);
        _speechRuntime?.BehaviorSequenceDidChange(_behaviorRuntime?.SequenceId);
        UpdateMovementRuntime();
        BehaviorStateChanged?.Invoke(this, EventArgs.Empty);
        SettingsStateChanged?.Invoke(this, EventArgs.Empty);
    }

    public void ReplaceActiveMotionReferences(string motionId, string? replacementMotionId) =>
        SaveBehaviorProfile(BehaviorProfileMotionReferences.Replacing(
            ActiveBehaviorProfile,
            motionId,
            replacementMotionId));

    public string RemoveInstallation(Guid installationId)
    {
        EnsureSettingsWritingEnabled();
        InstalledPetPackage removing = PetLibrary.GetInstallation(installationId);
        bool removesActive = ActiveInstallationId == installationId;
        PetBehaviorKey removedKey = new PetBehaviorKey.Installed(installationId);
        AppSettings withoutRemovedProfile = CurrentSettings with
        {
            BehaviorProfiles = CurrentSettings.BehaviorProfiles
                .Where(profile => profile.PetKey != removedKey)
                .ToArray(),
        };
        PetLibrary.RemoveInstallation(installationId);

        if (removesActive)
        {
            CurrentSettings = withoutRemovedProfile;
            InstalledPetPackage? fallback = PetLibrary.GetInstalledPackages().FirstOrDefault();
            if (fallback is not null)
            {
                ActivateInstalledPackage(fallback);
            }
            else
            {
                ActivateBundledSample();
            }
        }
        else
        {
            SettingsStore.Save(withoutRemovedProfile);
            CurrentSettings = withoutRemovedProfile;
            SettingsStateChanged?.Invoke(this, EventArgs.Empty);
        }

        return $"'{removing.Package.Manifest.DisplayName}' 설치를 삭제했습니다.";
    }

    private void InitializeOverlay()
    {
        try
        {
            AppSettingsLoadResult loadResult = SettingsStore.Load();
            SettingsLoadResult = loadResult;
            CurrentSettings = loadResult.Settings ?? AppSettings.Default with
            {
                SelectedPetInstallationId = loadResult.SelectedPetInstallationId,
            };
            SettingsStatusMessage = loadResult.Issues.Count == 0
                ? null
                : string.Join(" ", loadResult.Issues);

            IReadOnlyList<InstalledPetPackage> installed =
                PetLibrary.GetInstalledPackages();
            InstalledPetPackage? selected = loadResult.SelectedPetInstallationId is Guid id
                ? installed.FirstOrDefault(value => value.InstallationId == id)
                : null;
            selected ??= installed.FirstOrDefault();

            if (selected is not null)
            {
                CreateInitialOverlay(selected.Package, selected.InstallationId);
            }
            else
            {
                CreateInitialOverlay(LoadBundledSample(), null);
            }

            if (SettingsStore.IsWritingEnabled &&
                ActiveInstallationId != loadResult.SelectedPetInstallationId)
            {
                SettingsStore.SaveSelectedPetInstallationId(ActiveInstallationId);
                CurrentSettings = CurrentSettings with
                {
                    SelectedPetInstallationId = ActiveInstallationId,
                };
                SettingsStatusMessage = loadResult.SelectedPetInstallationId is Guid missing
                    ? $"저장된 설치 {missing:D}을 찾지 못해 사용 가능한 펫으로 복구했습니다."
                    : SettingsStatusMessage;
            }
        }
        catch (Exception exception)
        {
            OverlayInitializationError = exception.Message;
        }
    }

    private void CreateInitialOverlay(LoadedPetPackage package, Guid? installationId)
    {
        Overlay = new Overlay.PetOverlayWindow(package, CurrentSettings.Overlay);
        OverlaySettings positionedOverlay = RestoreSavedOverlayPosition(
            Overlay,
            CurrentSettings.Overlay);
        if (positionedOverlay != CurrentSettings.Overlay)
        {
            CurrentSettings = CurrentSettings with { Overlay = positionedOverlay };
            if (SettingsStore.IsWritingEnabled)
            {
                SettingsStore.Save(CurrentSettings);
            }
        }
        _activePackage = package;
        ActiveInstallationId = installationId;
        _behaviorRuntime = new PetBehaviorRuntime(package, Overlay);
        _behaviorRuntime.StateChanged += BehaviorRuntime_StateChanged;
        _speechRuntime = CreateSpeechRuntime(Overlay);
        _movementRuntime = CreateMovementRuntime(Overlay, package);
        Overlay.UserDragStateChanged += Overlay_UserDragStateChanged;
        Overlay.DisplayEnvironmentChanged += Overlay_DisplayEnvironmentChanged;
        _activityMonitor = CreateActivityMonitor(Overlay);
        ApplyPresentation(CurrentSettings.LastUserPresentation);
    }

    private void ActivateInstalledPackage(InstalledPetPackage installed) =>
        SwitchOverlay(installed.Package, installed.InstallationId);

    private void ActivateBundledSample() => SwitchOverlay(LoadBundledSample(), null);

    private void SwitchOverlay(LoadedPetPackage package, Guid? installationId)
    {
        AppSettings nextSettings = CurrentSettings with
        {
            SelectedPetInstallationId = installationId,
        };
        var nextOverlay = new Overlay.PetOverlayWindow(package, nextSettings.Overlay);
        nextSettings = nextSettings with
        {
            Overlay = RestoreSavedOverlayPosition(nextOverlay, nextSettings.Overlay),
        };
        PetBehaviorRuntime? nextRuntime = null;
        PetSpeechRuntime? nextSpeechRuntime = null;
        PetMovementRuntime? nextMovementRuntime = null;
        try
        {
            nextRuntime = new PetBehaviorRuntime(package, nextOverlay);
            BehaviorProfile nextProfile = ProfileFor(nextSettings, installationId);
            nextSpeechRuntime = CreateSpeechRuntime(nextOverlay);
            nextSpeechRuntime.Update(nextProfile.Speech);
            nextSpeechRuntime.SetAwake(
                nextSettings.LastUserPresentation == PetPresentation.Awake);
            nextRuntime.Update(nextProfile, nextSettings.LastUserPresentation);
            nextMovementRuntime = CreateMovementRuntime(nextOverlay, package);
            SettingsStore.Save(nextSettings);
            if (nextSettings.LastUserPresentation == PetPresentation.Awake)
            {
                nextOverlay.Show();
            }
            else
            {
                nextOverlay.Hide();
            }
            nextSpeechRuntime.BehaviorSequenceDidChange(nextRuntime.SequenceId);

            Overlay.PetOverlayWindow? previous = Overlay;
            PetBehaviorRuntime? previousRuntime = _behaviorRuntime;
            PetSpeechRuntime? previousSpeechRuntime = _speechRuntime;
            PetMovementRuntime? previousMovementRuntime = _movementRuntime;
            WindowsActivityMonitor? previousActivityMonitor = _activityMonitor;
            Overlay = nextOverlay;
            _behaviorRuntime = nextRuntime;
            _behaviorRuntime.StateChanged += BehaviorRuntime_StateChanged;
            _speechRuntime = nextSpeechRuntime;
            _movementRuntime = nextMovementRuntime;
            nextOverlay.UserDragStateChanged += Overlay_UserDragStateChanged;
            nextOverlay.DisplayEnvironmentChanged += Overlay_DisplayEnvironmentChanged;
            _activityMonitor = CreateActivityMonitor(nextOverlay);
            ActiveInstallationId = installationId;
            _activePackage = package;
            CurrentSettings = nextSettings;
            UpdateMovementRuntime();
            RefreshNotificationArea();
            SettingsStateChanged?.Invoke(this, EventArgs.Empty);
            _activityMonitor.SetPresentation(nextSettings.LastUserPresentation);
            if (previousActivityMonitor is not null)
            {
                previousActivityMonitor.SnapshotChanged -= ActivityMonitor_SnapshotChanged;
                previousActivityMonitor.Dispose();
            }
            if (previousRuntime is not null)
            {
                previousRuntime.StateChanged -= BehaviorRuntime_StateChanged;
                previousRuntime.Dispose();
            }
            previousSpeechRuntime?.Dispose();
            if (previousMovementRuntime is not null)
            {
                previousMovementRuntime.StateChanged -= MovementRuntime_StateChanged;
                previousMovementRuntime.MovementMotionChanged -= MovementRuntime_MovementMotionChanged;
                previousMovementRuntime.PettingRequested -= MovementRuntime_PettingRequested;
                previousMovementRuntime.Dispose();
            }
            if (previous is not null)
            {
                previous.UserDragStateChanged -= Overlay_UserDragStateChanged;
                previous.DisplayEnvironmentChanged -= Overlay_DisplayEnvironmentChanged;
            }
            previous?.Dispose();
            BehaviorStateChanged?.Invoke(this, EventArgs.Empty);
        }
        catch
        {
            nextMovementRuntime?.Dispose();
            nextRuntime?.Dispose();
            nextSpeechRuntime?.Dispose();
            nextOverlay.Dispose();
            throw;
        }
    }

    private LoadedPetPackage LoadBundledSample() =>
        new PetPackageLoader().LoadDirectory(BundledSamplePath);

    private void ApplyPresentation(PetPresentation presentation)
    {
        if (Overlay is not { } overlay)
        {
            return;
        }

        if (presentation == PetPresentation.Awake)
        {
            overlay.Show();
        }
        else
        {
            overlay.Hide();
        }
        _speechRuntime?.Update(ActiveBehaviorProfile.Speech);
        _speechRuntime?.SetAwake(presentation == PetPresentation.Awake);
        _behaviorRuntime?.Update(ActiveBehaviorProfile, presentation);
        _speechRuntime?.BehaviorSequenceDidChange(_behaviorRuntime?.SequenceId);
        _activityMonitor?.SetPresentation(presentation);
        UpdateMovementRuntime();
    }

    private OverlaySettings RestoreSavedOverlayPosition(
        Overlay.PetOverlayWindow overlay,
        OverlaySettings settings)
    {
        if (string.IsNullOrWhiteSpace(settings.ScreenIdentifier))
        {
            return settings;
        }

        PetScreenPlacement placement = _monitorPlacement.RestorePlacement(
            settings.ScreenIdentifier,
            settings.OriginX,
            settings.OriginY,
            Math.Max(1, (int)Math.Round(overlay.Width)),
            Math.Max(1, (int)Math.Round(overlay.Height)));
        overlay.MoveTo(placement.X, placement.Y);
        return settings with
        {
            ScreenIdentifier = placement.ScreenIdentifier,
            OriginX = placement.X,
            OriginY = placement.Y,
        };
    }

    private void InitializeNotificationArea()
    {
        try
        {
            _notificationArea = new WindowsNotificationAreaIcon(
                NotificationAreaState,
                Path.Combine(AppContext.BaseDirectory, "Assets", "AppIcon.ico"),
                HandleNotificationAreaCommand);
            _notificationArea.ErrorOccurred += NotificationArea_ErrorOccurred;
        }
        catch (Exception exception)
        {
            NotificationAreaInitializationError = exception.Message;
            SettingsStatusMessage = exception.Message;
        }
    }

    private NotificationAreaState NotificationAreaState => new(
        CurrentSettings.LastUserPresentation == PetPresentation.Awake,
        Overlay?.PackageDisplayName ?? "MonglePet",
        CurrentSettings.Overlay.ClickThrough);

    private void RefreshNotificationArea()
    {
        try
        {
            _notificationArea?.Update(NotificationAreaState);
        }
        catch (Exception exception)
        {
            NotificationArea_ErrorOccurred(
                this,
                new NotificationAreaErrorEventArgs(exception));
        }
    }

    private void HandleNotificationAreaCommand(NotificationAreaCommand command)
    {
        switch (command)
        {
            case NotificationAreaCommand.TogglePetAwake:
                SetUserPresentation(
                    CurrentSettings.LastUserPresentation == PetPresentation.Awake
                        ? PetPresentation.TuckedAway
                        : PetPresentation.Awake);
                break;
            case NotificationAreaCommand.ToggleClickThrough:
                SaveOverlaySettings(CurrentSettings.Overlay with
                {
                    ClickThrough = !CurrentSettings.Overlay.ClickThrough,
                });
                break;
            case NotificationAreaCommand.BringPetToCurrentScreen:
                BringPetToCurrentScreen();
                break;
            case NotificationAreaCommand.OpenSettings:
                // TrackPopupMenu owns foreground activation until its native
                // callback returns. Defer the WinUI activation so the settings
                // HWND can become the actual foreground window afterwards.
                if (!Microsoft.UI.Dispatching.DispatcherQueue
                    .GetForCurrentThread()
                    .TryEnqueue(ShowSettings))
                {
                    ShowSettings();
                }
                break;
            case NotificationAreaCommand.Quit:
                // The command originates in the notification area's native
                // window procedure. Defer teardown until that procedure has
                // returned so Dispose does not destroy its own HWND mid-call.
                if (!Microsoft.UI.Dispatching.DispatcherQueue
                    .GetForCurrentThread()
                    .TryEnqueue(QuitApplication))
                {
                    throw new InvalidOperationException(
                        "앱 종료 작업을 UI 큐에 예약하지 못했습니다.");
                }
                break;
            default:
                throw new ArgumentOutOfRangeException(nameof(command), command, null);
        }
    }

    private void NotificationArea_ErrorOccurred(
        object? sender,
        NotificationAreaErrorEventArgs e)
    {
        SettingsStatusMessage = e.Exception.Message;
        SettingsStateChanged?.Invoke(this, EventArgs.Empty);
    }

    private static BehaviorProfile ProfileFor(
        AppSettings settings,
        Guid? installationId)
    {
        PetBehaviorKey key = BehaviorProfileDefaults.KeyForInstallation(installationId);
        return settings.BehaviorProfiles.FirstOrDefault(profile => profile.PetKey == key)
            ?? BehaviorProfileDefaults.Create(key);
    }

    private void BehaviorRuntime_StateChanged(object? sender, EventArgs e)
    {
        _speechRuntime?.BehaviorSequenceDidChange(_behaviorRuntime?.SequenceId);
        BehaviorStateChanged?.Invoke(this, EventArgs.Empty);
    }

    private static PetSpeechRuntime CreateSpeechRuntime(
        Overlay.PetOverlayWindow overlay)
    {
        Microsoft.UI.Dispatching.DispatcherQueue dispatcher =
            Microsoft.UI.Dispatching.DispatcherQueue.GetForCurrentThread();
        return new PetSpeechRuntime(
            new DispatcherQueuePetSpeechScheduler(dispatcher),
            new DispatcherQueuePetSpeechScheduler(dispatcher),
            presentation =>
            {
                if (presentation is null)
                {
                    overlay.HideSpeechBubble();
                }
                else
                {
                    overlay.ShowSpeechBubble(presentation);
                }
            });
    }

    private PetMovementRuntime CreateMovementRuntime(
        Overlay.PetOverlayWindow overlay,
        LoadedPetPackage package)
    {
        var runtime = new PetMovementRuntime(
            overlay,
            _monitorPlacement,
            package.Manifest.Motions.Select(motion => motion.Id));
        runtime.StateChanged += MovementRuntime_StateChanged;
        runtime.MovementMotionChanged += MovementRuntime_MovementMotionChanged;
        runtime.PettingRequested += MovementRuntime_PettingRequested;
        return runtime;
    }

    private void UpdateMovementRuntime()
    {
        bool suspended = LatestActivitySnapshot is
            { IsScreenLocked: true } or { IsSystemSleeping: true };
        _movementRuntime?.Update(
            ActiveBehaviorProfile,
            CurrentSettings.Overlay,
            CurrentSettings.LastUserPresentation,
            suspended);
    }

    private void MovementRuntime_StateChanged(object? sender, EventArgs e) =>
        MovementStateChanged?.Invoke(this, EventArgs.Empty);

    private void MovementRuntime_MovementMotionChanged(
        object? sender,
        MovementMotionChangedEventArgs e) =>
        _behaviorRuntime?.SetMovementMotion(e.MotionId);

    private void MovementRuntime_PettingRequested(
        object? sender,
        PettingRequestedEventArgs e) =>
        _behaviorRuntime?.PlayInteraction(e.MotionId);

    private void Overlay_UserDragStateChanged(
        object? sender,
        Overlay.PetOverlayDragEventArgs e)
    {
        if (e.IsDragging)
        {
            _movementRuntime?.SetUserDragging(true);
            return;
        }

        try
        {
            if (Overlay is not { } overlay || !SettingsStore.IsWritingEnabled)
            {
                return;
            }
            PetScreenPlacement placement = _monitorPlacement.ClampPlacement(
                e.X,
                e.Y,
                Math.Max(1, (int)Math.Round(overlay.Width)),
                Math.Max(1, (int)Math.Round(overlay.Height)));
            overlay.MoveTo(placement.X, placement.Y);
            OverlaySettings nextOverlay = CurrentSettings.Overlay with
            {
                ScreenIdentifier = placement.ScreenIdentifier,
                OriginX = placement.X,
                OriginY = placement.Y,
            };
            AppSettings next = CurrentSettings with { Overlay = nextOverlay };
            SettingsStore.Save(next);
            CurrentSettings = next;
            SettingsStateChanged?.Invoke(this, EventArgs.Empty);
        }
        catch (Exception exception)
        {
            SettingsStatusMessage = $"펫 위치를 저장하지 못했습니다: {exception.Message}";
            SettingsStateChanged?.Invoke(this, EventArgs.Empty);
        }
        finally
        {
            _movementRuntime?.SetUserDragging(false);
        }
    }

    private void Overlay_DisplayEnvironmentChanged(object? sender, EventArgs e)
    {
        try
        {
            _movementRuntime?.InvalidateEnvironment();
            if (Overlay is not { } overlay ||
                ActiveBehaviorProfile.Movement.Mode != PetMovementMode.Fixed)
            {
                return;
            }
            PetScreenPlacement placement = _monitorPlacement.ClampPlacement(
                overlay.OriginX,
                overlay.OriginY,
                Math.Max(1, (int)Math.Round(overlay.Width)),
                Math.Max(1, (int)Math.Round(overlay.Height)));
            overlay.MoveTo(placement.X, placement.Y);
            if (!SettingsStore.IsWritingEnabled)
            {
                return;
            }
            OverlaySettings nextOverlay = CurrentSettings.Overlay with
            {
                ScreenIdentifier = placement.ScreenIdentifier,
                OriginX = placement.X,
                OriginY = placement.Y,
            };
            if (nextOverlay == CurrentSettings.Overlay)
            {
                return;
            }
            AppSettings next = CurrentSettings with { Overlay = nextOverlay };
            SettingsStore.Save(next);
            CurrentSettings = next;
            SettingsStateChanged?.Invoke(this, EventArgs.Empty);
        }
        catch (Exception exception)
        {
            SettingsStatusMessage = $"화면 구성 변경을 적용하지 못했습니다: {exception.Message}";
            SettingsStateChanged?.Invoke(this, EventArgs.Empty);
        }
    }

    private WindowsActivityMonitor CreateActivityMonitor(
        Overlay.PetOverlayWindow overlay)
    {
        var monitor = new WindowsActivityMonitor(overlay);
        monitor.SnapshotChanged += ActivityMonitor_SnapshotChanged;
        return monitor;
    }

    private void ActivityMonitor_SnapshotChanged(
        object? sender,
        ActivitySnapshotChangedEventArgs e)
    {
        _speechRuntime?.SetSystemSuspended(
            e.Snapshot.IsScreenLocked || e.Snapshot.IsSystemSleeping);
        if (_behaviorRuntime is { } runtime)
        {
            runtime.UpdateActivity(
                e.Snapshot,
                ActiveBehaviorProfile,
                CurrentSettings.LastUserPresentation);
            _speechRuntime?.BehaviorSequenceDidChange(runtime.SequenceId);
        }
        else
        {
            BehaviorStateChanged?.Invoke(this, EventArgs.Empty);
        }
        UpdateMovementRuntime();
    }

    private long? ResolveLegacyMotionCycleMilliseconds(
        Guid? selectedInstallationId,
        string motionId)
    {
        LoadedPetPackage package = LoadBundledSample();
        if (selectedInstallationId is Guid installationId)
        {
            try
            {
                package = PetLibrary.GetInstallation(installationId).Package;
            }
            catch (PetLibraryException)
            {
                return null;
            }
        }

        string resolvedMotionId = string.Equals(
            motionId,
            "__monglepet_current_pet_default__",
            StringComparison.Ordinal)
            ? package.DefaultMotionId
            : motionId;
        PetPackageMotion? motion = package.Manifest.Motions.FirstOrDefault(value =>
            string.Equals(value.Id, resolvedMotionId, StringComparison.Ordinal));
        if (motion is null || motion.Frames.Count == 0)
        {
            return null;
        }

        try
        {
            long total = motion.Frames.Sum(frame => checked((long)frame.DurationMs));
            return total > 0 ? total : null;
        }
        catch (OverflowException)
        {
            return null;
        }
    }

    private bool CanResolveLegacyPetDefinition(Guid? selectedInstallationId)
    {
        if (selectedInstallationId is null)
        {
            return true;
        }

        try
        {
            PetLibrary.GetInstallation(selectedInstallationId.Value);
            return true;
        }
        catch (PetLibraryException)
        {
            return false;
        }
    }

    private string BundledSamplePath => Path.Combine(
        AppContext.BaseDirectory,
        "Samples",
        "ReadOnlySample.monglepet");

    private void EnsureSettingsWritingEnabled()
    {
        if (!SettingsStore.IsWritingEnabled)
        {
            throw new AppSettingsException(
                AppSettingsError.WritingDisabled,
                "보호 중인 설정 schema가 있어 펫 라이브러리 변경을 저장할 수 없습니다.");
        }
    }

    private void TryRemoveInstallation(Guid installationId)
    {
        try
        {
            PetLibrary.RemoveInstallation(installationId);
        }
        catch (PetLibraryException)
        {
        }
    }

}
