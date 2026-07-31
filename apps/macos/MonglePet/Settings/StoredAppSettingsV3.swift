import Foundation

nonisolated struct StoredAppSettingsV3: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let selectedPetInstallationID: String?
    let lastUserPresentation: String
    let overlay: StoredOverlaySettings
    let behaviorProfiles: [StoredPetProfileV3]
}

nonisolated struct StoredPetProfileV3: Codable, Equatable, Sendable {
    let petKey: StoredPetBehaviorKeyV2
    let mode: String
    let manualSequenceID: String?
    let sequences: [StoredBehaviorSequenceV2]
    let automaticRules: [StoredAutomaticRule]
    let movement: StoredPetMovementSettingsV3
    let pettingMotionID: String?

    init(
        petKey: StoredPetBehaviorKeyV2,
        mode: String,
        manualSequenceID: String?,
        sequences: [StoredBehaviorSequenceV2],
        automaticRules: [StoredAutomaticRule],
        movement: StoredPetMovementSettingsV3,
        pettingMotionID: String? = nil
    ) {
        self.petKey = petKey
        self.mode = mode
        self.manualSequenceID = manualSequenceID
        self.sequences = sequences
        self.automaticRules = automaticRules
        self.movement = movement
        self.pettingMotionID = pettingMotionID
    }
}

nonisolated struct StoredPetMovementSettingsV3: Codable, Equatable, Sendable {
    let mode: String
    let speed: Double
    let cursorDistance: Double
    let stopRadius: Double
    let freeRoamingDwellMilliseconds: Int64
    let prefersFrontmostWindow: Bool
    let cursorFollowingMotionID: String?
    let freeRoamingMotionID: String?

    init(
        mode: String,
        speed: Double,
        cursorDistance: Double,
        stopRadius: Double,
        freeRoamingDwellMilliseconds: Int64,
        prefersFrontmostWindow: Bool,
        cursorFollowingMotionID: String? = nil,
        freeRoamingMotionID: String? = nil
    ) {
        self.mode = mode
        self.speed = speed
        self.cursorDistance = cursorDistance
        self.stopRadius = stopRadius
        self.freeRoamingDwellMilliseconds = freeRoamingDwellMilliseconds
        self.prefersFrontmostWindow = prefersFrontmostWindow
        self.cursorFollowingMotionID = cursorFollowingMotionID
        self.freeRoamingMotionID = freeRoamingMotionID
    }
}

nonisolated struct AppSettingsV2ToV3MigrationResult: Equatable, Sendable {
    let settings: StoredAppSettingsV3
    let issues: [SettingsRecoveryIssue]
}

nonisolated enum AppSettingsV2ToV3MigrationError: Error, Equatable, Sendable {
    case unsupportedSourceSchema(Int)
}

nonisolated enum AppSettingsV2ToV3Migrator {
    static func migrate(
        _ stored: StoredAppSettingsV2
    ) throws -> AppSettingsV2ToV3MigrationResult {
        guard stored.schemaVersion == 2 else {
            throw AppSettingsV2ToV3MigrationError.unsupportedSourceSchema(
                stored.schemaVersion
            )
        }
        let mapped = AppSettingsV2Mapper.domainSettings(from: stored)
        return AppSettingsV2ToV3MigrationResult(
            settings: try AppSettingsV3Mapper.storedSettings(from: mapped.settings),
            issues: mapped.issues
        )
    }
}
