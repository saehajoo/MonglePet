import AppKit

@MainActor
final class AppCoordinator: NSObject {
    private let settingsSession: AppSettingsSession
    private let petLibrarySession: PetLibrarySession
    private let loginLaunchSettings: LoginLaunchSettings
    private let settingsWindowController: SettingsWindowController
    private let petWindowController: PetWindowController
    private let playbackCoordinator: PetPlaybackCoordinator
    private let behaviorRuntime: PetBehaviorRuntime
    private let movementController: PetMovementController
    private let movementLifecycle: PetMovementLifecycle
    private let activityMonitor: any ActivitySnapshotMonitoring
    private let workspaceNotificationCenter: NotificationCenter
    private let reduceMotionProvider: () -> Bool
    private var menuBarController: MenuBarController?
    private var hasAppliedSettings = false
    private(set) var latestActivitySnapshot: ActivitySnapshot?
    private(set) var latestMovementActivity = PetMovementActivity.stationary

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
        let petWindowController = PetWindowController()
        let petLibrarySession = PetLibrarySession(
            store: petLibraryStore,
            builtInDefinition: petWindowController.petDefinition
        )
        let movementController = PetMovementController(
            originProvider: { [weak petWindowController] in
                petWindowController?.movementOrigin
            },
            petSizeProvider: { [weak petWindowController] in
                petWindowController?.movementSize
            },
            applyOrigin: { [weak petWindowController] origin in
                petWindowController?.setMovementOrigin(origin)
            },
            movementBoundaryProvider: { [weak settingsSession] in
                settingsSession?.settings.overlay.movementBoundary ?? .default
            }
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
        self.petWindowController = petWindowController
        let playbackCoordinator = PetPlaybackCoordinator(
            petDefinition: petWindowController.petDefinition
        ) { [weak petWindowController] playback in
            petWindowController?.setScheduledMotion(playback)
        }
        self.playbackCoordinator = playbackCoordinator
        behaviorRuntime = PetBehaviorRuntime(
            petDefinition: petWindowController.petDefinition
        ) { [weak playbackCoordinator] playback in
            playbackCoordinator?.setBehaviorPlayback(playback)
        }
        self.movementController = movementController
        movementLifecycle = PetMovementLifecycle(controller: movementController)
        self.activityMonitor = activityMonitor
        self.workspaceNotificationCenter = workspaceNotificationCenter
        self.reduceMotionProvider = reduceMotionProvider

        super.init()

        movementController.setActivityChangeHandler { [weak self] activity in
            self?.latestMovementActivity = activity
            self?.playbackCoordinator.setMovementActivity(activity)
        }

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
        petWindowController.onOverlayGeometryDidChange = { [weak self] in
            self?.persistCurrentOverlayGeometry()
        }
        petWindowController.onUserDragStateDidChange = { [weak self] isDragging in
            self?.movementLifecycle.setUserDragging(isDragging)
        }
        petWindowController.onMovementEnvironmentDidChange = { [weak self] in
            self?.movementEnvironmentDidChange()
        }
        petWindowController.onPettingRequested = { [weak self] in
            self?.pettingDidRequest()
        }
    }

    var currentSettings: AppSettings {
        settingsSession.settings
    }

    var isPetAwake: Bool {
        petWindowController.isAwake
    }

    var currentMotionID: String? {
        petWindowController.currentMotionID
    }

