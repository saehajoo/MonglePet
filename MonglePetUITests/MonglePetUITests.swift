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
            app.images["monglepet.settings.petPreview"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["monglepet.settings.petAnimations"]
                .exists
        )

        scrollPetTab(in: app, by: -280)

        XCTAssertTrue(
            app.buttons["monglepet.settings.importPackage"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertEqual(
            app.buttons["monglepet.settings.importPackage"].label,
            "패키지 가져오기"
        )
        XCTAssertTrue(
            app.buttons["monglepet.settings.createUserPet"].exists
        )
        XCTAssertFalse(
            app.buttons["monglepet.settings.createEditablePetCopy"].exists
        )

        let generalTab = app.radioButtons["일반"]
        XCTAssertTrue(generalTab.exists)
        generalTab.click()

        XCTAssertTrue(
            app.descendants(matching: .any)["monglepet.settings.awake"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["monglepet.settings.behaviorMode"]
                .exists
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["monglepet.settings.overlayWidth"]
                .exists
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["monglepet.settings.clickThrough"]
                .exists
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["monglepet.settings.appVersion"]
                .exists
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["monglepet.settings.launchAtLogin"]
                .exists
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

        scrollPetTab(in: app, by: -280)

        let createButton = app.buttons["monglepet.settings.createUserPet"]
        XCTAssertTrue(createButton.waitForExistence(timeout: 5))
        XCTAssertEqual(createButton.label, "새 펫 만들기")
        createButton.click()

        XCTAssertTrue(
            app.descendants(matching: .any)["monglepet.userPet.petName"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(app.descendants(matching: .any)["monglepet.userPet.author"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["monglepet.userPet.version"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["monglepet.userPet.license"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["monglepet.userPet.description"].exists)

        let frameImportMenu = app.descendants(matching: .any)[
            "monglepet.userPet.frameImportMenu"
        ]
        XCTAssertTrue(frameImportMenu.waitForExistence(timeout: 5))
        frameImportMenu.click()

        let choosePNGsMenuItem = app.menuItems["개별 PNG 추가…"]
        XCTAssertTrue(choosePNGsMenuItem.waitForExistence(timeout: 5))
        XCTAssertTrue(choosePNGsMenuItem.isHittable)
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(app.buttons["monglepet.userPet.save"].exists)
    }

    @MainActor
    private func scrollPetTab(
        in app: XCUIApplication,
        by deltaY: CGFloat
    ) {
        let scrollView = app.scrollViews.firstMatch
        XCTAssertTrue(scrollView.waitForExistence(timeout: 5))
        scrollView.scroll(byDeltaX: 0, deltaY: deltaY)
    }
}
