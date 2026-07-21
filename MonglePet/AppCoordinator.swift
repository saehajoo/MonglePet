import AppKit

@MainActor
final class AppCoordinator {
    private let settingsWindowController = SettingsWindowController()
    private let petWindowController = PetWindowController()
    private var menuBarController: MenuBarController?

    func start(openSettingsOnLaunch: Bool = false) {
        guard menuBarController == nil else {
            return
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

    private func togglePetAwakeState() {
        if petWindowController.isAwake {
            petWindowController.sleep()
        } else {
            petWindowController.wake()
        }

        menuBarController?.setPetAwake(petWindowController.isAwake)
    }
}
