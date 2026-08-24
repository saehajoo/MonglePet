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
        let isOpeningSpriteEditorForUITest = arguments.contains(
            "--ui-testing-open-sprite-editor"
        )
        let isUITesting = isOpeningSettingsForUITest
            || isOpeningImageEditorForUITest
            || isOpeningSpriteEditorForUITest
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
            if isOpeningSpriteEditorForUITest {
                openSpriteEditorForUITest()
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

    private func openSpriteEditorForUITest() {
        let columns = 12
        let rows = 3
        let frameLength = 100
        guard let context = CGContext(
            data: nil,
            width: columns * frameLength,
            height: rows * frameLength,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return
        }
        context.clear(
            CGRect(
                x: 0,
                y: 0,
                width: columns * frameLength,
                height: rows * frameLength
            )
        )
        for row in 0..<rows {
            for column in 0..<columns {
                context.setFillColor(
                    NSColor(
                        calibratedHue: CGFloat(row * columns + column)
                            / CGFloat(rows * columns),
                        saturation: 0.72,
                        brightness: 0.94,
                        alpha: 1
                    ).cgColor
                )
                context.fill(
                    CGRect(
                        x: column * frameLength + 12,
                        y: row * frameLength + 12,
                        width: frameLength - 24,
                        height: frameLength - 24
                    )
                )
            }
        }
        guard let image = context.makeImage() else {
            return
        }
        let regions = (0..<rows).flatMap { row in
            (0..<columns).map { column in
                PixelRect(
                    x: column * frameLength,
                    y: row * frameLength,
                    width: frameLength,
                    height: frameLength
                )
            }
        }
        let document = SpriteSheetDocument(
            sourceURL: URL(fileURLWithPath: "/tmp/monglepet-qa-12x3.png"),
            image: image,
            pixelSize: PixelSize(width: image.width, height: image.height),
            suggestedRegions: regions,
            suggestedBackgroundColor: .clear,
            hasTransparentBackground: true
        )
        let editor = SpriteSheetImportView(document: document) { _ in }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 780, height: 590),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "스프라이트 시트 가져오기"
        window.contentViewController = NSHostingController(rootView: editor)
        window.minSize = NSSize(width: 780, height: 590)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        uiTestingImageEditorWindow = window
    }
}