    var isPetMovementAllowed: Bool {
        movementLifecycle.isMovementAllowed
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
        movementLifecycle.setReduceMotion(shouldReduceMotion)
        petWindowController.setReduceMotion(shouldReduceMotion)

        let loadResult = settingsSession.load { [petLibrarySession] installationID in
            _ = petLibrarySession.reload(
                preferredInstallationID: installationID
            )
            return petLibrarySession.selectedItem.definition
        }
        settingsSession.ensureSystemDefaultBehavior()
        var effectiveInstallationID = petLibrarySession.reload(
            preferredInstallationID: settingsSession.settings.selectedPetInstallationID
        )
        if !applySelectedPet(petLibrarySession.selectedItem) {
            _ = petLibrarySession.select(.builtIn)
            effectiveInstallationID = nil
        }
        if effectiveInstallationID != settingsSession.settings.selectedPetInstallationID {
            settingsSession.setSelectedPetInstallationID(effectiveInstallationID)
        }
        apply(
            settings: settingsSession.settings,
            restorePosition: loadResult.shouldRestoreOverlayPosition
        )
        activityMonitor.start { [weak self] snapshot in
            self?.activitySnapshotDidChange(snapshot)
        }
        let menuBarController = MenuBarController(
            isPetAwake: petWindowController.isAwake,
            onTogglePetAwakeState: { [weak self] in
                self?.togglePetAwakeState()
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
        behaviorRuntime.stop()
        movementLifecycle.setAwake(false)
        movementLifecycle.setSystemSuspended(true)
        movementLifecycle.stop()
        menuBarController?.stop()
        menuBarController = nil
        petWindowController.sleep()
    }

    private func togglePetAwakeState() {
        if petWindowController.isAwake {
            settingsSession.setUserPresentation(.tuckedAway)
        } else {
            settingsSession.setUserPresentation(.awake)
        }
    }

    private func activitySnapshotDidChange(_ snapshot: ActivitySnapshot) {
        latestActivitySnapshot = snapshot
        petWindowController.setSystemSuspended(
            snapshot.isScreenLocked || snapshot.isSystemSleeping
        )
        movementLifecycle.setSystemSuspended(
            snapshot.isScreenLocked || snapshot.isSystemSleeping
        )
        behaviorRuntime.update(
            settings: settingsSession.settings,
            snapshot: snapshot
        )
    }

    private func settingsDidChange(_ settings: AppSettings) {
        if settings.selectedPetInstallationID != petLibrarySession.selectedInstallationID {
            let effectiveInstallationID = petLibrarySession.reload(
                preferredInstallationID: settings.selectedPetInstallationID
            )
            if !applySelectedPet(petLibrarySession.selectedItem) {
                _ = petLibrarySession.select(.builtIn)
                return
            }
            if effectiveInstallationID != settings.selectedPetInstallationID {
                settingsSession.setSelectedPetInstallationID(effectiveInstallationID)
                return
            }
        }
        apply(settings: settings, restorePosition: true)
        guard let latestActivitySnapshot else {
            return
        }
        behaviorRuntime.update(
            settings: settingsSession.settings,
            snapshot: latestActivitySnapshot
        )
    }

    private func selectedPetDidChange(_ item: PetLibraryItem) {
        guard applySelectedPet(item) else {
            _ = petLibrarySession.select(.builtIn)
            return
        }
        guard
            settingsSession.settings.selectedPetInstallationID
                != item.selection.installationID
        else {
            return
        }
        settingsSession.setSelectedPetInstallationID(item.selection.installationID)
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

    private func pettingDidRequest() {
        guard
            let motionID = settingsSession.settings.pettingMotionID,
            petLibrarySession.selectedItem.definition.motion(id: motionID) != nil
        else {
            return
        }
        behaviorRuntime.triggerInteraction(motionID: motionID)
    }

    @discardableResult
    private func applySelectedPet(_ item: PetLibraryItem) -> Bool {
        do {
            try petWindowController.applyPet(item)
            playbackCoordinator.replacePetDefinition(item.definition)
            behaviorRuntime.replacePetDefinition(item.definition)
            if let latestActivitySnapshot {
                behaviorRuntime.update(
                    settings: settingsSession.settings,
                    snapshot: latestActivitySnapshot
                )
            }
            movementLifecycle.invalidateEnvironment()
            return true
        } catch {
            return false
        }
    }

    private func apply(settings: AppSettings, restorePosition: Bool) {
        let shouldRestorePosition = restorePosition
            && (!hasAppliedSettings || settings.movementSettings.mode == .fixed)
        petWindowController.applyOverlaySettings(
            settings.overlay,
            restorePosition: shouldRestorePosition
        )
        hasAppliedSettings = true

        switch settings.lastUserPresentation {
        case .awake:
            if !petWindowController.isAwake {
                petWindowController.wake()
            }
        case .tuckedAway:
            if petWindowController.isAwake {
                petWindowController.sleep()
            }
        case .suspended:
            break
        }
        movementLifecycle.setSettings(settings.movementSettings)
        movementLifecycle.setAwake(petWindowController.isAwake)
        movementLifecycle.invalidateEnvironment()
        if settings.movementSettings.mode == .fixed,
           let appliedOverlay = petWindowController.currentOverlaySettings() {
            settingsSession.synchronizeOverlayGeometry(appliedOverlay)
        }
        menuBarController?.setPetAwake(petWindowController.isAwake)
    }

    private func persistCurrentOverlayGeometry() {
        guard let overlay = petWindowController.currentOverlaySettings() else {
            return
        }
        settingsSession.setOverlayGeometry(overlay)
    }

    private func movementEnvironmentDidChange() {
        movementLifecycle.invalidateEnvironment()
        guard settingsSession.settings.movementSettings.mode == .fixed else {
            return
        }
        persistCurrentOverlayGeometry()
    }

    @objc
    private func accessibilityDisplayOptionsDidChange(
        _ notification: Notification
    ) {
        let shouldReduceMotion = reduceMotionProvider()
        movementLifecycle.setReduceMotion(shouldReduceMotion)
        petWindowController.setReduceMotion(shouldReduceMotion)
    }
}
