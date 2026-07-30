import Foundation

nonisolated struct StoredAppSettingsV7: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let selectedPetInstallationID: String?
    let lastUserPresentation: String
    let overlay: StoredOverlaySettingsV4
    let behaviorProfiles: [StoredPetProfileV7]
}

nonisolated struct StoredPetProfileV7: Codable, Equatable, Sendable {
    let petKey: StoredPetBehaviorKeyV2
    let mode: String
    let manualSequenceID: String?
    let sequences: [StoredBehaviorSequenceV2]
    let automaticRules: [StoredAutomaticRule]
    let movement: StoredPetMovementSettingsV6
    let pettingMotionID: String?
    let speech: StoredPetSpeechSettingsV7
}

nonisolated struct StoredPetSpeechSettingsV7:
    Codable,
    Equatable,
    Sendable
{
    let isEnabled: Bool
    let periodicIntervalMilliseconds: Int64
    let phrases: [StoredPetSpeechPhraseV7]
}

nonisolated struct StoredPetSpeechPhraseV7:
    Codable,
    Equatable,
    Sendable
{
    let id: String
    let text: String
    let displayDurationMilliseconds: Int64
    let trigger: StoredPetSpeechTriggerV7
}

nonisolated struct StoredPetSpeechTriggerV7:
    Codable,
    Equatable,
    Sendable
{
    let type: String
    let sequenceID: String?
}

nonisolated struct AppSettingsV6ToV7MigrationResult:
    Equatable,
    Sendable
{
    let settings: StoredAppSettingsV7
    let issues: [SettingsRecoveryIssue]
}

nonisolated enum AppSettingsV6ToV7MigrationError:
    Error,
    Equatable,
    Sendable
{
    case unsupportedSourceSchema(Int)
}

nonisolated enum AppSettingsV6ToV7Migrator {
    static func migrate(
        _ stored: StoredAppSettingsV6
    ) throws -> AppSettingsV6ToV7MigrationResult {
        guard stored.schemaVersion == 6 else {
            throw AppSettingsV6ToV7MigrationError.unsupportedSourceSchema(
                stored.schemaVersion
            )
        }
        return AppSettingsV6ToV7MigrationResult(
            settings: StoredAppSettingsV7(
                schemaVersion: 7,
                selectedPetInstallationID:
                    stored.selectedPetInstallationID,
                lastUserPresentation: stored.lastUserPresentation,
                overlay: stored.overlay,
                behaviorProfiles: stored.behaviorProfiles.map { profile in
                    StoredPetProfileV7(
                        petKey: profile.petKey,
                        mode: profile.mode,
                        manualSequenceID: profile.manualSequenceID,
                        sequences: profile.sequences,
                        automaticRules: profile.automaticRules,
                        movement: profile.movement,
                        pettingMotionID: profile.pettingMotionID,
                        speech: StoredPetSpeechSettingsV7(
                            isEnabled: false,
                            periodicIntervalMilliseconds:
                                AppSettingsLimits
                                    .defaultSpeechPeriodicIntervalMilliseconds,
                            phrases: []
                        )
                    )
                }
            ),
            issues: []
        )
    }
}
