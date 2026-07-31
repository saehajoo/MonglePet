import Foundation

nonisolated struct StoredAppSettingsV6: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let selectedPetInstallationID: String?
    let lastUserPresentation: String
    let overlay: StoredOverlaySettingsV4
    let behaviorProfiles: [StoredPetProfileV6]
}

nonisolated struct StoredPetProfileV6: Codable, Equatable, Sendable {
    let petKey: StoredPetBehaviorKeyV2
    let mode: String
    let manualSequenceID: String?
    let sequences: [StoredBehaviorSequenceV2]
    let automaticRules: [StoredAutomaticRule]
    let movement: StoredPetMovementSettingsV6
    let pettingMotionID: String?
}

nonisolated struct StoredPetMovementSettingsV6:
    Codable,
    Equatable,
    Sendable
{
    let mode: String
    let speed: Double
    let cursorDistance: Double
    let stopRadius: Double
    let freeRoamingDwellMilliseconds: Int64
    let prefersFrontmostWindow: Bool
    let cursorFollowingAnimation: StoredMovementAnimationSettingsV5
    let freeRoamingAnimation: StoredMovementAnimationSettingsV5
    let cursorAvoidingIdleBehavior: String
    let cursorAvoidingDetectionDistance: Double
    let cursorAvoidingSpeed: Double
    let cursorAvoidingAnimation: StoredMovementAnimationSettingsV5
}

nonisolated struct AppSettingsV5ToV6MigrationResult:
    Equatable,
    Sendable
{
    let settings: StoredAppSettingsV6
    let issues: [SettingsRecoveryIssue]
}

nonisolated enum AppSettingsV5ToV6MigrationError:
    Error,
    Equatable,
    Sendable
{
    case unsupportedSourceSchema(Int)
}

nonisolated enum AppSettingsV5ToV6Migrator {
    static func migrate(
        _ stored: StoredAppSettingsV5
    ) throws -> AppSettingsV5ToV6MigrationResult {
        guard stored.schemaVersion == 5 else {
            throw AppSettingsV5ToV6MigrationError.unsupportedSourceSchema(
                stored.schemaVersion
            )
        }
        let emptyAnimation = StoredMovementAnimationSettingsV5(
            fallbackMotionID: nil,
            usesDirectionalMotions: false,
            usesDiagonalMotions: false,
            directionMotionIDs: StoredDirectionalMotionIDsV5(
                left: nil,
                right: nil,
                up: nil,
                down: nil,
                upLeft: nil,
                upRight: nil,
                downLeft: nil,
                downRight: nil
            )
        )
        return AppSettingsV5ToV6MigrationResult(
            settings: StoredAppSettingsV6(
                schemaVersion: 6,
                selectedPetInstallationID:
                    stored.selectedPetInstallationID,
                lastUserPresentation: stored.lastUserPresentation,
                overlay: stored.overlay,
                behaviorProfiles: stored.behaviorProfiles.map { profile in
                    let movement = profile.movement
                    return StoredPetProfileV6(
                        petKey: profile.petKey,
                        mode: profile.mode,
                        manualSequenceID: profile.manualSequenceID,
                        sequences: profile.sequences,
                        automaticRules: profile.automaticRules,
                        movement: StoredPetMovementSettingsV6(
                            mode: movement.mode,
                            speed: movement.speed,
                            cursorDistance: movement.cursorDistance,
                            stopRadius: movement.stopRadius,
                            freeRoamingDwellMilliseconds:
                                movement.freeRoamingDwellMilliseconds,
                            prefersFrontmostWindow:
                                movement.prefersFrontmostWindow,
                            cursorFollowingAnimation:
                                movement.cursorFollowingAnimation,
                            freeRoamingAnimation:
                                movement.freeRoamingAnimation,
                            cursorAvoidingIdleBehavior: "stationary",
                            cursorAvoidingDetectionDistance:
                                AppSettingsLimits
                                    .defaultCursorAvoidingDetectionDistance,
                            cursorAvoidingSpeed:
                                AppSettingsLimits.defaultCursorAvoidingSpeed,
                            cursorAvoidingAnimation: emptyAnimation
                        ),
                        pettingMotionID: profile.pettingMotionID
                    )
                }
            ),
            issues: []
        )
    }
}
