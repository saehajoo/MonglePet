import AppKit

@MainActor
final class AppCoordinator {
    private let settingsSession: AppSettingsSession
    private let petLibrarySession: PetLibrarySession
    private let settingsWindowController: SettingsWindowController
    private let petWindowController: PetWindowController
    private let behaviorRuntime: PetBehaviorRuntime
    private let activityMonitor: any ActivitySnapshotMonitoring
    private var menuBarController: MenuBarController?
    private(set) var latestActivitySnapshot: ActivitySnapshot?

    init(
        settingsStore: AppSettingsStore,
        petLibraryStore: PetLibraryStore,
        activityMonitor: any ActivitySnapshotMonitoring = ActivitySnapshotMonitor()
    ) {
        let settingsSession = AppSettingsSession(store: settingsStore)
        let petWindowController = PetWindowController()
        let petLibrarySession = PetLibrarySession(
            store: petLibraryStore,
            builtInDefinition: petWindowController.petDefinition
        )
        self.settingsSession = settingsSession
        self.petLibrarySession = petLibrarySession
        settingsWindowController = SettingsWindowController(
            settingsSession: settingsSession,
            petLibrarySession: petLibrarySession
        )
        self.petWindowController = petWindowController
        behaviorRuntime = PetBehaviorRuntime(
            petDefinition: petWindowController.petDefinition
        ) { [weak petWindowController] playback in
            petWindowController?.setScheduledMotion(playback)
        }
        self.activityMonitor = activityMonitor

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
        petWindowController.onOverlayGeometryDidChange = { [weak self] in
            self?.persistCurrentOverlayGeometry()
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

    func start(openSettingsOnLaunch: Bool = false) {
        guard menuBarController == nil else {
            return
        }

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
        activityMonitor.stop()
        behaviorRuntime.stop()
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
            _ = settingsSession.replaceBehaviorMotionReferences(
                from: oldMotionID,
                with: newMotionID
            )
        case let .removed(motionID):
            _ = settingsSession.replaceBehaviorMotionReferences(
                from: motionID,
                with: PetMotionReference.currentPetDefault
            )
        }
    }

    @discardableResult
    private func applySelectedPet(_ item: PetLibraryItem) -> Bool {
        do {
            try petWindowController.applyPet(item)
            behaviorRuntime.replacePetDefinition(item.definition)
            if let latestActivitySnapshot {
                behaviorRuntime.update(
                    settings: settingsSession.settings,
                    snapshot: latestActivitySnapshot
                )
            }
            return true
        } catch {
            return false
        }
    }

    private func apply(settings: AppSettings, restorePosition: Bool) {
        petWindowController.applyOverlaySettings(
            settings.overlay,
            restorePosition: restorePosition
        )

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
        if let appliedOverlay = petWindowController.currentOverlaySettings() {
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
}
