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

    private func writePNG(to fileURL: URL, width: Int, height: Int) throws {
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
        context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.9, alpha: 0.8))
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
}

private struct UserPetEditorFixture {
    let rootURL: URL
    let libraryURL: URL
}
