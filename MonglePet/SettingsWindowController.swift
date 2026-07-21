import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    private lazy var windowController = makeWindowController()

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
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 320),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "MonglePet 설정"
        window.identifier = NSUserInterfaceItemIdentifier("monglepet.settings.window")
        window.contentViewController = NSHostingController(rootView: SettingsView())
        window.isReleasedWhenClosed = false
        window.center()

        return NSWindowController(window: window)
    }
}
