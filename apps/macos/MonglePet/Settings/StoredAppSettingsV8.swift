import Foundation

nonisolated struct StoredAppSettingsV8: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let selectedPetInstallationID: String?
    let lastUserPresentation: String
    let overlay: StoredOverlaySettingsV4
    let behaviorProfiles: [StoredPetProfileV8]
}

nonisolated struct StoredPetProfileV8: Codable, Equatable, Sendable {
    let petKey: StoredPetBehaviorKeyV2
    let mode: String
    let manualSequenceID: String?
    let sequences: [StoredBehaviorSequenceV2]
    let automaticRules: [StoredAutomaticRule]
    let movement: StoredPetMovementSettingsV6
    let pettingMotionID: String?
    let speech: StoredPetSpeechSettingsV8
}

nonisolated struct StoredPetSpeechSettingsV8:
    Codable,
    Equatable,
    Sendable
{
    let isEnabled: Bool
    let periodicIntervalMilliseconds: Int64
    let phrases: [StoredPetSpeechPhraseV7]
    let theme: StoredPetSpeechBubbleThemeV8
}

nonisolated struct StoredPetSpeechBubbleThemeV8:
    Codable,
    Equatable,
    Sendable
{
    let colorStyle: String
    let customBackgroundColor: StoredPetSpeechColorV8
    let customTextColor: StoredPetSpeechColorV8
    let backgroundOpacity: Double
    let fontSize: Double
    let contentPadding: Double
    let cornerRadius: Double
    let showsTail: Bool
    let tailAlignment: String
}

nonisolated struct StoredPetSpeechColorV8:
    Codable,
    Equatable,
    Sendable
{
    let red: Double
    let green: Double
    let blue: Double
}

nonisolated struct AppSettingsV7ToV8MigrationResult:
    Equatable,
    Sendable
{
    let settings: StoredAppSettingsV8
    let issues: [SettingsRecoveryIssue]
}

nonisolated enum AppSettingsV7ToV8MigrationError:
    Error,
    Equatable,
    Sendable
{
    case unsupportedSourceSchema(Int)
}

nonisolated enum AppSettingsV7ToV8Migrator {
    static func migrate(
        _ stored: StoredAppSettingsV7
    ) throws -> AppSettingsV7ToV8MigrationResult {
        guard stored.schemaVersion == 7 else {
            throw AppSettingsV7ToV8MigrationError.unsupportedSourceSchema(
                stored.schemaVersion
            )
        }
        let theme = StoredPetSpeechBubbleThemeV8(
            colorStyle: "system",
            customBackgroundColor: StoredPetSpeechColorV8(
                red: 1,
                green: 1,
                blue: 1
            ),
            customTextColor: StoredPetSpeechColorV8(
                red: 0,
                green: 0,
                blue: 0
            ),
            backgroundOpacity:
                AppSettingsLimits.defaultSpeechBubbleBackgroundOpacity,
            fontSize: AppSettingsLimits.defaultSpeechBubbleFontSize,
            contentPadding:
                AppSettingsLimits.defaultSpeechBubbleContentPadding,
            cornerRadius:
                AppSettingsLimits.defaultSpeechBubbleCornerRadius,
            showsTail: false,
            tailAlignment: "center"
        )
        return AppSettingsV7ToV8MigrationResult(
            settings: StoredAppSettingsV8(
                schemaVersion: 8,
                selectedPetInstallationID:
                    stored.selectedPetInstallationID,
                lastUserPresentation: stored.lastUserPresentation,
                overlay: stored.overlay,
                behaviorProfiles: stored.behaviorProfiles.map { profile in
                    StoredPetProfileV8(
                        petKey: profile.petKey,
                        mode: profile.mode,
                        manualSequenceID: profile.manualSequenceID,
                        sequences: profile.sequences,
                        automaticRules: profile.automaticRules,
                        movement: profile.movement,
                        pettingMotionID: profile.pettingMotionID,
                        speech: StoredPetSpeechSettingsV8(
                            isEnabled: profile.speech.isEnabled,
                            periodicIntervalMilliseconds:
                                profile.speech
                                    .periodicIntervalMilliseconds,
                            phrases: profile.speech.phrases,
                            theme: theme
                        )
                    )
                }
            ),
            issues: []
        )
    }
}
