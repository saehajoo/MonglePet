import XCTest
@testable import MonglePet

final class AppSettingsV10MigrationTests: XCTestCase {
    func testV9MigrationAddsAutomaticPlacementDefaults() throws {
        let settings = makeSettings(speech: .default)
        let storedV9 = try AppSettingsV9Mapper.storedSettings(
            from: settings
        )

        let migrated = try AppSettingsV9ToV10Migrator.migrate(
            storedV9
        )
        let placement = try XCTUnwrap(
            migrated.settings.behaviorProfiles.first?
                .speech.placement
        )
        let mapped = AppSettingsV10Mapper.domainSettings(
            from: migrated.settings
        )

        XCTAssertEqual(migrated.settings.schemaVersion, 10)
        XCTAssertEqual(placement.preferredPosition, "automatic")
        XCTAssertEqual(placement.horizontalOffset, 0)
        XCTAssertEqual(placement.gap, 8)
        XCTAssertEqual(mapped.settings, settings)
        XCTAssertTrue(mapped.issues.isEmpty)
    }

    func testV10MapperRoundTripsSpeechPlacement() throws {
        let placement = PetSpeechBubblePlacementSettings(
            preferredPosition: .below,
            horizontalOffset: 72,
            gap: 24
        )
        let settings = makeSettings(
            speech: PetSpeechSettings(
                isEnabled: true,
                periodicIsEnabled: false,
                phrases: [],
                placement: placement
            )
        )

        let stored = try AppSettingsV10Mapper.storedSettings(
            from: settings
        )
        let mapped = AppSettingsV10Mapper.domainSettings(from: stored)

        XCTAssertEqual(stored.schemaVersion, 10)
        XCTAssertEqual(
            stored.behaviorProfiles.first?
                .speech.placement.preferredPosition,
            "below"
        )
        XCTAssertEqual(mapped.settings, settings)
        XCTAssertTrue(mapped.issues.isEmpty)
    }

    func testV10MapperRecoversPlacementFieldsIndependently() throws {
        let valid = try AppSettingsV10Mapper.storedSettings(
            from: makeSettings(speech: .default)
        )
        let profile = try XCTUnwrap(valid.behaviorProfiles.first)
        let stored = StoredAppSettingsV10(
            schemaVersion: 10,
            selectedPetInstallationID:
                valid.selectedPetInstallationID,
            lastUserPresentation: valid.lastUserPresentation,
            overlay: valid.overlay,
            behaviorProfiles: [
                StoredPetProfileV10(
                    petKey: profile.petKey,
                    mode: profile.mode,
                    manualSequenceID: profile.manualSequenceID,
                    sequences: profile.sequences,
                    automaticRules: profile.automaticRules,
                    movement: profile.movement,
                    pettingMotionID: profile.pettingMotionID,
                    speech: StoredPetSpeechSettingsV10(
                        isEnabled: profile.speech.isEnabled,
                        periodicIsEnabled:
                            profile.speech.periodicIsEnabled,
                        periodicIntervalMilliseconds:
                            profile.speech
                                .periodicIntervalMilliseconds,
                        periodicOrder:
                            profile.speech.periodicOrder,
                        behaviorChangePolicy:
                            profile.speech.behaviorChangePolicy,
                        phrases: profile.speech.phrases,
                        theme: profile.speech.theme,
                        placement:
                            StoredPetSpeechBubblePlacementV10(
                                preferredPosition: "sideways",
                                horizontalOffset: 500,
                                gap: -20
                            )
                    )
                )
            ]
        )

        let mapped = AppSettingsV10Mapper.domainSettings(from: stored)

        XCTAssertEqual(
            mapped.settings.speechSettings.placement,
            PetSpeechBubblePlacementSettings(
                preferredPosition: .automatic,
                horizontalOffset: 160,
                gap: 0
            )
        )
        XCTAssertEqual(
            mapped.issues,
            [
                .invalidField(
                    "behaviorProfiles.0.speech.placement.preferredPosition"
                ),
                .invalidField(
                    "behaviorProfiles.0.speech.placement.horizontalOffset"
                ),
                .invalidField(
                    "behaviorProfiles.0.speech.placement.gap"
                )
            ]
        )
    }

    private func makeSettings(
        speech: PetSpeechSettings
    ) -> AppSettings {
        let sequence = BehaviorSequence(
            id: "default",
            steps: [
                BehaviorStep(motionID: "idle", repeatCount: 1)
            ],
            repeats: true
        )
        return AppSettings(
            selectedPetInstallationID: nil,
            lastUserPresentation: .awake,
            behaviorMode: .manual,
            overlay: .default,
            speech: speech,
            manualSequenceID: sequence.id,
            sequences: [sequence],
            automaticRules: []
        )
    }
}
