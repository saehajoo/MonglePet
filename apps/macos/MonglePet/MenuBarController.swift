import AppKit

nonisolated struct MenuBarPetState: Equatable, Sendable {
    let instanceID: UUID
    let displayName: String
    let isAwake: Bool
    let isClickThrough: Bool
    let isSelected: Bool
}

@MainActor
final class MenuBarController: NSObject {
    private let onSelectPet: (UUID) -> Void
    private let onSetPetAwake: (UUID, Bool) -> Void
    private let onSetPetClickThrough: (UUID, Bool) -> Void
    private let onBringPetToCurrentScreen: (UUID) -> Void
    private let onSetAllPetsAwake: (Bool) -> Void
    private let onSetAllPetsPaused: (Bool) -> Void
    private let onEnterSafeMode: () -> Void
    private let onOpenSettings: () -> Void
    private let onQuit: () -> Void
    private var pets: [MenuBarPetState]
    private var isAllPaused: Bool
    private var resourceWarning: PetResourceWarning?
    private(set) var statusItem = NSStatusBar.system.statusItem(
        withLength: NSStatusItem.variableLength
    )

    init(
        pets: [MenuBarPetState],
        onSelectPet: @escaping (UUID) -> Void,
        onSetPetAwake: @escaping (UUID, Bool) -> Void,
        onSetPetClickThrough: @escaping (UUID, Bool) -> Void,
        onBringPetToCurrentScreen: @escaping (UUID) -> Void,
        onSetAllPetsAwake: @escaping (Bool) -> Void,
        isAllPaused: Bool,
        resourceWarning: PetResourceWarning?,
        onSetAllPetsPaused: @escaping (Bool) -> Void,
        onEnterSafeMode: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        self.pets = pets
        self.onSelectPet = onSelectPet
        self.onSetPetAwake = onSetPetAwake
        self.onSetPetClickThrough = onSetPetClickThrough
        self.onBringPetToCurrentScreen = onBringPetToCurrentScreen
        self.onSetAllPetsAwake = onSetAllPetsAwake
        self.isAllPaused = isAllPaused
        self.resourceWarning = resourceWarning
        self.onSetAllPetsPaused = onSetAllPetsPaused
        self.onEnterSafeMode = onEnterSafeMode
        self.onOpenSettings = onOpenSettings
        self.onQuit = onQuit
    }

    func start() {
        configureStatusButton()
        rebuildMenu()
    }

