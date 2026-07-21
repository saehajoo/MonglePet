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
    func testMenuBarContainsSettingsAndQuitActions() throws {
        var didOpenSettings = false
        var didQuit = false
        let controller = MenuBarController(
            onOpenSettings: { didOpenSettings = true },
            onQuit: { didQuit = true }
        )
        controller.start()
        defer { controller.stop() }

        let menu = try XCTUnwrap(controller.statusItem.menu)
        XCTAssertEqual(menu.items.map(\.title), ["설정…", "", "MonglePet 종료"])

        menu.performActionForItem(at: 0)
        menu.performActionForItem(at: 2)

        XCTAssertTrue(didOpenSettings)
        XCTAssertTrue(didQuit)
    }

    @MainActor
    func testSettingsWindowCanBeReopenedAfterClosing() throws {
        let controller = SettingsWindowController()

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
        XCTAssertEqual(panel.contentLayoutRect.size, PetWindowController.defaultContentSize)
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

        controller.show()
        XCTAssertTrue(panel.isVisible)
        XCTAssertFalse(panel.isKeyWindow)

        panel.orderOut(nil)
    }
}
