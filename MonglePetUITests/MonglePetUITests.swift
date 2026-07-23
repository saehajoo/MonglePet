//
//  MonglePetUITests.swift
//  MonglePetUITests
//
//  Created by netsprint on 7/21/26.
//

import XCTest

final class MonglePetUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testSettingsWindowOpens() throws {
        let app = XCUIApplication()
        app.launchArguments.append("--ui-testing-open-settings")
        app.launch()

        XCTAssertTrue(app.windows["MonglePet 설정"].waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.descendants(matching: .any)["monglepet.settings.awake"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["monglepet.settings.behaviorMode"].exists
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["monglepet.settings.overlayWidth"].exists
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["monglepet.settings.clickThrough"].exists
        )
        XCTAssertTrue(
            app.images["monglepet.settings.petPreview"].exists
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["monglepet.settings.petAnimations"].exists
        )
        XCTAssertFalse(
            app.buttons["monglepet.settings.createEditablePetCopy"].exists
        )
    }

    @MainActor
    func testPetOverlayAppears() throws {
        let app = XCUIApplication()
        app.launchArguments.append("--ui-testing")
        app.launch()

        XCTAssertTrue(
            app.images["monglepet.overlay.pet"].waitForExistence(timeout: 5)
        )
    }

    @MainActor
    func testMovementSettingsTabShowsCurrentPetAndMode() throws {
        let app = XCUIApplication()
        app.launchArguments.append("--ui-testing-open-settings")
        app.launch()

        let movementTab = app.buttons["이동"]
        XCTAssertTrue(movementTab.waitForExistence(timeout: 5))
        movementTab.click()

        XCTAssertTrue(
            app.descendants(matching: .any)["monglepet.settings.movementPetName"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["monglepet.settings.movementMode"]
                .exists
        )
    }

    @MainActor
    func testNewPetSheetIncludesMetadataFields() throws {
        let app = XCUIApplication()
        app.launchArguments.append("--ui-testing-open-settings")
        app.launch()

        let createButton = app.buttons["monglepet.settings.createUserPet"]
        XCTAssertTrue(createButton.waitForExistence(timeout: 5))
        createButton.click()

        XCTAssertTrue(
            app.descendants(matching: .any)["monglepet.userPet.petName"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(app.descendants(matching: .any)["monglepet.userPet.author"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["monglepet.userPet.version"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["monglepet.userPet.license"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["monglepet.userPet.description"].exists)

        let choosePNGsButton = app.buttons["monglepet.userPet.choosePNGs"]
        XCTAssertTrue(choosePNGsButton.waitForExistence(timeout: 5))
        XCTAssertEqual(choosePNGsButton.label, "PNG 선택…")
        XCTAssertTrue(choosePNGsButton.isHittable)
        XCTAssertTrue(app.buttons["monglepet.userPet.save"].exists)
    }
}
