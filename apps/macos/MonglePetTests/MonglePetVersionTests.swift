import Foundation
import ImageIO
import XCTest
@testable import MonglePet

final class MonglePetVersionTests: XCTestCase {
    func testParsesAndComparesNumericSemanticVersions() throws {
        let version = try XCTUnwrap(SemanticVersion("12.3.45"))

        XCTAssertEqual(version.major, 12)
        XCTAssertEqual(version.minor, 3)
        XCTAssertEqual(version.patch, 45)
        XCTAssertEqual(version.description, "12.3.45")
        XCTAssertGreaterThan(
            try XCTUnwrap(SemanticVersion("0.10.0")),
            try XCTUnwrap(SemanticVersion("0.9.0"))
        )
        XCTAssertGreaterThan(
            try XCTUnwrap(SemanticVersion("1.0.0")),
            try XCTUnwrap(SemanticVersion("0.99.99"))
        )
        XCTAssertLessThan(
            try XCTUnwrap(SemanticVersion("1.2.3")),
            try XCTUnwrap(SemanticVersion("1.2.4"))
        )
    }

    func testRejectsNonCanonicalOrOutOfRangeSemanticVersions() {
        for value in [
            "",
            "1",
            "1.2",
            "1.2.3.4",
            "1..3",
            "01.2.3",
            "1.02.3",
            "1.2.03",
            "-1.2.3",
            "1.2.3-beta",
            " 1.2.3",
            "1.2.3 ",
            "999999999999999999999999999999.0.0"
        ] {
            XCTAssertNil(SemanticVersion(value), value)
        }
    }

    func testCompatibilityPolicyRecommendsUpdateAndWarnsForNewerCreator() throws {
        let current = try XCTUnwrap(SemanticVersion("0.1.0"))

        XCTAssertEqual(
            PetPackageCompatibilityPolicy.assess(
                PetPackageCompatibility(
                    createdWithMonglePetVersion: try XCTUnwrap(
                        SemanticVersion("0.3.0")
                    ),
                    minimumMonglePetVersion: try XCTUnwrap(
                        SemanticVersion("0.2.0")
                    )
                ),
                currentVersion: current
            ),
            .updateRecommended(try XCTUnwrap(SemanticVersion("0.2.0")))
        )
        XCTAssertEqual(
            PetPackageCompatibilityPolicy.assess(
                PetPackageCompatibility(
                    createdWithMonglePetVersion: try XCTUnwrap(
                        SemanticVersion("0.3.0")
                    ),
                    minimumMonglePetVersion: current
                ),
                currentVersion: current
            ),
            .createdWithNewerVersion(
                try XCTUnwrap(SemanticVersion("0.3.0"))
            )
        )
        XCTAssertEqual(
            PetPackageCompatibilityPolicy.assess(nil, currentVersion: current),
            .compatible
        )
    }

    func testBuiltApplicationBundleUsesPlannedVersion() throws {
        let version = MonglePetAppVersion.current

        XCTAssertEqual(
            version.semanticVersion,
            try XCTUnwrap(SemanticVersion("1.6.0"))
        )
        XCTAssertEqual(version.buildNumber, "12")
        XCTAssertEqual(version.displayText, "MonglePet 1.6.0 (12)")
    }

    func testAppIconCatalogContainsEveryMacRendition() throws {
        let iconSetURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("MonglePet/Assets.xcassets/AppIcon.appiconset")
        let contents = try String(
            contentsOf: iconSetURL.appendingPathComponent("Contents.json"),
            encoding: .utf8
        )
        let expectedPixelsByFilename = [
            "icon_16x16.png": 16,
            "icon_16x16@2x.png": 32,
            "icon_32x32.png": 32,
            "icon_32x32@2x.png": 64,
            "icon_128x128.png": 128,
            "icon_128x128@2x.png": 256,
            "icon_256x256.png": 256,
            "icon_256x256@2x.png": 512,
            "icon_512x512.png": 512,
            "icon_512x512@2x.png": 1_024
        ]

        for (filename, expectedPixels) in expectedPixelsByFilename {
            XCTAssertTrue(contents.contains("\"\(filename)\""), filename)
            let imageURL = iconSetURL.appendingPathComponent(filename)
            let source = try XCTUnwrap(
                CGImageSourceCreateWithURL(imageURL as CFURL, nil),
                filename
            )
            let properties = try XCTUnwrap(
                CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                    as? [CFString: Any],
                filename
            )
            XCTAssertEqual(
                properties[kCGImagePropertyPixelWidth] as? Int,
                expectedPixels,
                filename
            )
            XCTAssertEqual(
                properties[kCGImagePropertyPixelHeight] as? Int,
                expectedPixels,
                filename
            )
        }
    }
}
