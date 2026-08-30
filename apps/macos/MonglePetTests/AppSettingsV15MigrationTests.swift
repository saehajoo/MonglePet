import XCTest
@testable import MonglePet

final class AppSettingsV15MigrationTests: XCTestCase {
    func testAutomaticProfileKeepsRulesEnabledAndBecomesFixedFallback() throws {
        let migrated = try migrate(mode: .automatic, manualSequenceID: nil)
        let profile = try XCTUnwrap(migrated.behaviorProfiles.first)

        XCTAssertEqual(migrated.schemaVersion, 15)
        XCTAssertEqual(profile.stationaryBehaviorMode, "fixed")
        XCTAssertNil(profile.stationarySequenceID)
        XCTAssertTrue(profile.automaticRules.allSatisfy(\.isEnabled))
    }

    func testManualProfileKeepsSelectionAndDisablesDormantRules() throws {
        let migrated = try migrate(
            mode: .manual,
            manualSequenceID: "focus"
        )
        let profile = try XCTUnwrap(migrated.behaviorProfiles.first)

        XCTAssertEqual(profile.stationaryBehaviorMode, "fixed")
        XCTAssertEqual(profile.stationarySequenceID, "focus")
        XCTAssertTrue(profile.automaticRules.allSatisfy { !$0.isEnabled })
    }

    func testRandomProfileKeepsBagAndDisablesDormantRules() throws {
        let migrated = try migrate(mode: .random, manualSequenceID: nil)
        let profile = try XCTUnwrap(migrated.behaviorProfiles.first)

        XCTAssertEqual(profile.stationaryBehaviorMode, "random")
        XCTAssertNil(profile.stationarySequenceID)
        XCTAssertEqual(profile.randomSequenceIDs, ["default", "focus"])
        XCTAssertTrue(profile.automaticRules.allSatisfy { !$0.isEnabled })
    }

    func testV15RoundTripPreservesStationarySelectionAndRules() throws {
        let settings = makeSettings(
            mode: .random,
            manualSequenceID: nil
        )
        let profile = settings.petBehaviorProfiles[0].profile
        let updatedProfile = BehaviorProfile(
            petKey: profile.petKey,
            stationaryBehaviorMode: .random,
            stationarySequenceID: nil,
            randomSequenceIDs: profile.randomSequenceIDs,
            sequences: profile.sequences,
            automaticRules: profile.automaticRules,
            automaticRulePriorityOrder: profile.automaticRulePriorityOrder,
            movement: profile.movement,
            pettingMotionID: profile.pettingMotionID,
            speech: profile.speech
        )
        let updated = AppSettings(
            selectedPetInstanceID: settings.selectedPetInstanceID,
            activePetInstances: settings.activePetInstances,
            petBehaviorProfiles: [
                PetBehaviorProfileSettings(
                    profileID: settings.petBehaviorProfiles[0].profileID,
                    profile: updatedProfile
                )
            ]
        )

        let stored = try AppSettingsV15Mapper.storedSettings(from: updated)
        let decoded = AppSettingsV15Mapper.domainSettings(from: stored)

        XCTAssertTrue(decoded.issues.isEmpty)
        XCTAssertEqual(decoded.settings, updated)
        XCTAssertEqual(decoded.settings.stationaryBehaviorMode, .random)
        XCTAssertTrue(
            decoded.settings.automaticRules.allSatisfy(\.isEnabled)
        )
    }

    private func migrate(
        mode: BehaviorMode,
        manualSequenceID: String?
    ) throws -> StoredAppSettingsV15 {
        let v14 = try AppSettingsV14Mapper.storedSettings(
            from: makeSettings(
                mode: mode,
                manualSequenceID: manualSequenceID
            )
        )
        return try AppSettingsV14ToV15Migrator.migrate(v14)
    }

    private func makeSettings(
        mode: BehaviorMode,
        manualSequenceID: String?
    ) -> AppSettings {
        let sequences = ["default", "focus"].map {
            BehaviorSequence(
                id: $0,
                steps: [BehaviorStep(motionID: $0, repeatCount: 1)],
                repeats: true
            )
        }
        return AppSettings(
            selectedPetInstallationID: nil,
            lastUserPresentation: .awake,
            behaviorMode: mode,
            overlay: .default,
            manualSequenceID: manualSequenceID,
            randomSequenceIDs: ["default", "focus"],
            sequences: sequences,
            automaticRules: [
                AutomaticRule(
                    id: UUID(),
                    isEnabled: true,
                    priority: 10,
                    condition: .idleAtLeast(milliseconds: 1_000),
                    sequenceID: "focus"
                )
            ]
        )
    }
}
