import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    private let settingsSession: AppSettingsSession
    private let petLibrarySession: PetLibrarySession
    private let loginLaunchSettings: LoginLaunchSettings
    private let runtimeControlSession: PetRuntimeControlSession
    private let remotePetImportRequestCenter: RemotePetImportRequestCenter
    private let remotePetImportService: RemotePetImportService
    private lazy var windowController = makeWindowController()

    init(
        settingsSession: AppSettingsSession,
        petLibrarySession: PetLibrarySession,
        loginLaunchSettings: LoginLaunchSettings,
        runtimeControlSession: PetRuntimeControlSession,
        remotePetImportRequestCenter: RemotePetImportRequestCenter =
            RemotePetImportRequestCenter(),
        remotePetImportService: RemotePetImportService = RemotePetImportService()
    ) {
        self.settingsSession = settingsSession
        self.petLibrarySession = petLibrarySession
        self.loginLaunchSettings = loginLaunchSettings
        self.runtimeControlSession = runtimeControlSession
        self.remotePetImportRequestCenter = remotePetImportRequestCenter
        self.remotePetImportService = remotePetImportService
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
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "MonglePet 설정"
        window.identifier = NSUserInterfaceItemIdentifier("monglepet.settings.window")
        window.contentViewController = NSHostingController(
            rootView: SettingsView(
                settingsSession: settingsSession,
                petLibrarySession: petLibrarySession,
                loginLaunchSettings: loginLaunchSettings,
                runtimeControlSession: runtimeControlSession,
                remotePetImportRequestCenter: remotePetImportRequestCenter,
                remotePetImportService: remotePetImportService
            )
        )
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 840, height: 620)
        window.center()

        return NSWindowController(window: window)
    }
}
