import AppKit

@MainActor
final class AppCoordinator {
    private let settingsWindowController = SettingsWindowController()
    private let petWindowController = PetWindowController()
    private let activityMonitor: any ActivitySnapshotMonitoring
    private var menuBarController: MenuBarController?
    private(set) var latestActivitySnapshot: ActivitySnapshot?

    init(
        activityMonitor: any ActivitySnapshotMonitoring = ActivitySnapshotMonitor()
    ) {
        self.activityMonitor = activityMonitor
    }

    func start(openSettingsOnLaunch: Bool = false) {
        guard menuBarController == nil else {
            return
        }

        activityMonitor.start { [weak self] snapshot in
            self?.activitySnapshotDidChange(snapshot)
        }
        petWindowController.wake()
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
        menuBarController?.stop()
        menuBarController = nil
        petWindowController.sleep()
    }

    private func togglePetAwakeState() {
        if petWindowController.isAwake {
            petWindowController.sleep()
        } else {
            petWindowController.wake()
        }

        menuBarController?.setPetAwake(petWindowController.isAwake)
    }

    private func activitySnapshotDidChange(_ snapshot: ActivitySnapshot) {
        latestActivitySnapshot = snapshot
        petWindowController.setSystemSuspended(
            snapshot.isScreenLocked || snapshot.isSystemSleeping
        )
    }
}
