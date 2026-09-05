import XCTest
@testable import MonglePet

final class AppSettingsV16MigrationTests: XCTestCase {
    func testV15MigrationMapsLegacyDwellBooleansToExplicitModes() throws {
        let settings = settings(
            freeRoaming: roaming(mode: .random),
            cursorAvoidingRoaming: roaming(mode: .fixed)
        )
        let v15 = try AppSettingsV15Mapper.storedSettings(from: settings)

        let migrated = try AppSettingsV15ToV16Migrator.migrate(v15)
        let movement = try XCTUnwrap(migrated.behaviorProfiles.first?.movement)

        XCTAssertEqual(migrated.schemaVersion, 16)
        XCTAssertEqual(movement.freeRoaming.dwellMode, "random")
        XCTAssertEqual(
            movement.cursorAvoiding.idleFreeRoaming.dwellMode,
            "fixed"
        )
    }

    func testV16RoundTripPreservesIndependentBehaviorCompletionModes() throws {
        let expected = settings(
            freeRoaming: roaming(mode: .behaviorCompletion),
            cursorAvoidingRoaming: roaming(mode: .fixed)
        )

        let stored = try AppSettingsV16Mapper.storedSettings(from: expected)
        let decoded = AppSettingsV16Mapper.domainSettings(from: stored)

        XCTAssertTrue(decoded.issues.isEmpty)
        XCTAssertEqual(decoded.settings, expected)
        XCTAssertEqual(
            decoded.settings.movementSettings.freeRoaming.dwellMode,
            .behaviorCompletion
        )
        XCTAssertEqual(
            decoded.settings.movementSettings.cursorAvoiding
                .idleFreeRoaming.dwellMode,
            .fixed
        )
    }

    func testMigratorRejectsNonV15Source() throws {
        let v15 = try AppSettingsV15Mapper.storedSettings(from: .default)
        let invalid = StoredAppSettingsV15(
            schemaVersion: 14,
            selectedPetInstanceID: v15.selectedPetInstanceID,
            activePetInstances: v15.activePetInstances,
            behaviorProfiles: v15.behaviorProfiles
        )

        XCTAssertThrowsError(
            try AppSettingsV15ToV16Migrator.migrate(invalid)
        ) { error in
            XCTAssertEqual(
                error as? AppSettingsV15ToV16MigrationError,
                .unsupportedSourceSchema(14)
            )
        }
    }

    private func roaming(
        mode: FreeRoamingDwellMode
    ) -> FreeRoamingMovementSettings {
        FreeRoamingMovementSettings(
            speed: 180,
            stopRadius: 16,
            dwellMilliseconds: 8_000,
            dwellMinimumMilliseconds: 2_000,
            prefersFrontmostWindow: true,
            animation: .single(nil),
            dwellMode: mode
        )
    }

    private func settings(
        freeRoaming: FreeRoamingMovementSettings,
        cursorAvoidingRoaming: FreeRoamingMovementSettings
    ) -> AppSettings {
        let base = AppSettings.default
        let record = base.petBehaviorProfiles[0]
        let profile = record.profile
        let movement = PetMovementSettings(
            mode: .freeRoaming,
            cursorFollowing: profile.movement.cursorFollowing,
            freeRoaming: freeRoaming,
            cursorAvoiding: CursorAvoidingMovementSettings(
                idleBehavior: .freeRoaming,
                detectionDistance:
                    profile.movement.cursorAvoiding.detectionDistance,
                speed: profile.movement.cursorAvoiding.speed,
                stopRadius: profile.movement.cursorAvoiding.stopRadius,
                animation: profile.movement.cursorAvoiding.animation,
                idleFreeRoaming: cursorAvoidingRoaming
            )
        )
        let updated = BehaviorProfile(
            petKey: profile.petKey,
            stationaryBehaviorMode: profile.stationaryBehaviorMode,
            stationarySequenceID: profile.stationarySequenceID,
            randomSequenceIDs: profile.randomSequenceIDs,
            sequences: profile.sequences,
            automaticRules: profile.automaticRules,
            automaticRulePriorityOrder:
                profile.automaticRulePriorityOrder,
            movement: movement,
            pettingMotionID: profile.pettingMotionID,
            speech: profile.speech
        )
        return AppSettings(
            selectedPetInstanceID: base.selectedPetInstanceID,
            activePetInstances: base.activePetInstances,
            petBehaviorProfiles: [
                PetBehaviorProfileSettings(
                    profileID: record.profileID,
                    profile: updated
                )
            ]
        )
    }
}
