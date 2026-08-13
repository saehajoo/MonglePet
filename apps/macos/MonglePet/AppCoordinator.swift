import AppKit

@MainActor
final class AppCoordinator: NSObject {
    private let settingsSession: AppSettingsSession
    private let petLibrarySession: PetLibrarySession
    private let loginLaunchSettings: LoginLaunchSettings
    private let settingsWindowController: SettingsWindowController
    private let petInstanceManager: PetInstanceManager
    private let activityMonitor: any ActivitySnapshotMonitoring
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
        workspaceNotificationCenter: NotificationCenter =
            NSWorkspace.shared.notificationCenter,
        reduceMotionProvider: @escaping () -> Bool = {
            NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        }
    ) {
        let settingsSession = AppSettingsSession(store: settingsStore)
        let bootstrapWindowController = PetWindowController()
        let petLibrarySession = PetLibrarySession(
            store: petLibraryStore,
            builtInDefinition: bootstrapWindowController.petDefinition
        )
        self.settingsSession = settingsSession
        self.petLibrarySession = petLibrarySession
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
                ?? PetWindowController()
            availableBootstrapController = nil
            return PetRuntimeContext(
                instanceID: instanceID,
                petWindowController: windowController,
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
            isPetAwake: isPetAwake,
            petDisplayName: petLibrarySession.selectedItem.metadata.displayName,
            isClickThrough: settingsSession.settings.overlay.clickThrough,
            onTogglePetAwakeState: { [weak self] in
                self?.togglePetAwakeState()
            },
            onSetClickThrough: { [weak settingsSession] isEnabled in
                settingsSession?.setClickThrough(isEnabled)
            },
            onBringPetToCurrentScreen: { [weak self] in
                self?.bringPetToCurrentScreen()
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
        petInstanceManager.stopAll()
        menuBarController?.stop()
        menuBarController = nil
    }

    private func togglePetAwakeState() {
        if isPetAwake {
            settingsSession.setUserPresentation(.tuckedAway)
        } else {
            settingsSession.setUserPresentation(.awake)
        }
    }

    private func bringPetToCurrentScreen() {
        let mouseLocation = NSEvent.mouseLocation
        guard
            let targetScreen = NSScreen.screens.first(where: {
                $0.frame.contains(mouseLocation)
            }) ?? NSScreen.main ?? NSScreen.screens.first
        else {
            return
        }

        petInstanceManager.selectedContext?.moveToVisibleFrame(
            targetScreen.visibleFrame
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
        if settingsSession.settings.selectedPetKey != selectedPetKey {
            settingsSession.setSelectedPetInstallationID(
                item.selection.installationID
            )
            guard settingsSession.settings.selectedPetKey == selectedPetKey else {
                return
            }
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
        _ = settingsSession.removeBehaviorProfile(
            forInstallationID: installationID
        )
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
            let selectedItem = petLibrarySession.item(
                for: settings.selectedPetKey
            ) ?? petLibrarySession.selectedItem
            menuBarController?.setCurrentPetDisplayName(
                selectedItem.metadata.displayName
            )
            menuBarController?.setPetAwake(isPetAwake)
            menuBarController?.setClickThrough(
                settings.overlay.clickThrough
            )
            return !result.unavailableInstanceIDs.contains(
                settings.selectedPetInstanceID
            )
        } catch {
            return false
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
