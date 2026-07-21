import AppKit

@MainActor
final class AppCoordinator {
    private let settingsWindowController = SettingsWindowController()
    private var menuBarController: MenuBarController?

    func start(openSettingsOnLaunch: Bool = false) {
        guard menuBarController == nil else {
            return
        }

        let menuBarController = MenuBarController(
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
}
