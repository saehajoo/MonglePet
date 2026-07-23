import Foundation
import XCTest
@testable import MonglePet

final class AppSettingsV3MigrationTests: XCTestCase {
    func testV3MapperRoundTripsIndependentMovementSettings() throws {
        let installationID = UUID(
            uuidString: "50000000-0000-0000-0000-000000000001"
        )!
        let builtIn = makeProfile(
            key: .builtIn,
            movement: .default
        )
        let installedMovement = PetMovementSettings(
            mode: .freeRoaming,
            speed: 320,
            cursorDistance: 140,
            stopRadius: 24,
            freeRoamingDwellMilliseconds: 12_000,
            prefersFrontmostWindow: false,
            cursorFollowingMotionID: "run",
            freeRoamingMotionID: "walk"
        )
        let installed = makeProfile(
            key: .installed(installationID),
            movement: installedMovement
        )
        let settings = AppSettings(
            selectedPetInstallationID: installationID,
            lastUserPresentation: .awake,
            overlay: .default,
            behaviorProfiles: [builtIn, installed]
        )

        let stored = try AppSettingsV3Mapper.storedSettings(from: settings)
        let mapped = AppSettingsV3Mapper.domainSettings(from: stored)

        XCTAssertEqual(stored.schemaVersion, 3)
        XCTAssertEqual(mapped.settings, settings)
        XCTAssertTrue(mapped.issues.isEmpty)
        XCTAssertEqual(mapped.settings.movementSettings, installedMovement)
    }

    func testV3MapperRecoversInvalidMovementFieldsIndependently() {
        let stored = makeStoredSettings(
            movement: StoredPetMovementSettingsV3(
                mode: "future",
                speed: .infinity,
                cursorDistance: 999,
                stopRadius: -1,
                freeRoamingDwellMilliseconds: 0,
                prefersFrontmostWindow: false,
                cursorFollowingMotionID: "   ",
                freeRoamingMotionID: "walk"
            )
        )

        let mapped = AppSettingsV3Mapper.domainSettings(from: stored)

        XCTAssertEqual(
            mapped.settings.movementSettings,
            PetMovementSettings(
                mode: .fixed,
                speed: AppSettingsLimits.defaultMovementSpeed,
                cursorDistance: AppSettingsLimits.defaultCursorDistance,
                stopRadius: AppSettingsLimits.defaultMovementStopRadius,
                freeRoamingDwellMilliseconds:
                    AppSettingsLimits.defaultFreeRoamingDwellMilliseconds,
                prefersFrontmostWindow: false,
                cursorFollowingMotionID: nil,
                freeRoamingMotionID: "walk"
            )
        )
        XCTAssertEqual(mapped.issues.count, 6)
        XCTAssertTrue(
            mapped.issues.contains(.invalidField("behaviorProfiles.0.movement.mode"))
        )
        XCTAssertTrue(
            mapped.issues.contains(.invalidField("behaviorProfiles.0.movement.speed"))
        )
        XCTAssertTrue(
            mapped.issues.contains(
                .invalidField("behaviorProfiles.0.movement.cursorFollowingMotionID")
            )
        )
    }

    func testV2MigrationAddsFixedMovementDefaults() throws {
        let v2 = StoredAppSettingsV2(
            schemaVersion: 2,
            selectedPetInstallationID: nil,
            lastUserPresentation: "awake",
            overlay: StoredOverlaySettings(
                screenIdentifier: nil,
                originX: 0,
                originY: 0,
                width: 192,
                clickThrough: false
            ),
            behaviorProfiles: [
                StoredBehaviorProfileV2(
                    petKey: .builtIn,
                    mode: "automatic",
                    manualSequenceID: "default",
                    sequences: [storedSequence],
                    automaticRules: []
                )
            ]
        )

        let migrated = try AppSettingsV2ToV3Migrator.migrate(v2)

        XCTAssertTrue(migrated.issues.isEmpty)
        XCTAssertEqual(migrated.settings.schemaVersion, 3)
        XCTAssertEqual(
            migrated.settings.behaviorProfiles.first?.movement,
            StoredPetMovementSettingsV3(
                mode: "fixed",
                speed: AppSettingsLimits.defaultMovementSpeed,
                cursorDistance: AppSettingsLimits.defaultCursorDistance,
                stopRadius: AppSettingsLimits.defaultMovementStopRadius,
                freeRoamingDwellMilliseconds:
                    AppSettingsLimits.defaultFreeRoamingDwellMilliseconds,
                prefersFrontmostWindow: true
            )
        )
    }

    func testV2MigrationRejectsOtherSchema() {
        let stored = StoredAppSettingsV2(
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

        XCTAssertThrowsError(try AppSettingsV2ToV3Migrator.migrate(stored)) { error in
            XCTAssertEqual(
                error as? AppSettingsV2ToV3MigrationError,
                .unsupportedSourceSchema(3)
            )
        }
    }

    func testV3MapperRejectsInvalidDomainMovement() {
        let invalidProfile = makeProfile(
            key: .builtIn,
            movement: PetMovementSettings(
                mode: .fixed,
                speed: 0,
                cursorDistance: AppSettingsLimits.defaultCursorDistance,
                stopRadius: AppSettingsLimits.defaultMovementStopRadius,
                freeRoamingDwellMilliseconds:
                    AppSettingsLimits.defaultFreeRoamingDwellMilliseconds,
                prefersFrontmostWindow: true
            )
        )
        let settings = AppSettings(
            selectedPetInstallationID: nil,
            lastUserPresentation: .awake,
            overlay: .default,
            behaviorProfiles: [invalidProfile]
        )

        XCTAssertThrowsError(try AppSettingsV3Mapper.storedSettings(from: settings)) { error in
            XCTAssertEqual(
                error as? AppSettingsMappingError,
                .invalidSettings("behaviorProfiles.0.movement")
            )
        }
    }

    private var storedSequence: StoredBehaviorSequenceV2 {
        StoredBehaviorSequenceV2(
            id: "default",
            steps: [StoredBehaviorStepV2(motionID: "idle", repeatCount: 1)],
            repeats: true
        )
    }

    private func makeProfile(
        key: PetBehaviorKey,
        movement: PetMovementSettings
    ) -> BehaviorProfile {
        BehaviorProfile(
            petKey: key,
            mode: .automatic,
            manualSequenceID: "default",
            sequences: [
                BehaviorSequence(
                    id: "default",
                    steps: [BehaviorStep(motionID: "idle", repeatCount: 1)],
                    repeats: true
                )
            ],
            automaticRules: [],
            movement: movement
        )
    }

    private func makeStoredSettings(
        movement: StoredPetMovementSettingsV3
    ) -> StoredAppSettingsV3 {
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
            behaviorProfiles: [
                StoredPetProfileV3(
                    petKey: .builtIn,
                    mode: "automatic",
                    manualSequenceID: "default",
                    sequences: [storedSequence],
                    automaticRules: [],
                    movement: movement
                )
            ]
        )
    }
}
