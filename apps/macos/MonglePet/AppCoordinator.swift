import AppKit

@MainActor
final class AppCoordinator: NSObject {
    private let settingsSession: AppSettingsSession
    private let petLibrarySession: PetLibrarySession
    private let loginLaunchSettings: LoginLaunchSettings
    private let settingsWindowController: SettingsWindowController
    private let petInstanceManager: PetInstanceManager
    private let activityMonitor: any ActivitySnapshotMonitoring
    private let desktopEnvironmentMonitor: PetDesktopEnvironmentMonitor
    private let presentationResourceCache: PetPresentationResourceCache
    private let runtimeControlSession: PetRuntimeControlSession
    private let remotePetImportRequestCenter: RemotePetImportRequestCenter
    private let startupRecoveryStore: any PetStartupRecoveryStoring
    private let startupRestorer: PetStartupRestorer
    private let workspaceNotificationCenter: NotificationCenter
    private let reduceMotionProvider: () -> Bool
    private var menuBarController: MenuBarController?
    private var resourceMonitor: PetResourceMonitor!
    private var limitedRestoredInstanceIDs: Set<UUID>?
    private var pendingRecoveryInstanceID: UUID?
    private var isUserRequestedSafeMode = false
    private(set) var latestActivitySnapshot: ActivitySnapshot?

    var latestMovementActivity: PetMovementActivity {
        petInstanceManager.selectedContext?.latestMovementActivity
            ?? .stationary
    }

