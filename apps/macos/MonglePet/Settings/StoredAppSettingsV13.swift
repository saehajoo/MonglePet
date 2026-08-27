import Foundation

/// schema-v13 adds a shuffle-bag behavior mode and a randomized free-roaming
/// dwell range. Existing point-based pet size storage remains compatible.
nonisolated struct StoredAppSettingsV13: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let selectedPetInstanceID: String
    let activePetInstances: [StoredPetInstanceV11]
    let behaviorProfiles: [StoredPetProfileV13]
}

nonisolated struct StoredPetProfileV13: Codable, Equatable, Sendable {
    let profileID: String
    let petKey: StoredPetBehaviorKeyV2
    let mode: String
    let manualSequenceID: String?
    let randomSequenceIDs: [String]
    let sequences: [StoredBehaviorSequenceV12]
    let automaticRules: [StoredAutomaticRule]
    let automaticRulePriorityOrder: [String]
    let movement: StoredPetMovementSettingsV13
    let pettingBehaviorID: String?
    let speech: StoredPetSpeechSettingsV10
}

nonisolated struct StoredPetMovementSettingsV13:
    Codable,
    Equatable,
    Sendable
{
    let mode: String
    let speed: Double
    let cursorDistance: Double
    let stopRadius: Double
    let freeRoamingDwellMilliseconds: Int64
    let randomizesFreeRoamingDwell: Bool
    let freeRoamingDwellMinimumMilliseconds: Int64
    let prefersFrontmostWindow: Bool
    let cursorFollowingBehavior: StoredMovementBehaviorSettingsV12
    let freeRoamingBehavior: StoredMovementBehaviorSettingsV12
    let cursorAvoidingIdleBehavior: String
    let cursorAvoidingDetectionDistance: Double
    let cursorAvoidingSpeed: Double
    let cursorAvoidingBehavior: StoredMovementBehaviorSettingsV12
}

nonisolated enum AppSettingsV12ToV13MigrationError:
    Error,
    Equatable,
    Sendable
{
    case unsupportedSourceSchema(Int)
}

nonisolated enum AppSettingsV12ToV13Migrator {
    static func migrate(
        _ stored: StoredAppSettingsV12
    ) throws -> StoredAppSettingsV13 {
        guard stored.schemaVersion == 12 else {
            throw AppSettingsV12ToV13MigrationError
                .unsupportedSourceSchema(stored.schemaVersion)
        }
        return StoredAppSettingsV13(
            schemaVersion: 13,
            selectedPetInstanceID: stored.selectedPetInstanceID,
            activePetInstances: stored.activePetInstances,
            behaviorProfiles: stored.behaviorProfiles.map { profile in
                let movement = profile.movement
                let maximum = movement.freeRoamingDwellMilliseconds
                let minimum = min(
                    maximum,
                    max(
                        AppSettingsLimits.minimumFreeRoamingDwellMilliseconds,
                        maximum / 2
                    )
                )
                return StoredPetProfileV13(
                    profileID: profile.profileID,
                    petKey: profile.petKey,
                    mode: profile.mode,
                    manualSequenceID: profile.manualSequenceID,
                    randomSequenceIDs: [],
                    sequences: profile.sequences,
                    automaticRules: profile.automaticRules,
                    automaticRulePriorityOrder:
                        profile.automaticRulePriorityOrder,
                    movement: StoredPetMovementSettingsV13(
                        mode: movement.mode,
                        speed: movement.speed,
                        cursorDistance: movement.cursorDistance,
                        stopRadius: movement.stopRadius,
                        freeRoamingDwellMilliseconds: maximum,
                        randomizesFreeRoamingDwell: false,
                        freeRoamingDwellMinimumMilliseconds: minimum,
                        prefersFrontmostWindow:
                            movement.prefersFrontmostWindow,
                        cursorFollowingBehavior:
                            movement.cursorFollowingBehavior,
                        freeRoamingBehavior: movement.freeRoamingBehavior,
                        cursorAvoidingIdleBehavior:
                            movement.cursorAvoidingIdleBehavior,
                        cursorAvoidingDetectionDistance:
                            movement.cursorAvoidingDetectionDistance,
                        cursorAvoidingSpeed: movement.cursorAvoidingSpeed,
                        cursorAvoidingBehavior:
                            movement.cursorAvoidingBehavior
                    ),
                    pettingBehaviorID: profile.pettingBehaviorID,
                    speech: profile.speech
                )
            }
        )
    }
}
