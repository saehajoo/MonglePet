import Foundation
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

    func testCompatibilityPolicyBlocksMinimumAndWarnsForNewerCreator() throws {
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
            .requiresNewerVersion(try XCTUnwrap(SemanticVersion("0.2.0")))
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
            try XCTUnwrap(SemanticVersion("0.1.0"))
        )
        XCTAssertEqual(version.buildNumber, "1")
        XCTAssertEqual(version.displayText, "MonglePet 0.1.0 (1)")
    }
}