    init(
        settingsStore: AppSettingsStore,
        petLibraryStore: PetLibraryStore,
        activityMonitor: any ActivitySnapshotMonitoring = ActivitySnapshotMonitor(),
        desktopEnvironmentMonitor: PetDesktopEnvironmentMonitor =
            PetDesktopEnvironmentMonitor(),
        presentationResourceCache: PetPresentationResourceCache =
            PetPresentationResourceCache(),
        runtimeControlSession: PetRuntimeControlSession? = nil,
        startupRecoveryStore: (any PetStartupRecoveryStoring)? = nil,
        resourceSampler: any PetProcessResourceSampling =
            SystemPetProcessResourceSampler(),
        workspaceNotificationCenter: NotificationCenter =
            NSWorkspace.shared.notificationCenter,
        reduceMotionProvider: @escaping () -> Bool = {
            NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        }
    ) {
        let settingsSession = AppSettingsSession(store: settingsStore)
        let frontmostWindowProvider = FrontmostWindowProvider(
            displayLayoutProvider: { [weak desktopEnvironmentMonitor] in
                desktopEnvironmentMonitor?.currentSnapshot.displayLayout
            }
        )
        let bootstrapWindowController = PetWindowController(
            environmentProvider: desktopEnvironmentMonitor,
            resourceCache: presentationResourceCache
        )
        let petLibrarySession = PetLibrarySession(
            store: petLibraryStore,
            builtInDefinition: bootstrapWindowController.petDefinition
        )
        self.settingsSession = settingsSession
        self.petLibrarySession = petLibrarySession
        self.desktopEnvironmentMonitor = desktopEnvironmentMonitor
        self.presentationResourceCache = presentationResourceCache
        let effectiveRuntimeControlSession = runtimeControlSession
            ?? PetRuntimeControlSession()
        self.runtimeControlSession = effectiveRuntimeControlSession
        let effectiveRecoveryStore = startupRecoveryStore
            ?? PetStartupRecoveryStore(
                journalURL: PetStartupRecoveryStore.journalURL(
                    for: settingsStore.settingsURL
                )
            )
        self.startupRecoveryStore = effectiveRecoveryStore
        startupRestorer = PetStartupRestorer(
            recoveryStore: effectiveRecoveryStore
        )
        let loginLaunchSettings = LoginLaunchSettings()
        self.loginLaunchSettings = loginLaunchSettings
        let remotePetImportRequestCenter = RemotePetImportRequestCenter()
        self.remotePetImportRequestCenter = remotePetImportRequestCenter
        settingsWindowController = SettingsWindowController(
            settingsSession: settingsSession,
            petLibrarySession: petLibrarySession,
            loginLaunchSettings: loginLaunchSettings,
            runtimeControlSession: effectiveRuntimeControlSession,
            remotePetImportRequestCenter: remotePetImportRequestCenter
        )
        var availableBootstrapController: PetWindowController? =
            bootstrapWindowController
        petInstanceManager = PetInstanceManager { [weak settingsSession] instanceID in
            let windowController = availableBootstrapController
                ?? PetWindowController(
                    environmentProvider: desktopEnvironmentMonitor,
                    resourceCache: presentationResourceCache
                )
            availableBootstrapController = nil
            return PetRuntimeContext(
                instanceID: instanceID,
                petWindowController: windowController,
                environmentProvider: desktopEnvironmentMonitor,
                frontmostWindowProvider: frontmostWindowProvider,
                onOverlayGeometryDidChange: {
                    [weak settingsSession] instanceID, overlay in
                    settingsSession?.setOverlayGeometry(
                        overlay,
                        for: instanceID
                    )
                },
                onOverlayGeometryDidSynchronize: {
                    [weak settingsSession] instanceID, overlay in
                    settingsSession?.synchronizeOverlayGeometry(
                        overlay,
                        for: instanceID
                    )
                }
            )
        }
        self.activityMonitor = activityMonitor
        self.workspaceNotificationCenter = workspaceNotificationCenter
        self.reduceMotionProvider = reduceMotionProvider

        super.init()

        resourceMonitor = PetResourceMonitor(
            sampler: resourceSampler,
            runtimeCountsProvider: { [weak self] in
                guard let self else {
                    return (0, 0)
                }
                let statuses = self.petInstanceManager.runtimeStatuses
                return (
                    statuses.count,
                    statuses.filter {
                        $0.movementActivity.isMoving
                    }.count
                )
            },
            onWarningChange: { [weak self] warning in
                self?.resourceWarningDidChange(warning)
            }
        )

        settingsSession.onChange = { [weak self] settings in
            self?.settingsDidChange(settings)
        }
        petLibrarySession.onSelectionChange = { [weak self] item in
            self?.selectedPetDidChange(item)
        }
        petLibrarySession.onInstallationRemoved = { [weak self] installationID in
            self?.installedPetDidRemove(installationID)
        }
        petLibrarySession.onAnimationReferenceChange = { [weak self] change in
            self?.petAnimationReferencesDidChange(change)
        }
        petLibrarySession.onRecommendedProfileApplied = {
            [weak settingsSession] installationID, profile in
            _ = settingsSession?.applyRecommendedProfile(
                profile,
                to: installationID
            )
        }
        effectiveRuntimeControlSession.onSetAllPaused = {
            [weak self] isPaused in
            self?.setAllPetsPaused(isPaused)
        }
        effectiveRuntimeControlSession.onRestoreInstance = {
            [weak self] instanceID in
            self?.restoreInstance(instanceID)
        }
        effectiveRuntimeControlSession.onRestoreAll = { [weak self] in
            self?.restoreAllInstances()
        }
        effectiveRuntimeControlSession.onRestoreAllExceptPending = {
            [weak self] in
            self?.restoreAllExceptPendingInstance()
        }
    }

    var currentSettings: AppSettings {
        settingsSession.settings
    }

    var isPetAwake: Bool {
        petInstanceManager.selectedContext?.isAwake ?? false
    }

    var currentMotionID: String? {
        petInstanceManager.selectedContext?.currentMotionID
    }

    var isPetMovementAllowed: Bool {
        petInstanceManager.selectedContext?.isMovementAllowed ?? false
    }

    var activePetInstanceIDs: [UUID] {
        petInstanceManager.activeInstanceIDs
    }

    var awakePetInstanceIDs: [UUID] {
        petInstanceManager.activeInstanceIDs.filter {
            petInstanceManager.context(for: $0)?.isAwake == true
        }
    }

