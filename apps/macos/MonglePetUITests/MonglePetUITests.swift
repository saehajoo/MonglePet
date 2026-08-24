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
            "monglepet.settings.navigation.petLibrary",
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

        scrollPetTab(in: app, by: -280)

        XCTAssertTrue(
            app.buttons["monglepet.settings.importPackage"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertEqual(
            app.buttons["monglepet.settings.importPackage"].label,
            "패키지 파일 선택…"
        )
        XCTAssertTrue(
            app.buttons["monglepet.settings.browseWebPets"].exists
        )
        XCTAssertTrue(
            app.textFields["monglepet.settings.remotePetURL"].exists
        )
        XCTAssertTrue(
            app.buttons["monglepet.settings.importRemotePackage"].exists
        )
        XCTAssertTrue(
            app.buttons["monglepet.settings.createUserPet"].exists
        )
        XCTAssertFalse(
            app.buttons["monglepet.settings.createEditablePetCopy"].exists
        )

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
            app.staticTexts["활성 펫 추가"].waitForExistence(timeout: 5)
        )
        XCTAssertTrue(app.buttons["추가"].exists)
        XCTAssertTrue(app.buttons["취소"].exists)
    }

    @MainActor
    func testMovementSettingsTabShowsCurrentPetAndMode() throws {
        let app = XCUIApplication()
        app.launchArguments.append("--ui-testing-open-settings")
        app.launch()

        selectSettingsDestination(
            "monglepet.settings.navigation.movement",
            in: app
        )

        XCTAssertTrue(
            app.descendants(matching: .any)["monglepet.settings.movementPetName"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["monglepet.settings.movementMode"]
                .exists
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["monglepet.settings.awake"]
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
            app.descendants(matching: .any)["monglepet.settings.pettingMotion"]
                .exists
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
        XCTAssertTrue(app.descendants(matching: .any)["monglepet.userPet.version"].exists)
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
        XCTAssertTrue(app.buttons["monglepet.userPet.save"].exists)
    }

    @MainActor
    func testPNGEditorKeepsFooterVisibleAndScrollsThroughContent() throws {
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

        let contentScroll = app.scrollViews["monglepet.pngCrop.contentScroll"]
        XCTAssertTrue(contentScroll.waitForExistence(timeout: 5))
        contentScroll.scroll(byDeltaX: 0, deltaY: -620)

        let resultPreview = app.descendants(matching: .any)[
            "monglepet.pngCrop.resultPreview"
        ]
        XCTAssertTrue(resultPreview.waitForExistence(timeout: 5))
        XCTAssertTrue(resultPreview.isHittable)
        XCTAssertTrue(importButton.isHittable)

        let attachment = XCTAttachment(screenshot: window.screenshot())
        attachment.name = "png-editor-scrolled-minimum-size"
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
