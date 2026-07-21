import AppKit

@MainActor
final class MenuBarController: NSObject {
    private let onTogglePetAwakeState: () -> Void
    private let onOpenSettings: () -> Void
    private let onQuit: () -> Void
    private var isPetAwake: Bool
    private weak var petAwakeStateItem: NSMenuItem?
    private(set) var statusItem = NSStatusBar.system.statusItem(
        withLength: NSStatusItem.variableLength
    )

    init(
        isPetAwake: Bool,
        onTogglePetAwakeState: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        self.isPetAwake = isPetAwake
        self.onTogglePetAwakeState = onTogglePetAwakeState
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

    func setPetAwake(_ isAwake: Bool) {
        isPetAwake = isAwake
        updatePetAwakeStateItem()
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

        let petAwakeStateItem = NSMenuItem(
            title: petAwakeStateTitle,
            action: #selector(togglePetAwakeState),
            keyEquivalent: ""
        )
        petAwakeStateItem.target = self
        petAwakeStateItem.setAccessibilityIdentifier("monglepet.menu.petAwakeState")
        menu.addItem(petAwakeStateItem)
        self.petAwakeStateItem = petAwakeStateItem

        menu.addItem(.separator())

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

    private var petAwakeStateTitle: String {
        isPetAwake ? "몽글이 재우기" : "몽글이 깨우기"
    }

    private func updatePetAwakeStateItem() {
        petAwakeStateItem?.title = petAwakeStateTitle
    }

    @objc
    private func togglePetAwakeState() {
        onTogglePetAwakeState()
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
