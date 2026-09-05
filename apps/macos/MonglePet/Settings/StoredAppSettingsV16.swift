import Foundation

/// schema-v16 replaces the free-roaming randomization boolean with an
/// explicit timing mode so movement can also wait for a stationary behavior
/// pass to finish.
nonisolated struct StoredAppSettingsV16: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let selectedPetInstanceID: String
    let activePetInstances: [StoredPetInstanceV11]
    let behaviorProfiles: [StoredPetProfileV16]
}

nonisolated struct StoredPetProfileV16: Codable, Equatable, Sendable {
    let profileID: String
    let petKey: StoredPetBehaviorKeyV2
    let stationaryBehaviorMode: String
    let stationarySequenceID: String?
    let randomSequenceIDs: [String]
    let sequences: [StoredBehaviorSequenceV12]
    let automaticRules: [StoredAutomaticRule]
    let automaticRulePriorityOrder: [String]
    let movement: StoredPetMovementSettingsV16
    let pettingBehaviorID: String?
    let speech: StoredPetSpeechSettingsV10
}

nonisolated struct StoredPetMovementSettingsV16:
    Codable,
    Equatable,
    Sendable
{
    let mode: String
    let cursorFollowing: StoredCursorFollowingMovementSettingsV14
    let freeRoaming: StoredFreeRoamingMovementSettingsV16
    let cursorAvoiding: StoredCursorAvoidingMovementSettingsV16
}

nonisolated struct StoredFreeRoamingMovementSettingsV16:
    Codable,
    Equatable,
    Sendable
{
    let speed: Double
    let stopRadius: Double
    let dwellMode: String
    let dwellMilliseconds: Int64
    let dwellMinimumMilliseconds: Int64
    let prefersFrontmostWindow: Bool
    let behavior: StoredMovementBehaviorSettingsV12
}

nonisolated struct StoredCursorAvoidingMovementSettingsV16:
    Codable,
    Equatable,
    Sendable
{
    let idleBehavior: String
    let detectionDistance: Double
    let speed: Double
    let stopRadius: Double
    let behavior: StoredMovementBehaviorSettingsV12
    let idleFreeRoaming: StoredFreeRoamingMovementSettingsV16
}

nonisolated enum AppSettingsV15ToV16MigrationError:
    Error,
    Equatable,
    Sendable
{
    case unsupportedSourceSchema(Int)
}

nonisolated enum AppSettingsV15ToV16Migrator {
    static func migrate(
        _ stored: StoredAppSettingsV15
    ) throws -> StoredAppSettingsV16 {
        guard stored.schemaVersion == 15 else {
            throw AppSettingsV15ToV16MigrationError
                .unsupportedSourceSchema(stored.schemaVersion)
        }
        return StoredAppSettingsV16(
            schemaVersion: 16,
            selectedPetInstanceID: stored.selectedPetInstanceID,
            activePetInstances: stored.activePetInstances,
            behaviorProfiles: stored.behaviorProfiles.map { profile in
                StoredPetProfileV16(
                    profileID: profile.profileID,
                    petKey: profile.petKey,
                    stationaryBehaviorMode:
                        profile.stationaryBehaviorMode,
                    stationarySequenceID: profile.stationarySequenceID,
                    randomSequenceIDs: profile.randomSequenceIDs,
                    sequences: profile.sequences,
                    automaticRules: profile.automaticRules,
                    automaticRulePriorityOrder:
                        profile.automaticRulePriorityOrder,
                    movement: migrate(profile.movement),
                    pettingBehaviorID: profile.pettingBehaviorID,
                    speech: profile.speech
                )
            }
        )
    }

    private static func migrate(
        _ movement: StoredPetMovementSettingsV14
    ) -> StoredPetMovementSettingsV16 {
        StoredPetMovementSettingsV16(
            mode: movement.mode,
            cursorFollowing: movement.cursorFollowing,
            freeRoaming: migrate(movement.freeRoaming),
            cursorAvoiding: StoredCursorAvoidingMovementSettingsV16(
                idleBehavior: movement.cursorAvoiding.idleBehavior,
                detectionDistance:
                    movement.cursorAvoiding.detectionDistance,
                speed: movement.cursorAvoiding.speed,
                stopRadius: movement.cursorAvoiding.stopRadius,
                behavior: movement.cursorAvoiding.behavior,
                idleFreeRoaming: migrate(
                    movement.cursorAvoiding.idleFreeRoaming
                )
            )
        )
    }

    private static func migrate(
        _ roaming: StoredFreeRoamingMovementSettingsV14
    ) -> StoredFreeRoamingMovementSettingsV16 {
        StoredFreeRoamingMovementSettingsV16(
            speed: roaming.speed,
            stopRadius: roaming.stopRadius,
            dwellMode: roaming.randomizesDwell
                ? FreeRoamingDwellMode.random.rawValue
                : FreeRoamingDwellMode.fixed.rawValue,
            dwellMilliseconds: roaming.dwellMilliseconds,
            dwellMinimumMilliseconds: roaming.dwellMinimumMilliseconds,
            prefersFrontmostWindow: roaming.prefersFrontmostWindow,
            behavior: roaming.behavior
        )
    }
}
