import AppKit

@MainActor
final class AppCoordinator {
    private let settingsSession: AppSettingsSession
    private let settingsWindowController: SettingsWindowController
    private let petWindowController: PetWindowController
    private let behaviorRuntime: PetBehaviorRuntime
    private let activityMonitor: any ActivitySnapshotMonitoring
    private var menuBarController: MenuBarController?
    private(set) var latestActivitySnapshot: ActivitySnapshot?

    init(
        settingsStore: AppSettingsStore,
        activityMonitor: any ActivitySnapshotMonitoring = ActivitySnapshotMonitor()
    ) {
        let settingsSession = AppSettingsSession(store: settingsStore)
        let petWindowController = PetWindowController()
        self.settingsSession = settingsSession
        settingsWindowController = SettingsWindowController(
            settingsSession: settingsSession,
            petDefinition: petWindowController.petDefinition
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

        let loadResult = settingsSession.load()
        settingsSession.installBuiltInBehaviorPresetsIfNeeded()
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
        apply(settings: settings, restorePosition: true)
        guard let latestActivitySnapshot else {
            return
        }
        behaviorRuntime.update(
            settings: settingsSession.settings,
            snapshot: latestActivitySnapshot
        )
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
