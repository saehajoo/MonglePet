import AppKit

@MainActor
final class MenuBarController: NSObject {
    private let onOpenSettings: () -> Void
    private let onQuit: () -> Void
    private(set) var statusItem = NSStatusBar.system.statusItem(
        withLength: NSStatusItem.variableLength
    )

    init(
        onOpenSettings: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        self.onOpenSettings = onOpenSettings
        self.onQuit = onQuit
    }

    func start() {
        configureStatusButton()
        statusItem.menu = makeMenu()
    }

    func stop() {
        statusItem.menu = nil
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    private func configureStatusButton() {
        guard let button = statusItem.button else {
            return
        }

        button.image = NSImage(
            systemSymbolName: "pawprint.fill",
            accessibilityDescription: "MonglePet"
        )
        button.image?.isTemplate = true
        button.toolTip = "MonglePet"
        button.setAccessibilityLabel("MonglePet")
        button.setAccessibilityIdentifier("monglepet.statusItem")
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu(title: "MonglePet")

        let settingsItem = NSMenuItem(
            title: "설정…",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        settingsItem.setAccessibilityIdentifier("monglepet.menu.settings")
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "MonglePet 종료",
            action: #selector(quitApplication),
            keyEquivalent: "q"
        )
        quitItem.target = self
        quitItem.setAccessibilityIdentifier("monglepet.menu.quit")
        menu.addItem(quitItem)

        return menu
    }

    @objc
    private func openSettings() {
        onOpenSettings()
    }

    @objc
    private func quitApplication() {
        onQuit()
    }
}
