import Foundation

nonisolated struct StoredAppSettingsV5: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let selectedPetInstallationID: String?
    let lastUserPresentation: String
    let overlay: StoredOverlaySettingsV4
    let behaviorProfiles: [StoredPetProfileV5]
}

nonisolated struct StoredPetProfileV5: Codable, Equatable, Sendable {
    let petKey: StoredPetBehaviorKeyV2
    let mode: String
    let manualSequenceID: String?
    let sequences: [StoredBehaviorSequenceV2]
    let automaticRules: [StoredAutomaticRule]
    let movement: StoredPetMovementSettingsV5
    let pettingMotionID: String?
}

nonisolated struct StoredPetMovementSettingsV5: Codable, Equatable, Sendable {
    let mode: String
    let speed: Double
    let cursorDistance: Double
    let stopRadius: Double
    let freeRoamingDwellMilliseconds: Int64
    let prefersFrontmostWindow: Bool
    let cursorFollowingAnimation: StoredMovementAnimationSettingsV5
    let freeRoamingAnimation: StoredMovementAnimationSettingsV5
}

nonisolated struct StoredMovementAnimationSettingsV5:
    Codable,
    Equatable,
    Sendable
{
    let fallbackMotionID: String?
    let usesDirectionalMotions: Bool
    let usesDiagonalMotions: Bool
    let directionMotionIDs: StoredDirectionalMotionIDsV5
}

nonisolated struct StoredDirectionalMotionIDsV5:
    Codable,
    Equatable,
    Sendable
{
    let left: String?
    let right: String?
    let up: String?
    let down: String?
    let upLeft: String?
    let upRight: String?
    let downLeft: String?
    let downRight: String?
}

nonisolated struct AppSettingsV4ToV5MigrationResult: Equatable, Sendable {
    let settings: StoredAppSettingsV5
    let issues: [SettingsRecoveryIssue]
}

nonisolated enum AppSettingsV4ToV5MigrationError:
    Error,
    Equatable,
    Sendable
{
    case unsupportedSourceSchema(Int)
}

nonisolated enum AppSettingsV4ToV5Migrator {
    static func migrate(
        _ stored: StoredAppSettingsV4
    ) throws -> AppSettingsV4ToV5MigrationResult {
        guard stored.schemaVersion == 4 else {
            throw AppSettingsV4ToV5MigrationError.unsupportedSourceSchema(
                stored.schemaVersion
            )
        }
        let mapped = AppSettingsV4Mapper.domainSettings(from: stored)
        return AppSettingsV4ToV5MigrationResult(
            settings: try AppSettingsV5Mapper.storedSettings(
                from: mapped.settings
            ),
            issues: mapped.issues
        )
    }
}
