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
            app.descendants(matching: .any)["monglepet.settings.appVersion"].exists
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["monglepet.settings.launchAtLogin"].exists
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

        let movementTab = app.radioButtons["이동"]
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
        XCTAssertTrue(
            app.descendants(matching: .any)["monglepet.settings.pettingMotion"]
                .exists
        )
    }

    @MainActor
    func testAutomaticRulesOffersApplicationSelectionPaths() throws {
        let app = XCUIApplication()
        app.launchArguments.append("--ui-testing-open-settings")
        app.launch()

        let automaticRulesTab = app.radioButtons["자동 규칙"]
        XCTAssertTrue(automaticRulesTab.waitForExistence(timeout: 5))
        automaticRulesTab.click()

        XCTAssertTrue(
            app.descendants(matching: .any)[
                "monglepet.settings.newApplicationRule.selectionMenu"
            ]
            .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(
            app.descendants(matching: .any)[
                "monglepet.settings.newIdleRule.idleMinutes.increment"
            ]
            .exists
        )
        XCTAssertTrue(
            app.descendants(matching: .any)[
                "monglepet.settings.newIdleRule.idleMinutes.decrement"
            ]
            .exists
        )
        XCTAssertTrue(
            app.buttons["monglepet.settings.addApplicationRule"].exists
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
