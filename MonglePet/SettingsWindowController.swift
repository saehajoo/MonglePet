import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    private let settingsSession: AppSettingsSession
    private let petLibrarySession: PetLibrarySession
    private let loginLaunchSettings: LoginLaunchSettings
    private lazy var windowController = makeWindowController()

    init(
        settingsSession: AppSettingsSession,
        petLibrarySession: PetLibrarySession,
        loginLaunchSettings: LoginLaunchSettings
    ) {
        self.settingsSession = settingsSession
        self.petLibrarySession = petLibrarySession
        self.loginLaunchSettings = loginLaunchSettings
    }

    var window: NSWindow? {
        windowController.window
    }

    func show() {
        loginLaunchSettings.refresh()
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
                petLibrarySession: petLibrarySession,
                loginLaunchSettings: loginLaunchSettings
            )
        )
        window.isReleasedWhenClosed = false
        window.center()

        return NSWindowController(window: window)
    }
}
