import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import MonglePet

final class PetPackageLoaderTests: XCTestCase {
    func testLoadsValidDirectoryPackageIntoRuntimeDefinition() throws {
        let fixture = try makePackage()

        let package = try PetPackageLoader().loadPackage(at: fixture.packageURL)

        XCTAssertEqual(package.metadata.id, "com.example.mongle")
        XCTAssertEqual(package.metadata.displayName, "테스트 몽글이")
        XCTAssertEqual(package.metadata.version, "1.0.0")
        XCTAssertEqual(package.atlases.count, 1)
        XCTAssertEqual(package.atlases[0].format, .png)
        XCTAssertEqual(package.atlases[0].pixelSize, PixelSize(width: 4, height: 4))
        XCTAssertEqual(package.definition.defaultMotionID, "idle")
        let idle = try XCTUnwrap(package.definition.defaultMotion)
        XCTAssertEqual(idle.frames.count, 2)
        XCTAssertEqual(idle.frames[0].sourceRect, PixelRect(x: 0, y: 0, width: 2, height: 4))
        XCTAssertEqual(idle.frames[0].duration, .milliseconds(120))
    }

    func testUsesIdleWhenDefaultMotionIsOmitted() throws {
        var manifest = validManifest()
        manifest.removeValue(forKey: "defaultMotion")
        let fixture = try makePackage(manifest: manifest)

        let package = try PetPackageLoader().loadPackage(at: fixture.packageURL)

        XCTAssertEqual(package.definition.defaultMotionID, "idle")
    }

    func testLoadsCompleteAndPartialCompatibilityMetadata() throws {
        var completeManifest = validManifest()
        completeManifest["compatibility"] = [
            "createdWithMonglePetVersion": "0.10.0",
            "minimumMonglePetVersion": "0.2.0"
        ]
        let completeFixture = try makePackage(manifest: completeManifest)

        XCTAssertEqual(
            try PetPackageLoader().loadPackage(at: completeFixture.packageURL)
                .compatibility,
            PetPackageCompatibility(
                createdWithMonglePetVersion: try XCTUnwrap(
                    SemanticVersion("0.10.0")
                ),
                minimumMonglePetVersion: try XCTUnwrap(
                    SemanticVersion("0.2.0")
                )
            )
        )

        var partialManifest = validManifest()
        partialManifest["compatibility"] = [
            "minimumMonglePetVersion": "0.1.0"
        ]
        let partialFixture = try makePackage(manifest: partialManifest)
        let partialCompatibility = try XCTUnwrap(
            try PetPackageLoader().loadPackage(at: partialFixture.packageURL)
                .compatibility
        )

        XCTAssertNil(partialCompatibility.createdWithMonglePetVersion)
        XCTAssertEqual(
            partialCompatibility.minimumMonglePetVersion,
            try XCTUnwrap(SemanticVersion("0.1.0"))
        )
    }

    func testPackageWithoutCompatibilityKeepsLegacyLoadingBehavior() throws {
        let fixture = try makePackage()

        XCTAssertNil(
            try PetPackageLoader().loadPackage(at: fixture.packageURL)
                .compatibility
        )
    }

    func testRejectsMalformedCompatibilityVersion() throws {
        var manifest = validManifest()
        manifest["compatibility"] = [
            "createdWithMonglePetVersion": "0.1-beta"
        ]
        let fixture = try makePackage(manifest: manifest)

        XCTAssertThrowsError(
            try PetPackageLoader().loadPackage(at: fixture.packageURL)
        ) { error in
            XCTAssertEqual(
                error as? PetPackageLoadingError,
                .invalidCompatibilityVersion(
                    field: "createdWithMonglePetVersion",
                    value: "0.1-beta"
                )
            )
        }
    }

    func testRejectsUnsupportedManifestVersion() throws {
        var manifest = validManifest()
        manifest["formatVersion"] = 2
        let fixture = try makePackage(manifest: manifest)

        XCTAssertThrowsError(try PetPackageLoader().loadPackage(at: fixture.packageURL)) { error in
            XCTAssertEqual(error as? PetPackageLoadingError, .unsupportedFormatVersion(2))
        }
    }

