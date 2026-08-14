using Microsoft.UI.Xaml;
using MonglePet.Activity;
using MonglePet.Core.Behavior;
using MonglePet.Packages;
using MonglePet.PetLibrary;
using MonglePet.Settings;
using MonglePet.Shell;
using MonglePet.Windows.Runtime;

namespace MonglePet.Windows;

public partial class App : Application
{
    private const string DevelopmentPackageFamilyName =
        "4B7E245F-A59A-4E0F-84D7-52B511356256_1z32rh13vfry6";
    private Window? _window;
    private PetInstanceManager? _instanceManager;
    private PetResourceMonitor? _resourceMonitor;
    private PetRestoreJournal? _restoreJournal;
    private readonly WindowsMonitorPlacementService _monitorPlacement = new();
    private WindowsNotificationAreaIcon? _notificationArea;
    private readonly HashSet<Guid> _sessionExcludedInstanceIds = [];
    private Microsoft.UI.Dispatching.DispatcherQueueTimer? _selectionSaveTimer;
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

    public Guid? ActiveInstallationId => CurrentSettings.SelectedPetInstance?.PetKey is
        PetBehaviorKey.Installed installed
            ? installed.InstallationId
            : null;

    public LoadedPetPackage? ActivePackage => _instanceManager?.SelectedContext?.Package;

    public Overlay.PetOverlayWindow? Overlay { get; private set; }

    public string? OverlayInitializationError { get; private set; }

    public string? SettingsStatusMessage { get; private set; }

    public string? NotificationAreaInitializationError { get; private set; }

    public BehaviorProfile ActiveBehaviorProfile =>
        CurrentSettings.SelectedBehaviorProfile ??
        BehaviorProfileDefaults.Create(
            BehaviorProfileDefaults.KeyForInstallation(ActiveInstallationId));

    public IReadOnlyList<string> ActiveMotionIds =>
        ActivePackage?.Manifest.Motions.Select(motion => motion.Id).ToList() ?? [];

    public IReadOnlyList<MonitorWorkArea> AvailableMonitorWorkAreas() =>
        _monitorPlacement.AvailableWorkAreas();

    public string BehaviorStatus => _instanceManager?.SelectedContext?.Snapshot.BehaviorStatus
        ?? "행동 런타임 없음";

    public string SpeechStatus => _instanceManager?.SelectedContext?.Snapshot.SpeechStatus
        ?? "말풍선 런타임 없음";

    public string MovementStatus => _instanceManager?.SelectedContext?.Snapshot.MovementStatus
        ?? "이동 런타임 없음";

    public ActivitySnapshot? LatestActivitySnapshot => _instanceManager?.LatestActivitySnapshot;

    internal IReadOnlyList<PetRuntimeSnapshot> ActivePetSnapshots =>
        _instanceManager?.Snapshots ?? [];

    public bool AreAllPetsPaused => _instanceManager?.IsPaused ?? false;

    public PetResourceWarning? ResourceWarning => _resourceMonitor?.Warning;

    public PetRestoreRecoveryState? SafeStartRecovery { get; private set; }

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

