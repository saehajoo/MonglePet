import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    private let settingsSession: AppSettingsSession
    private let petDefinition: PetDefinition
    private lazy var windowController = makeWindowController()

    init(
        settingsSession: AppSettingsSession,
        petDefinition: PetDefinition
    ) {
        self.settingsSession = settingsSession
        self.petDefinition = petDefinition
    }

    var window: NSWindow? {
        windowController.window
    }

    func show() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        windowController.showWindow(nil)
        windowController.window?.makeKeyAndOrderFront(nil)
    }

    private func makeWindowController() -> NSWindowController {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 620),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "MonglePet 설정"
        window.identifier = NSUserInterfaceItemIdentifier("monglepet.settings.window")
        window.contentViewController = NSHostingController(
            rootView: SettingsView(
                settingsSession: settingsSession,
                petDefinition: petDefinition
            )
        )
        window.isReleasedWhenClosed = false
        window.center()

        return NSWindowController(window: window)
    }
}