    func testRejectsMissingManifestAndReferencedFile() throws {
        let fixture = try makePackage()
        try FileManager.default.removeItem(
            at: fixture.packageURL.appendingPathComponent("pet.json")
        )

        XCTAssertThrowsError(try PetPackageLoader().loadPackage(at: fixture.packageURL)) { error in
            XCTAssertEqual(error as? PetPackageLoadingError, .missingManifest)
        }

        try writeManifest(validManifest(), to: fixture.packageURL)
        try FileManager.default.removeItem(
            at: fixture.packageURL.appendingPathComponent("preview.png")
        )

        XCTAssertThrowsError(try PetPackageLoader().loadPackage(at: fixture.packageURL)) { error in
            XCTAssertEqual(error as? PetPackageLoadingError, .missingReferencedFile("preview.png"))
        }
    }

    func testRejectsPathTraversal() throws {
        var manifest = validManifest()
        manifest["previewPath"] = "../preview.png"
        let fixture = try makePackage(manifest: manifest)

        XCTAssertThrowsError(try PetPackageLoader().loadPackage(at: fixture.packageURL)) { error in
            XCTAssertEqual(error as? PetPackageLoadingError, .invalidRelativePath("../preview.png"))
        }
    }

    func testRejectsSymbolicLinks() throws {
        let fixture = try makePackage()
        let atlasURL = fixture.packageURL.appendingPathComponent("assets/spritesheet.png")
        let externalURL = fixture.temporaryURL.appendingPathComponent("external.png")
        try FileManager.default.moveItem(at: atlasURL, to: externalURL)
        try FileManager.default.createSymbolicLink(at: atlasURL, withDestinationURL: externalURL)

        XCTAssertThrowsError(try PetPackageLoader().loadPackage(at: fixture.packageURL)) { error in
            XCTAssertEqual(error as? PetPackageLoadingError, .symbolicLink("assets/spritesheet.png"))
        }
    }

    func testRejectsExecutableOrScriptFiles() throws {
        let fixture = try makePackage()
        try Data("#!/bin/sh".utf8).write(
            to: fixture.packageURL.appendingPathComponent("run.sh")
        )

        XCTAssertThrowsError(try PetPackageLoader().loadPackage(at: fixture.packageURL)) { error in
            XCTAssertEqual(error as? PetPackageLoadingError, .unsupportedFileType("run.sh"))
        }
    }

    func testRejectsAtlasDimensionMismatch() throws {
        var manifest = validManifest()
        var atlases = try XCTUnwrap(manifest["atlases"] as? [[String: Any]])
        atlases[0]["pixelWidth"] = 8
        manifest["atlases"] = atlases
        let fixture = try makePackage(manifest: manifest)

        XCTAssertThrowsError(try PetPackageLoader().loadPackage(at: fixture.packageURL)) { error in
            XCTAssertEqual(
                error as? PetPackageLoadingError,
                .imageDimensionsMismatch("assets/spritesheet.png")
            )
        }
    }

    func testRejectsAtlasWithoutAlphaChannel() throws {
        let fixture = try makePackage(atlasHasAlpha: false)

        XCTAssertThrowsError(try PetPackageLoader().loadPackage(at: fixture.packageURL)) { error in
            XCTAssertEqual(
                error as? PetPackageLoadingError,
                .imageMissingAlpha("assets/spritesheet.png")
            )
        }
    }

    func testRejectsExtensionAndImageFormatMismatch() throws {
        var manifest = validManifest()
        var atlases = try XCTUnwrap(manifest["atlases"] as? [[String: Any]])
        atlases[0]["path"] = "assets/spritesheet.webp"
        manifest["atlases"] = atlases
        let fixture = try makePackage(manifest: manifest, atlasPath: "assets/spritesheet.webp")

        XCTAssertThrowsError(try PetPackageLoader().loadPackage(at: fixture.packageURL)) { error in
            XCTAssertEqual(
                error as? PetPackageLoadingError,
                .imageFormatMismatch("assets/spritesheet.webp")
            )
        }
    }