    func stop() {
        statusItem.menu = nil
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    func setPets(_ pets: [MenuBarPetState]) {
        guard self.pets != pets else {
            return
        }
        self.pets = pets
        rebuildMenu()
    }

    func setRuntimeState(
        isAllPaused: Bool,
        resourceWarning: PetResourceWarning?
    ) {
        guard
            self.isAllPaused != isAllPaused
                || self.resourceWarning != resourceWarning
        else {
            return
        }
        self.isAllPaused = isAllPaused
        self.resourceWarning = resourceWarning
        rebuildMenu()
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

    private func rebuildMenu() {
        statusItem.menu = makeMenu()
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu(title: "MonglePet")
        let summaryItem = NSMenuItem(
            title: "활성 펫 \(pets.count)마리",
            action: nil,
            keyEquivalent: ""
        )
        summaryItem.isEnabled = false
        summaryItem.setAccessibilityIdentifier("monglepet.menu.petSummary")
        menu.addItem(summaryItem)

        if resourceWarning != nil {
            let warningItem = NSMenuItem(
                title: "⚠ 성능 사용량 확인 필요",
                action: #selector(openSettings),
                keyEquivalent: ""
            )
            warningItem.target = self
            menu.addItem(warningItem)
        }

        let wakeAllItem = NSMenuItem(
            title: "모든 펫 깨우기",
            action: #selector(wakeAllPets),
            keyEquivalent: ""
        )
        wakeAllItem.target = self
        wakeAllItem.isEnabled = pets.contains { !$0.isAwake }
        menu.addItem(wakeAllItem)

        let sleepAllItem = NSMenuItem(
            title: "모든 펫 재우기",
            action: #selector(sleepAllPets),
            keyEquivalent: ""
        )
        sleepAllItem.target = self
        sleepAllItem.isEnabled = pets.contains { $0.isAwake }
        menu.addItem(sleepAllItem)

        let pauseAllItem = NSMenuItem(
            title: isAllPaused
                ? "모든 펫 계속하기"
                : "모든 펫 일시정지",
            action: #selector(toggleAllPetsPaused),
            keyEquivalent: ""
        )
        pauseAllItem.target = self
        menu.addItem(pauseAllItem)

        menu.addItem(.separator())

        for pet in pets {
            menu.addItem(makePetMenuItem(pet))
        }

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

        let troubleshootingItem = NSMenuItem(
            title: "문제 해결",
            action: nil,
            keyEquivalent: ""
        )
        let troubleshootingMenu = NSMenu(title: "문제 해결")
        let safeModeItem = NSMenuItem(
            title: "안전 모드로 전환…",
            action: #selector(enterSafeMode),
            keyEquivalent: ""
        )
        safeModeItem.target = self
        safeModeItem.setAccessibilityIdentifier("monglepet.menu.safeMode")
        troubleshootingMenu.addItem(safeModeItem)
        troubleshootingItem.submenu = troubleshootingMenu
        troubleshootingItem.setAccessibilityIdentifier(
            "monglepet.menu.troubleshooting"
        )
        menu.addItem(troubleshootingItem)

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

    private func makePetMenuItem(_ pet: MenuBarPetState) -> NSMenuItem {
        let item = NSMenuItem(
            title: visibleName(pet.displayName),
            action: nil,
            keyEquivalent: ""
        )
        item.state = pet.isSelected ? .on : .off
        item.representedObject = pet.instanceID

        let submenu = NSMenu(title: pet.displayName)
        submenu.addItem(
            actionItem(
                title: "이 펫 설정 편집",
                action: #selector(selectPet),
                pet: pet
            )
        )
        submenu.addItem(
            actionItem(
                title: pet.isAwake ? "펫 재우기" : "펫 깨우기",
                action: #selector(togglePetAwake),
                pet: pet
            )
        )
        let clickThrough = actionItem(
            title: "클릭 통과",
            action: #selector(togglePetClickThrough),
            pet: pet
        )
        clickThrough.state = pet.isClickThrough ? .on : .off
        submenu.addItem(clickThrough)
        submenu.addItem(
            actionItem(
                title: "현재 화면으로 가져오기",
                action: #selector(bringPetToCurrentScreen),
                pet: pet
            )
        )
        item.submenu = submenu
        return item
    }

    private func actionItem(
        title: String,
        action: Selector,
        pet: MenuBarPetState
    ) -> NSMenuItem {
        let item = NSMenuItem(
            title: title,
            action: action,
            keyEquivalent: ""
        )
        item.target = self
        item.representedObject = pet.instanceID
        return item
    }

    private func visibleName(_ name: String) -> String {
        let maximumLength = 40
        guard name.count > maximumLength else {
            return name
        }
        return "\(name.prefix(maximumLength))…"
    }

    private func instanceID(from sender: NSMenuItem) -> UUID? {
        sender.representedObject as? UUID
    }

    @objc
    private func wakeAllPets() {
        onSetAllPetsAwake(true)
    }

    @objc
    private func sleepAllPets() {
        onSetAllPetsAwake(false)
    }

    @objc
    private func toggleAllPetsPaused() {
        onSetAllPetsPaused(!isAllPaused)
    }

    @objc
    private func enterSafeMode() {
        onEnterSafeMode()
    }

    @objc
    private func selectPet(_ sender: NSMenuItem) {
        guard let instanceID = instanceID(from: sender) else {
            return
        }
        onSelectPet(instanceID)
        onOpenSettings()
    }

    @objc
    private func togglePetAwake(_ sender: NSMenuItem) {
        guard
            let instanceID = instanceID(from: sender),
            let pet = pets.first(where: { $0.instanceID == instanceID })
        else {
            return
        }
        onSetPetAwake(instanceID, !pet.isAwake)
    }

    @objc
    private func togglePetClickThrough(_ sender: NSMenuItem) {
        guard
            let instanceID = instanceID(from: sender),
            let pet = pets.first(where: { $0.instanceID == instanceID })
        else {
            return
        }
        onSetPetClickThrough(instanceID, !pet.isClickThrough)
    }

    @objc
    private func bringPetToCurrentScreen(_ sender: NSMenuItem) {
        guard let instanceID = instanceID(from: sender) else {
            return
        }
        onBringPetToCurrentScreen(instanceID)
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
