import Foundation

nonisolated struct StoredAppSettingsV9: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let selectedPetInstallationID: String?
    let lastUserPresentation: String
    let overlay: StoredOverlaySettingsV4
    let behaviorProfiles: [StoredPetProfileV9]
}

nonisolated struct StoredPetProfileV9: Codable, Equatable, Sendable {
    let petKey: StoredPetBehaviorKeyV2
    let mode: String
    let manualSequenceID: String?
    let sequences: [StoredBehaviorSequenceV2]
    let automaticRules: [StoredAutomaticRule]
    let movement: StoredPetMovementSettingsV6
    let pettingMotionID: String?
    let speech: StoredPetSpeechSettingsV9
}

nonisolated struct StoredPetSpeechSettingsV9:
    Codable,
    Equatable,
    Sendable
{
    let isEnabled: Bool
    let periodicIsEnabled: Bool
    let periodicIntervalMilliseconds: Int64
    let periodicOrder: String
    let behaviorChangePolicy: String
    let phrases: [StoredPetSpeechPhraseV9]
    let theme: StoredPetSpeechBubbleThemeV8
}

nonisolated struct StoredPetSpeechPhraseV9:
    Codable,
    Equatable,
    Sendable
{
    let id: String
    let text: String
    let displayDurationMilliseconds: Int64
    let trigger: StoredPetSpeechTriggerV7
    let displayMode: String
}

nonisolated struct AppSettingsV8ToV9MigrationResult:
    Equatable,
    Sendable
{
    let settings: StoredAppSettingsV9
    let issues: [SettingsRecoveryIssue]
}

nonisolated enum AppSettingsV8ToV9MigrationError:
    Error,
    Equatable,
    Sendable
{
    case unsupportedSourceSchema(Int)
}

nonisolated enum AppSettingsV8ToV9Migrator {
    static func migrate(
        _ stored: StoredAppSettingsV8
    ) throws -> AppSettingsV8ToV9MigrationResult {
        guard stored.schemaVersion == 8 else {
            throw AppSettingsV8ToV9MigrationError.unsupportedSourceSchema(
                stored.schemaVersion
            )
        }
        return AppSettingsV8ToV9MigrationResult(
            settings: StoredAppSettingsV9(
                schemaVersion: 9,
                selectedPetInstallationID:
                    stored.selectedPetInstallationID,
                lastUserPresentation: stored.lastUserPresentation,
                overlay: stored.overlay,
                behaviorProfiles: stored.behaviorProfiles.map { profile in
                    StoredPetProfileV9(
                        petKey: profile.petKey,
                        mode: profile.mode,
                        manualSequenceID: profile.manualSequenceID,
                        sequences: profile.sequences,
                        automaticRules: profile.automaticRules,
                        movement: profile.movement,
                        pettingMotionID: profile.pettingMotionID,
                        speech: StoredPetSpeechSettingsV9(
                            isEnabled: profile.speech.isEnabled,
                            periodicIsEnabled:
                                profile.speech.phrases.contains {
                                    $0.trigger.type == "periodic"
                                },
                            periodicIntervalMilliseconds:
                                profile.speech
                                    .periodicIntervalMilliseconds,
                            periodicOrder: "random",
                            behaviorChangePolicy: "dismiss",
                            phrases: profile.speech.phrases.map {
                                StoredPetSpeechPhraseV9(
                                    id: $0.id,
                                    text: $0.text,
                                    displayDurationMilliseconds:
                                        $0.displayDurationMilliseconds,
                                    trigger: $0.trigger,
                                    displayMode: "timed"
                                )
                            },
                            theme: profile.speech.theme
                        )
                    )
                }
            ),
            issues: []
        )
    }
}