    func testRecognizesStaticWebPAndRejectsMissingAlpha() throws {
        var manifest = validManifest()
        var atlases = try XCTUnwrap(manifest["atlases"] as? [[String: Any]])
        atlases[0]["path"] = "assets/spritesheet.webp"
        atlases[0]["pixelWidth"] = 1
        atlases[0]["pixelHeight"] = 1
        manifest["atlases"] = atlases
        var motions = try XCTUnwrap(manifest["motions"] as? [[String: Any]])
        motions[0]["frames"] = [
            ["x": 0, "y": 0, "width": 1, "height": 1, "durationMs": 120]
        ]
        manifest["motions"] = motions
        let webPData = try XCTUnwrap(
            Data(
                base64Encoded: "UklGRiIAAABXRUJQVlA4IBYAAAAwAQCdASoBAAEADMDOJaQAA3AA/v89WAAAAA=="
            )
        )
        let fixture = try makePackage(
            manifest: manifest,
            atlasPath: "assets/spritesheet.webp",
            atlasData: webPData
        )

        XCTAssertThrowsError(try PetPackageLoader().loadPackage(at: fixture.packageURL)) { error in
            XCTAssertEqual(
                error as? PetPackageLoadingError,
                .imageMissingAlpha("assets/spritesheet.webp")
            )
        }
    }

    func testRejectsDuplicateMotionIdentifiers() throws {
        var manifest = validManifest()
        let motions = try XCTUnwrap(manifest["motions"] as? [[String: Any]])
        manifest["motions"] = [motions[0], motions[0]]
        let fixture = try makePackage(manifest: manifest)

        XCTAssertThrowsError(try PetPackageLoader().loadPackage(at: fixture.packageURL)) { error in
            XCTAssertEqual(
                error as? PetPackageLoadingError,
                .duplicateIdentifier(kind: "motion", id: "idle")
            )
        }
    }

    func testRejectsMissingDefaultMotionAndAtlasReferences() throws {
        var manifest = validManifest()
        manifest["defaultMotion"] = "sleep"
        let fixture = try makePackage(manifest: manifest)

        XCTAssertThrowsError(try PetPackageLoader().loadPackage(at: fixture.packageURL)) { error in
            XCTAssertEqual(error as? PetPackageLoadingError, .missingDefaultMotion("sleep"))
        }

        var motions = try XCTUnwrap(manifest["motions"] as? [[String: Any]])
        motions[0]["atlas"] = "missing"
        manifest["motions"] = motions
        try writeManifest(manifest, to: fixture.packageURL)

        XCTAssertThrowsError(try PetPackageLoader().loadPackage(at: fixture.packageURL)) { error in
            XCTAssertEqual(error as? PetPackageLoadingError, .missingAtlas("missing"))
        }
    }

    func testRejectsFrameOutsideAtlasOrInvalidDuration() throws {
        var manifest = validManifest()
        var motions = try XCTUnwrap(manifest["motions"] as? [[String: Any]])
        var frames = try XCTUnwrap(motions[0]["frames"] as? [[String: Any]])
        frames[0]["x"] = 4
        motions[0]["frames"] = frames
        manifest["motions"] = motions
        let fixture = try makePackage(manifest: manifest)

        XCTAssertThrowsError(try PetPackageLoader().loadPackage(at: fixture.packageURL)) { error in
            XCTAssertEqual(
                error as? PetPackageLoadingError,
                .invalidFrame(motionID: "idle", index: 0)
            )
        }

        frames[0]["x"] = 0
        frames[0]["durationMs"] = 15
        motions[0]["frames"] = frames
        manifest["motions"] = motions
        try writeManifest(manifest, to: fixture.packageURL)

        XCTAssertThrowsError(try PetPackageLoader().loadPackage(at: fixture.packageURL)) { error in
            XCTAssertEqual(
                error as? PetPackageLoadingError,
                .invalidFrame(motionID: "idle", index: 0)
            )
        }
    }

