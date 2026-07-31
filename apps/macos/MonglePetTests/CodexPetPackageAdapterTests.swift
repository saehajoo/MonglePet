import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import MonglePet

final class CodexPetPackageAdapterTests: XCTestCase {
    func testConvertsConfiguredLocalWebPFixture() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let fixturePath = environment["MONGLEPET_CODEX_FIXTURE"],
              FileManager.default.fileExists(atPath: fixturePath) else {
            throw XCTSkip("MONGLEPET_CODEX_FIXTURE가 지정된 수동 호환 검사입니다.")
        }
        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let outputURL = temporaryURL.appendingPathComponent("converted.monglepet", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryURL, withIntermediateDirectories: false)
        addTeardownBlock { try? FileManager.default.removeItem(at: temporaryURL) }

        let package = try CodexPetPackageAdapter().convert(
            sourceDirectoryURL: URL(fileURLWithPath: fixturePath, isDirectory: true),
            to: outputURL
        )

        XCTAssertEqual(package.atlases.first?.format, .webP)
        XCTAssertEqual(package.definition.motions.count, 9)
    }

    func testConvertsLegacyV1RowsAndTimingIntoMonglePetPackage() throws {
        let fixture = try makeFixture(version: .legacyV1)

        let package = try CodexPetPackageAdapter().convert(
            sourceDirectoryURL: fixture.sourceURL,
            to: fixture.outputURL
        )

        XCTAssertEqual(package.metadata.id, "codex.test.pet")
        XCTAssertEqual(package.metadata.displayName, "Codex 테스트 펫")
        XCTAssertEqual(package.metadata.version, "codex-1")
        XCTAssertEqual(package.atlases[0].pixelSize, PixelSize(width: 1_536, height: 1_872))
        XCTAssertEqual(package.atlases[0].format, .png)
        XCTAssertEqual(package.definition.motions.count, 9)
        let idle = try XCTUnwrap(package.definition.motion(id: "idle"))
        XCTAssertEqual(idle.frames.count, 6)
        XCTAssertEqual(
            idle.frames.map(\.duration),
            [.milliseconds(280), .milliseconds(110), .milliseconds(110),
             .milliseconds(140), .milliseconds(140), .milliseconds(320)]
        )
        let waving = try XCTUnwrap(package.definition.motion(id: "waving"))
        XCTAssertEqual(waving.frames.last?.sourceRect, PixelRect(x: 576, y: 624, width: 192, height: 208))
        XCTAssertTrue(FileManager.default.fileExists(atPath: package.previewURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.outputURL.appendingPathComponent("pet.json").path))
    }

    func testConvertsV2AndPreservesAllClockwiseLookDirections() throws {
        let fixture = try makeFixture(version: .v2)

        let package = try CodexPetPackageAdapter().convert(
            sourceDirectoryURL: fixture.sourceURL,
            to: fixture.outputURL
        )

        XCTAssertEqual(package.metadata.version, "codex-2")
        XCTAssertEqual(package.atlases[0].pixelSize, PixelSize(width: 1_536, height: 2_288))
        XCTAssertEqual(package.definition.motions.count, 25)
        let up = try XCTUnwrap(package.definition.motion(id: "look-000"))
        XCTAssertFalse(up.loops)
        XCTAssertEqual(up.frames.single?.sourceRect, PixelRect(x: 0, y: 1_872, width: 192, height: 208))
        let down = try XCTUnwrap(package.definition.motion(id: "look-180"))
        XCTAssertEqual(down.frames.single?.sourceRect, PixelRect(x: 0, y: 2_080, width: 192, height: 208))
        let finalDirection = try XCTUnwrap(package.definition.motion(id: "look-337.5"))
        XCTAssertEqual(finalDirection.frames.single?.sourceRect, PixelRect(x: 1_344, y: 2_080, width: 192, height: 208))
    }

    func testConvertsManifestlessSpritesheetOnlyAfterExplicitVersionConfirmation() throws {
        let fixture = try makeFixture(version: .legacyV1)
        let spritesheetURL = fixture.sourceURL.appendingPathComponent("spritesheet.png")

        let package = try CodexPetPackageAdapter().convertSpritesheet(
            at: spritesheetURL,
            confirmedVersion: .legacyV1,
            metadata: CodexPetImportMetadata(
                id: "local.confirmed.codex",
                displayName: "확인된 Codex 펫"
            ),
            to: fixture.outputURL
        )

        XCTAssertEqual(package.metadata.id, "local.confirmed.codex")
        XCTAssertEqual(package.metadata.displayName, "확인된 Codex 펫")
        XCTAssertEqual(package.metadata.version, "codex-1")
        XCTAssertEqual(package.definition.motions.count, 9)
    }

    func testRejectsVersionDimensionMismatchWithoutGuessing() throws {
        let fixture = try makeFixture(version: .legacyV1, declaredVersion: 2)

        XCTAssertThrowsError(
            try CodexPetPackageAdapter().convert(
                sourceDirectoryURL: fixture.sourceURL,
                to: fixture.outputURL
            )
        ) { error in
            XCTAssertEqual(
                error as? CodexPetImportError,
                .imageDimensionsMismatch(
                    expected: PixelSize(width: 1_536, height: 2_288),
                    actual: PixelSize(width: 1_536, height: 1_872)
                )
            )
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.outputURL.path))
    }

    func testRejectsEmptyUsedCell() throws {
        let fixture = try makeFixture(version: .legacyV1, omittedCell: (row: 3, column: 2))

        XCTAssertThrowsError(
            try CodexPetPackageAdapter().convert(
                sourceDirectoryURL: fixture.sourceURL,
                to: fixture.outputURL
            )
        ) { error in
            XCTAssertEqual(error as? CodexPetImportError, .emptyUsedCell(row: 3, column: 2))
        }
    }

    func testRejectsOpaqueUnusedCell() throws {
        let fixture = try makeFixture(version: .legacyV1, extraCell: (row: 0, column: 6))

        XCTAssertThrowsError(
            try CodexPetPackageAdapter().convert(
                sourceDirectoryURL: fixture.sourceURL,
                to: fixture.outputURL
            )
        ) { error in
            XCTAssertEqual(error as? CodexPetImportError, .opaqueUnusedCell(row: 0, column: 6))
        }
    }

    func testRejectsUnsafeSpritesheetPath() throws {
        let fixture = try makeFixture(version: .legacyV1, spritesheetPath: "../spritesheet.png")

        XCTAssertThrowsError(
            try CodexPetPackageAdapter().convert(
                sourceDirectoryURL: fixture.sourceURL,
                to: fixture.outputURL
            )
        ) { error in
            XCTAssertEqual(error as? CodexPetImportError, .invalidRelativePath("../spritesheet.png"))
        }
    }

    private func makeFixture(
        version: CodexSpriteVersion,
        declaredVersion: Int? = nil,
        omittedCell: (row: Int, column: Int)? = nil,
        extraCell: (row: Int, column: Int)? = nil,
        spritesheetPath: String = "spritesheet.png"
    ) throws -> CodexAdapterFixture {
        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sourceURL = temporaryURL.appendingPathComponent("codex-pet", isDirectory: true)
        let outputURL = temporaryURL.appendingPathComponent("converted.monglepet", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceURL, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: temporaryURL) }

        if !spritesheetPath.contains("..") {
            try writeAtlas(
                version: version,
                to: sourceURL.appendingPathComponent(spritesheetPath),
                omittedCell: omittedCell,
                extraCell: extraCell
            )
        }
        var manifest: [String: Any] = [
            "id": "codex.test.pet",
            "displayName": "Codex 테스트 펫",
            "description": "Codex adapter fixture",
            "spritesheetPath": spritesheetPath
        ]
        let manifestVersion = declaredVersion ?? version.rawValue
        if manifestVersion != 1 {
            manifest["spriteVersionNumber"] = manifestVersion
        }
        let data = try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys])
        try data.write(to: sourceURL.appendingPathComponent("pet.json"))
        return CodexAdapterFixture(sourceURL: sourceURL, outputURL: outputURL)
    }

    private func writeAtlas(
        version: CodexSpriteVersion,
        to fileURL: URL,
        omittedCell: (row: Int, column: Int)?,
        extraCell: (row: Int, column: Int)?
    ) throws {
        let size = version.pixelSize
        let context = try XCTUnwrap(
            CGContext(
                data: nil,
                width: size.width,
                height: size.height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        context.clear(CGRect(x: 0, y: 0, width: size.width, height: size.height))
        context.setFillColor(CGColor(red: 0.2, green: 0.6, blue: 1, alpha: 1))
        let usedColumns = [6, 8, 8, 4, 5, 8, 6, 6, 6] + (version == .v2 ? [8, 8] : [])
        for (row, count) in usedColumns.enumerated() {
            for column in 0..<count where omittedCell?.row != row || omittedCell?.column != column {
                fillVisibleMarker(row: row, column: column, atlasHeight: size.height, in: context)
            }
        }
        if let extraCell {
            fillVisibleMarker(
                row: extraCell.row,
                column: extraCell.column,
                atlasHeight: size.height,
                in: context
            )
        }
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

    private func fillVisibleMarker(
        row: Int,
        column: Int,
        atlasHeight: Int,
        in context: CGContext
    ) {
        context.fill(
            CGRect(
                x: column * 192 + 16,
                y: atlasHeight - (row + 1) * 208 + 16,
                width: 16,
                height: 16
            )
        )
    }
}

private struct CodexAdapterFixture {
    let sourceURL: URL
    let outputURL: URL
}

private extension Array {
    var single: Element? { count == 1 ? first : nil }
}
