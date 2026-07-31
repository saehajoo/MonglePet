import Foundation

nonisolated struct StoredAppSettingsV10: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let selectedPetInstallationID: String?
    let lastUserPresentation: String
    let overlay: StoredOverlaySettingsV4
    let behaviorProfiles: [StoredPetProfileV10]
}

nonisolated struct StoredPetProfileV10: Codable, Equatable, Sendable {
    let petKey: StoredPetBehaviorKeyV2
    let mode: String
    let manualSequenceID: String?
    let sequences: [StoredBehaviorSequenceV2]
    let automaticRules: [StoredAutomaticRule]
    let movement: StoredPetMovementSettingsV6
    let pettingMotionID: String?
    let speech: StoredPetSpeechSettingsV10
}

nonisolated struct StoredPetSpeechSettingsV10:
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
    let placement: StoredPetSpeechBubblePlacementV10
}

nonisolated struct StoredPetSpeechBubblePlacementV10:
    Codable,
    Equatable,
    Sendable
{
    let preferredPosition: String
    let horizontalOffset: Double
    let gap: Double
}

nonisolated struct AppSettingsV9ToV10MigrationResult:
    Equatable,
    Sendable
{
    let settings: StoredAppSettingsV10
    let issues: [SettingsRecoveryIssue]
}

nonisolated enum AppSettingsV9ToV10MigrationError:
    Error,
    Equatable,
    Sendable
{
    case unsupportedSourceSchema(Int)
}

nonisolated enum AppSettingsV9ToV10Migrator {
    static func migrate(
        _ stored: StoredAppSettingsV9
    ) throws -> AppSettingsV9ToV10MigrationResult {
        guard stored.schemaVersion == 9 else {
            throw AppSettingsV9ToV10MigrationError.unsupportedSourceSchema(
                stored.schemaVersion
            )
        }
        let placement = StoredPetSpeechBubblePlacementV10(
            preferredPosition: "automatic",
            horizontalOffset:
                AppSettingsLimits.defaultSpeechBubbleHorizontalOffset,
            gap: AppSettingsLimits.defaultSpeechBubbleGap
        )
        return AppSettingsV9ToV10MigrationResult(
            settings: StoredAppSettingsV10(
                schemaVersion: 10,
                selectedPetInstallationID:
                    stored.selectedPetInstallationID,
                lastUserPresentation: stored.lastUserPresentation,
                overlay: stored.overlay,
                behaviorProfiles: stored.behaviorProfiles.map { profile in
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
                            placement: placement
                        )
                    )
                }
            ),
            issues: []
        )
    }
}