    var activePetRuntimeStatuses: [PetRuntimeStatus] {
        petInstanceManager.runtimeStatuses
    }

    func start(openSettingsOnLaunch: Bool = false) {
        guard menuBarController == nil else {
            return
        }

        workspaceNotificationCenter.addObserver(
            self,
            selector: #selector(accessibilityDisplayOptionsDidChange),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil
        )
        let shouldReduceMotion = reduceMotionProvider()
        petInstanceManager.setReduceMotion(shouldReduceMotion)
        desktopEnvironmentMonitor.start { [weak petInstanceManager] in
            petInstanceManager?.desktopEnvironmentDidChange()
        }

        let loadResult = settingsSession.load { [petLibrarySession] installationID in
            _ = petLibrarySession.reload(
                preferredInstallationID: installationID
            )
            return petLibrarySession.selectedItem.definition
        }
        settingsSession.ensureSystemDefaultBehavior()
        let effectiveInstallationID = petLibrarySession.reload(
            preferredInstallationID: settingsSession.settings.selectedPetInstallationID
        )
        if effectiveInstallationID != settingsSession.settings.selectedPetInstallationID {
            settingsSession.setSelectedPetInstallationID(effectiveInstallationID)
        }
        prepareAndRestoreStartupRuntimes(
            shouldRestorePosition: loadResult.shouldRestoreOverlayPosition
        )
        activityMonitor.start { [weak self] snapshot in
            self?.activitySnapshotDidChange(snapshot)
        }
        let menuBarController = MenuBarController(
            pets: menuBarPetStates(for: settingsSession.settings),
            onSelectPet: { [weak settingsSession] instanceID in
                settingsSession?.selectPetInstance(instanceID)
            },
            onSetPetAwake: {
                [weak settingsSession] instanceID, isAwake in
                settingsSession?.setUserPresentation(
                    isAwake ? .awake : .tuckedAway,
                    for: instanceID
                )
            },
            onSetPetClickThrough: {
                [weak settingsSession] instanceID, isEnabled in
                settingsSession?.setClickThrough(
                    isEnabled,
                    for: instanceID
                )
            },
            onBringPetToCurrentScreen: { [weak self] instanceID in
                self?.bringPetToCurrentScreen(instanceID: instanceID)
            },
            onSetAllPetsAwake: { [weak self] isAwake in
                self?.setAllPetsAwake(isAwake)
            },
            isAllPaused: runtimeControlSession.isAllPaused,
            resourceWarning: runtimeControlSession.resourceWarning,
            onSetAllPetsPaused: { [weak self] isPaused in
                self?.setAllPetsPaused(isPaused)
            },
            onEnterSafeMode: { [weak self] in
                self?.enterSafeMode()
            },
            onOpenSettings: { [weak self] in
                self?.settingsWindowController.show()
            },
            onQuit: {
                NSApplication.shared.terminate(nil)
            }
        )
        menuBarController.start()
        self.menuBarController = menuBarController

        resourceMonitor.updateActivePetCount(
            petInstanceManager.activeInstanceIDs.count
        )

        if openSettingsOnLaunch || pendingRecoveryInstanceID != nil {
            settingsWindowController.show()
        }
    }

    func stop() {
        workspaceNotificationCenter.removeObserver(
            self,
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil
        )
        activityMonitor.stop()
        resourceMonitor.stop()
        desktopEnvironmentMonitor.stop()
        petInstanceManager.stopAll()
        presentationResourceCache.removeReleasedEntries()
        menuBarController?.stop()
        menuBarController = nil
    }

    func openExternalURLs(_ urls: [URL]) {
        guard let url = urls.last else {
            return
        }
        settingsWindowController.show()
        remotePetImportRequestCenter.submit(deepLinkURL: url)
    }

    private func setAllPetsAwake(_ isAwake: Bool) {
        let presentation: PetPresentation = isAwake
            ? .awake
            : .tuckedAway
        for instance in settingsSession.settings.activePetInstances {
            settingsSession.setUserPresentation(
                presentation,
                for: instance.instanceID
            )
        }
    }

