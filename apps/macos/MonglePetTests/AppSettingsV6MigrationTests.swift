import XCTest
@testable import MonglePet

final class AppSettingsV6MigrationTests: XCTestCase {
    func testV5MigrationAddsSafeCursorAvoidingDefaults() throws {
        let v5 = try AppSettingsV5Mapper.storedSettings(
            from: makeSettings(movement: .default)
        )

        let migrated = try AppSettingsV5ToV6Migrator.migrate(v5)
        let movement = try XCTUnwrap(
            migrated.settings.behaviorProfiles.first?.movement
        )

        XCTAssertEqual(migrated.settings.schemaVersion, 6)
        XCTAssertEqual(
            movement.cursorAvoidingIdleBehavior,
            "stationary"
        )
        XCTAssertEqual(
            movement.cursorAvoidingDetectionDistance,
            AppSettingsLimits.defaultCursorAvoidingDetectionDistance
        )
        XCTAssertEqual(
            movement.cursorAvoidingSpeed,
            AppSettingsLimits.defaultCursorAvoidingSpeed
        )
        XCTAssertNil(
            movement.cursorAvoidingAnimation.fallbackMotionID
        )
        XCTAssertFalse(
            movement.cursorAvoidingAnimation.usesDirectionalMotions
        )
        XCTAssertTrue(migrated.issues.isEmpty)
    }

    func testV6MapperRoundTripsAllCursorAvoidingFields() throws {
        let movement = PetMovementSettings(
            mode: .cursorAvoiding,
            speed: 120,
            cursorDistance: 80,
            stopRadius: 12,
            freeRoamingDwellMilliseconds: 8_000,
            prefersFrontmostWindow: false,
            cursorFollowingMotionID: "follow",
            freeRoamingMotionID: "walk",
            cursorAvoidingIdleBehavior: .freeRoaming,
            cursorAvoidingDetectionDistance: 240,
            cursorAvoidingSpeed: 480,
            cursorAvoidingAnimation: MovementAnimationSettings(
                fallbackMotionID: "escape",
                usesDirectionalMotions: true,
                usesDiagonalMotions: true,
                directionMotionIDs: DirectionalMotionIDs(
                    left: "left",
                    right: "right",
                    up: "up",
                    down: "down",
                    upLeft: "up-left",
                    upRight: "up-right",
                    downLeft: "down-left",
                    downRight: "down-right"
                )
            )
        )
        let settings = makeSettings(movement: movement)

        let stored = try AppSettingsV6Mapper.storedSettings(from: settings)
        let mapped = AppSettingsV6Mapper.domainSettings(from: stored)

        XCTAssertEqual(stored.schemaVersion, 6)
        XCTAssertEqual(mapped.settings, settings)
        XCTAssertTrue(mapped.issues.isEmpty)
    }

    private func makeSettings(
        movement: PetMovementSettings
    ) -> AppSettings {
        AppSettings(
            selectedPetInstallationID: nil,
            lastUserPresentation: .awake,
            overlay: .default,
            behaviorProfiles: [
                BehaviorProfile(
                    petKey: .builtIn,
                    mode: .manual,
                    manualSequenceID:
                        BuiltInBehaviorPresets.defaultSequenceID,
                    sequences: BuiltInBehaviorPresets.sequences,
                    automaticRules: [],
                    movement: movement
                )
            ]
        )
    }
}
