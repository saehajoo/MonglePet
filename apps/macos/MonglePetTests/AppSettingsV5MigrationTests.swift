import XCTest
@testable import MonglePet

final class AppSettingsV5MigrationTests: XCTestCase {
    func testV4MigrationPreservesSingleMovementMotionsAsFallbacks() throws {
        let v4 = try AppSettingsV4Mapper.storedSettings(
            from: makeSettings(
                movement: PetMovementSettings(
                    mode: .freeRoaming,
                    speed: 240,
                    cursorDistance: 120,
                    stopRadius: 20,
                    freeRoamingDwellMilliseconds: 9_000,
                    prefersFrontmostWindow: false,
                    cursorFollowingMotionID: "run",
                    freeRoamingMotionID: "walk"
                )
            )
        )

        let migrated = try AppSettingsV4ToV5Migrator.migrate(v4)
        let movement = try XCTUnwrap(
            migrated.settings.behaviorProfiles.first?.movement
        )

        XCTAssertEqual(migrated.settings.schemaVersion, 5)
        XCTAssertEqual(
            movement.cursorFollowingAnimation.fallbackMotionID,
            "run"
        )
        XCTAssertFalse(
            movement.cursorFollowingAnimation.usesDirectionalMotions
        )
        XCTAssertEqual(
            movement.freeRoamingAnimation.fallbackMotionID,
            "walk"
        )
        XCTAssertFalse(
            movement.freeRoamingAnimation.usesDirectionalMotions
        )
        XCTAssertTrue(migrated.issues.isEmpty)
    }

    func testV5MapperRoundTripsAllDirectionalMovementFields() throws {
        let movement = PetMovementSettings(
            mode: .cursorFollowing,
            speed: 320,
            cursorDistance: 140,
            stopRadius: 12,
            freeRoamingDwellMilliseconds: 12_000,
            prefersFrontmostWindow: false,
            cursorFollowingAnimation: MovementAnimationSettings(
                fallbackMotionID: "run",
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
            ),
            freeRoamingAnimation: MovementAnimationSettings(
                fallbackMotionID: "walk",
                usesDirectionalMotions: true,
                directionMotionIDs: DirectionalMotionIDs(
                    left: "walk-left",
                    right: "walk-right"
                )
            )
        )
        let settings = makeSettings(movement: movement)

        let stored = try AppSettingsV5Mapper.storedSettings(from: settings)
        let mapped = AppSettingsV5Mapper.domainSettings(from: stored)

        XCTAssertEqual(stored.schemaVersion, 5)
        XCTAssertEqual(mapped.settings, settings)
        XCTAssertTrue(mapped.issues.isEmpty)
    }

    func testV5MapperRecoversInvalidDirectionWithoutDroppingOthers() throws {
        let valid = try AppSettingsV5Mapper.storedSettings(
            from: makeSettings(
                movement: PetMovementSettings(
                    mode: .cursorFollowing,
                    speed: 160,
                    cursorDistance: 96,
                    stopRadius: 16,
                    freeRoamingDwellMilliseconds: 6_000,
                    prefersFrontmostWindow: true,
                    cursorFollowingAnimation: MovementAnimationSettings(
                        fallbackMotionID: "run",
                        usesDirectionalMotions: true,
                        directionMotionIDs: DirectionalMotionIDs(
                            left: "left",
                            right: "right"
                        )
                    )
                )
            )
        )
        let profile = try XCTUnwrap(valid.behaviorProfiles.first)
        let movement = profile.movement
        let directions = movement.cursorFollowingAnimation.directionMotionIDs
        let brokenProfile = StoredPetProfileV5(
            petKey: profile.petKey,
            mode: profile.mode,
            manualSequenceID: profile.manualSequenceID,
            sequences: profile.sequences,
            automaticRules: profile.automaticRules,
            movement: StoredPetMovementSettingsV5(
                mode: movement.mode,
                speed: movement.speed,
                cursorDistance: movement.cursorDistance,
                stopRadius: movement.stopRadius,
                freeRoamingDwellMilliseconds:
                    movement.freeRoamingDwellMilliseconds,
                prefersFrontmostWindow: movement.prefersFrontmostWindow,
                cursorFollowingAnimation:
                    StoredMovementAnimationSettingsV5(
                        fallbackMotionID:
                            movement.cursorFollowingAnimation
                                .fallbackMotionID,
                        usesDirectionalMotions: true,
                        usesDiagonalMotions: false,
                        directionMotionIDs:
                            StoredDirectionalMotionIDsV5(
                                left: "   ",
                                right: directions.right,
                                up: directions.up,
                                down: directions.down,
                                upLeft: directions.upLeft,
                                upRight: directions.upRight,
                                downLeft: directions.downLeft,
                                downRight: directions.downRight
                            )
                    ),
                freeRoamingAnimation: movement.freeRoamingAnimation
            ),
            pettingMotionID: profile.pettingMotionID
        )
        let broken = StoredAppSettingsV5(
            schemaVersion: 5,
            selectedPetInstallationID:
                valid.selectedPetInstallationID,
            lastUserPresentation: valid.lastUserPresentation,
            overlay: valid.overlay,
            behaviorProfiles: [brokenProfile]
        )

        let mapped = AppSettingsV5Mapper.domainSettings(from: broken)

        XCTAssertNil(
            mapped.settings.movementSettings
                .cursorFollowingAnimation.directionMotionIDs.left
        )
        XCTAssertEqual(
            mapped.settings.movementSettings
                .cursorFollowingAnimation.directionMotionIDs.right,
            "right"
        )
        XCTAssertTrue(
            mapped.issues.contains(
                .invalidField(
                    "behaviorProfiles.0.movement.cursorFollowingAnimation.directionMotionIDs.left"
                )
            )
        )
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
