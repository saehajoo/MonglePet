//
//  MonglePetApp.swift
//  MonglePet
//
//  Created by netsprint on 7/21/26.
//

import AppKit

@main
enum MonglePetApp {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        let delegate = MonglePetAppDelegate()
        application.delegate = delegate
        application.run()
    }
}

@MainActor
final class MonglePetAppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: AppCoordinator?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let arguments = ProcessInfo.processInfo.arguments
        let isOpeningSettingsForUITest = arguments.contains(
            "--ui-testing-open-settings"
        )
        let isUITesting = isOpeningSettingsForUITest || arguments.contains("--ui-testing")

        if isUITesting {
            NSApplication.shared.setActivationPolicy(.regular)
        }

        let coordinator = AppCoordinator()
        coordinator.start(openSettingsOnLaunch: isOpeningSettingsForUITest)
        self.coordinator = coordinator
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
