import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import MonglePet

final class PetPackageExporterTests: XCTestCase {
    private var temporaryDirectoryURL: URL!

    override func setUpWithError() throws {
        temporaryDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: temporaryDirectoryURL,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        if let temporaryDirectoryURL,
           FileManager.default.fileExists(atPath: temporaryDirectoryURL.path) {
            try FileManager.default.removeItem(at: temporaryDirectoryURL)
        }
        temporaryDirectoryURL = nil
    }

    func testExportIncludesOnlyCanonicalManifestAndReferencedImages() throws {
        let installedPackage = try makeInstalledPackage()
        let destinationURL = temporaryDirectoryURL.appendingPathComponent(
            "Shared Pet.monglepet"
        )

        try makeExporter().export(installedPackage, to: destinationURL)

        XCTAssertTrue(FileManager.default.fileExists(atPath: destinationURL.path))
        let extractedRootURL = try extract(destinationURL)
        XCTAssertEqual(
            try regularFilePaths(in: extractedRootURL),
            ["assets/spritesheet.png", "pet.json", "preview.png"]
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: extractedRootURL.appendingPathComponent(
                    UserPetPackageEditor.markerFileName
                ).path
            )
        )

        let manifestObject = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: Data(
                    contentsOf: extractedRootURL.appendingPathComponent("pet.json")
                )
            ) as? [String: Any]
        )
        XCTAssertNil(manifestObject["privateLocalField"])

        let roundTrippedPackage = try PetPackageLoader().loadPackage(
            at: extractedRootURL
        )
        XCTAssertEqual(
            roundTrippedPackage.metadata,
            installedPackage.package.metadata
        )
        XCTAssertEqual(
            roundTrippedPackage.definition,
            installedPackage.package.definition
        )
    }

    func testRevalidationFailurePreservesExistingDestination() throws {
        let installedPackage = try makeInstalledPackage()
        let destinationURL = temporaryDirectoryURL.appendingPathComponent(
            "Existing.monglepet"
        )
        let originalData = Data("existing export".utf8)
        try originalData.write(to: destinationURL)
        try Data("#!/bin/sh".utf8).write(
            to: installedPackage.rootURL.appendingPathComponent("script.sh")
        )

        XCTAssertThrowsError(
            try makeExporter().export(installedPackage, to: destinationURL)
        ) { error in
            XCTAssertEqual(
                error as? PetPackageExportError,
                .packageValidationFailed(.unsupportedFileType("script.sh"))
            )
        }

        XCTAssertEqual(try Data(contentsOf: destinationURL), originalData)
    }

    func testRejectsNonMonglePetDestination() throws {
        let installedPackage = try makeInstalledPackage()
        let destinationURL = temporaryDirectoryURL.appendingPathComponent(
            "Shared Pet.zip"
        )

        XCTAssertThrowsError(
            try makeExporter().export(installedPackage, to: destinationURL)
        ) { error in
            XCTAssertEqual(
                error as? PetPackageExportError,
                .invalidDestination
            )
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: destinationURL.path))
    }

    func testRejectsArchiveLargerThanConfiguredLimit() throws {
        let installedPackage = try makeInstalledPackage()
        let destinationURL = temporaryDirectoryURL.appendingPathComponent(
            "Too Large.monglepet"
        )
        let limits = PetPackageArchiveLimits(
            maximumArchiveByteCount: 1,
            maximumExpandedByteCount: 100 * 1_024 * 1_024,
            maximumEntryCount: 2_000,
            maximumCompressionRatio: 100
        )

        XCTAssertThrowsError(
            try PetPackageExporter(
                archiveLimits: limits,
                temporaryDirectoryURL: temporaryDirectoryURL
            ).export(installedPackage, to: destinationURL)
        ) { error in
            XCTAssertEqual(error as? PetPackageExportError, .archiveTooLarge)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: destinationURL.path))
    }

    func testSharingPolicyBlocksKnownNonDistributableLicenses() {
        let expectations: [(String, PetPackageSharingBlockReason)] = [
            (" Private-Use ", .privateOrPersonalUse),
            ("personal_use_only", .privateOrPersonalUse),
            ("ALL RIGHTS RESERVED", .allRightsReserved),
            ("Unknown", .unknownLicense),
            ("No License", .unknownLicense)
        ]

        for (license, expectedReason) in expectations {
            let review = PetPackageSharingPolicy.review(
                metadata: makeMetadata(license: license)
            )
            XCTAssertFalse(review.canExport)
            XCTAssertEqual(review.blockingReason, expectedReason)
        }

        let shareableReview = PetPackageSharingPolicy.review(
            metadata: makeMetadata(
                displayName: "몽글이/친구:테스트",
                license: "CC-BY-4.0"
            )
        )
        XCTAssertTrue(shareableReview.canExport)
        XCTAssertNil(shareableReview.blockingReason)
        XCTAssertEqual(
            shareableReview.suggestedFileName,
            "몽글이-친구-테스트.monglepet"
        )
    }

    func testSharingRequiresMetadataConfirmationBeforeExport() throws {
        let installedPackage = try makeInstalledPackage(license: "CC-BY-4.0")
        let service = PetPackageSharingService(
            exporter: makeExporter()
        )
        let review = try service.review(installedPackage)
        let destinationURL = temporaryDirectoryURL.appendingPathComponent(
            review.suggestedFileName
        )

        XCTAssertEqual(review.author, "Tester")
        XCTAssertEqual(review.version, "1.2.3")
        XCTAssertEqual(review.license, "CC-BY-4.0")
        XCTAssertThrowsError(
            try service.export(
                installedPackage,
                reviewed: review,
                isConfirmed: false,
                to: destinationURL
            )
        ) { error in
            XCTAssertEqual(
                error as? PetPackageSharingError,
                .confirmationRequired
            )
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: destinationURL.path))

        try service.export(
            installedPackage,
            reviewed: review,
            isConfirmed: true,
            to: destinationURL
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: destinationURL.path))
    }

    func testSharingCannotOverrideBlockedLicenseWithConfirmation() throws {
        let installedPackage = try makeInstalledPackage(license: "Private Use")
        let service = PetPackageSharingService(exporter: makeExporter())
        let review = try service.review(installedPackage)
        let destinationURL = temporaryDirectoryURL.appendingPathComponent(
            "Blocked.monglepet"
        )

        XCTAssertThrowsError(
            try service.export(
                installedPackage,
                reviewed: review,
                isConfirmed: true,
                to: destinationURL
            )
        ) { error in
            XCTAssertEqual(
                error as? PetPackageSharingError,
                .blocked(.privateOrPersonalUse)
            )
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: destinationURL.path))
    }

    func testSharingRequiresNewReviewAfterMetadataChanges() throws {
        let installedPackage = try makeInstalledPackage(license: "CC-BY-4.0")
        let service = PetPackageSharingService(exporter: makeExporter())
        let review = try service.review(installedPackage)
        try replaceLicense(
            with: "MIT",
            in: installedPackage.rootURL
        )
        let reloadedPackage = try PetPackageLoader().loadPackage(
            at: installedPackage.rootURL
        )
        let refreshedInstallation = InstalledPetPackage(
            installationID: installedPackage.installationID,
            rootURL: installedPackage.rootURL,
            package: reloadedPackage
        )

        XCTAssertThrowsError(
            try service.export(
                refreshedInstallation,
                reviewed: review,
                isConfirmed: true,
                to: temporaryDirectoryURL.appendingPathComponent(
                    "Outdated.monglepet"
                )
            )
        ) { error in
            XCTAssertEqual(
                error as? PetPackageSharingError,
                .reviewOutdated
            )
        }
    }

    private func makeExporter() -> PetPackageExporter {
        PetPackageExporter(temporaryDirectoryURL: temporaryDirectoryURL)
    }

    private func makeInstalledPackage(
        license: String = "CC-BY-4.0"
    ) throws -> InstalledPetPackage {
        let packageRootURL = temporaryDirectoryURL.appendingPathComponent(
            "Installed.monglepet",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: packageRootURL.appendingPathComponent("assets", isDirectory: true),
            withIntermediateDirectories: true
        )
        try writePNG(
            to: packageRootURL.appendingPathComponent("preview.png"),
            width: 2,
            height: 2
        )
        try writePNG(
            to: packageRootURL.appendingPathComponent("assets/spritesheet.png"),
            width: 4,
            height: 4
        )
        try writePNG(
            to: packageRootURL.appendingPathComponent("unused.png"),
            width: 1,
            height: 1
        )
        try Data(#"{"local":true}"#.utf8).write(
            to: packageRootURL.appendingPathComponent(
                UserPetPackageEditor.markerFileName
            )
        )
        try Data(#"{"unused":true}"#.utf8).write(
            to: packageRootURL.appendingPathComponent("unused.json")
        )

        let manifest: [String: Any] = [
            "formatVersion": 1,
            "id": "com.example.shareable",
            "displayName": "공유 테스트 펫",
            "version": "1.2.3",
            "author": "Tester",
            "license": license,
            "description": "공유 왕복 테스트",
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
                "frames": [[
                    "x": 0,
                    "y": 0,
                    "width": 4,
                    "height": 4,
                    "durationMs": 120
                ]]
            ]],
            "privateLocalField": "must-not-be-shared"
        ]
        let manifestData = try JSONSerialization.data(
            withJSONObject: manifest,
            options: [.sortedKeys]
        )
        try manifestData.write(
            to: packageRootURL.appendingPathComponent("pet.json")
        )

        let loadedPackage = try PetPackageLoader().loadPackage(at: packageRootURL)
        return InstalledPetPackage(
            installationID: UUID(
                uuidString: "11111111-1111-1111-1111-111111111111"
            )!,
            rootURL: packageRootURL,
            package: loadedPackage
        )
    }

    private func makeMetadata(
        displayName: String = "공유 테스트 펫",
        license: String
    ) -> PetPackageMetadata {
        PetPackageMetadata(
            id: "com.example.shareable",
            displayName: displayName,
            version: "1.2.3",
            author: "Tester",
            license: license,
            description: nil
        )
    }

    private func replaceLicense(
        with license: String,
        in packageRootURL: URL
    ) throws {
        let manifestURL = packageRootURL.appendingPathComponent("pet.json")
        var manifest = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: Data(contentsOf: manifestURL)
            ) as? [String: Any]
        )
        manifest["license"] = license
        try JSONSerialization.data(
            withJSONObject: manifest,
            options: [.sortedKeys]
        ).write(to: manifestURL, options: .atomic)
    }

    private func extract(_ archiveURL: URL) throws -> URL {
        let workspaceURL = temporaryDirectoryURL.appendingPathComponent(
            "Extracted-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: workspaceURL,
            withIntermediateDirectories: true
        )
        return try PetPackageArchiveExtractor().extractArchive(
            at: archiveURL,
            into: workspaceURL
        )
    }

    private func regularFilePaths(in rootURL: URL) throws -> [String] {
        let keys: [URLResourceKey] = [.isRegularFileKey]
        let enumerator = try XCTUnwrap(
            FileManager.default.enumerator(
                at: rootURL,
                includingPropertiesForKeys: keys
            )
        )
        let rootPath = rootURL.standardizedFileURL.path + "/"
        return try enumerator.compactMap { item -> String? in
            let fileURL = try XCTUnwrap(item as? URL)
            let values = try fileURL.resourceValues(forKeys: Set(keys))
            guard values.isRegularFile == true else {
                return nil
            }
            return String(fileURL.standardizedFileURL.path.dropFirst(rootPath.count))
        }.sorted()
    }

    private func writePNG(to url: URL, width: Int, height: Int) throws {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerRow = width * 4
        let pixels = [UInt8](repeating: 255, count: height * bytesPerRow)
        let provider = try XCTUnwrap(CGDataProvider(data: Data(pixels) as CFData))
        let image = try XCTUnwrap(
            CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGBitmapInfo(
                    rawValue: CGImageAlphaInfo.premultipliedLast.rawValue
                ),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
            )
        )
        let destination = try XCTUnwrap(
            CGImageDestinationCreateWithURL(
                url as CFURL,
                UTType.png.identifier as CFString,
                1,
                nil
            )
        )
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }
}
