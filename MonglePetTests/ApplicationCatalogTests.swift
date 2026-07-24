import Foundation
import XCTest
@testable import MonglePet

final class ApplicationCatalogTests: XCTestCase {
    func testRunningChoicesFilterNormalizeDeduplicateAndSort() {
        let duplicateURL = URL(fileURLWithPath: "/Applications/Editor.app")
        let choices = ApplicationCatalogNormalizer.choices(
            from: [
                RunningApplicationCandidate(
                    bundleIdentifier: "com.example.Zebra",
                    displayName: "Zebra",
                    bundleURL: nil,
                    isUserFacing: true
                ),
                RunningApplicationCandidate(
                    bundleIdentifier: " com.example.Editor ",
                    displayName: nil,
                    bundleURL: nil,
                    isUserFacing: true
                ),
                RunningApplicationCandidate(
                    bundleIdentifier: "com.example.Editor",
                    displayName: "Editor",
                    bundleURL: duplicateURL,
                    isUserFacing: true
                ),
                RunningApplicationCandidate(
                    bundleIdentifier: "kr.mapleroom.MonglePet",
                    displayName: "MonglePet",
                    bundleURL: nil,
                    isUserFacing: true
                ),
                RunningApplicationCandidate(
                    bundleIdentifier: "com.example.Helper",
                    displayName: "Helper",
                    bundleURL: nil,
                    isUserFacing: false
                ),
                RunningApplicationCandidate(
                    bundleIdentifier: nil,
                    displayName: "Identifier 없음",
                    bundleURL: nil,
                    isUserFacing: true
                )
            ],
            excluding: "kr.mapleroom.MonglePet"
        )

        XCTAssertEqual(
            choices.map(\.bundleIdentifier),
            ["com.example.Editor", "com.example.Zebra"]
        )
        XCTAssertEqual(choices.first?.displayName, "Editor")
        XCTAssertEqual(choices.first?.bundleURL, duplicateURL)
    }

    func testIdentifierAndDisplayNameNormalization() {
        XCTAssertEqual(
            ApplicationCatalogNormalizer.normalizedIdentifier(
                "  com.example.App\n"
            ),
            "com.example.App"
        )
        XCTAssertNil(
            ApplicationCatalogNormalizer.normalizedIdentifier(
                "com.example Bad"
            )
        )
        XCTAssertEqual(
            ApplicationCatalogNormalizer.normalizedDisplayName(
                " ",
                fallback: "Example",
                bundleIdentifier: "com.example.App"
            ),
            "Example"
        )
    }

    @MainActor
    func testApplicationBundleInspectionReadsNameAndIdentifier() throws {
        let fixture = try makeApplicationBundle(
            name: "Fixture Editor",
            bundleIdentifier: "com.example.fixture-editor"
        )
        defer {
            try? FileManager.default.removeItem(
                at: fixture.deletingLastPathComponent()
            )
        }
        let catalog = SystemApplicationCatalog(
            excludedBundleIdentifier: "kr.mapleroom.MonglePet"
        )

        let application = try catalog.application(at: fixture)

        XCTAssertEqual(
            application.bundleIdentifier,
            "com.example.fixture-editor"
        )
        XCTAssertEqual(application.displayName, "Fixture Editor")
        XCTAssertEqual(application.bundleURL, fixture)
    }

    @MainActor
    func testApplicationBundleInspectionRejectsInvalidAndExcludedApps() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let catalog = SystemApplicationCatalog(
            excludedBundleIdentifier: "kr.mapleroom.MonglePet"
        )

        XCTAssertThrowsError(
            try catalog.application(
                at: directory.appendingPathComponent("NotAnApp.txt")
            )
        ) { error in
            XCTAssertEqual(
                error as? ApplicationCatalogError,
                .notApplicationBundle
            )
        }

        let missingIdentifier = try makeApplicationBundle(
            inside: directory,
            name: "Missing Identifier",
            bundleIdentifier: nil
        )
        XCTAssertThrowsError(
            try catalog.application(at: missingIdentifier)
        ) { error in
            XCTAssertEqual(
                error as? ApplicationCatalogError,
                .missingBundleIdentifier
            )
        }

        let excluded = try makeApplicationBundle(
            inside: directory,
            name: "MonglePet",
            bundleIdentifier: "kr.mapleroom.MonglePet"
        )
        XCTAssertThrowsError(
            try catalog.application(at: excluded)
        ) { error in
            XCTAssertEqual(
                error as? ApplicationCatalogError,
                .monglePetCannotBeSelected
            )
        }
    }

    private func makeApplicationBundle(
        inside parent: URL? = nil,
        name: String,
        bundleIdentifier: String?
    ) throws -> URL {
        let root = parent ?? FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let applicationURL = root.appendingPathComponent(
            "\(UUID().uuidString).app",
            isDirectory: true
        )
        let contentsURL = applicationURL.appendingPathComponent(
            "Contents",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: contentsURL,
            withIntermediateDirectories: true
        )

        var info: [String: Any] = [
            "CFBundleName": name,
            "CFBundlePackageType": "APPL"
        ]
        if let bundleIdentifier {
            info["CFBundleIdentifier"] = bundleIdentifier
        }
        let data = try PropertyListSerialization.data(
            fromPropertyList: info,
            format: .xml,
            options: 0
        )
        try data.write(
            to: contentsURL.appendingPathComponent("Info.plist"),
            options: .atomic
        )
        return applicationURL
    }
}
