import AppKit

final class PetWindow: NSPanel {
    override var canBecomeKey: Bool {
        false
    }

    override var canBecomeMain: Bool {
        false
    }

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        isMovable = true
        isMovableByWindowBackground = true
        animationBehavior = .none
        isExcludedFromWindowsMenu = true
        title = "MonglePet 펫"
        identifier = NSUserInterfaceItemIdentifier("monglepet.overlay.window")
        setAccessibilityLabel("MonglePet 펫")
        setAccessibilityIdentifier("monglepet.overlay.window")
    }
}
