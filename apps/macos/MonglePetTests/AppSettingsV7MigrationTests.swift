import XCTest
@testable import MonglePet

final class AppSettingsV7MigrationTests: XCTestCase {
    func testV6MigrationAddsDisabledEmptySpeechDefaults() throws {
        let v6 = try AppSettingsV6Mapper.storedSettings(from: makeSettings())

        let migrated = try AppSettingsV6ToV7Migrator.migrate(v6)
        let speech = try XCTUnwrap(
            migrated.settings.behaviorProfiles.first?.speech
        )

        XCTAssertEqual(migrated.settings.schemaVersion, 7)
        XCTAssertFalse(speech.isEnabled)
        XCTAssertEqual(
            speech.periodicIntervalMilliseconds,
            AppSettingsLimits.defaultSpeechPeriodicIntervalMilliseconds
        )
        XCTAssertTrue(speech.phrases.isEmpty)
        XCTAssertTrue(migrated.issues.isEmpty)
    }

    func testV7MapperRoundTripsSpeechTriggersPerPet() throws {
        let phraseID = UUID(
            uuidString: "20000000-0000-0000-0000-000000000001"
        )!
        let speech = PetSpeechSettings(
            isEnabled: true,
            periodicIntervalMilliseconds: 30_000,
            phrases: [
                PetSpeechPhrase(
                    id: phraseID,
                    text: "집중해 볼까요?",
                    displayDurationMilliseconds: 4_000,
                    trigger: .sequence(
                        BuiltInBehaviorPresets.defaultSequenceID
                    )
                ),
                PetSpeechPhrase(text: "반가워요!", trigger: .periodic)
            ]
        )
        let settings = makeSettings(speech: speech)

        let stored = try AppSettingsV7Mapper.storedSettings(from: settings)
        let mapped = AppSettingsV7Mapper.domainSettings(from: stored)

        XCTAssertEqual(stored.schemaVersion, 7)
        XCTAssertEqual(mapped.settings, settings)
        XCTAssertTrue(mapped.issues.isEmpty)
    }

    func testV7MapperDropsInvalidSequenceSpeechReferenceOnly() throws {
        let validSettings = makeSettings(
            speech: PetSpeechSettings(
                isEnabled: true,
                phrases: [
                    PetSpeechPhrase(text: "주기 대사", trigger: .periodic)
                ]
            )
        )
        let stored = try AppSettingsV7Mapper.storedSettings(
            from: validSettings
        )
        let profile = try XCTUnwrap(stored.behaviorProfiles.first)
        let broken = StoredAppSettingsV7(
            schemaVersion: 7,
            selectedPetInstallationID: stored.selectedPetInstallationID,
            lastUserPresentation: stored.lastUserPresentation,
            overlay: stored.overlay,
            behaviorProfiles: [
                StoredPetProfileV7(
                    petKey: profile.petKey,
                    mode: profile.mode,
                    manualSequenceID: profile.manualSequenceID,
                    sequences: profile.sequences,
                    automaticRules: profile.automaticRules,
                    movement: profile.movement,
                    pettingMotionID: profile.pettingMotionID,
                    speech: StoredPetSpeechSettingsV7(
                        isEnabled: true,
                        periodicIntervalMilliseconds: 30_000,
                        phrases: profile.speech.phrases + [
                            StoredPetSpeechPhraseV7(
                                id: UUID().uuidString,
                                text: "잘못된 참조",
                                displayDurationMilliseconds: 3_000,
                                trigger: StoredPetSpeechTriggerV7(
                                    type: "sequence",
                                    sequenceID: "missing"
                                )
                            )
                        ]
                    )
                )
            ]
        )

        let mapped = AppSettingsV7Mapper.domainSettings(from: broken)

        XCTAssertEqual(mapped.settings.speechSettings.phrases.count, 1)
        XCTAssertEqual(
            mapped.settings.speechSettings.phrases.first?.text,
            "주기 대사"
        )
        XCTAssertTrue(
            mapped.issues.contains(
                .invalidField(
                    "behaviorProfiles.0.speech.phrases.1.trigger.sequenceID"
                )
            )
        )
    }

    func testV7MapperDropsPeriodicTriggerWithUnexpectedSequenceID() throws {
        let validSettings = makeSettings(
            speech: PetSpeechSettings(
                isEnabled: true,
                phrases: [
                    PetSpeechPhrase(text: "유효한 대사", trigger: .periodic)
                ]
            )
        )
        let stored = try AppSettingsV7Mapper.storedSettings(
            from: validSettings
        )
        let profile = try XCTUnwrap(stored.behaviorProfiles.first)
        let phrase = try XCTUnwrap(profile.speech.phrases.first)
        let broken = StoredAppSettingsV7(
            schemaVersion: 7,
            selectedPetInstallationID: stored.selectedPetInstallationID,
            lastUserPresentation: stored.lastUserPresentation,
            overlay: stored.overlay,
            behaviorProfiles: [
                StoredPetProfileV7(
                    petKey: profile.petKey,
                    mode: profile.mode,
                    manualSequenceID: profile.manualSequenceID,
                    sequences: profile.sequences,
                    automaticRules: profile.automaticRules,
                    movement: profile.movement,
                    pettingMotionID: profile.pettingMotionID,
                    speech: StoredPetSpeechSettingsV7(
                        isEnabled: true,
                        periodicIntervalMilliseconds: 30_000,
                        phrases: [
                            StoredPetSpeechPhraseV7(
                                id: phrase.id,
                                text: phrase.text,
                                displayDurationMilliseconds:
                                    phrase.displayDurationMilliseconds,
                                trigger: StoredPetSpeechTriggerV7(
                                    type: "periodic",
                                    sequenceID:
                                        BuiltInBehaviorPresets
                                            .defaultSequenceID
                                )
                            )
                        ]
                    )
                )
            ]
        )

        let mapped = AppSettingsV7Mapper.domainSettings(from: broken)

        XCTAssertTrue(mapped.settings.speechSettings.phrases.isEmpty)
        XCTAssertTrue(
            mapped.issues.contains(
                .invalidField(
                    "behaviorProfiles.0.speech.phrases.0.trigger"
                )
            )
        )
    }

    private func makeSettings(
        speech: PetSpeechSettings = .default
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
                    speech: speech
                )
            ]
        )
    }
}
