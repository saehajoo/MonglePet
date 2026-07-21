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
}