    private func setAllPetsPaused(_ isPaused: Bool) {
        petInstanceManager.setAllPaused(isPaused)
        runtimeControlSession.updateAllPaused(isPaused)
        menuBarController?.setRuntimeState(
            isAllPaused: isPaused,
            resourceWarning: runtimeControlSession.resourceWarning
        )
    }

    private func prepareAndRestoreStartupRuntimes(
        shouldRestorePosition: Bool
    ) {
        let orderedIDs = orderedInstanceIDs
        if let record = startupRecoveryStore.pendingRecord(),
           orderedIDs.contains(record.restoringInstanceID) {
            pendingRecoveryInstanceID = record.restoringInstanceID
            isUserRequestedSafeMode = record.reason == .userRequestedSafeMode
            limitedRestoredInstanceIDs = []
            updateRuntimeControlState()
            return
        }

        try? startupRecoveryStore.clear()
        pendingRecoveryInstanceID = nil
        isUserRequestedSafeMode = false
        limitedRestoredInstanceIDs = []
        restoreStepwise(
            instanceIDs: orderedIDs,
            shouldRestorePosition: shouldRestorePosition
        )
        if petInstanceManager.activeInstanceIDs.count == orderedIDs.count {
            limitedRestoredInstanceIDs = nil
        }
        updateRuntimeControlState()
    }

    private func restoreInstance(_ instanceID: UUID) {
        guard
            settingsSession.settings.activePetInstances.contains(where: {
                $0.instanceID == instanceID
            }),
            petInstanceManager.context(for: instanceID) == nil
        else {
            return
        }
        restoreStepwise(
            instanceIDs: [instanceID],
            shouldRestorePosition: true
        )
        if pendingRecoveryInstanceID == instanceID,
           petInstanceManager.context(for: instanceID) != nil {
            pendingRecoveryInstanceID = nil
            isUserRequestedSafeMode = false
            if petInstanceManager.activeInstanceIDs.count
                == orderedInstanceIDs.count {
                limitedRestoredInstanceIDs = nil
            }
            try? startupRecoveryStore.clear()
        }
        updateRuntimeControlState()
    }

    private func restoreAllInstances() {
        let missingIDs = orderedInstanceIDs.filter {
            petInstanceManager.context(for: $0) == nil
        }
        restoreStepwise(
            instanceIDs: missingIDs,
            shouldRestorePosition: true
        )
        pendingRecoveryInstanceID = nil
        isUserRequestedSafeMode = false
        limitedRestoredInstanceIDs = nil
        try? startupRecoveryStore.clear()
        _ = synchronizeActiveRuntimes(
            settings: settingsSession.settings,
            reason: .settingsChange
        )
        updateRuntimeControlState()
    }

    private func restoreAllExceptPendingInstance() {
        guard let pendingRecoveryInstanceID else {
            restoreAllInstances()
            return
        }
        let targetIDs = orderedInstanceIDs.filter {
            $0 != pendingRecoveryInstanceID
                && petInstanceManager.context(for: $0) == nil
        }
        restoreStepwise(
            instanceIDs: targetIDs,
            shouldRestorePosition: true
        )
        updateRuntimeControlState()
    }

    private func enterSafeMode() {
        let pendingID = settingsSession.settings.selectedPetInstanceID
        try? startupRecoveryStore.markSafeMode(pendingID)
        pendingRecoveryInstanceID = pendingID
        isUserRequestedSafeMode = true
        limitedRestoredInstanceIDs = []
        _ = synchronizeActiveRuntimes(
            settings: settingsSession.settings,
            reason: .settingsChange
        )
        setAllPetsPaused(false)
        updateRuntimeControlState()
        settingsWindowController.show()
    }

