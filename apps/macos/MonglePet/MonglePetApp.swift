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
    private var qaTerminationTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let arguments = ProcessInfo.processInfo.arguments
        let isOpeningSettingsForUITest = arguments.contains(
            "--ui-testing-open-settings"
        )
        let isUITesting = isOpeningSettingsForUITest || arguments.contains("--ui-testing")
        let qaConfiguration = MultiPetQALaunchConfiguration(
            arguments: arguments
        )

        if isUITesting {
            NSApplication.shared.setActivationPolicy(.regular)
        }

        do {
            let settingsStore = try makeSettingsStore(
                isUITesting: isUITesting,
                qaConfiguration: qaConfiguration
            )
            let petLibraryStore = try makePetLibraryStore(isUITesting: isUITesting)
            let coordinator = AppCoordinator(
                settingsStore: settingsStore,
                petLibraryStore: petLibraryStore
            )
            coordinator.start(openSettingsOnLaunch: isOpeningSettingsForUITest)
            self.coordinator = coordinator
            scheduleQATerminationIfNeeded(qaConfiguration)
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
        qaTerminationTimer?.invalidate()
        qaTerminationTimer = nil
        coordinator?.stop()
        if let uiTestingSettingsDirectoryURL {
            try? FileManager.default.removeItem(at: uiTestingSettingsDirectoryURL)
        }
    }

    private func makeSettingsStore(
        isUITesting: Bool,
        qaConfiguration: MultiPetQALaunchConfiguration?
    ) throws -> AppSettingsStore {
        if isUITesting {
            let directoryURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(
                    "MonglePet-UITests-\(ProcessInfo.processInfo.processIdentifier)",
                    isDirectory: true
            )
            uiTestingSettingsDirectoryURL = directoryURL
            let store = AppSettingsStore(
                settingsURL: directoryURL.appendingPathComponent("settings.json")
            )
            if let qaConfiguration {
                try store.save(qaConfiguration.makeSettings())
            }
            return store
        }

        return AppSettingsStore(
            settingsURL: try AppSettingsStore.defaultSettingsURL()
        )
    }

    private func makePetLibraryStore(isUITesting: Bool) throws -> PetLibraryStore {
        if isUITesting, let uiTestingSettingsDirectoryURL {
            return PetLibraryStore(
                libraryRootURL: uiTestingSettingsDirectoryURL
                    .appendingPathComponent("Library", isDirectory: true)
            )
        }
        return PetLibraryStore(
            libraryRootURL: try PetLibraryStore.defaultLibraryRootURL()
        )
    }

    private func scheduleQATerminationIfNeeded(
        _ configuration: MultiPetQALaunchConfiguration?
    ) {
        guard let duration = configuration?.duration else {
            return
        }
        qaTerminationTimer = Timer.scheduledTimer(
            withTimeInterval: duration,
            repeats: false
        ) { _ in
            MainActor.assumeIsolated {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}
