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
    private let workspaceNotificationCenter: NotificationCenter
    private let reduceMotionProvider: () -> Bool
    private var menuBarController: MenuBarController?
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
        let loginLaunchSettings = LoginLaunchSettings()
        self.loginLaunchSettings = loginLaunchSettings
        settingsWindowController = SettingsWindowController(
            settingsSession: settingsSession,
            petLibrarySession: petLibrarySession,
            loginLaunchSettings: loginLaunchSettings
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
        let instanceIDs = Set(
            settingsSession.settings.activePetInstances.map(\.instanceID)
        )
        if !synchronizeActiveRuntimes(
            settings: settingsSession.settings,
            reason: .initialLoad(
                shouldRestorePosition:
                    loadResult.shouldRestoreOverlayPosition
            ),
            reloadPetInstanceIDs: instanceIDs
        ), settingsSession.settings.selectedPetKey != .builtIn {
            _ = petLibrarySession.select(.builtIn)
        }
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
            onOpenSettings: { [weak self] in
                self?.settingsWindowController.show()
            },
            onQuit: {
                NSApplication.shared.terminate(nil)
            }
        )
        menuBarController.start()
        self.menuBarController = menuBarController

        if openSettingsOnLaunch {
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
        desktopEnvironmentMonitor.stop()
        petInstanceManager.stopAll()
        presentationResourceCache.removeReleasedEntries()
        menuBarController?.stop()
        menuBarController = nil
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
                reloadPetInstanceIDs: reloadPetInstanceIDs
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