    private func restoreStepwise(
        instanceIDs: [UUID],
        shouldRestorePosition: Bool
    ) {
        do {
            try startupRestorer.restore(instanceIDs: instanceIDs) {
                [weak self] instanceID in
                guard let self else {
                    return
                }
                var restoredIDs = self.limitedRestoredInstanceIDs
                    ?? Set(self.petInstanceManager.activeInstanceIDs)
                restoredIDs.insert(instanceID)
                self.limitedRestoredInstanceIDs = restoredIDs
                _ = self.synchronizeActiveRuntimes(
                    settings: self.settingsSession.settings,
                    reason: .initialLoad(
                        shouldRestorePosition: shouldRestorePosition
                    )
                )
            }
        } catch {
            if pendingRecoveryInstanceID == nil {
                pendingRecoveryInstanceID = instanceIDs.first(where: {
                    petInstanceManager.context(for: $0) == nil
                })
            }
        }
        if let pendingRecoveryInstanceID,
           petInstanceManager.context(for: pendingRecoveryInstanceID) == nil {
            if isUserRequestedSafeMode {
                try? startupRecoveryStore.markSafeMode(
                    pendingRecoveryInstanceID
                )
            } else {
                try? startupRecoveryStore.markRestoring(
                    pendingRecoveryInstanceID
                )
            }
        }
        resourceMonitor?.updateActivePetCount(
            petInstanceManager.activeInstanceIDs.count
        )
    }

    private var orderedInstanceIDs: [UUID] {
        settingsSession.settings.activePetInstances.sorted {
            $0.displayOrder < $1.displayOrder
        }.map(\.instanceID)
    }

    private func updateRuntimeControlState() {
        runtimeControlSession.updateRecovery(
            pendingInstanceID: pendingRecoveryInstanceID,
            isUserRequestedSafeMode: isUserRequestedSafeMode,
            restoredInstanceIDs: Set(petInstanceManager.activeInstanceIDs)
        )
        resourceMonitor?.updateActivePetCount(
            petInstanceManager.activeInstanceIDs.count
        )
    }

    private func resourceWarningDidChange(
        _ warning: PetResourceWarning?
    ) {
        runtimeControlSession.updateResourceWarning(warning)
        menuBarController?.setRuntimeState(
            isAllPaused: runtimeControlSession.isAllPaused,
            resourceWarning: warning
        )
    }

    private func bringPetToCurrentScreen(instanceID: UUID) {
        let snapshot = desktopEnvironmentMonitor.currentSnapshot
        let targetDisplay = snapshot.pointerLocation.flatMap { pointer in
            snapshot.displays.first { display in
                display.frame.contains(pointer)
            }
        } ?? snapshot.displays.first
        guard let targetDisplay else {
            return
        }

        petInstanceManager.context(for: instanceID)?.moveToVisibleFrame(
            NSRect(
                x: targetDisplay.visibleFrame.minX,
                y: targetDisplay.visibleFrame.minY,
                width: targetDisplay.visibleFrame.size.width,
                height: targetDisplay.visibleFrame.size.height
            )
        )
    }

    private func activitySnapshotDidChange(_ snapshot: ActivitySnapshot) {
        latestActivitySnapshot = snapshot
        petInstanceManager.updateActivitySnapshot(snapshot)
    }

    private func settingsDidChange(_ settings: AppSettings) {
        var shouldRestoreAfterRemovingPending = false
        if let pendingRecoveryInstanceID,
           !settings.activePetInstances.contains(where: {
               $0.instanceID == pendingRecoveryInstanceID
           }) {
            self.pendingRecoveryInstanceID = nil
            isUserRequestedSafeMode = false
            try? startupRecoveryStore.clear()
            shouldRestoreAfterRemovingPending = true
        }
        if settings.selectedPetInstallationID != petLibrarySession.selectedInstallationID {
            let effectiveInstallationID = petLibrarySession.reload(
                preferredInstallationID: settings.selectedPetInstallationID
            )
            if effectiveInstallationID != settings.selectedPetInstallationID {
                _ = petLibrarySession.select(.builtIn)
                settingsSession.setSelectedPetInstallationID(
                    effectiveInstallationID
                )
                return
            }
        }
        if !synchronizeActiveRuntimes(
            settings: settings,
            reason: .settingsChange
        ), settings.selectedPetKey != .builtIn {
            _ = petLibrarySession.select(.builtIn)
        }
        updateRuntimeControlState()
        if shouldRestoreAfterRemovingPending {
            restoreAllInstances()
        }
    }

