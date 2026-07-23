import Foundation

nonisolated struct StoredAppSettingsV4: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let selectedPetInstallationID: String?
    let lastUserPresentation: String
    let overlay: StoredOverlaySettingsV4
    let behaviorProfiles: [StoredPetProfileV3]
}

nonisolated struct StoredOverlaySettingsV4: Codable, Equatable, Sendable {
    let screenIdentifier: String?
    let originX: Double
    let originY: Double
    let width: Double
    let clickThrough: Bool
    let opacity: Double
    let pointerOverlapFadeEnabled: Bool
    let pointerOverlapOpacity: Double
    let movementBoundary: StoredMovementBoundarySettingsV4
}

nonisolated struct StoredMovementBoundarySettingsV4: Codable, Equatable, Sendable {
    let mode: String
    let screenIdentifier: String?
    let normalizedRect: StoredNormalizedMovementRectV4?
}

nonisolated struct StoredNormalizedMovementRectV4: Codable, Equatable, Sendable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}

nonisolated struct AppSettingsV3ToV4MigrationResult: Equatable, Sendable {
    let settings: StoredAppSettingsV4
    let issues: [SettingsRecoveryIssue]
}

nonisolated enum AppSettingsV3ToV4MigrationError: Error, Equatable, Sendable {
    case unsupportedSourceSchema(Int)
}

nonisolated enum AppSettingsV3ToV4Migrator {
    static func migrate(
        _ stored: StoredAppSettingsV3
    ) throws -> AppSettingsV3ToV4MigrationResult {
        guard stored.schemaVersion == 3 else {
            throw AppSettingsV3ToV4MigrationError.unsupportedSourceSchema(
                stored.schemaVersion
            )
        }
        return AppSettingsV3ToV4MigrationResult(
            settings: StoredAppSettingsV4(
                schemaVersion: 4,
                selectedPetInstallationID: stored.selectedPetInstallationID,
                lastUserPresentation: stored.lastUserPresentation,
                overlay: StoredOverlaySettingsV4(
                    screenIdentifier: stored.overlay.screenIdentifier,
                    originX: stored.overlay.originX,
                    originY: stored.overlay.originY,
                    width: stored.overlay.width,
                    clickThrough: stored.overlay.clickThrough,
                    opacity: AppSettingsLimits.defaultOverlayOpacity,
                    pointerOverlapFadeEnabled: false,
                    pointerOverlapOpacity:
                        AppSettingsLimits.defaultPointerOverlapOpacity,
                    movementBoundary: StoredMovementBoundarySettingsV4(
                        mode: "allDisplays",
                        screenIdentifier: nil,
                        normalizedRect: nil
                    )
                ),
                behaviorProfiles: stored.behaviorProfiles
            ),
            issues: []
        )
    }
}
