import XCTest
@testable import MonglePet

final class AppSettingsV9MigrationTests: XCTestCase {
    func testV8MigrationSeparatesPeriodicSettingsWithSafeDefaults() throws {
        let settings = makeSettings(
            speech: PetSpeechSettings(
                isEnabled: true,
                periodicIntervalMilliseconds: 20_000,
                phrases: [
                    PetSpeechPhrase(
                        text: "주기 대사",
                        trigger: .periodic
                    ),
                    PetSpeechPhrase(
                        text: "행동 대사",
                        trigger: .sequence("default")
                    )
                ]
            )
        )
        let storedV8 = try AppSettingsV8Mapper.storedSettings(from: settings)

        let migrated = try AppSettingsV8ToV9Migrator.migrate(storedV8)
        let speech = try XCTUnwrap(
            migrated.settings.behaviorProfiles.first?.speech
        )
        let mapped = AppSettingsV9Mapper.domainSettings(
            from: migrated.settings
        )

        XCTAssertEqual(migrated.settings.schemaVersion, 9)
        XCTAssertTrue(speech.periodicIsEnabled)
        XCTAssertEqual(speech.periodicOrder, "random")
        XCTAssertEqual(speech.behaviorChangePolicy, "dismiss")
        XCTAssertTrue(
            speech.phrases.allSatisfy { $0.displayMode == "timed" }
        )
        XCTAssertEqual(mapped.settings, settings)
        XCTAssertTrue(mapped.issues.isEmpty)
    }

    func testV9MapperRoundTripsNewSpeechPolicies() throws {
        let speech = PetSpeechSettings(
            isEnabled: true,
            periodicIsEnabled: true,
            periodicIntervalMilliseconds: 35_000,
            periodicOrder: .sequential,
            behaviorChangePolicy: .keep,
            phrases: [
                PetSpeechPhrase(
                    text: "다음 말까지 유지",
                    trigger: .periodic,
                    displayMode: .untilNextPhrase
                ),
                PetSpeechPhrase(
                    text: "행동 시작",
                    displayDurationMilliseconds: 4_000,
                    trigger: .sequence("default"),
                    displayMode: .timed
                )
            ]
        )
        let settings = makeSettings(speech: speech)

        let stored = try AppSettingsV9Mapper.storedSettings(from: settings)
        let mapped = AppSettingsV9Mapper.domainSettings(from: stored)

        XCTAssertEqual(stored.schemaVersion, 9)
        XCTAssertEqual(mapped.settings, settings)
        XCTAssertTrue(mapped.issues.isEmpty)
    }

    func testV9MapperRecoversUnknownSpeechPoliciesIndependently() throws {
        let valid = try AppSettingsV9Mapper.storedSettings(
            from: makeSettings(speech: .default)
        )
        let profile = try XCTUnwrap(valid.behaviorProfiles.first)
        let stored = StoredAppSettingsV9(
            schemaVersion: 9,
            selectedPetInstallationID: valid.selectedPetInstallationID,
            lastUserPresentation: valid.lastUserPresentation,
            overlay: valid.overlay,
            behaviorProfiles: [
                StoredPetProfileV9(
                    petKey: profile.petKey,
                    mode: profile.mode,
                    manualSequenceID: profile.manualSequenceID,
                    sequences: profile.sequences,
                    automaticRules: profile.automaticRules,
                    movement: profile.movement,
                    pettingMotionID: profile.pettingMotionID,
                    speech: StoredPetSpeechSettingsV9(
                        isEnabled: true,
                        periodicIsEnabled: true,
                        periodicIntervalMilliseconds: 20_000,
                        periodicOrder: "future-order",
                        behaviorChangePolicy: "future-policy",
                        phrases: [
                            StoredPetSpeechPhraseV9(
                                id: UUID().uuidString,
                                text: "안녕하세요",
                                displayDurationMilliseconds: 3_000,
                                trigger: StoredPetSpeechTriggerV7(
                                    type: "periodic",
                                    sequenceID: nil
                                ),
                                displayMode: "future-mode"
                            )
                        ],
                        theme: profile.speech.theme
                    )
                )
            ]
        )

        let mapped = AppSettingsV9Mapper.domainSettings(from: stored)

        XCTAssertEqual(mapped.settings.speechSettings.periodicOrder, .random)
        XCTAssertEqual(
            mapped.settings.speechSettings.behaviorChangePolicy,
            .dismiss
        )
        XCTAssertEqual(
            mapped.settings.speechSettings.phrases.first?.displayMode,
            .timed
        )
        XCTAssertEqual(
            mapped.issues,
            [
                .invalidField(
                    "behaviorProfiles.0.speech.periodicOrder"
                ),
                .invalidField(
                    "behaviorProfiles.0.speech.behaviorChangePolicy"
                ),
                .invalidField(
                    "behaviorProfiles.0.speech.phrases.0.displayMode"
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