    private func selectedPetDidChange(_ item: PetLibraryItem) {
        let selectedPetKey = PetBehaviorKey(
            installationID: item.selection.installationID
        )
        let shouldInvalidateResources = item.selection != .builtIn
            && settingsSession.settings.selectedPetKey == selectedPetKey
        if settingsSession.settings.selectedPetKey != selectedPetKey {
            settingsSession.setSelectedPetInstallationID(
                item.selection.installationID
            )
            guard settingsSession.settings.selectedPetKey == selectedPetKey else {
                return
            }
        }

        if shouldInvalidateResources {
            presentationResourceCache.invalidate(item.selection)
        }

        let reloadedInstanceIDs = Set(
            settingsSession.settings.activePetInstances.compactMap {
                $0.petKey == selectedPetKey
                    ? $0.instanceID
                    : nil
            }
        )
        if !synchronizeActiveRuntimes(
            settings: settingsSession.settings,
            reason: .settingsChange,
            reloadPetInstanceIDs: reloadedInstanceIDs
        ), item.selection != .builtIn {
            _ = petLibrarySession.select(.builtIn)
        }
    }

    private func installedPetDidRemove(_ installationID: UUID) {
        presentationResourceCache.invalidate(.installed(installationID))
        _ = settingsSession.removeBehaviorProfile(
            forInstallationID: installationID
        )
    }

    var isDesktopEnvironmentMonitoring: Bool {
        desktopEnvironmentMonitor.isRunning
    }

    var presentationResourceLoadCount: Int {
        presentationResourceCache.resourceLoadCount
    }

    private func petAnimationReferencesDidChange(
        _ change: PetAnimationReferenceChange
    ) {
        switch change {
        case let .renamed(oldMotionID, newMotionID):
            _ = settingsSession.renameMotionReferences(
                from: oldMotionID,
                to: newMotionID
            )
        case let .removed(motionID):
            _ = settingsSession.removeMotionReferences(motionID)
        }
    }

    @discardableResult
    private func synchronizeActiveRuntimes(
        settings: AppSettings,
        reason: PetOverlayApplicationReason,
        reloadPetInstanceIDs: Set<UUID> = []
    ) -> Bool {
        do {
            let result = try petInstanceManager.synchronizeActiveRuntimes(
                settings: settings,
                itemProvider: { [petLibrarySession] petKey in
                    petLibrarySession.item(for: petKey)
                },
                reason: reason,
                reloadPetInstanceIDs: reloadPetInstanceIDs,
                restoringInstanceIDs: limitedRestoredInstanceIDs
            )
            menuBarController?.setPets(
                menuBarPetStates(for: settings)
            )
            return !result.unavailableInstanceIDs.contains(
                settings.selectedPetInstanceID
            )
        } catch {
            return false
        }
    }

    private func menuBarPetStates(
        for settings: AppSettings
    ) -> [MenuBarPetState] {
        settings.activePetInstances.sorted {
            $0.displayOrder < $1.displayOrder
        }.map { instance in
            let item = petLibrarySession.item(for: instance.petKey)
            return MenuBarPetState(
                instanceID: instance.instanceID,
                displayName: instance.nickname
                    ?? item?.metadata.displayName
                    ?? "사용할 수 없는 펫",
                isAwake: instance.presentation == .awake,
                isClickThrough: instance.overlay.clickThrough,
                isSelected: instance.instanceID
                    == settings.selectedPetInstanceID
            )
        }
    }

    @objc
    private func accessibilityDisplayOptionsDidChange(
        _ notification: Notification
    ) {
        let shouldReduceMotion = reduceMotionProvider()
        petInstanceManager.setReduceMotion(shouldReduceMotion)
    }
}
