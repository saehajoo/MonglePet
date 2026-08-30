import Foundation

/// schema-v15 separates the behavior shown while stationary from conditional
/// rule evaluation. Rules can therefore override either a fixed or random
/// stationary selection without changing the selection mode itself.
nonisolated struct StoredAppSettingsV15: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let selectedPetInstanceID: String
    let activePetInstances: [StoredPetInstanceV11]
    let behaviorProfiles: [StoredPetProfileV15]
}

nonisolated struct StoredPetProfileV15: Codable, Equatable, Sendable {
    let profileID: String
    let petKey: StoredPetBehaviorKeyV2
    let stationaryBehaviorMode: String
    let stationarySequenceID: String?
    let randomSequenceIDs: [String]
    let sequences: [StoredBehaviorSequenceV12]
    let automaticRules: [StoredAutomaticRule]
    let automaticRulePriorityOrder: [String]
    let movement: StoredPetMovementSettingsV14
    let pettingBehaviorID: String?
    let speech: StoredPetSpeechSettingsV10
}

nonisolated enum AppSettingsV14ToV15MigrationError:
    Error,
    Equatable,
    Sendable
{
    case unsupportedSourceSchema(Int)
}

nonisolated enum AppSettingsV14ToV15Migrator {
    static func migrate(
        _ stored: StoredAppSettingsV14
    ) throws -> StoredAppSettingsV15 {
        guard stored.schemaVersion == 14 else {
            throw AppSettingsV14ToV15MigrationError
                .unsupportedSourceSchema(stored.schemaVersion)
        }

        return StoredAppSettingsV15(
            schemaVersion: 15,
            selectedPetInstanceID: stored.selectedPetInstanceID,
            activePetInstances: stored.activePetInstances,
            behaviorProfiles: stored.behaviorProfiles.map { profile in
                let stationaryBehaviorMode: String
                let stationarySequenceID: String?
                let rules: [StoredAutomaticRule]
                switch profile.mode {
                case BehaviorMode.random.rawValue:
                    stationaryBehaviorMode = StationaryBehaviorMode.random.rawValue
                    stationarySequenceID = nil
                    rules = profile.automaticRules.map(disabledRule)
                case BehaviorMode.manual.rawValue:
                    stationaryBehaviorMode = StationaryBehaviorMode.fixed.rawValue
                    stationarySequenceID = profile.manualSequenceID
                    rules = profile.automaticRules.map(disabledRule)
                default:
                    stationaryBehaviorMode = StationaryBehaviorMode.fixed.rawValue
                    stationarySequenceID = nil
                    rules = profile.automaticRules
                }

                return StoredPetProfileV15(
                    profileID: profile.profileID,
                    petKey: profile.petKey,
                    stationaryBehaviorMode: stationaryBehaviorMode,
                    stationarySequenceID: stationarySequenceID,
                    randomSequenceIDs: profile.randomSequenceIDs,
                    sequences: profile.sequences,
                    automaticRules: rules,
                    automaticRulePriorityOrder:
                        profile.automaticRulePriorityOrder,
                    movement: profile.movement,
                    pettingBehaviorID: profile.pettingBehaviorID,
                    speech: profile.speech
                )
            }
        )
    }

    private static func disabledRule(
        _ rule: StoredAutomaticRule
    ) -> StoredAutomaticRule {
        StoredAutomaticRule(
            id: rule.id,
            isEnabled: false,
            priority: rule.priority,
            condition: rule.condition,
            sequenceID: rule.sequenceID
        )
    }
}
