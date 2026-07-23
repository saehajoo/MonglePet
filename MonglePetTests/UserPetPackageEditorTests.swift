import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import MonglePet

final class UserPetPackageEditorTests: XCTestCase {
    func testCreatesEditablePetAndAtomicallyAddsPNGAnimation() throws {
        let environment = try makeEnvironment()
        let firstID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let store = PetLibraryStore(
            libraryRootURL: environment.libraryURL,
            installationIDGenerator: { firstID }
        )
        let editor = UserPetPackageEditor(store: store)
        let firstFrameURL = environment.rootURL.appendingPathComponent("frame-1.png")
        let secondFrameURL = environment.rootURL.appendingPathComponent("frame-2.png")
        try writePNG(to: firstFrameURL, width: 4, height: 3)
        try writePNG(to: secondFrameURL, width: 2, height: 5)

        let created = try editor.createPet(
            UserPetCreationRequest(
                displayName: "사용자 펫",
                animationName: "기본",
                frameDurationMilliseconds: 140,
                loops: true,
                sourceURLs: [firstFrameURL, secondFrameURL]
            )
        )

        XCTAssertEqual(created.installationID, firstID)
        XCTAssertTrue(editor.isEditable(created))
        XCTAssertEqual(created.package.definition.defaultMotionID, "기본")
        XCTAssertEqual(
            created.package.compatibility,
            PetPackageCompatibility(
                createdWithMonglePetVersion: MonglePetAppVersion.current.semanticVersion,
                minimumMonglePetVersion: MonglePetAppVersion.current.semanticVersion
            )
        )
        let baseMotion = try XCTUnwrap(created.package.definition.motion(id: "기본"))
        XCTAssertEqual(baseMotion.frames.count, 2)
        XCTAssertEqual(baseMotion.frames.map(\.duration), [.milliseconds(140), .milliseconds(140)])
        XCTAssertEqual(
            baseMotion.frames.map(\.sourceRect),
            [
                PixelRect(x: 0, y: 0, width: 4, height: 5),
                PixelRect(x: 4, y: 0, width: 4, height: 5)
            ]
        )

        let added = try editor.addAnimation(
            UserPetAnimationRequest(
                animationName: "집중",
                frameDurationMilliseconds: 250,
                loops: false,
                sourceURLs: [secondFrameURL]
            ),
            to: created
        )

        XCTAssertEqual(added.installationID, firstID)
        XCTAssertTrue(editor.isEditable(added))
        XCTAssertEqual(added.package.compatibility, created.package.compatibility)
        XCTAssertEqual(added.package.definition.motions.map(\.id), ["기본", "집중"])
        XCTAssertEqual(added.package.atlases.count, 2)
        let focusMotion = try XCTUnwrap(added.package.definition.motion(id: "집중"))
        XCTAssertFalse(focusMotion.loops)
        XCTAssertEqual(focusMotion.frames.map(\.duration), [.milliseconds(250)])
        XCTAssertEqual(store.installedPackages().count, 1)
    }

    func testRejectsDuplicateAnimationNameIgnoringCase() throws {
        let environment = try makeEnvironment()
        let store = PetLibraryStore(libraryRootURL: environment.libraryURL)
        let editor = UserPetPackageEditor(store: store)
        let frameURL = environment.rootURL.appendingPathComponent("frame.png")
        try writePNG(to: frameURL, width: 3, height: 3)
        let created = try editor.createPet(
            UserPetCreationRequest(
                displayName: "사용자 펫",
                animationName: "Idle",
                frameDurationMilliseconds: 120,
                loops: true,
                sourceURLs: [frameURL]
            )
        )

        XCTAssertThrowsError(
            try editor.addAnimation(
                UserPetAnimationRequest(
                    animationName: "idle",
                    frameDurationMilliseconds: 120,
                    loops: true,
                    sourceURLs: [frameURL]
                ),
                to: created
            )
        ) { error in
            XCTAssertEqual(
                error as? UserPetEditingError,
                .duplicateAnimationName("idle")
            )
        }
    }

