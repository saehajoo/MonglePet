//
//  MonglePetTests.swift
//  MonglePetTests
//
//  Created by netsprint on 7/21/26.
//

import ImageIO
import UniformTypeIdentifiers
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
            petLibrarySession: PetLibrarySession(
                builtInDefinition: BuiltInPet.mongleDefinition(
                    atlasPixelSize: PixelSize(width: 192, height: 208)
                ),
                installedPackagesProvider: { [] },
                installationRemover: { _ in }
            ),
            loginLaunchSettings: LoginLaunchSettings()
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
    func testPetOverlaySwitchesBetweenRegisteredAtlases() throws {
        let firstImage = try makeImage(width: 20, height: 10)
        let secondImage = try makeImage(width: 12, height: 24)
        let view = try XCTUnwrap(
            PetOverlayView(
                atlasID: "first",
                image: NSImage(
                    cgImage: firstImage,
                    size: NSSize(width: 20, height: 10)
                )
            )
        )
        view.replaceAtlases(
            [
                PetAtlasImage(
                    id: "first",
                    image: firstImage,
                    pixelSize: PixelSize(width: 20, height: 10)
                ),
                PetAtlasImage(
                    id: "second",
                    image: secondImage,
                    pixelSize: PixelSize(width: 12, height: 24)
                )
            ],
            accessibilityLabel: "테스트 펫"
        )

        XCTAssertTrue(
            view.display(
                MotionFrame(
                    atlasID: "second",
                    sourceRect: PixelRect(x: 0, y: 0, width: 12, height: 24),
                    duration: .milliseconds(100)
                )
            )
        )
        XCTAssertEqual(view.displayedAtlasID, "second")
        XCTAssertFalse(
            view.display(
                MotionFrame(
                    atlasID: "missing",
                    sourceRect: PixelRect(x: 0, y: 0, width: 1, height: 1),
                    duration: .milliseconds(100)
                )
            )
        )
    }

    @MainActor
    func testPetPresentationResourceLoaderProvidesBuiltInAtlasForPreview() throws {
        let definition = BuiltInPet.mongleDefinition(
            atlasPixelSize: PixelSize(width: 192, height: 208)
        )
        let session = PetLibrarySession(
            builtInDefinition: definition,
            installedPackagesProvider: { [] },
            installationRemover: { _ in }
        )

        let atlases = try PetPresentationResourceLoader.loadAtlases(
            for: session.selectedItem
        )

        let atlas = try XCTUnwrap(atlases.first)
        XCTAssertEqual(atlases.count, 1)
        XCTAssertEqual(atlas.id, BuiltInPet.atlasID)
        XCTAssertGreaterThan(atlas.pixelSize.width, 0)
        XCTAssertGreaterThan(atlas.pixelSize.height, 0)
    }

    @MainActor
    func testPetWindowAppliesInstalledPetDefinitionAtlasAndFrameAspectRatio() throws {
        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporaryURL) }
        try FileManager.default.createDirectory(
            at: temporaryURL.appendingPathComponent("assets", isDirectory: true),
            withIntermediateDirectories: true
        )
        try writePNG(
            to: temporaryURL.appendingPathComponent("preview.png"),
            width: 12,
            height: 24
        )
        try writePNG(
            to: temporaryURL.appendingPathComponent("assets/atlas.png"),
            width: 12,
            height: 24
        )
        let manifest: [String: Any] = [
            "formatVersion": 1,
            "id": "test.tall-pet",
            "displayName": "세로 펫",
            "version": "1.0.0",
            "author": "Tester",
            "license": "Test",
            "previewPath": "preview.png",
            "defaultMotion": "idle",
            "atlases": [[
                "id": "main",
                "path": "assets/atlas.png",
                "pixelWidth": 12,
                "pixelHeight": 24
            ]],
            "motions": [[
                "id": "idle",
                "atlas": "main",
                "loop": true,
                "frames": [[
                    "x": 0,
                    "y": 0,
                    "width": 12,
                    "height": 24,
                    "durationMs": 120
                ]]
            ]]
        ]
        try JSONSerialization.data(withJSONObject: manifest)
            .write(to: temporaryURL.appendingPathComponent("pet.json"))
        let package = try PetPackageLoader().loadPackage(at: temporaryURL)
        let installationID = UUID(
            uuidString: "11111111-1111-1111-1111-111111111111"
        )!
        let installed = InstalledPetPackage(
            installationID: installationID,
            rootURL: temporaryURL,
            package: package
        )
        let item = PetLibraryItem(
            selection: .installed(installationID),
            metadata: package.metadata,
            previewURL: package.previewURL,
            definition: package.definition,
            installedPackage: installed
        )
        let controller = PetWindowController()
        let panel = try XCTUnwrap(controller.panel)
        controller.wake()

        try controller.applyPet(item)

        XCTAssertEqual(controller.petDefinition.id, "test.tall-pet")
        XCTAssertEqual(controller.activeInstallationID, installationID)
        XCTAssertEqual(panel.frame.height, panel.frame.width * 2, accuracy: 0.001)
        XCTAssertTrue(controller.isAnimationPlaying)
        controller.sleep()
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
            clickThrough: true,
            opacity: 0.65,
            pointerOverlapFadeEnabled: true,
            pointerOverlapOpacity: 0.15
        )

        controller.applyOverlaySettings(settings, restorePosition: true)

        XCTAssertEqual(panel.frame.width, 288, accuracy: 0.001)
        XCTAssertEqual(panel.frame.height, 312, accuracy: 0.001)
        XCTAssertTrue(panel.ignoresMouseEvents)
        XCTAssertEqual(panel.alphaValue, 0.65, accuracy: 0.001)
        XCTAssertTrue(
            NSScreen.screens.map(\.visibleFrame).contains { $0.contains(panel.frame) }
        )

        let captured = try XCTUnwrap(controller.currentOverlaySettings())
        XCTAssertEqual(captured.width, 288, accuracy: 0.001)
        XCTAssertTrue(captured.clickThrough)
        XCTAssertEqual(captured.opacity, 0.65, accuracy: 0.001)
        XCTAssertTrue(captured.pointerOverlapFadeEnabled)
        XCTAssertEqual(
            captured.pointerOverlapOpacity,
            0.15,
            accuracy: 0.001
        )
        XCTAssertEqual(captured.originX, panel.frame.minX, accuracy: 0.001)
        XCTAssertEqual(captured.originY, panel.frame.minY, accuracy: 0.001)
    }

    @MainActor
    func testPetWindowMovementAdapterDoesNotPersistAutomaticOrigin() throws {
        let controller = PetWindowController()
        let panel = try XCTUnwrap(controller.panel)
        var geometryChangeCount = 0
        controller.onOverlayGeometryDidChange = {
            geometryChangeCount += 1
        }

        controller.setMovementOrigin(PetMovementPoint(x: 240, y: 180))

        XCTAssertEqual(panel.frame.origin, NSPoint(x: 240, y: 180))
        XCTAssertEqual(controller.movementOrigin, PetMovementPoint(x: 240, y: 180))
        XCTAssertEqual(
            controller.movementSize,
            PetMovementSize(
                width: Double(panel.frame.width),
                height: Double(panel.frame.height)
            )
        )
        XCTAssertEqual(geometryChangeCount, 0)
    }

    @MainActor
    func testPetWindowUserDragPausesBeforePersistingGeometry() {
        let controller = PetWindowController()
        var events: [String] = []
        controller.onUserDragStateDidChange = {
            events.append("drag:\($0)")
        }
        controller.onOverlayGeometryDidChange = {
            events.append("geometry")
        }

        controller.userDragDidBegin()
        XCTAssertTrue(controller.isUserDragging)
        controller.userDragDidEnd()

        XCTAssertFalse(controller.isUserDragging)
        XCTAssertEqual(events, ["drag:true", "drag:false", "geometry"])
    }

    @MainActor
    func testPetWindowClickDoesNotPersistGeometryAndRequestsPetting() {
        let controller = PetWindowController()
        var events: [String] = []
        controller.onUserDragStateDidChange = {
            events.append("drag:\($0)")
        }
        controller.onOverlayGeometryDidChange = {
            events.append("geometry")
        }
        controller.onPettingRequested = {
            events.append("petting")
        }

        controller.wake()
        controller.userDragDidBegin()
        controller.userDragDidEnd(didMove: false)
        controller.pettingDidRequest()
        controller.sleep()

        XCTAssertEqual(events, ["drag:true", "drag:false", "petting"])
    }

    @MainActor
    func testPetOverlayDistinguishesClickFromWindowDrag() {
        let origin = NSPoint(x: 100, y: 200)

        XCTAssertFalse(PetOverlayView.didMove(from: origin, to: origin))
        XCTAssertFalse(
            PetOverlayView.didMove(
                from: origin,
                to: NSPoint(x: 102, y: 200)
            )
        )
        XCTAssertTrue(
            PetOverlayView.didMove(
                from: origin,
                to: NSPoint(x: 104, y: 200)
            )
        )
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

    private func makeImage(width: Int, height: Int) throws -> CGImage {
        let context = try XCTUnwrap(
            CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        context.setFillColor(NSColor.systemBlue.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try XCTUnwrap(context.makeImage())
    }

    private func writePNG(to fileURL: URL, width: Int, height: Int) throws {
        let image = try makeImage(width: width, height: height)
        let destination = try XCTUnwrap(
            CGImageDestinationCreateWithURL(
                fileURL as CFURL,
                UTType.png.identifier as CFString,
                1,
                nil
            )
        )
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }
}
