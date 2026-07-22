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
    private var uiTestingSettingsDirectoryURL: URL?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let arguments = ProcessInfo.processInfo.arguments
        let isOpeningSettingsForUITest = arguments.contains(
            "--ui-testing-open-settings"
        )
        let isUITesting = isOpeningSettingsForUITest || arguments.contains("--ui-testing")

        if isUITesting {
            NSApplication.shared.setActivationPolicy(.regular)
        }

        do {
            let settingsStore = try makeSettingsStore(isUITesting: isUITesting)
            let coordinator = AppCoordinator(settingsStore: settingsStore)
            coordinator.start(openSettingsOnLaunch: isOpeningSettingsForUITest)
            self.coordinator = coordinator
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "MonglePet을 시작할 수 없습니다."
            alert.runModal()
            NSApplication.shared.terminate(nil)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator?.stop()
        if let uiTestingSettingsDirectoryURL {
            try? FileManager.default.removeItem(at: uiTestingSettingsDirectoryURL)
        }
    }

    private func makeSettingsStore(isUITesting: Bool) throws -> AppSettingsStore {
        if isUITesting {
            let directoryURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(
                    "MonglePet-UITests-\(ProcessInfo.processInfo.processIdentifier)",
                    isDirectory: true
                )
            uiTestingSettingsDirectoryURL = directoryURL
            return AppSettingsStore(
                settingsURL: directoryURL.appendingPathComponent("settings.json")
            )
        }

        return AppSettingsStore(
            settingsURL: try AppSettingsStore.defaultSettingsURL()
        )
    }
}