    func testAtomicallyUpdatesEditablePetDetailsAndDefaultAnimation() throws {
        let environment = try makeEnvironment()
        let installationID = UUID(
            uuidString: "33333333-3333-3333-3333-333333333333"
        )!
        let store = PetLibraryStore(
            libraryRootURL: environment.libraryURL,
            installationIDGenerator: { installationID }
        )
        let editor = UserPetPackageEditor(store: store)
        let frameURL = environment.rootURL.appendingPathComponent("frame.png")
        try writePNG(to: frameURL, width: 4, height: 4)
        let created = try editor.createPet(
            UserPetCreationRequest(
                displayName: "처음 이름",
                animationName: "기본",
                frameDurationMilliseconds: 120,
                loops: true,
                sourceURLs: [frameURL],
                version: "0.1.0",
                author: "처음 제작자",
                license: "Private Use",
                description: "처음 설명"
            )
        )
        XCTAssertEqual(created.package.metadata.version, "0.1.0")
        XCTAssertEqual(created.package.metadata.author, "처음 제작자")
        XCTAssertEqual(created.package.metadata.license, "Private Use")
        XCTAssertEqual(created.package.metadata.description, "처음 설명")
        let withSecondAnimation = try editor.addAnimation(
            UserPetAnimationRequest(
                animationName: "인사",
                frameDurationMilliseconds: 180,
                loops: false,
                sourceURLs: [frameURL]
            ),
            to: created
        )

        let updated = try editor.updateDetails(
            UserPetDetailsRequest(
                displayName: "  새 이름  ",
                version: " 2.0.0 ",
                author: " 새 제작자 ",
                license: " CC-BY-4.0 ",
                description: "  새 설명  ",
                defaultMotionID: "인사"
            ),
            for: withSecondAnimation
        )

        XCTAssertEqual(updated.installationID, installationID)
        XCTAssertEqual(updated.package.metadata.id, created.package.metadata.id)
        XCTAssertEqual(updated.package.metadata.displayName, "새 이름")
        XCTAssertEqual(updated.package.metadata.version, "2.0.0")
        XCTAssertEqual(updated.package.metadata.author, "새 제작자")
        XCTAssertEqual(updated.package.metadata.license, "CC-BY-4.0")
        XCTAssertEqual(updated.package.metadata.description, "새 설명")
        XCTAssertEqual(updated.package.definition.defaultMotionID, "인사")
        XCTAssertEqual(store.installedPackages().count, 1)
        XCTAssertTrue(editor.isEditable(updated))
    }

    func testRejectsInvalidDetailsWithoutChangingInstalledManifest() throws {
        let environment = try makeEnvironment()
        let store = PetLibraryStore(libraryRootURL: environment.libraryURL)
        let editor = UserPetPackageEditor(store: store)
        let frameURL = environment.rootURL.appendingPathComponent("frame.png")
        try writePNG(to: frameURL, width: 3, height: 3)
        let created = try editor.createPet(
            UserPetCreationRequest(
                displayName: "사용자 펫",
                animationName: "기본",
                frameDurationMilliseconds: 120,
                loops: true,
                sourceURLs: [frameURL]
            )
        )
        let manifestURL = created.rootURL.appendingPathComponent("pet.json")
        let originalManifest = try Data(contentsOf: manifestURL)

        XCTAssertThrowsError(
            try editor.updateDetails(
                UserPetDetailsRequest(
                    displayName: "바뀌면 안 됨",
                    version: "2.0.0",
                    author: "제작자",
                    license: "Test",
                    description: nil,
                    defaultMotionID: "없는 애니메이션"
                ),
                for: created
            )
        ) { error in
            XCTAssertEqual(
                error as? UserPetEditingError,
                .invalidDefaultAnimation("없는 애니메이션")
            )
        }

        XCTAssertEqual(try Data(contentsOf: manifestURL), originalManifest)
        XCTAssertEqual(
            store.installedPackages().first?.package.metadata.displayName,
            "사용자 펫"
        )
    }

