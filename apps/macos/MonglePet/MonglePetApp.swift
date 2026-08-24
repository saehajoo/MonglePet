//
//  MonglePetApp.swift
//  MonglePet
//
//  Created by netsprint on 7/21/26.
//

import AppKit
import SwiftUI

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
    private var pendingExternalURLs: [URL] = []
    private var uiTestingSettingsDirectoryURL: URL?
    private var uiTestingImageEditorWindow: NSWindow?
    private var qaTerminationTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let arguments = ProcessInfo.processInfo.arguments
        let isOpeningSettingsForUITest = arguments.contains(
            "--ui-testing-open-settings"
        )
        let isOpeningImageEditorForUITest = arguments.contains(
            "--ui-testing-open-png-editor"
        )
        let isUITesting = isOpeningSettingsForUITest
            || isOpeningImageEditorForUITest
            || arguments.contains("--ui-testing")
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
            if isOpeningImageEditorForUITest {
                openPNGEditorForUITest(
                    startsAtResultPreview: arguments.contains(
                        "--ui-testing-png-editor-start-scrolled"
                    )
                )
            }
            if !pendingExternalURLs.isEmpty {
                coordinator.openExternalURLs(pendingExternalURLs)
                pendingExternalURLs = []
            }
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

    func application(_ application: NSApplication, open urls: [URL]) {
        if let coordinator {
            coordinator.openExternalURLs(urls)
        } else {
            pendingExternalURLs.append(contentsOf: urls)
        }
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

    private func openPNGEditorForUITest(startsAtResultPreview: Bool) {
        guard let context = CGContext(
            data: nil,
            width: 180,
            height: 140,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return
        }
        context.clear(CGRect(x: 0, y: 0, width: 180, height: 140))
        context.setFillColor(NSColor.systemPurple.cgColor)
        context.fill(CGRect(x: 38, y: 30, width: 98, height: 78))
        guard let image = context.makeImage() else {
            return
        }

        let editor = PNGFrameCropEditorView(
            images: [
                UserPetSourceImage(
                    displayName: "몽글이-기본-프레임.png",
                    image: image
                )
            ],
            initialScrollsToResultPreview: startsAtResultPreview,
            onImport: { _ in }
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 680),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "PNG 프레임 자르기"
        window.contentViewController = NSHostingController(rootView: editor)
        window.minSize = NSSize(width: 860, height: 680)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        uiTestingImageEditorWindow = window
    }
}
