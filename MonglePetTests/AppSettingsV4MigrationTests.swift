import Foundation
import XCTest
@testable import MonglePet

final class AppSettingsV4MigrationTests: XCTestCase {
    func testV3MigrationAddsDefaultMovementBoundary() throws {
        let migrated = try AppSettingsV3ToV4Migrator.migrate(
            makeStoredV3()
        )

        XCTAssertEqual(migrated.settings.schemaVersion, 4)
        XCTAssertEqual(
            migrated.settings.overlay.movementBoundary,
            StoredMovementBoundarySettingsV4(
                mode: "allDisplays",
                screenIdentifier: nil,
                normalizedRect: nil
            )
        )
        XCTAssertTrue(migrated.issues.isEmpty)
    }

    func testV4MapperRoundTripsCustomAreaBoundary() throws {
        let boundary = MovementBoundarySettings(
            mode: .customArea,
            screenIdentifier: "display-personal",
            normalizedRect: NormalizedMovementRect(
                x: 0.15,
                y: 0.2,
                width: 0.7,
                height: 0.6
            )
        )
        let settings = AppSettings(
            selectedPetInstallationID: nil,
            lastUserPresentation: .awake,
            overlay: OverlaySettings(
                screenIdentifier: nil,
                originX: 10,
                originY: 20,
                width: 192,
                clickThrough: false,
                movementBoundary: boundary
            ),
            behaviorProfiles: []
        )

        let stored = try AppSettingsV4Mapper.storedSettings(from: settings)
        let mapped = AppSettingsV4Mapper.domainSettings(from: stored)

        XCTAssertEqual(stored.schemaVersion, 4)
        XCTAssertEqual(mapped.settings, settings)
        XCTAssertTrue(mapped.issues.isEmpty)
    }

    func testV4MapperRecoversInvalidCustomAreaIndependently() {
        let stored = StoredAppSettingsV4(
            schemaVersion: 4,
            selectedPetInstallationID: nil,
            lastUserPresentation: "awake",
            overlay: StoredOverlaySettingsV4(
                screenIdentifier: nil,
                originX: 10,
                originY: 20,
                width: 192,
                clickThrough: true,
                opacity: 1,
                pointerOverlapFadeEnabled: false,
                pointerOverlapOpacity: 0.2,
                movementBoundary: StoredMovementBoundarySettingsV4(
                    mode: "customArea",
                    screenIdentifier: "display-personal",
                    normalizedRect: StoredNormalizedMovementRectV4(
                        x: 0.8,
                        y: 0,
                        width: 0.4,
                        height: 1
                    )
                )
            ),
            behaviorProfiles: []
        )

        let mapped = AppSettingsV4Mapper.domainSettings(from: stored)

        XCTAssertEqual(mapped.settings.overlay.movementBoundary, .default)
        XCTAssertEqual(mapped.settings.overlay.originX, 10)
        XCTAssertEqual(mapped.settings.overlay.originY, 20)
        XCTAssertTrue(mapped.settings.overlay.clickThrough)
        XCTAssertTrue(
            mapped.issues.contains(
                .invalidField("overlay.movementBoundary.normalizedRect")
            )
        )
    }

    func testV4MapperPreservesDisconnectedDisplaySelection() {
        let stored = StoredAppSettingsV4(
            schemaVersion: 4,
            selectedPetInstallationID: nil,
            lastUserPresentation: "awake",
            overlay: StoredOverlaySettingsV4(
                screenIdentifier: nil,
                originX: 0,
                originY: 0,
                width: 192,
                clickThrough: false,
                opacity: 1,
                pointerOverlapFadeEnabled: false,
                pointerOverlapOpacity: 0.2,
                movementBoundary: StoredMovementBoundarySettingsV4(
                    mode: "selectedDisplay",
                    screenIdentifier: "display-disconnected",
                    normalizedRect: nil
                )
            ),
            behaviorProfiles: []
        )

        let mapped = AppSettingsV4Mapper.domainSettings(from: stored)

        XCTAssertEqual(
            mapped.settings.overlay.movementBoundary,
            MovementBoundarySettings(
                mode: .selectedDisplay,
                screenIdentifier: "display-disconnected",
                normalizedRect: nil
            )
        )
        XCTAssertTrue(mapped.issues.isEmpty)
    }

    func testV3MigrationRejectsOtherSchema() {
        let stored = StoredAppSettingsV3(
            schemaVersion: 2,
            selectedPetInstallationID: nil,
            lastUserPresentation: "awake",
            overlay: makeStoredV3().overlay,
            behaviorProfiles: []
        )

        XCTAssertThrowsError(
            try AppSettingsV3ToV4Migrator.migrate(stored)
        ) { error in
            XCTAssertEqual(
                error as? AppSettingsV3ToV4MigrationError,
                .unsupportedSourceSchema(2)
            )
        }
    }

    private func makeStoredV3() -> StoredAppSettingsV3 {
        StoredAppSettingsV3(
            schemaVersion: 3,
            selectedPetInstallationID: nil,
            lastUserPresentation: "awake",
            overlay: StoredOverlaySettings(
                screenIdentifier: nil,
                originX: 0,
                originY: 0,
                width: 192,
                clickThrough: false
            ),
            behaviorProfiles: []
        )
    }
}