    func testRenamesAnimationUpdatesDefaultAndRemovesUnusedAtlas() throws {
        let environment = try makeEnvironment()
        let installationID = UUID(
            uuidString: "44444444-4444-4444-4444-444444444444"
        )!
        let store = PetLibraryStore(
            libraryRootURL: environment.libraryURL,
            installationIDGenerator: { installationID }
        )
        let editor = UserPetPackageEditor(store: store)
        let frameURL = environment.rootURL.appendingPathComponent("frame.png")
        try writePNG(to: frameURL, width: 4, height: 4)
        let created = try editor.createPet(
            UserPetCreationRequest(
                displayName: "사용자 펫",
                animationName: "기본",
                frameDurationMilliseconds: 120,
                loops: true,
                sourceURLs: [frameURL]
            )
        )
        let withSecondAnimation = try editor.addAnimation(
            UserPetAnimationRequest(
                animationName: "인사",
                frameDurationMilliseconds: 180,
                loops: true,
                sourceURLs: [frameURL]
            ),
            to: created
        )
        let secondAtlasURL = try XCTUnwrap(
            withSecondAnimation.package.atlases.first { $0.id != "main" }?.fileURL
        )

        let renamedDefault = try editor.updateAnimation(
            UserPetAnimationDetailsRequest(
                animationID: "기본",
                animationName: "대기",
                loops: false,
                frames: [
                    UserPetAnimationFrameRequest(
                        source: .existing(index: 0),
                        durationMilliseconds: 120
                    )
                ]
            ),
            for: withSecondAnimation
        )

        XCTAssertEqual(renamedDefault.installationID, installationID)
        XCTAssertEqual(renamedDefault.package.definition.defaultMotionID, "대기")
        XCTAssertEqual(renamedDefault.package.definition.motions.map(\.id), ["대기", "인사"])
        XCTAssertFalse(try XCTUnwrap(renamedDefault.package.definition.motion(id: "대기")).loops)

        let removed = try editor.removeAnimation(id: "인사", from: renamedDefault)

        XCTAssertEqual(removed.installationID, installationID)
        XCTAssertEqual(removed.package.definition.motions.map(\.id), ["대기"])
        XCTAssertEqual(removed.package.atlases.count, 1)
        XCTAssertEqual(
            removed.package.atlases.first?.id,
            removed.package.definition.motions.first?.frames.first?.atlasID
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: secondAtlasURL.path))
        XCTAssertTrue(editor.isEditable(removed))
    }

    func testRebuildsAnimationWithReorderedExistingAndNewFrames() throws {
        let environment = try makeEnvironment()
        let installationID = UUID(
            uuidString: "77777777-7777-7777-7777-777777777777"
        )!
        let store = PetLibraryStore(
            libraryRootURL: environment.libraryURL,
            installationIDGenerator: { installationID }
        )
        let editor = UserPetPackageEditor(store: store)
        let firstFrameURL = environment.rootURL.appendingPathComponent("first.png")
        let secondFrameURL = environment.rootURL.appendingPathComponent("second.png")
        let addedFrameURL = environment.rootURL.appendingPathComponent("added.png")
        try writePNG(to: firstFrameURL, width: 4, height: 4)
        try writePNG(to: secondFrameURL, width: 3, height: 5)
        try writePNG(to: addedFrameURL, width: 6, height: 2)
        let created = try editor.createPet(
            UserPetCreationRequest(
                displayName: "사용자 펫",
                animationName: "기본",
                frameDurationMilliseconds: 120,
                loops: true,
                sourceURLs: [firstFrameURL, secondFrameURL]
            )
        )
        let originalAtlasURL = try XCTUnwrap(created.package.atlases.first?.fileURL)

        let updated = try editor.updateAnimation(
            UserPetAnimationDetailsRequest(
                animationID: "기본",
                animationName: "새 기본",
                loops: false,
                frames: [
                    UserPetAnimationFrameRequest(
                        source: .existing(index: 1),
                        durationMilliseconds: 275
                    ),
                    UserPetAnimationFrameRequest(
                        source: .png(addedFrameURL),
                        durationMilliseconds: 430
                    )
                ]
            ),
            for: created
        )

        XCTAssertEqual(updated.installationID, installationID)
        XCTAssertEqual(updated.package.definition.defaultMotionID, "새 기본")
        let motion = try XCTUnwrap(updated.package.definition.motion(id: "새 기본"))
        XCTAssertFalse(motion.loops)
        XCTAssertEqual(motion.frames.map(\.duration), [
            .milliseconds(275),
            .milliseconds(430)
        ])
        XCTAssertEqual(motion.frames.map(\.sourceRect), [
            PixelRect(x: 0, y: 0, width: 6, height: 5),
            PixelRect(x: 6, y: 0, width: 6, height: 5)
        ])
        XCTAssertEqual(Set(motion.frames.map(\.atlasID)).count, 1)
        XCTAssertEqual(updated.package.atlases.count, 1)
        XCTAssertNotEqual(updated.package.atlases[0].fileURL, originalAtlasURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: originalAtlasURL.path))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: updated.package.atlases[0].fileURL.path
        ))
        XCTAssertEqual(store.installedPackages().count, 1)
    }

    func testRejectsEmptyAndInvalidDurationAnimationEditsAtomically() throws {
        let environment = try makeEnvironment()
        let store = PetLibraryStore(libraryRootURL: environment.libraryURL)
        let editor = UserPetPackageEditor(store: store)
        let frameURL = environment.rootURL.appendingPathComponent("frame.png")
        try writePNG(to: frameURL, width: 3, height: 3)
        let created = try editor.createPet(
            UserPetCreationRequest(
                displayName: "사용자 펫",
                animationName: "기본",
                frameDurationMilliseconds: 120,
                loops: true,
                sourceURLs: [frameURL]
            )
        )
        let manifestURL = created.rootURL.appendingPathComponent("pet.json")
        let originalManifest = try Data(contentsOf: manifestURL)

        XCTAssertThrowsError(
            try editor.updateAnimation(
                UserPetAnimationDetailsRequest(
                    animationID: "기본",
                    animationName: "기본",
                    loops: true,
                    frames: []
                ),
                for: created
            )
        ) { error in
            XCTAssertEqual(error as? UserPetEditingError, .emptyAnimation)
        }

        XCTAssertThrowsError(
            try editor.updateAnimation(
                UserPetAnimationDetailsRequest(
                    animationID: "기본",
                    animationName: "기본",
                    loops: true,
                    frames: [
                        UserPetAnimationFrameRequest(
                            source: .existing(index: 0),
                            durationMilliseconds: 15
                        )
                    ]
                ),
                for: created
            )
        ) { error in
            XCTAssertEqual(error as? UserPetEditingError, .invalidFrameDuration)
        }

        XCTAssertEqual(try Data(contentsOf: manifestURL), originalManifest)
        XCTAssertEqual(
            store.installedPackages().first?.installationID,
            created.installationID
        )
        XCTAssertEqual(
            store.installedPackages().first?.package.definition,
            created.package.definition
        )
    }

    func testRebuildUsesTopLeftFrameCoordinatesAcrossAtlasRows() throws {
        let environment = try makeEnvironment()
        let store = PetLibraryStore(libraryRootURL: environment.libraryURL)
        let editor = UserPetPackageEditor(store: store)
        var frameURLs: [URL] = []
        for index in 0..<9 {
            let frameURL = environment.rootURL.appendingPathComponent("frame-\(index).png")
            try writePNG(
                to: frameURL,
                width: 2,
                height: 2,
                red: index == 8 ? 0.1 : 0.9,
                green: index == 8 ? 0.9 : 0.1,
                blue: 0.1
            )
            frameURLs.append(frameURL)
        }
        let created = try editor.createPet(
            UserPetCreationRequest(
                displayName: "사용자 펫",
                animationName: "기본",
                frameDurationMilliseconds: 120,
                loops: true,
                sourceURLs: frameURLs
            )
        )

        let updated = try editor.updateAnimation(
            UserPetAnimationDetailsRequest(
                animationID: "기본",
                animationName: "기본",
                loops: true,
                frames: [
                    UserPetAnimationFrameRequest(
                        source: .existing(index: 8),
                        durationMilliseconds: 200
                    )
                ]
            ),
            for: created
        )
        let atlasURL = try XCTUnwrap(updated.package.atlases.first?.fileURL)
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(atlasURL as CFURL, nil))
        let atlasImage = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let pixel = try centerPixel(of: atlasImage)

        XCTAssertGreaterThan(pixel.green, pixel.red)
    }

    func testCreatesUserPetUsingTransparentCanvasPlacement() throws {
        let environment = try makeEnvironment()
        let store = PetLibraryStore(libraryRootURL: environment.libraryURL)
        let editor = UserPetPackageEditor(store: store)
        let frameURL = environment.rootURL.appendingPathComponent("small.png")
        try writePNG(to: frameURL, width: 2, height: 2)

        let created = try editor.createPet(
            UserPetCreationRequest(
                displayName: "배치 펫",
                animationName: "기본",
                loops: true,
                frames: [
                    UserPetSourceFrameRequest(
                        sourceURL: frameURL,
                        durationMilliseconds: 180,
                        placement: FrameCanvasPlacement(
                            canvasWidth: 10,
                            canvasHeight: 10,
                            scale: 3,
                            x: 2,
                            y: 1
                        )
                    )
                ]
            )
        )

        let motion = try XCTUnwrap(created.package.definition.defaultMotion)
        XCTAssertEqual(motion.frames.first?.sourceRect, PixelRect(
            x: 0,
            y: 0,
            width: 10,
            height: 10
        ))
        XCTAssertEqual(motion.frames.first?.duration, .milliseconds(180))
        let atlasURL = try XCTUnwrap(created.package.atlases.first?.fileURL)
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(atlasURL as CFURL, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let content = try FrameCanvasComposer().transparentContent(in: image)
        XCTAssertEqual(content.sourceBounds, PixelRect(
            x: 2,
            y: 1,
            width: 6,
            height: 6
        ))
    }

    func testProtectsDefaultAndLastAnimationsFromDeletion() throws {
        let environment = try makeEnvironment()
        let store = PetLibraryStore(libraryRootURL: environment.libraryURL)
        let editor = UserPetPackageEditor(store: store)
        let frameURL = environment.rootURL.appendingPathComponent("frame.png")
        try writePNG(to: frameURL, width: 3, height: 3)
        let created = try editor.createPet(
            UserPetCreationRequest(
                displayName: "사용자 펫",
                animationName: "기본",
                frameDurationMilliseconds: 120,
                loops: true,
                sourceURLs: [frameURL]
            )
        )

        XCTAssertThrowsError(
            try editor.removeAnimation(id: "기본", from: created)
        ) { error in
            XCTAssertEqual(error as? UserPetEditingError, .cannotDeleteLastAnimation)
        }

        let withSecondAnimation = try editor.addAnimation(
            UserPetAnimationRequest(
                animationName: "인사",
                frameDurationMilliseconds: 120,
                loops: true,
                sourceURLs: [frameURL]
            ),
            to: created
        )
        XCTAssertThrowsError(
            try editor.removeAnimation(id: "기본", from: withSecondAnimation)
        ) { error in
            XCTAssertEqual(error as? UserPetEditingError, .cannotDeleteDefaultAnimation)
        }
        XCTAssertEqual(store.installedPackages().first?.package.definition.motions.count, 2)
    }

    func testCreatesIndependentEditableCopyWithoutChangingReadOnlyOriginal() throws {
        let environment = try makeEnvironment()
        let originalInstallationID = UUID(
            uuidString: "55555555-5555-5555-5555-555555555555"
        )!
        let copyInstallationID = UUID(
            uuidString: "66666666-6666-6666-6666-666666666666"
        )!
        var installationIDs = [originalInstallationID, copyInstallationID]
        let store = PetLibraryStore(
            libraryRootURL: environment.libraryURL,
            installationIDGenerator: { installationIDs.removeFirst() }
        )
        let editor = UserPetPackageEditor(store: store)
        let frameURL = environment.rootURL.appendingPathComponent("frame.png")
        try writePNG(to: frameURL, width: 4, height: 4)
        let original = try editor.createPet(
            UserPetCreationRequest(
                displayName: "가져온 펫",
                animationName: "기본",
                frameDurationMilliseconds: 175,
                loops: false,
                sourceURLs: [frameURL],
                version: "2.3.0",
                author: "원작자",
                license: "CC-BY-4.0",
                description: "원본 설명"
            )
        )
        let originalMarkerURL = original.rootURL.appendingPathComponent(
            UserPetPackageEditor.markerFileName
        )
        try FileManager.default.removeItem(at: originalMarkerURL)
        let originalManifestURL = original.rootURL.appendingPathComponent("pet.json")
        let originalManifest = try Data(contentsOf: originalManifestURL)

        XCTAssertFalse(editor.isEditable(original))

        let copy = try editor.createEditableCopy(
            of: original,
            displayName: "  편집용 펫  "
        )

        XCTAssertEqual(copy.installationID, copyInstallationID)
        XCTAssertNotEqual(copy.installationID, original.installationID)
        XCTAssertNotEqual(copy.package.metadata.id, original.package.metadata.id)
        XCTAssertEqual(copy.package.metadata.displayName, "편집용 펫")
        XCTAssertEqual(copy.package.metadata.version, original.package.metadata.version)
        XCTAssertEqual(copy.package.metadata.author, original.package.metadata.author)
        XCTAssertEqual(copy.package.metadata.license, original.package.metadata.license)
        XCTAssertEqual(copy.package.metadata.description, original.package.metadata.description)
        XCTAssertEqual(
            copy.package.definition.defaultMotionID,
            original.package.definition.defaultMotionID
        )
        XCTAssertEqual(copy.package.definition.motions, original.package.definition.motions)
        XCTAssertTrue(editor.isEditable(copy))
        XCTAssertFalse(editor.isEditable(original))
        XCTAssertEqual(try Data(contentsOf: originalManifestURL), originalManifest)
        XCTAssertEqual(Set(store.installedPackages().map(\.installationID)), [
            originalInstallationID,
            copyInstallationID
        ])

        let editedCopy = try editor.updateDetails(
            UserPetDetailsRequest(
                displayName: "수정된 사본",
                version: copy.package.metadata.version,
                author: copy.package.metadata.author,
                license: copy.package.metadata.license,
                description: copy.package.metadata.description,
                defaultMotionID: copy.package.definition.defaultMotionID
            ),
            for: copy
        )
        XCTAssertEqual(editedCopy.package.metadata.displayName, "수정된 사본")
        XCTAssertEqual(try Data(contentsOf: originalManifestURL), originalManifest)
    }

    func testRejectsEditableCopyCreationFromAlreadyEditablePet() throws {
        let environment = try makeEnvironment()
        let store = PetLibraryStore(libraryRootURL: environment.libraryURL)
        let editor = UserPetPackageEditor(store: store)
        let frameURL = environment.rootURL.appendingPathComponent("frame.png")
        try writePNG(to: frameURL, width: 3, height: 3)
        let created = try editor.createPet(
            UserPetCreationRequest(
                displayName: "사용자 펫",
                animationName: "기본",
                frameDurationMilliseconds: 120,
                loops: true,
                sourceURLs: [frameURL]
            )
        )

        XCTAssertThrowsError(
            try editor.createEditableCopy(of: created, displayName: "사본")
        ) { error in
            XCTAssertEqual(error as? UserPetEditingError, .petIsAlreadyEditable)
        }
        XCTAssertEqual(store.installedPackages().count, 1)
    }

    private func makeEnvironment() throws -> UserPetEditorFixture {
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "MonglePet-UserPetTests-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: false)
        addTeardownBlock { try? FileManager.default.removeItem(at: rootURL) }
        return UserPetEditorFixture(
            rootURL: rootURL,
            libraryURL: rootURL.appendingPathComponent("Library", isDirectory: true)
        )
    }

    private func writePNG(
        to fileURL: URL,
        width: Int,
        height: Int,
        red: CGFloat = 0.2,
        green: CGFloat = 0.5,
        blue: CGFloat = 0.9
    ) throws {
        let context = try XCTUnwrap(
            CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(red: red, green: green, blue: blue, alpha: 0.8))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try XCTUnwrap(context.makeImage())
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

    private func centerPixel(of image: CGImage) throws -> (red: UInt8, green: UInt8) {
        var bytes = [UInt8](repeating: 0, count: 4)
        let context = try XCTUnwrap(
            CGContext(
                data: &bytes,
                width: 1,
                height: 1,
                bitsPerComponent: 8,
                bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        context.interpolationQuality = .none
        context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return (bytes[0], bytes[1])
    }
}

private struct UserPetEditorFixture {
    let rootURL: URL
    let libraryURL: URL
}
