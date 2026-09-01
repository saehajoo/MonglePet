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

        selectSettingsDestination(
            "monglepet.settings.navigation.activePets",
            in: app
        )
        XCTAssertTrue(
            app.buttons["monglepet.settings.createUserPet"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(app.buttons["monglepet.settings.importPet"].exists)
        XCTAssertTrue(app.buttons["monglepet.settings.createPetCopy"].exists)

        selectSettingsDestination(
            "monglepet.settings.navigation.petContent",
            in: app
        )
        XCTAssertTrue(
            app.images["monglepet.settings.petPreview"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["monglepet.settings.petAnimations"]
                .exists
        )

        XCTAssertTrue(app.buttons["monglepet.settings.editPetDetails"].exists)
        XCTAssertTrue(app.buttons["monglepet.settings.addPetAnimation"].exists)

        selectSettingsDestination(
            "monglepet.settings.navigation.general",
            in: app
        )

        XCTAssertTrue(
            app.descendants(matching: .any)["monglepet.settings.appVersion"]
                .waitForExistence(timeout: 5)
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
    func testActivePetsIsDefaultAndOffersManagementActions() throws {
        let app = XCUIApplication()
        app.launchArguments.append("--ui-testing-open-settings")
        app.launch()

        XCTAssertTrue(
            app.descendants(matching: .any)["monglepet.settings.activePets"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(app.buttons["모두 깨우기"].exists)
        XCTAssertTrue(app.buttons["모두 재우기"].exists)
        XCTAssertTrue(app.buttons["모두 일시정지"].exists)
        XCTAssertTrue(
            app.descendants(matching: .any)[
                "monglepet.settings.activePetCard"
            ].exists
        )

        let addButton = app.buttons["monglepet.settings.addActivePet"]
        XCTAssertTrue(addButton.exists)
        addButton.click()

        XCTAssertTrue(
            app.staticTexts["내 펫에 추가"].waitForExistence(timeout: 5)
        )
        XCTAssertTrue(app.buttons["추가"].exists)
        XCTAssertTrue(app.buttons["취소"].exists)
    }

    @MainActor
    func testSelectedPetSettingsAreSplitIntoNativeSidebarDestinations() throws {
        let app = XCUIApplication()
        app.launchArguments.append("--ui-testing-open-settings")
        app.launch()

        selectSettingsDestination(
            "monglepet.settings.navigation.display",
            in: app
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["monglepet.settings.movementPetName"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["monglepet.settings.overlayWidth"]
                .exists
        )
        let tenPercentButton =
            app.descendants(matching: .any)[
                "monglepet.settings.quickScale.10"
            ]
        XCTAssertTrue(tenPercentButton.exists)
        tenPercentButton.click()
        XCTAssertTrue(
            app.descendants(matching: .any)[
                "monglepet.settings.smallPetWarning"
            ]
            .waitForExistence(timeout: 2)
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["monglepet.settings.clickThrough"]
                .exists
        )

        selectSettingsDestination(
            "monglepet.settings.navigation.stationaryBehavior",
            in: app
        )
        XCTAssertTrue(
            app.descendants(matching: .any)[
                "monglepet.settings.stationaryBehaviorMode"
            ]
            .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(
            app.descendants(matching: .any)[
                "monglepet.settings.stationaryBehavior"
            ]
            .exists
        )

        selectSettingsDestination(
            "monglepet.settings.navigation.movement",
            in: app
        )

        XCTAssertTrue(
            app.descendants(matching: .any)["monglepet.settings.movementMode"]
                .waitForExistence(timeout: 5)
        )
        selectSettingsDestination(
            "monglepet.settings.navigation.interaction",
            in: app
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["monglepet.settings.pettingMotion"]
                .waitForExistence(timeout: 5)
        )
    }

    @MainActor
    func testAutomaticRulesOffersApplicationSelectionPaths() throws {
        let app = XCUIApplication()
        app.launchArguments.append("--ui-testing-open-settings")
        app.launch()

        selectSettingsDestination(
            "monglepet.settings.navigation.automaticRules",
            in: app
        )

        XCTAssertTrue(
            app.staticTexts["규칙 및 이동 우선순위"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertFalse(
            app.descendants(matching: .any)[
                "monglepet.settings.stationaryBehaviorMode"
            ]
            .exists
        )
        XCTAssertTrue(
            app.descendants(matching: .any)[
                "monglepet.settings.newApplicationRule.selectionMenu"
            ]
            .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(
            app.descendants(matching: .any)[
                "monglepet.settings.newIdleRule.idleSeconds.increment"
            ]
            .exists
        )
        XCTAssertTrue(
            app.descendants(matching: .any)[
                "monglepet.settings.newIdleRule.idleSeconds.decrement"
            ]
            .exists
        )
        XCTAssertTrue(app.staticTexts["초"].exists)
        XCTAssertTrue(
            app.descendants(matching: .any)[
                "monglepet.settings.idleRuleEnabled"
            ]
            .exists
        )
        XCTAssertTrue(
            app.buttons["monglepet.settings.changeIdleRule"].exists
        )
        XCTAssertTrue(
            app.buttons["monglepet.settings.priority.movement.down"].exists
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

        selectSettingsDestination(
            "monglepet.settings.navigation.petLibrary",
            in: app
        )
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
        let versionField = app.descendants(matching: .any)[
            "monglepet.userPet.version"
        ]
        XCTAssertTrue(versionField.exists)
        XCTAssertTrue(app.descendants(matching: .any)["monglepet.userPet.description"].exists)
        let frameDuration = app.descendants(matching: .any)[
            "monglepet.userPet.frameDuration"
        ]
        XCTAssertTrue(frameDuration.exists)
        XCTAssertEqual(frameDuration.value as? String, "450")

        let frameImportMenu = app.descendants(matching: .any)[
            "monglepet.userPet.frameImportMenu"
        ]
        XCTAssertTrue(frameImportMenu.waitForExistence(timeout: 5))
        frameImportMenu.click()

        let choosePNGsMenuItem = app.menuItems["개별 PNG 추가…"]
        XCTAssertTrue(choosePNGsMenuItem.waitForExistence(timeout: 5))
        XCTAssertTrue(choosePNGsMenuItem.isHittable)
        XCTAssertFalse(app.menuItems["AI 제작 프롬프트 복사"].exists)
        app.typeKey(.escape, modifierFlags: [])

        versionField.click()
        versionField.typeKey("a", modifierFlags: .command)
        versionField.typeText("01.0.0")
        XCTAssertTrue(
            app.staticTexts["monglepet.userPet.versionError"]
                .waitForExistence(timeout: 2)
        )
        XCTAssertTrue(app.buttons["monglepet.userPet.save"].exists)
    }

    @MainActor
    func testPNGEditorKeepsResultPreviewVisibleWhileSettingsScroll() throws {
        let app = XCUIApplication()
        app.launchArguments.append("--ui-testing-open-png-editor")
        app.launch()

        let window = app.windows["PNG 프레임 자르기"]
        XCTAssertTrue(window.waitForExistence(timeout: 5))

        let importButton = app.buttons["monglepet.pngCrop.import"]
        XCTAssertTrue(importButton.waitForExistence(timeout: 5))
        XCTAssertTrue(importButton.isHittable)

        let zoomOut = app.buttons["monglepet.imageEditor.zoomOut"]
        let zoomIn = app.buttons["monglepet.imageEditor.zoomIn"]
        XCTAssertTrue(zoomOut.waitForExistence(timeout: 5))
        XCTAssertTrue(zoomIn.exists)
        XCTAssertEqual(zoomOut.frame.height, zoomIn.frame.height, accuracy: 1)

        let resultPreview = app.descendants(matching: .any)[
            "monglepet.pngCrop.resultPreview"
        ]
        XCTAssertTrue(resultPreview.waitForExistence(timeout: 5))
        XCTAssertTrue(resultPreview.isHittable)

        let resultPanel = app.descendants(matching: .any)[
            "monglepet.pngCrop.resultPanel"
        ]
        XCTAssertTrue(resultPanel.waitForExistence(timeout: 5))

        let settingsScroll = app.scrollViews[
            "monglepet.pngCrop.settingsScroll"
        ]
        XCTAssertTrue(settingsScroll.waitForExistence(timeout: 5))
        settingsScroll.scroll(byDeltaX: 0, deltaY: -420)

        let selectAll = app.buttons["monglepet.pngCrop.selectAll"]
        XCTAssertTrue(selectAll.waitForExistence(timeout: 5))
        selectAll.click()

        let nextResult = app.buttons[
            "monglepet.pngCrop.nextSelectedResult"
        ]
        XCTAssertTrue(nextResult.waitForExistence(timeout: 5))
        XCTAssertTrue(nextResult.isEnabled)
        nextResult.click()

        XCTAssertTrue(resultPanel.isHittable)
        XCTAssertTrue(resultPreview.isHittable)
        XCTAssertTrue(importButton.isHittable)

        let attachment = XCTAttachment(screenshot: window.screenshot())
        attachment.name = "png-editor-pinned-result-preview"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testSpriteEditorKeepsSelectedPreviewVisibleWhileSettingsScroll() throws {
        let app = XCUIApplication()
        app.launchArguments.append("--ui-testing-open-sprite-editor")
        app.launch()

        let window = app.windows["스프라이트 시트 가져오기"]
        XCTAssertTrue(window.waitForExistence(timeout: 5))

        let sheetPreview = app.descendants(matching: .any)[
            "monglepet.spriteSheet.preview"
        ]
        XCTAssertTrue(sheetPreview.waitForExistence(timeout: 5))
        XCTAssertLessThanOrEqual(sheetPreview.frame.height, 180)

        let selectedPreview = app.descendants(matching: .any)[
            "monglepet.spriteSheet.selectedRegionPanel"
        ]
        XCTAssertTrue(selectedPreview.waitForExistence(timeout: 5))
        XCTAssertTrue(selectedPreview.isHittable)

        let settingsScroll = app.scrollViews[
            "monglepet.spriteSheet.settingsScroll"
        ]
        XCTAssertTrue(settingsScroll.waitForExistence(timeout: 5))
        settingsScroll.scroll(byDeltaX: 0, deltaY: -420)

        XCTAssertTrue(selectedPreview.isHittable)
        XCTAssertTrue(app.buttons["monglepet.spriteSheet.import"].isHittable)

        let attachment = XCTAttachment(screenshot: window.screenshot())
        attachment.name = "sprite-editor-pinned-selected-preview"
        attachment.lifetime = .keepAlways
        add(attachment)
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

    @MainActor
    private func selectSettingsDestination(
        _ identifier: String,
        in app: XCUIApplication
    ) {
        let destination = app.descendants(matching: .any)[identifier]
        XCTAssertTrue(destination.waitForExistence(timeout: 5))
        destination.click()
    }
}
