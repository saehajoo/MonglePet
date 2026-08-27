import Foundation

/// schema-v14 stores every movement mode independently. The v13 shared
/// values are copied into the corresponding profiles during migration so the
/// active behavior does not change when an existing user upgrades.
nonisolated struct StoredAppSettingsV14: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let selectedPetInstanceID: String
    let activePetInstances: [StoredPetInstanceV11]
    let behaviorProfiles: [StoredPetProfileV14]
}

nonisolated struct StoredPetProfileV14: Codable, Equatable, Sendable {
    let profileID: String
    let petKey: StoredPetBehaviorKeyV2
    let mode: String
    let manualSequenceID: String?
    let randomSequenceIDs: [String]
    let sequences: [StoredBehaviorSequenceV12]
    let automaticRules: [StoredAutomaticRule]
    let automaticRulePriorityOrder: [String]
    let movement: StoredPetMovementSettingsV14
    let pettingBehaviorID: String?
    let speech: StoredPetSpeechSettingsV10
}

nonisolated struct StoredPetMovementSettingsV14:
    Codable,
    Equatable,
    Sendable
{
    let mode: String
    let cursorFollowing: StoredCursorFollowingMovementSettingsV14
    let freeRoaming: StoredFreeRoamingMovementSettingsV14
    let cursorAvoiding: StoredCursorAvoidingMovementSettingsV14
}

nonisolated struct StoredCursorFollowingMovementSettingsV14:
    Codable,
    Equatable,
    Sendable
{
    let speed: Double
    let cursorDistance: Double
    let stopRadius: Double
    let behavior: StoredMovementBehaviorSettingsV12
}

nonisolated struct StoredFreeRoamingMovementSettingsV14:
    Codable,
    Equatable,
    Sendable
{
    let speed: Double
    let stopRadius: Double
    let dwellMilliseconds: Int64
    let randomizesDwell: Bool
    let dwellMinimumMilliseconds: Int64
    let prefersFrontmostWindow: Bool
    let behavior: StoredMovementBehaviorSettingsV12
}

nonisolated struct StoredCursorAvoidingMovementSettingsV14:
    Codable,
    Equatable,
    Sendable
{
    let idleBehavior: String
    let detectionDistance: Double
    let speed: Double
    let stopRadius: Double
    let behavior: StoredMovementBehaviorSettingsV12
    let idleFreeRoaming: StoredFreeRoamingMovementSettingsV14
}

nonisolated enum AppSettingsV13ToV14MigrationError:
    Error,
    Equatable,
    Sendable
{
    case unsupportedSourceSchema(Int)
}

nonisolated enum AppSettingsV13ToV14Migrator {
    static func migrate(
        _ stored: StoredAppSettingsV13
    ) throws -> StoredAppSettingsV14 {
        guard stored.schemaVersion == 13 else {
            throw AppSettingsV13ToV14MigrationError
                .unsupportedSourceSchema(stored.schemaVersion)
        }
        return StoredAppSettingsV14(
            schemaVersion: 14,
            selectedPetInstanceID: stored.selectedPetInstanceID,
            activePetInstances: stored.activePetInstances,
            behaviorProfiles: stored.behaviorProfiles.map { profile in
                let movement = profile.movement
                let roaming = StoredFreeRoamingMovementSettingsV14(
                    speed: movement.speed,
                    stopRadius: movement.stopRadius,
                    dwellMilliseconds:
                        movement.freeRoamingDwellMilliseconds,
                    randomizesDwell:
                        movement.randomizesFreeRoamingDwell,
                    dwellMinimumMilliseconds:
                        movement.freeRoamingDwellMinimumMilliseconds,
                    prefersFrontmostWindow:
                        movement.prefersFrontmostWindow,
                    behavior: movement.freeRoamingBehavior
                )
                return StoredPetProfileV14(
                    profileID: profile.profileID,
                    petKey: profile.petKey,
                    mode: profile.mode,
                    manualSequenceID: profile.manualSequenceID,
                    randomSequenceIDs: profile.randomSequenceIDs,
                    sequences: profile.sequences,
                    automaticRules: profile.automaticRules,
                    automaticRulePriorityOrder:
                        profile.automaticRulePriorityOrder,
                    movement: StoredPetMovementSettingsV14(
                        mode: movement.mode,
                        cursorFollowing:
                            StoredCursorFollowingMovementSettingsV14(
                                speed: movement.speed,
                                cursorDistance: movement.cursorDistance,
                                stopRadius: movement.stopRadius,
                                behavior: movement.cursorFollowingBehavior
                            ),
                        freeRoaming: roaming,
                        cursorAvoiding:
                            StoredCursorAvoidingMovementSettingsV14(
                                idleBehavior:
                                    movement.cursorAvoidingIdleBehavior,
                                detectionDistance:
                                    movement.cursorAvoidingDetectionDistance,
                                speed: movement.cursorAvoidingSpeed,
                                stopRadius: movement.stopRadius,
                                behavior: movement.cursorAvoidingBehavior,
                                idleFreeRoaming: roaming
                            )
                    ),
                    pettingBehaviorID: profile.pettingBehaviorID,
                    speech: profile.speech
                )
            }
        )
    }
}