    public event EventHandler? SelectedPetInstanceChanged;

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
        CurrentSettings = CurrentSettings.WithSelectedOverlay(settings);
        SynchronizePetInstances();
    }

    public void SaveOverlaySettings(OverlaySettings settings)
    {
        ArgumentNullException.ThrowIfNull(settings);
        EnsureSettingsWritingEnabled();
        AppSettings next = CurrentSettings.WithSelectedOverlay(settings);
        SettingsStore.Save(next);
        CurrentSettings = next;
        SynchronizePetInstances();
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
        AppSettings next = CurrentSettings.WithSelectedPresentation(presentation);
        SettingsStore.Save(next);
        CurrentSettings = next;
        SynchronizePetInstances();
        RefreshNotificationArea();
        SettingsStateChanged?.Invoke(this, EventArgs.Empty);
    }

    public void SelectPetInstance(Guid instanceId)
    {
        EnsureSettingsWritingEnabled();
        if (CurrentSettings.SelectedPetInstanceId == instanceId)
        {
            return;
        }
        CurrentSettings = ActivePetSettingsEditor.Select(CurrentSettings, instanceId);
        if (SafeStartRecovery is null)
        {
            _instanceManager?.SelectInstance(instanceId);
            Overlay = _instanceManager?.SelectedContext?.Overlay;
            RefreshNotificationArea();
        }
        SelectedPetInstanceChanged?.Invoke(this, EventArgs.Empty);
        ScheduleSelectedPetSave();
    }

    public void AddSamePetInstance(bool copiesSelectedSettings)
    {
        EnsureSettingsWritingEnabled();
        CurrentSettings = ActivePetSettingsEditor.AddSamePet(
            CurrentSettings,
            copiesSelectedSettings);
        SettingsStore.Save(CurrentSettings);
        SynchronizePetInstances();
        SettingsStateChanged?.Invoke(this, EventArgs.Empty);
    }

    public void RenamePetInstance(Guid instanceId, string? nickname)
    {
        EnsureSettingsWritingEnabled();
        CurrentSettings = ActivePetSettingsEditor.Rename(CurrentSettings, instanceId, nickname);
        SettingsStore.Save(CurrentSettings);
        SynchronizePetInstances();
        SettingsStateChanged?.Invoke(this, EventArgs.Empty);
    }

    public void RemovePetInstance(Guid instanceId)
    {
        EnsureSettingsWritingEnabled();
        CurrentSettings = ActivePetSettingsEditor.Remove(CurrentSettings, instanceId);
        SettingsStore.Save(CurrentSettings);
        SynchronizePetInstances();
        SettingsStateChanged?.Invoke(this, EventArgs.Empty);
    }

    public void MovePetInstance(Guid instanceId, int targetIndex)
    {
        EnsureSettingsWritingEnabled();
        CurrentSettings = ActivePetSettingsEditor.Move(CurrentSettings, instanceId, targetIndex);
        SettingsStore.Save(CurrentSettings);
        SynchronizePetInstances();
        SettingsStateChanged?.Invoke(this, EventArgs.Empty);
    }

    public void SetAllPetPresentations(PetPresentation presentation)
    {
        EnsureSettingsWritingEnabled();
        CurrentSettings = ActivePetSettingsEditor.SetAllPresentations(
            CurrentSettings,
            presentation);
        SettingsStore.Save(CurrentSettings);
        SynchronizePetInstances();
        RefreshNotificationArea();
        SettingsStateChanged?.Invoke(this, EventArgs.Empty);
    }

    public void ToggleAllPetsPaused()
    {
        _instanceManager?.SetPaused(!AreAllPetsPaused);
        RefreshNotificationArea();
        SettingsStateChanged?.Invoke(this, EventArgs.Empty);
    }

    public void ResumeSafeStart(bool excludesLastRestoredInstance)
    {
        if (SafeStartRecovery is not { } recovery)
        {
            return;
        }
        SafeStartRecovery = null;
        _restoreJournal?.Complete();
        _sessionExcludedInstanceIds.Clear();
        if (excludesLastRestoredInstance && recovery.InstanceId != Guid.Empty)
        {
            _sessionExcludedInstanceIds.Add(recovery.InstanceId);
        }
        SynchronizePetInstances();
        SettingsStatusMessage = _sessionExcludedInstanceIds.Count == 0
            ? "활성 펫 복원을 다시 시작했습니다."
            : "마지막 복원 펫을 제외하고 시작했습니다.";
        SettingsStateChanged?.Invoke(this, EventArgs.Empty);
    }

    public void RestorePetInstance(Guid instanceId)
    {
        if (!CurrentSettings.ActivePetInstances.Any(instance => instance.InstanceId == instanceId))
        {
            throw new ArgumentException("복원할 활성 펫이 없습니다.", nameof(instanceId));
        }
        if (SafeStartRecovery is not null)
        {
            _sessionExcludedInstanceIds.Clear();
            foreach (ActivePetInstance instance in CurrentSettings.ActivePetInstances)
            {
                if (instance.InstanceId != instanceId)
                {
                    _sessionExcludedInstanceIds.Add(instance.InstanceId);
                }
            }
            SafeStartRecovery = null;
            _restoreJournal?.Complete();
        }
        else
        {
            _sessionExcludedInstanceIds.Remove(instanceId);
        }
        CurrentSettings = ActivePetSettingsEditor.Select(CurrentSettings, instanceId);
        SettingsStore.Save(CurrentSettings);
        SynchronizePetInstances();
        SettingsStateChanged?.Invoke(this, EventArgs.Empty);
    }

    public string PetDisplayName(PetBehaviorKey key) => key switch
    {
        PetBehaviorKey.BuiltIn => "몽글이",
        PetBehaviorKey.Installed installed =>
            PetLibrary.GetInstallation(installed.InstallationId).Package.Manifest.DisplayName,
        _ => "알 수 없는 펫",
    };

    internal LoadedPetPackage PetPackage(Guid instanceId, PetBehaviorKey key) =>
        _instanceManager?.PackageFor(instanceId) ?? ResolvePackage(key);

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
        if (_instanceManager is not { SelectedInstanceId: Guid instanceId })
        {
            throw new InvalidOperationException("이동할 펫 오버레이가 없습니다.");
        }
        OverlaySettings nextOverlay = _instanceManager.BringToCurrentScreen(instanceId);
        AppSettings next = ActivePetSettingsEditor.SetOverlay(
            CurrentSettings,
            instanceId,
            nextOverlay);
        SettingsStore.Save(next);
        CurrentSettings = next;
        SynchronizePetInstances();
        SettingsStateChanged?.Invoke(this, EventArgs.Empty);
    }

    public void QuitApplication()
    {
        if (_isQuitting)
        {
            return;
        }

        _isQuitting = true;
        FlushSelectedPetSave();
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
        _resourceMonitor?.Dispose();
        _resourceMonitor = null;
        if (_instanceManager is not null)
        {
            _instanceManager.StateChanged -= InstanceManager_StateChanged;
            _instanceManager.OverlayChanged -= InstanceManager_OverlayChanged;
            _instanceManager.Dispose();
            _instanceManager = null;
        }
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

        AppSettings next = CurrentSettings.WithSelectedBehaviorProfile(profile);
        SettingsStore.Save(next);
        CurrentSettings = next;
        SynchronizePetInstances();
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
        PetBehaviorKey removedKey = new PetBehaviorKey.Installed(installationId);
        CurrentSettings = ActivePetSettingsEditor.ReplaceAllPetReferences(
            CurrentSettings,
            removedKey,
            PetBehaviorKey.BuiltInKey);
        PetLibrary.RemoveInstallation(installationId);
        SettingsStore.Save(CurrentSettings);
        SynchronizePetInstances();
        SettingsStateChanged?.Invoke(this, EventArgs.Empty);

        return $"'{removing.Package.Manifest.DisplayName}' 설치를 삭제했습니다.";
    }

    private void InitializeOverlay()
    {
        try
        {
            AppSettingsLoadResult loadResult = SettingsStore.Load();
            SettingsLoadResult = loadResult;
            CurrentSettings = loadResult.Settings ?? AppSettings.Default;
            SettingsStatusMessage = loadResult.Issues.Count == 0
                ? null
                : string.Join(" ", loadResult.Issues);

            string settingsDirectory = Path.GetDirectoryName(SettingsStore.SettingsPath)
                ?? throw new InvalidOperationException("설정 폴더를 확인할 수 없습니다.");
            _restoreJournal = new PetRestoreJournal(
                Path.Combine(settingsDirectory, "pet-restore-journal.json"));
            SafeStartRecovery = _restoreJournal.Load();
            _instanceManager = new PetInstanceManager(
                ResolvePackage,
                _monitorPlacement,
                _restoreJournal);
            _instanceManager.StateChanged += InstanceManager_StateChanged;
            _instanceManager.OverlayChanged += InstanceManager_OverlayChanged;
            if (SafeStartRecovery is null)
            {
                SynchronizePetInstances();
            }
            else
            {
                SettingsStatusMessage = "이전 실행이 펫 복원 중 종료되어 안전 시작으로 열었습니다.";
            }
            _resourceMonitor = new PetResourceMonitor(() =>
                _instanceManager?.Snapshots ?? []);
            _resourceMonitor.WarningChanged += ResourceMonitor_WarningChanged;
            _resourceMonitor.Start();
        }
        catch (Exception exception)
        {
            OverlayInitializationError = exception.Message;
        }
    }

    private void ActivateInstalledPackage(InstalledPetPackage installed)
    {
        Guid instanceId = CurrentSettings.SelectedPetInstanceId;
        CurrentSettings = ActivePetSettingsEditor.ReplacePet(
            CurrentSettings,
            instanceId,
            new PetBehaviorKey.Installed(installed.InstallationId));
        SettingsStore.Save(CurrentSettings);
        _instanceManager?.InvalidateInstance(instanceId);
        SynchronizePetInstances();
        SettingsStateChanged?.Invoke(this, EventArgs.Empty);
    }

    private void ActivateBundledSample()
    {
        Guid instanceId = CurrentSettings.SelectedPetInstanceId;
        CurrentSettings = ActivePetSettingsEditor.ReplacePet(
            CurrentSettings,
            instanceId,
            PetBehaviorKey.BuiltInKey);
        SettingsStore.Save(CurrentSettings);
        _instanceManager?.InvalidateInstance(instanceId);
        SynchronizePetInstances();
        SettingsStateChanged?.Invoke(this, EventArgs.Empty);
    }

    private LoadedPetPackage LoadBundledSample() =>
        new PetPackageLoader().LoadDirectory(BundledSamplePath);

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
        ActivePetSnapshots.Select(snapshot =>
        {
            ActivePetInstance? instance = CurrentSettings.ActivePetInstances.FirstOrDefault(value =>
                value.InstanceId == snapshot.InstanceId);
            return new NotificationAreaPetState(
                snapshot.InstanceId,
                snapshot.DisplayName,
                snapshot.Presentation == PetPresentation.Awake,
                instance?.Overlay.ClickThrough ?? false,
                snapshot.InstanceId == CurrentSettings.SelectedPetInstanceId);
        }).ToList(),
        AreAllPetsPaused,
        ResourceWarning is not null,
        SafeStartRecovery is not null);

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

    private void HandleNotificationAreaCommand(NotificationAreaMenuItem item)
    {
        NotificationAreaCommand command = item.Command
            ?? throw new ArgumentException("notification area 명령이 없습니다.", nameof(item));
        Guid? instanceId = item.InstanceId;
        switch (command)
        {
            case NotificationAreaCommand.WakeAllPets:
                SetAllPetPresentations(PetPresentation.Awake);
                break;
            case NotificationAreaCommand.TuckAwayAllPets:
                SetAllPetPresentations(PetPresentation.TuckedAway);
                break;
            case NotificationAreaCommand.ToggleAllPetsPaused:
                ToggleAllPetsPaused();
                break;
            case NotificationAreaCommand.SelectPet:
                SelectPetInstance(RequiredInstanceId(instanceId));
                ShowSettings();
                break;
            case NotificationAreaCommand.TogglePetAwake:
                Guid presentationInstanceId = RequiredInstanceId(instanceId);
                ActivePetInstance presentationInstance = CurrentSettings.ActivePetInstances.Single(value =>
                    value.InstanceId == presentationInstanceId);
                CurrentSettings = ActivePetSettingsEditor.SetPresentation(
                    CurrentSettings,
                    presentationInstanceId,
                    presentationInstance.Presentation == PetPresentation.Awake
                        ? PetPresentation.TuckedAway
                        : PetPresentation.Awake);
                SettingsStore.Save(CurrentSettings);
                SynchronizePetInstances();
                SettingsStateChanged?.Invoke(this, EventArgs.Empty);
                break;
            case NotificationAreaCommand.ToggleClickThrough:
                Guid clickInstanceId = RequiredInstanceId(instanceId);
                ActivePetInstance clickInstance = CurrentSettings.ActivePetInstances.Single(value =>
                    value.InstanceId == clickInstanceId);
                CurrentSettings = ActivePetSettingsEditor.SetOverlay(
                    CurrentSettings,
                    clickInstanceId,
                    clickInstance.Overlay with
                {
                    ClickThrough = !clickInstance.Overlay.ClickThrough,
                });
                SettingsStore.Save(CurrentSettings);
                SynchronizePetInstances();
                SettingsStateChanged?.Invoke(this, EventArgs.Empty);
                break;
            case NotificationAreaCommand.BringPetToCurrentScreen:
                Guid bringInstanceId = RequiredInstanceId(instanceId);
                OverlaySettings overlay = _instanceManager?.BringToCurrentScreen(bringInstanceId)
                    ?? throw new InvalidOperationException("활성 펫 런타임을 찾지 못했습니다.");
                CurrentSettings = ActivePetSettingsEditor.SetOverlay(
                    CurrentSettings,
                    bringInstanceId,
                    overlay);
                SettingsStore.Save(CurrentSettings);
                SynchronizePetInstances();
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

    private Guid RequiredInstanceId(Guid? instanceId) => instanceId is Guid id && id != Guid.Empty
        ? id
        : CurrentSettings.SelectedPetInstanceId;

    private void NotificationArea_ErrorOccurred(
        object? sender,
        NotificationAreaErrorEventArgs e)
    {
        SettingsStatusMessage = e.Exception.Message;
        SettingsStateChanged?.Invoke(this, EventArgs.Empty);
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

    private LoadedPetPackage ResolvePackage(PetBehaviorKey key) => key switch
    {
        PetBehaviorKey.BuiltIn => LoadBundledSample(),
        PetBehaviorKey.Installed installed =>
            PetLibrary.GetInstallation(installed.InstallationId).Package,
        _ => throw new InvalidOperationException("지원하지 않는 펫 식별자입니다."),
    };

    private void ScheduleSelectedPetSave()
    {
        if (_selectionSaveTimer is null)
        {
            Microsoft.UI.Dispatching.DispatcherQueue dispatcher =
                Microsoft.UI.Dispatching.DispatcherQueue.GetForCurrentThread();
            _selectionSaveTimer = dispatcher.CreateTimer();
            _selectionSaveTimer.IsRepeating = false;
            _selectionSaveTimer.Interval = TimeSpan.FromMilliseconds(180);
            _selectionSaveTimer.Tick += SelectionSaveTimer_Tick;
        }

        _selectionSaveTimer.Stop();
        _selectionSaveTimer.Start();
    }

    private void SelectionSaveTimer_Tick(
        Microsoft.UI.Dispatching.DispatcherQueueTimer sender,
        object args)
    {
        sender.Stop();
        try
        {
            SettingsStore.Save(CurrentSettings);
        }
        catch (Exception exception)
        {
            SettingsStatusMessage = $"선택한 펫을 저장하지 못했습니다. {exception.Message}";
            SettingsStateChanged?.Invoke(this, EventArgs.Empty);
        }
    }

    private void FlushSelectedPetSave()
    {
        if (_selectionSaveTimer?.IsRunning != true)
        {
            return;
        }

        _selectionSaveTimer.Stop();
        try
        {
            SettingsStore.Save(CurrentSettings);
        }
        catch
        {
            // The app is already closing; the previous atomic settings file remains valid.
        }
    }

    private void SynchronizePetInstances(ISet<Guid>? excludedInstanceIds = null)
    {
        if (_instanceManager is null || SafeStartRecovery is not null)
        {
            return;
        }
        var excluded = new HashSet<Guid>(_sessionExcludedInstanceIds);
        if (excludedInstanceIds is not null)
        {
            excluded.UnionWith(excludedInstanceIds);
        }
        _instanceManager.Synchronize(CurrentSettings, excluded);
        Overlay = _instanceManager.SelectedContext?.Overlay;
        if (_instanceManager.RestoreIssues.Count > 0)
        {
            SettingsStatusMessage = string.Join(
                " ",
                _instanceManager.RestoreIssues.Select(issue =>
                    $"펫 {issue.InstanceId:D} 복원 실패: {issue.Message}"));
        }
        RefreshNotificationArea();
        BehaviorStateChanged?.Invoke(this, EventArgs.Empty);
        MovementStateChanged?.Invoke(this, EventArgs.Empty);
    }

    private void InstanceManager_StateChanged(object? sender, EventArgs e)
    {
        Overlay = _instanceManager?.SelectedContext?.Overlay;
        BehaviorStateChanged?.Invoke(this, EventArgs.Empty);
        MovementStateChanged?.Invoke(this, EventArgs.Empty);
    }

    private void InstanceManager_OverlayChanged(
        object? sender,
        PetOverlayChangedEventArgs e)
    {
        try
        {
            if (!SettingsStore.IsWritingEnabled)
            {
                return;
            }
            CurrentSettings = ActivePetSettingsEditor.SetOverlay(
                CurrentSettings,
                e.InstanceId,
                e.Overlay);
            SettingsStore.Save(CurrentSettings);
            SettingsStateChanged?.Invoke(this, EventArgs.Empty);
        }
        catch (Exception exception)
        {
            SettingsStatusMessage = $"펫 위치를 저장하지 못했습니다: {exception.Message}";
            SettingsStateChanged?.Invoke(this, EventArgs.Empty);
        }
    }

    private void ResourceMonitor_WarningChanged(object? sender, EventArgs e)
    {
        RefreshNotificationArea();
        SettingsStateChanged?.Invoke(this, EventArgs.Empty);
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
