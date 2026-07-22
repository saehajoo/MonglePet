//
//  MonglePetTests.swift
//  MonglePetTests
//
//  Created by netsprint on 7/21/26.
//

import XCTest
@testable import MonglePet

final class MonglePetTests: XCTestCase {
    func testBundleIdentifier() {
        XCTAssertEqual(Bundle.main.bundleIdentifier, "kr.mapleroom.MonglePet")
    }

    func testAppRunsWithoutDockIcon() {
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "LSUIElement") as? Bool, true)
    }

    @MainActor
    func testMenuBarContainsPetStateSettingsAndQuitActions() throws {
        var didTogglePetAwakeState = false
        var didOpenSettings = false
        var didQuit = false
        let controller = MenuBarController(
            isPetAwake: true,
            onTogglePetAwakeState: { didTogglePetAwakeState = true },
            onOpenSettings: { didOpenSettings = true },
            onQuit: { didQuit = true }
        )
        controller.start()
        defer { controller.stop() }

        let menu = try XCTUnwrap(controller.statusItem.menu)
        XCTAssertEqual(
            menu.items.map(\.title),
            ["몽글이 재우기", "", "설정…", "", "MonglePet 종료"]
        )

        menu.performActionForItem(at: 0)
        menu.performActionForItem(at: 2)
        menu.performActionForItem(at: 4)

        XCTAssertTrue(didTogglePetAwakeState)
        XCTAssertTrue(didOpenSettings)
        XCTAssertTrue(didQuit)

        controller.setPetAwake(false)
        XCTAssertEqual(menu.items[0].title, "몽글이 깨우기")
    }

    @MainActor
    func testSettingsWindowCanBeReopenedAfterClosing() throws {
        let settingsURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("settings.json")
        defer {
            try? FileManager.default.removeItem(
                at: settingsURL.deletingLastPathComponent()
            )
        }
        let session = AppSettingsSession(
            store: AppSettingsStore(settingsURL: settingsURL)
        )
        _ = session.load()
        let controller = SettingsWindowController(
            settingsSession: session,
            petDefinition: BuiltInPet.mongleDefinition(
                atlasPixelSize: PixelSize(width: 192, height: 208)
            )
        )

        controller.show()
        let firstWindow = try XCTUnwrap(controller.window)
        XCTAssertTrue(firstWindow.isVisible)

        firstWindow.close()
        XCTAssertFalse(firstWindow.isVisible)

        controller.show()
        XCTAssertTrue(firstWindow === controller.window)
        XCTAssertTrue(firstWindow.isVisible)

        firstWindow.close()
    }

    @MainActor
    func testPetWindowUsesNonActivatingOverlayConfiguration() throws {
        let controller = PetWindowController()
        let panel = try XCTUnwrap(controller.panel)

        XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel))
        XCTAssertFalse(panel.isOpaque)
        XCTAssertEqual(panel.backgroundColor, .clear)
        XCTAssertFalse(panel.hasShadow)
        XCTAssertFalse(panel.canBecomeKey)
        XCTAssertFalse(panel.canBecomeMain)
        XCTAssertEqual(panel.level, .floating)
        XCTAssertTrue(panel.collectionBehavior.contains(.canJoinAllSpaces))
        XCTAssertTrue(panel.collectionBehavior.contains(.fullScreenAuxiliary))
        XCTAssertTrue(panel.isMovable)
        XCTAssertTrue(panel.isMovableByWindowBackground)
        XCTAssertEqual(panel.contentLayoutRect.size, PetWindowController.defaultContentSize)
    }

    @MainActor
    func testPetWindowAppliesSizePositionAndClickThroughSettings() throws {
        let controller = PetWindowController()
        let panel = try XCTUnwrap(controller.panel)
        let settings = OverlaySettings(
            screenIdentifier: nil,
            originX: 120,
            originY: 160,
            width: 288,
            clickThrough: true
        )

        controller.applyOverlaySettings(settings, restorePosition: true)

        XCTAssertEqual(panel.frame.width, 288, accuracy: 0.001)
        XCTAssertEqual(panel.frame.height, 312, accuracy: 0.001)
        XCTAssertTrue(panel.ignoresMouseEvents)
        XCTAssertTrue(
            NSScreen.screens.map(\.visibleFrame).contains { $0.contains(panel.frame) }
        )

        let captured = try XCTUnwrap(controller.currentOverlaySettings())
        XCTAssertEqual(captured.width, 288, accuracy: 0.001)
        XCTAssertTrue(captured.clickThrough)
        XCTAssertEqual(captured.originX, panel.frame.minX, accuracy: 0.001)
        XCTAssertEqual(captured.originY, panel.frame.minY, accuracy: 0.001)
    }

    @MainActor
    func testPetWindowDefaultOriginUsesBottomRightInset() {
        let visibleFrame = NSRect(x: 100, y: 50, width: 1_200, height: 800)

        let origin = PetWindowController.defaultOrigin(in: visibleFrame)

        XCTAssertEqual(origin, NSPoint(x: 1_076, y: 82))
    }

    @MainActor
    func testPetWindowShowsBundledPlaceholderWithoutBecomingKey() throws {
        XCTAssertNotNil(NSImage(named: "PlaceholderPet"))

        let controller = PetWindowController()
        let panel = try XCTUnwrap(controller.panel)

        controller.wake()
        XCTAssertTrue(panel.isVisible)
        XCTAssertFalse(panel.isKeyWindow)
        XCTAssertTrue(controller.isAnimationPlaying)

        controller.sleep()
    }

    @MainActor
    func testPetWindowSleepAndWakeRestoreLastPosition() throws {
        let controller = PetWindowController()
        let panel = try XCTUnwrap(controller.panel)

        controller.wake()
        let originalOrigin = panel.frame.origin

        controller.sleep()
        XCTAssertFalse(controller.isAwake)
        XCTAssertFalse(controller.isAnimationPlaying)
        XCTAssertFalse(panel.isVisible)

        controller.wake()
        XCTAssertTrue(controller.isAwake)
        XCTAssertTrue(controller.isAnimationPlaying)
        XCTAssertTrue(panel.isVisible)
        XCTAssertEqual(panel.frame.origin, originalOrigin)

        controller.sleep()
    }

    @MainActor
    func testSystemSuspensionPausesAnimationWithoutChangingUserAwakeState() {
        let controller = PetWindowController()

        controller.wake()
        controller.setSystemSuspended(true)
        XCTAssertTrue(controller.isAwake)
        XCTAssertTrue(controller.isSystemSuspended)
        XCTAssertFalse(controller.isAnimationPlaying)

        controller.sleep()
        controller.setSystemSuspended(false)
        XCTAssertFalse(controller.isAwake)
        XCTAssertFalse(controller.isSystemSuspended)
        XCTAssertFalse(controller.isAnimationPlaying)

        controller.wake()
        XCTAssertTrue(controller.isAnimationPlaying)
        controller.sleep()
    }

    @MainActor
    func testCorrectedOriginKeepsVisibleWindowPosition() {
        let visibleFrame = NSRect(x: 0, y: 0, width: 1_000, height: 800)
        let windowFrame = NSRect(x: 600, y: 300, width: 192, height: 208)

        let origin = PetWindowController.correctedOrigin(
            for: windowFrame,
            within: [visibleFrame]
        )

        XCTAssertEqual(origin, windowFrame.origin)
    }

    @MainActor
    func testCorrectedOriginClampsWindowInsideNearestVisibleFrame() {
        let primaryFrame = NSRect(x: 0, y: 0, width: 1_000, height: 800)
        let secondaryFrame = NSRect(x: 1_000, y: 100, width: 800, height: 600)
        let windowFrame = NSRect(x: 1_750, y: 650, width: 192, height: 208)

        let origin = PetWindowController.correctedOrigin(
            for: windowFrame,
            within: [primaryFrame, secondaryFrame]
        )

        XCTAssertEqual(origin, NSPoint(x: 1_608, y: 492))
    }

    @MainActor
    func testCorrectedOriginMovesDisconnectedWindowToPrimaryFrame() {
        let primaryFrame = NSRect(x: 0, y: 0, width: 1_000, height: 800)
        let disconnectedWindowFrame = NSRect(x: 2_000, y: 1_000, width: 192, height: 208)

        let origin = PetWindowController.correctedOrigin(
            for: disconnectedWindowFrame,
            within: [primaryFrame]
        )

        XCTAssertEqual(origin, NSPoint(x: 808, y: 592))
    }
}
