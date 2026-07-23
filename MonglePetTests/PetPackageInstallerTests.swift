import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
import ZIPFoundation
@testable import MonglePet

final class PetPackageInstallerTests: XCTestCase {
    func testReviewsAndInstallsAvailableRecommendedProfile() throws {
        let environment = try makeEnvironment()
        let packageURL = try makePackage(in: environment.temporaryURL)
        let definition = try PetPackageLoader()
            .loadPackage(at: packageURL)
            .definition
        let profile = makeRecommendedProfile(speed: 180)
        try RecommendedPetProfileCodec.encode(profile, for: definition)
            .write(
                to: packageURL.appendingPathComponent(
                    "recommended-profile.json",
                    isDirectory: false
                )
            )
        let installer = makeInstaller(environment: environment)

        let review = try installer.review(from: packageURL)
        let result = try installer.installReviewed(
            from: packageURL,
            mode: .rejectDuplicate,
            expectedReview: review
        )

        XCTAssertTrue(review.containsRecommendedProfile)
        XCTAssertEqual(review.recommendedProfile, profile)
        XCTAssertNil(review.recommendedProfileIssue)
        XCTAssertEqual(result.importReview, review)
        XCTAssertEqual(result.installedPackage.package.metadata.id, review.metadata.id)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: result.installedPackage.rootURL
                    .appendingPathComponent("recommended-profile.json")
                    .path
            )
        )
        XCTAssertTrue(try visibleChildren(of: environment.importsURL).isEmpty)
    }

    func testInvalidRecommendedProfileDoesNotBlockPetInstallation() throws {
        let environment = try makeEnvironment()
        let packageURL = try makePackage(in: environment.temporaryURL)
        try Data(#"{"schemaVersion":999}"#.utf8).write(
            to: packageURL.appendingPathComponent("recommended-profile.json")
        )
        let installer = makeInstaller(environment: environment)

        let review = try installer.review(from: packageURL)
        let result = try installer.installReviewed(
            from: packageURL,
            mode: .rejectDuplicate,
            expectedReview: review
        )

        XCTAssertTrue(review.containsRecommendedProfile)
        XCTAssertNil(review.recommendedProfile)
        XCTAssertEqual(
            review.recommendedProfileIssue,
            .unsupportedSchemaVersion(999)
        )
        XCTAssertEqual(
            result.installedPackage.package.metadata.id,
            "com.example.installable"
        )
    }

    func testMalformedRecommendedProfileDoesNotBlockPetInstallation() throws {
        let environment = try makeEnvironment()
        let packageURL = try makePackage(in: environment.temporaryURL)
        try Data(#"{"schemaVersion":"#.utf8).write(
            to: packageURL.appendingPathComponent("recommended-profile.json")
        )
        let installer = makeInstaller(environment: environment)

        let review = try installer.review(from: packageURL)
        let result = try installer.installReviewed(
            from: packageURL,
            mode: .rejectDuplicate,
            expectedReview: review
        )

        XCTAssertTrue(review.containsRecommendedProfile)
        XCTAssertNil(review.recommendedProfile)
        XCTAssertEqual(review.recommendedProfileIssue, .unreadable)
        XCTAssertEqual(
            result.installedPackage.package.metadata.id,
            "com.example.installable"
        )
    }

    func testPackageWithoutRecommendedProfileKeepsLegacyImportBehavior() throws {
        let environment = try makeEnvironment()
        let packageURL = try makePackage(in: environment.temporaryURL)
        let installer = makeInstaller(environment: environment)

        let review = try installer.review(from: packageURL)
        let result = try installer.installReviewed(
            from: packageURL,
            mode: .rejectDuplicate,
            expectedReview: review
        )

        XCTAssertFalse(review.containsRecommendedProfile)
        XCTAssertNil(review.recommendedProfile)
        XCTAssertNil(review.recommendedProfileIssue)
        XCTAssertEqual(
            result.installedPackage.package.metadata,
            review.metadata
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: result.installedPackage.rootURL
                    .appendingPathComponent("recommended-profile.json")
                    .path
            )
        )
    }

    func testMinimumAppVersionCanBeReviewedButBlocksInstallation() throws {
        let environment = try makeEnvironment()
        let packageURL = try makePackage(
            in: environment.temporaryURL,
            compatibility: [
                "createdWithMonglePetVersion": "0.3.0",
                "minimumMonglePetVersion": "0.2.0"
            ]
        )
        let currentVersion = try XCTUnwrap(SemanticVersion("0.1.0"))
        let requiredVersion = try XCTUnwrap(SemanticVersion("0.2.0"))
        let installer = makeInstaller(
            environment: environment,
            currentAppVersion: currentVersion
        )

        let review = try installer.review(from: packageURL)

        XCTAssertEqual(
            review.compatibilityAssessment,
            .requiresNewerVersion(requiredVersion)
        )
        XCTAssertFalse(review.canInstall)
        XCTAssertThrowsError(
            try installer.installReviewed(
                from: packageURL,
                mode: .rejectDuplicate,
                expectedReview: review
            )
        ) { error in
            XCTAssertEqual(
                error as? PetPackageImportError,
                .minimumAppVersionRequired(
                    required: requiredVersion,
                    current: currentVersion
                )
            )
        }
        XCTAssertThrowsError(
            try installer.install(from: packageURL)
        ) { error in
            XCTAssertEqual(
                error as? PetPackageImportError,
                .minimumAppVersionRequired(
                    required: requiredVersion,
                    current: currentVersion
                )
            )
        }
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: environment.libraryURL.path)
        )
    }

    func testNewerCreatorVersionWarnsButAllowsInstallation() throws {
        let environment = try makeEnvironment()
        let packageURL = try makePackage(
            in: environment.temporaryURL,
            compatibility: [
                "createdWithMonglePetVersion": "0.3.0",
                "minimumMonglePetVersion": "0.1.0"
            ]
        )
        let currentVersion = try XCTUnwrap(SemanticVersion("0.1.0"))
        let createdWithVersion = try XCTUnwrap(SemanticVersion("0.3.0"))
        let installer = makeInstaller(
            environment: environment,
            currentAppVersion: currentVersion
        )

        let review = try installer.review(from: packageURL)
        let result = try installer.installReviewed(
            from: packageURL,
            mode: .rejectDuplicate,
            expectedReview: review
        )

        XCTAssertEqual(
            review.compatibilityAssessment,
            .createdWithNewerVersion(createdWithVersion)
        )
        XCTAssertTrue(review.canInstall)
        XCTAssertEqual(
            result.installedPackage.package.compatibility,
            review.compatibility
        )
    }

    func testOversizedRecommendedProfileRejectsWholeImport() throws {
        let environment = try makeEnvironment()
        let packageURL = try makePackage(in: environment.temporaryURL)
        try Data(
            repeating: 0x20,
            count: RecommendedPetProfileCodec.maximumFileSize + 1
        ).write(
            to: packageURL.appendingPathComponent("recommended-profile.json")
        )
        let installer = makeInstaller(environment: environment)

        XCTAssertThrowsError(try installer.review(from: packageURL)) { error in
            XCTAssertEqual(
                error as? PetPackageImportError,
                .recommendedProfileFileTooLarge
            )
        }
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: environment.libraryURL.path)
        )
        XCTAssertTrue(try visibleChildren(of: environment.importsURL).isEmpty)
    }

    func testInstallRejectsPackageChangedAfterReview() throws {
        let environment = try makeEnvironment()
        let packageURL = try makePackage(in: environment.temporaryURL)
        let definition = try PetPackageLoader()
            .loadPackage(at: packageURL)
            .definition
        try RecommendedPetProfileCodec.encode(
            makeRecommendedProfile(speed: 160),
            for: definition
        ).write(
            to: packageURL.appendingPathComponent("recommended-profile.json")
        )
        let installer = makeInstaller(environment: environment)
        let review = try installer.review(from: packageURL)
        try RecommendedPetProfileCodec.encode(
            makeRecommendedProfile(speed: 320),
            for: definition
        ).write(
            to: packageURL.appendingPathComponent("recommended-profile.json")
        )

        XCTAssertThrowsError(
            try installer.installReviewed(
                from: packageURL,
                mode: .rejectDuplicate,
                expectedReview: review
            )
        ) { error in
            XCTAssertEqual(
                error as? PetPackageImportError,
                .reviewedContentChanged
            )
        }
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: environment.libraryURL.path)
        )
        XCTAssertTrue(try visibleChildren(of: environment.importsURL).isEmpty)
    }

    func testInstallsValidatedArchiveAndBalancesSecurityScopedAccess() throws {
        let environment = try makeEnvironment()
        let packageURL = try makePackage(in: environment.temporaryURL)
        let archiveURL = try makeArchive(from: packageURL, keepParent: false)
        let installationID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let access = RecordingSecurityScopedAccess()
        let installer = makeInstaller(
            environment: environment,
            installationIDs: [installationID],
            securityAccessor: access
        )

        let installed = try installer.install(from: archiveURL)

        XCTAssertEqual(installed.installationID, installationID)
        XCTAssertEqual(installed.package.metadata.id, "com.example.installable")
        XCTAssertEqual(installed.package.definition.defaultMotionID, "idle")
        XCTAssertTrue(FileManager.default.fileExists(atPath: installed.rootURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: archiveURL.path))
        XCTAssertEqual(access.startedURLs, [archiveURL])
        XCTAssertEqual(access.stoppedURLs, [archiveURL])
        XCTAssertTrue(try visibleChildren(of: environment.importsURL).isEmpty)
    }

    func testInstallsArchiveWithSingleWrapperDirectory() throws {
        let environment = try makeEnvironment()
        let packageURL = try makePackage(in: environment.temporaryURL)
        let archiveURL = try makeArchive(from: packageURL, keepParent: true)
        let installer = makeInstaller(environment: environment)

        let installed = try installer.install(from: archiveURL)

        XCTAssertEqual(installed.package.metadata.displayName, "설치 테스트 펫")
    }

    func testImportedDirectoryCannotClaimUserEditableMarker() throws {
        let environment = try makeEnvironment()
        let packageURL = try makePackage(in: environment.temporaryURL)
        try Data(#"{"schemaVersion":1,"packageID":"com.example.installable"}"#.utf8)
            .write(
                to: packageURL.appendingPathComponent(
                    UserPetPackageEditor.markerFileName,
                    isDirectory: false
                )
            )
        let store = makeStore(
            environment: environment,
            installationIDs: [
                UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
            ]
        )
        let installer = makeInstaller(environment: environment, store: store)

        let installed = try installer.install(from: packageURL)

        XCTAssertFalse(UserPetPackageEditor(store: store).isEditable(installed))
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: packageURL.appendingPathComponent(
                    UserPetPackageEditor.markerFileName,
                    isDirectory: false
                ).path
            ),
            "가져오기 원본은 변경하지 않아야 합니다."
        )
    }

    func testRejectsDuplicateThenAllowsSeparateInstallation() throws {
        let environment = try makeEnvironment()
        let packageURL = try makePackage(in: environment.temporaryURL)
        let archiveURL = try makeArchive(from: packageURL, keepParent: false)
        let firstID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let secondID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let store = makeStore(
            environment: environment,
            installationIDs: [firstID, secondID]
        )
        let installer = makeInstaller(environment: environment, store: store)

        _ = try installer.install(from: archiveURL)

        XCTAssertThrowsError(try installer.install(from: archiveURL)) { error in
            guard case let .duplicatePackage(metadata, installationIDs) = error
                as? PetLibraryError else {
                return XCTFail("중복 패키지 오류가 필요합니다: \(error)")
            }
            XCTAssertEqual(metadata.id, "com.example.installable")
            XCTAssertEqual(metadata.version, "1.0.0")
            XCTAssertEqual(installationIDs, [firstID])
        }

        let separate = try installer.install(from: archiveURL, mode: .installSeparately)
        XCTAssertEqual(separate.installationID, secondID)
        XCTAssertEqual(store.installedPackages().map(\.installationID).sorted(by: uuidSort), [firstID, secondID])
    }

    func testAtomicallyReplacesSamePackageInstallation() throws {
        let environment = try makeEnvironment()
        let firstPackageURL = try makePackage(in: environment.temporaryURL, version: "1.0.0")
        let firstArchiveURL = try makeArchive(
            from: firstPackageURL,
            keepParent: false,
            filename: "first.monglepet"
        )
        let installationID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let store = makeStore(environment: environment, installationIDs: [installationID])
        let installer = makeInstaller(environment: environment, store: store)
        let first = try installer.install(from: firstArchiveURL)

        let secondPackageURL = try makePackage(
            in: environment.temporaryURL,
            directoryName: "updated.monglepet",
            version: "2.0.0"
        )
        let secondArchiveURL = try makeArchive(
            from: secondPackageURL,
            keepParent: false,
            filename: "second.monglepet"
        )
        let replaced = try installer.install(
            from: secondArchiveURL,
            mode: .replace(installationID: installationID)
        )

        XCTAssertEqual(replaced.installationID, installationID)
        XCTAssertEqual(replaced.rootURL, first.rootURL)
        XCTAssertEqual(replaced.package.metadata.version, "2.0.0")
        XCTAssertEqual(store.installedPackages().count, 1)
        XCTAssertTrue(try hiddenChildren(of: environment.libraryURL).isEmpty)
    }

    func testRemovesInstalledPackageAndRejectsMissingInstallation() throws {
        let environment = try makeEnvironment()
        let packageURL = try makePackage(in: environment.temporaryURL)
        let archiveURL = try makeArchive(from: packageURL, keepParent: false)
        let installationID = UUID(
            uuidString: "11111111-1111-1111-1111-111111111111"
        )!
        let store = makeStore(
            environment: environment,
            installationIDs: [installationID]
        )
        let installer = makeInstaller(environment: environment, store: store)
        _ = try installer.install(from: archiveURL)

        try store.removeInstallation(installationID)

        XCTAssertTrue(store.installedPackages().isEmpty)
        XCTAssertThrowsError(try store.removeInstallation(installationID)) { error in
            XCTAssertEqual(error as? PetLibraryError, .missingInstallation(installationID))
        }
    }

    func testReplacementRequiresExistingInstallationWithSamePackageID() throws {
        let environment = try makeEnvironment()
        let firstPackageURL = try makePackage(in: environment.temporaryURL)
        let firstArchiveURL = try makeArchive(
            from: firstPackageURL,
            keepParent: false,
            filename: "first.monglepet"
        )
        let installationID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let missingID = UUID(uuidString: "99999999-9999-9999-9999-999999999999")!
        let store = makeStore(environment: environment, installationIDs: [installationID])
        let installer = makeInstaller(environment: environment, store: store)
        _ = try installer.install(from: firstArchiveURL)

        let otherPackageURL = try makePackage(
            in: environment.temporaryURL,
            directoryName: "other.monglepet",
            packageID: "com.example.other"
        )
        let otherArchiveURL = try makeArchive(
            from: otherPackageURL,
            keepParent: false,
            filename: "other-archive.monglepet"
        )

        XCTAssertThrowsError(
            try installer.install(
                from: otherArchiveURL,
                mode: .replace(installationID: installationID)
            )
        ) { error in
            XCTAssertEqual(
                error as? PetLibraryError,
                .packageIdentifierMismatch(
                    expected: "com.example.installable",
                    actual: "com.example.other"
                )
            )
        }
        XCTAssertThrowsError(
            try installer.install(
                from: otherArchiveURL,
                mode: .replace(installationID: missingID)
            )
        ) { error in
            XCTAssertEqual(error as? PetLibraryError, .missingInstallation(missingID))
        }
        XCTAssertEqual(store.installedPackages().first?.package.metadata.id, "com.example.installable")
        XCTAssertTrue(try hiddenChildren(of: environment.libraryURL).isEmpty)
    }

    func testRejectsPathTraversalAndSymlinkEntriesBeforeExtraction() throws {
        let environment = try makeEnvironment()
        let traversalArchiveURL = environment.temporaryURL
            .appendingPathComponent("traversal.monglepet")
        try makeCustomArchive(
            at: traversalArchiveURL,
            entries: [ArchiveFixtureEntry(path: "../x.txt", type: .file, data: Data("x".utf8))]
        )

        XCTAssertThrowsError(
            try PetPackageArchiveExtractor().extractArchive(
                at: traversalArchiveURL,
                into: environment.importsURL
            )
        ) { error in
            XCTAssertEqual(error as? PetPackageArchiveError, .invalidEntryPath("../x.txt"))
        }

        let absoluteArchiveURL = environment.temporaryURL
            .appendingPathComponent("absolute.monglepet")
        try makeCustomArchive(
            at: absoluteArchiveURL,
            entries: [
                ArchiveFixtureEntry(path: "/absolute.txt", type: .file, data: Data("x".utf8))
            ]
        )
        XCTAssertThrowsError(
            try PetPackageArchiveExtractor().extractArchive(
                at: absoluteArchiveURL,
                into: environment.importsURL
            )
        ) { error in
            XCTAssertEqual(
                error as? PetPackageArchiveError,
                .invalidEntryPath("/absolute.txt")
            )
        }

        let symlinkArchiveURL = environment.temporaryURL
            .appendingPathComponent("symlink.monglepet")
        try makeCustomArchive(
            at: symlinkArchiveURL,
            entries: [
                ArchiveFixtureEntry(
                    path: "assets/link.png",
                    type: .symlink,
                    data: Data("../../outside".utf8)
                )
            ]
        )
        let secondWorkspaceURL = environment.temporaryURL.appendingPathComponent("SecondImports")
        try FileManager.default.createDirectory(at: secondWorkspaceURL, withIntermediateDirectories: false)

        XCTAssertThrowsError(
            try PetPackageArchiveExtractor().extractArchive(
                at: symlinkArchiveURL,
                into: secondWorkspaceURL
            )
        ) { error in
            XCTAssertEqual(
                error as? PetPackageArchiveError,
                .unsupportedEntry("assets/link.png")
            )
        }
    }

    func testRejectsCaseInsensitiveDuplicateAndFileParentPaths() throws {
        let environment = try makeEnvironment()
        let duplicateArchiveURL = environment.temporaryURL
            .appendingPathComponent("duplicate.monglepet")
        try makeCustomArchive(
            at: duplicateArchiveURL,
            entries: [
                ArchiveFixtureEntry(path: "FILE.json", type: .file, data: Data()),
                ArchiveFixtureEntry(path: "file.json", type: .file, data: Data())
            ]
        )

        XCTAssertThrowsError(
            try PetPackageArchiveExtractor().extractArchive(
                at: duplicateArchiveURL,
                into: environment.importsURL
            )
        ) { error in
            XCTAssertEqual(error as? PetPackageArchiveError, .duplicateEntry("file.json"))
        }

        let hierarchyArchiveURL = environment.temporaryURL
            .appendingPathComponent("hierarchy.monglepet")
        try makeCustomArchive(
            at: hierarchyArchiveURL,
            entries: [
                ArchiveFixtureEntry(path: "assets", type: .file, data: Data()),
                ArchiveFixtureEntry(path: "assets/pet.png", type: .file, data: Data())
            ]
        )
        let secondWorkspaceURL = environment.temporaryURL.appendingPathComponent("HierarchyImports")
        try FileManager.default.createDirectory(at: secondWorkspaceURL, withIntermediateDirectories: false)

        XCTAssertThrowsError(
            try PetPackageArchiveExtractor().extractArchive(
                at: hierarchyArchiveURL,
                into: secondWorkspaceURL
            )
        ) { error in
            XCTAssertEqual(error as? PetPackageArchiveError, .invalidEntryPath("assets"))
        }
    }

    func testRejectsArchiveSizeExpandedSizeAndCompressionRatioLimits() throws {
        let environment = try makeEnvironment()
        let packageURL = try makePackage(in: environment.temporaryURL)
        let archiveURL = try makeArchive(from: packageURL, keepParent: false)
        let archiveSizeLimits = PetPackageArchiveLimits(
            maximumArchiveByteCount: 1,
            maximumExpandedByteCount: 100 * 1_024 * 1_024,
            maximumEntryCount: 2_000,
            maximumCompressionRatio: 100
        )

        XCTAssertThrowsError(
            try PetPackageArchiveExtractor(limits: archiveSizeLimits)
                .extractArchive(at: archiveURL, into: environment.importsURL)
        ) { error in
            XCTAssertEqual(error as? PetPackageArchiveError, .archiveTooLarge)
        }

        let expandedWorkspaceURL = environment.temporaryURL.appendingPathComponent("ExpandedImports")
        try FileManager.default.createDirectory(at: expandedWorkspaceURL, withIntermediateDirectories: false)
        let expandedLimits = PetPackageArchiveLimits(
            maximumArchiveByteCount: 20 * 1_024 * 1_024,
            maximumExpandedByteCount: 1,
            maximumEntryCount: 2_000,
            maximumCompressionRatio: 100
        )
        XCTAssertThrowsError(
            try PetPackageArchiveExtractor(limits: expandedLimits)
                .extractArchive(at: archiveURL, into: expandedWorkspaceURL)
        ) { error in
            XCTAssertEqual(error as? PetPackageArchiveError, .expandedSizeExceeded)
        }

        let entryWorkspaceURL = environment.temporaryURL.appendingPathComponent("EntryImports")
        try FileManager.default.createDirectory(at: entryWorkspaceURL, withIntermediateDirectories: false)
        let entryLimits = PetPackageArchiveLimits(
            maximumArchiveByteCount: 20 * 1_024 * 1_024,
            maximumExpandedByteCount: 100 * 1_024 * 1_024,
            maximumEntryCount: 1,
            maximumCompressionRatio: 100
        )
        XCTAssertThrowsError(
            try PetPackageArchiveExtractor(limits: entryLimits)
                .extractArchive(at: archiveURL, into: entryWorkspaceURL)
        ) { error in
            XCTAssertEqual(error as? PetPackageArchiveError, .entryCountExceeded)
        }

        let compressedArchiveURL = environment.temporaryURL
            .appendingPathComponent("compressed.monglepet")
        try makeCustomArchive(
            at: compressedArchiveURL,
            entries: [
                ArchiveFixtureEntry(
                    path: "large.txt",
                    type: .file,
                    data: Data(repeating: 0, count: 8_192),
                    compressionMethod: .deflate
                )
            ]
        )
        let ratioWorkspaceURL = environment.temporaryURL.appendingPathComponent("RatioImports")
        try FileManager.default.createDirectory(at: ratioWorkspaceURL, withIntermediateDirectories: false)
        let ratioLimits = PetPackageArchiveLimits(
            maximumArchiveByteCount: 20 * 1_024 * 1_024,
            maximumExpandedByteCount: 100 * 1_024 * 1_024,
            maximumEntryCount: 2_000,
            maximumCompressionRatio: 2
        )
        XCTAssertThrowsError(
            try PetPackageArchiveExtractor(limits: ratioLimits)
                .extractArchive(at: compressedArchiveURL, into: ratioWorkspaceURL)
        ) { error in
            XCTAssertEqual(
                error as? PetPackageArchiveError,
                .suspiciousCompressionRatio("large.txt")
            )
        }
    }

    func testValidationFailureLeavesLibraryAndWorkspaceCleanAndStopsAccess() throws {
        let environment = try makeEnvironment()
        let packageURL = try makePackage(in: environment.temporaryURL)
        try Data("not-json".utf8).write(to: packageURL.appendingPathComponent("pet.json"))
        let archiveURL = try makeArchive(from: packageURL, keepParent: false)
        let access = RecordingSecurityScopedAccess()
        let installer = makeInstaller(environment: environment, securityAccessor: access)

        XCTAssertThrowsError(try installer.install(from: archiveURL)) { error in
            XCTAssertEqual(error as? PetPackageLoadingError, .invalidManifest)
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: environment.libraryURL.path))
        XCTAssertTrue(try visibleChildren(of: environment.importsURL).isEmpty)
        XCTAssertEqual(access.stoppedURLs, [archiveURL])
    }

    func testRejectsCorruptedArchiveAndStopsSecurityScopedAccess() throws {
        let environment = try makeEnvironment()
        let archiveURL = environment.temporaryURL.appendingPathComponent("broken.monglepet")
        try Data("not-a-zip".utf8).write(to: archiveURL)
        let access = RecordingSecurityScopedAccess()
        let installer = makeInstaller(environment: environment, securityAccessor: access)

        XCTAssertThrowsError(try installer.install(from: archiveURL)) { error in
            XCTAssertEqual(error as? PetPackageArchiveError, .invalidArchive)
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: environment.libraryURL.path))
        XCTAssertTrue(try visibleChildren(of: environment.importsURL).isEmpty)
        XCTAssertEqual(access.startedURLs, [archiveURL])
        XCTAssertEqual(access.stoppedURLs, [archiveURL])
    }

    private func makeEnvironment() throws -> InstallerTestEnvironment {
        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let libraryURL = temporaryURL.appendingPathComponent("Library", isDirectory: true)
        let importsURL = temporaryURL.appendingPathComponent("Imports", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryURL, withIntermediateDirectories: false)
        try FileManager.default.createDirectory(at: importsURL, withIntermediateDirectories: false)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: temporaryURL)
        }
        return InstallerTestEnvironment(
            temporaryURL: temporaryURL,
            libraryURL: libraryURL,
            importsURL: importsURL
        )
    }

    private func makeRecommendedProfile(speed: Double) -> RecommendedPetProfile {
        RecommendedPetProfile(
            mode: .manual,
            manualSequenceID: "기본",
            sequences: [
                BehaviorSequence(
                    id: "기본",
                    steps: [
                        BehaviorStep(
                            motionID: PetMotionReference.currentPetDefault,
                            repeatCount: 2
                        )
                    ],
                    repeats: true
                )
            ],
            automaticRules: [],
            movement: PetMovementSettings(
                mode: .freeRoaming,
                speed: speed,
                cursorDistance: 96,
                stopRadius: 16,
                freeRoamingDwellMilliseconds: 6_000,
                prefersFrontmostWindow: true,
                cursorFollowingMotionID: nil,
                freeRoamingMotionID: "idle"
            ),
            pettingMotionID: "idle"
        )
    }

    private func makePackage(
        in temporaryURL: URL,
        directoryName: String = "source.monglepet",
        packageID: String = "com.example.installable",
        version: String = "1.0.0",
        compatibility: [String: String]? = nil
    ) throws -> URL {
        let packageURL = temporaryURL.appendingPathComponent(directoryName, isDirectory: true)
        try FileManager.default.createDirectory(
            at: packageURL.appendingPathComponent("assets", isDirectory: true),
            withIntermediateDirectories: true
        )
        try writePNG(to: packageURL.appendingPathComponent("preview.png"), width: 2, height: 2)
        try writePNG(
            to: packageURL.appendingPathComponent("assets/spritesheet.png"),
            width: 4,
            height: 4
        )
        var manifest: [String: Any] = [
            "formatVersion": 1,
            "id": packageID,
            "displayName": "설치 테스트 펫",
            "version": version,
            "author": "Tester",
            "license": "All Rights Reserved",
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
            ]]
        ]
        if let compatibility {
            manifest["compatibility"] = compatibility
        }
        let manifestData = try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys])
        try manifestData.write(to: packageURL.appendingPathComponent("pet.json"))
        return packageURL
    }

    private func makeArchive(
        from packageURL: URL,
        keepParent: Bool,
        filename: String = "package.monglepet"
    ) throws -> URL {
        let archiveURL = packageURL.deletingLastPathComponent().appendingPathComponent(filename)
        try FileManager.default.zipItem(
            at: packageURL,
            to: archiveURL,
            shouldKeepParent: keepParent,
            compressionMethod: .deflate
        )
        return archiveURL
    }

    private func makeCustomArchive(
        at archiveURL: URL,
        entries: [ArchiveFixtureEntry]
    ) throws {
        let archive = try Archive(url: archiveURL, accessMode: .create)
        for entry in entries {
            try archive.addEntry(
                with: entry.path,
                type: entry.type,
                uncompressedSize: Int64(entry.data.count),
                compressionMethod: entry.compressionMethod
            ) { position, size in
                let start = Int(position)
                let end = min(start + size, entry.data.count)
                return entry.data.subdata(in: start..<end)
            }
        }
    }

    private func makeInstaller(
        environment: InstallerTestEnvironment,
        installationIDs: [UUID] = [UUID(uuidString: "11111111-1111-1111-1111-111111111111")!],
        store: PetLibraryStore? = nil,
        securityAccessor: RecordingSecurityScopedAccess = RecordingSecurityScopedAccess(),
        currentAppVersion: SemanticVersion = MonglePetAppVersion.current.semanticVersion
    ) -> PetPackageInstaller {
        let resolvedStore = store ?? makeStore(
            environment: environment,
            installationIDs: installationIDs
        )
        return PetPackageInstaller(
            libraryStore: resolvedStore,
            securityScopedAccess: SecurityScopedResourceAccess(accessor: securityAccessor),
            temporaryDirectoryURL: environment.importsURL,
            currentAppVersion: currentAppVersion
        )
    }

    private func makeStore(
        environment: InstallerTestEnvironment,
        installationIDs: [UUID]
    ) -> PetLibraryStore {
        var remainingIDs = installationIDs
        return PetLibraryStore(
            libraryRootURL: environment.libraryURL,
            installationIDGenerator: {
                precondition(!remainingIDs.isEmpty)
                return remainingIDs.removeFirst()
            }
        )
    }

    private func writePNG(to fileURL: URL, width: Int, height: Int) throws {
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 255, count: height * bytesPerRow)
        let image = try pixels.withUnsafeMutableBytes { bytes in
            let context = try XCTUnwrap(
                CGContext(
                    data: bytes.baseAddress,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: bytesPerRow,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
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

    private func visibleChildren(of directoryURL: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
    }

    private func hiddenChildren(of directoryURL: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: []
        ).filter { $0.lastPathComponent.hasPrefix(".") }
    }

    private func uuidSort(_ lhs: UUID, _ rhs: UUID) -> Bool {
        lhs.uuidString < rhs.uuidString
    }
}

private struct InstallerTestEnvironment {
    let temporaryURL: URL
    let libraryURL: URL
    let importsURL: URL
}

private struct ArchiveFixtureEntry {
    let path: String
    let type: Entry.EntryType
    let data: Data
    var compressionMethod: CompressionMethod = .none
}

private nonisolated final class RecordingSecurityScopedAccess: SecurityScopedResourceAccessing {
    private(set) var startedURLs: [URL] = []
    private(set) var stoppedURLs: [URL] = []

    func startAccessing(_ url: URL) -> Bool {
        startedURLs.append(url)
        return true
    }

    func stopAccessing(_ url: URL) {
        stoppedURLs.append(url)
    }
}
