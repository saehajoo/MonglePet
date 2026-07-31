import AppKit

@MainActor
final class MenuBarController: NSObject {
    private let onTogglePetAwakeState: () -> Void
    private let onSetClickThrough: (Bool) -> Void
    private let onBringPetToCurrentScreen: () -> Void
    private let onOpenSettings: () -> Void
    private let onQuit: () -> Void
    private var isPetAwake: Bool
    private var petDisplayName: String
    private var isClickThrough: Bool
    private weak var currentPetItem: NSMenuItem?
    private weak var petAwakeStateItem: NSMenuItem?
    private weak var clickThroughItem: NSMenuItem?
    private(set) var statusItem = NSStatusBar.system.statusItem(
        withLength: NSStatusItem.variableLength
    )

    init(
        isPetAwake: Bool,
        petDisplayName: String,
        isClickThrough: Bool,
        onTogglePetAwakeState: @escaping () -> Void,
        onSetClickThrough: @escaping (Bool) -> Void,
        onBringPetToCurrentScreen: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        self.isPetAwake = isPetAwake
        self.petDisplayName = petDisplayName
        self.isClickThrough = isClickThrough
        self.onTogglePetAwakeState = onTogglePetAwakeState
        self.onSetClickThrough = onSetClickThrough
        self.onBringPetToCurrentScreen = onBringPetToCurrentScreen
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

    func setCurrentPetDisplayName(_ displayName: String) {
        petDisplayName = displayName
        currentPetItem?.title = currentPetTitle
    }

    func setClickThrough(_ isEnabled: Bool) {
        isClickThrough = isEnabled
        clickThroughItem?.state = isEnabled ? .on : .off
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

        let currentPetItem = NSMenuItem(
            title: currentPetTitle,
            action: nil,
            keyEquivalent: ""
        )
        currentPetItem.isEnabled = false
        currentPetItem.setAccessibilityIdentifier("monglepet.menu.currentPet")
        menu.addItem(currentPetItem)
        self.currentPetItem = currentPetItem

        menu.addItem(.separator())

        let petAwakeStateItem = NSMenuItem(
            title: petAwakeStateTitle,
            action: #selector(togglePetAwakeState),
            keyEquivalent: ""
        )
        petAwakeStateItem.target = self
        petAwakeStateItem.setAccessibilityIdentifier("monglepet.menu.petAwakeState")
        menu.addItem(petAwakeStateItem)
        self.petAwakeStateItem = petAwakeStateItem

        let clickThroughItem = NSMenuItem(
            title: "클릭 통과",
            action: #selector(toggleClickThrough),
            keyEquivalent: ""
        )
        clickThroughItem.target = self
        clickThroughItem.state = isClickThrough ? .on : .off
        clickThroughItem.setAccessibilityIdentifier(
            "monglepet.menu.clickThrough"
        )
        menu.addItem(clickThroughItem)
        self.clickThroughItem = clickThroughItem

        let bringToCurrentScreenItem = NSMenuItem(
            title: "펫을 현재 화면으로 가져오기",
            action: #selector(bringPetToCurrentScreen),
            keyEquivalent: ""
        )
        bringToCurrentScreenItem.target = self
        bringToCurrentScreenItem.setAccessibilityIdentifier(
            "monglepet.menu.bringToCurrentScreen"
        )
        menu.addItem(bringToCurrentScreenItem)

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

    private var currentPetTitle: String {
        let maximumLength = 40
        let visibleName: String
        if petDisplayName.count > maximumLength {
            visibleName = "\(petDisplayName.prefix(maximumLength))…"
        } else {
            visibleName = petDisplayName
        }
        return "현재 펫: \(visibleName)"
    }

    private var petAwakeStateTitle: String {
        isPetAwake ? "펫 재우기" : "펫 깨우기"
    }

    private func updatePetAwakeStateItem() {
        petAwakeStateItem?.title = petAwakeStateTitle
    }

    @objc
    private func togglePetAwakeState() {
        onTogglePetAwakeState()
    }

    @objc
    private func toggleClickThrough() {
        setClickThrough(!isClickThrough)
        onSetClickThrough(isClickThrough)
    }

    @objc
    private func bringPetToCurrentScreen() {
        onBringPetToCurrentScreen()
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