    func testRejectsConfiguredPackageAndDecodedPixelLimits() throws {
        let fixture = try makePackage()
        let byteLimits = PetPackageLimits(
            maximumExpandedByteCount: 1,
            maximumImageDimension: 8_192,
            maximumDecodedPixelCount: 64 * 1_024 * 1_024,
            maximumMotionCount: 100,
            maximumFrameCount: 1_000
        )

        XCTAssertThrowsError(
            try PetPackageLoader(limits: byteLimits).loadPackage(at: fixture.packageURL)
        ) { error in
            XCTAssertEqual(error as? PetPackageLoadingError, .packageTooLarge)
        }

        let pixelLimits = PetPackageLimits(
            maximumExpandedByteCount: 100 * 1_024 * 1_024,
            maximumImageDimension: 8_192,
            maximumDecodedPixelCount: 16,
            maximumMotionCount: 100,
            maximumFrameCount: 1_000
        )
        XCTAssertThrowsError(
            try PetPackageLoader(limits: pixelLimits).loadPackage(at: fixture.packageURL)
        ) { error in
            XCTAssertEqual(error as? PetPackageLoadingError, .limitExceeded("전체 디코딩 픽셀"))
        }

        let frameLimits = PetPackageLimits(
            maximumExpandedByteCount: 100 * 1_024 * 1_024,
            maximumImageDimension: 8_192,
            maximumDecodedPixelCount: 64 * 1_024 * 1_024,
            maximumMotionCount: 100,
            maximumFrameCount: 1
        )
        XCTAssertThrowsError(
            try PetPackageLoader(limits: frameLimits).loadPackage(at: fixture.packageURL)
        ) { error in
            XCTAssertEqual(error as? PetPackageLoadingError, .limitExceeded("전체 프레임 수"))
        }
    }

    private func makePackage(
        manifest: [String: Any]? = nil,
        atlasPath: String = "assets/spritesheet.png",
        atlasHasAlpha: Bool = true,
        atlasData: Data? = nil
    ) throws -> PackageFixture {
        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let packageURL = temporaryURL.appendingPathComponent("test.monglepet", isDirectory: true)
        try FileManager.default.createDirectory(
            at: packageURL.appendingPathComponent("assets", isDirectory: true),
            withIntermediateDirectories: true
        )
        addTeardownBlock {
            try? FileManager.default.removeItem(at: temporaryURL)
        }

        try writePNG(
            to: packageURL.appendingPathComponent("preview.png"),
            width: 2,
            height: 2,
            hasAlpha: true
        )
        let atlasURL = packageURL.appendingPathComponent(atlasPath)
        if let atlasData {
            try atlasData.write(to: atlasURL)
        } else {
            try writePNG(
                to: atlasURL,
                width: 4,
                height: 4,
                hasAlpha: atlasHasAlpha
            )
        }
        try writeManifest(manifest ?? validManifest(), to: packageURL)
        return PackageFixture(temporaryURL: temporaryURL, packageURL: packageURL)
    }

    private func validManifest() -> [String: Any] {
        [
            "formatVersion": 1,
            "id": "com.example.mongle",
            "displayName": "테스트 몽글이",
            "version": "1.0.0",
            "author": "Tester",
            "license": "All Rights Reserved",
            "description": "Package loader fixture",
            "previewPath": "preview.png",
            "defaultMotion": "idle",
            "atlases": [[
                "id": "main",
                "path": "assets/spritesheet.png",
                "pixelWidth": 4,
                "pixelHeight": 4
            ]],
            "motions": [[
                "id": "idle",
                "atlas": "main",
                "loop": true,
                "frames": [
                    ["x": 0, "y": 0, "width": 2, "height": 4, "durationMs": 120],
                    ["x": 2, "y": 0, "width": 2, "height": 4, "durationMs": 180]
                ]
            ]]
        ]
    }

    private func writeManifest(_ manifest: [String: Any], to packageURL: URL) throws {
        let data = try JSONSerialization.data(
            withJSONObject: manifest,
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: packageURL.appendingPathComponent("pet.json"))
    }

    private func writePNG(
        to fileURL: URL,
        width: Int,
        height: Int,
        hasAlpha: Bool
    ) throws {
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 255, count: height * bytesPerRow)
        let bitmapInfo = hasAlpha
            ? CGImageAlphaInfo.premultipliedLast.rawValue
            : CGImageAlphaInfo.noneSkipLast.rawValue
        let image = try pixels.withUnsafeMutableBytes { bytes in
            let context = try XCTUnwrap(
                CGContext(
                    data: bytes.baseAddress,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: bytesPerRow,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: bitmapInfo
                )
            )
            return try XCTUnwrap(context.makeImage())
        }
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

private struct PackageFixture {
    let temporaryURL: URL
    let packageURL: URL
}
