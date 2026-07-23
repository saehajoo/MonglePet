import Foundation

nonisolated enum AppSettingsV4Mapper {
    static func domainSettings(
        from stored: StoredAppSettingsV4
    ) -> (settings: AppSettings, issues: [SettingsRecoveryIssue]) {
        let storedV3 = StoredAppSettingsV3(
            schemaVersion: 3,
            selectedPetInstallationID: stored.selectedPetInstallationID,
            lastUserPresentation: stored.lastUserPresentation,
            overlay: StoredOverlaySettings(
                screenIdentifier: stored.overlay.screenIdentifier,
                originX: stored.overlay.originX,
                originY: stored.overlay.originY,
                width: stored.overlay.width,
                clickThrough: stored.overlay.clickThrough
            ),
            behaviorProfiles: stored.behaviorProfiles
        )
        let mappedV3 = AppSettingsV3Mapper.domainSettings(from: storedV3)
        var issues = mappedV3.issues
        let movementBoundary = normalizedMovementBoundary(
            from: stored.overlay.movementBoundary,
            issues: &issues
        )
        let baseOverlay = mappedV3.settings.overlay
        let overlay = OverlaySettings(
            screenIdentifier: baseOverlay.screenIdentifier,
            originX: baseOverlay.originX,
            originY: baseOverlay.originY,
            width: baseOverlay.width,
            clickThrough: baseOverlay.clickThrough,
            opacity: normalizedDouble(
                stored.overlay.opacity,
                range: AppSettingsLimits.minimumOverlayOpacity
                    ... AppSettingsLimits.maximumOverlayOpacity,
                fallback: AppSettingsLimits.defaultOverlayOpacity,
                field: "overlay.opacity",
                issues: &issues
            ),
            pointerOverlapFadeEnabled:
                stored.overlay.pointerOverlapFadeEnabled,
            pointerOverlapOpacity: normalizedDouble(
                stored.overlay.pointerOverlapOpacity,
                range: AppSettingsLimits.minimumPointerOverlapOpacity
                    ... AppSettingsLimits.maximumPointerOverlapOpacity,
                fallback: AppSettingsLimits.defaultPointerOverlapOpacity,
                field: "overlay.pointerOverlapOpacity",
                issues: &issues
            ),
            movementBoundary: movementBoundary
        )
        return (
            AppSettings(
                selectedPetInstallationID:
                    mappedV3.settings.selectedPetInstallationID,
                lastUserPresentation:
                    mappedV3.settings.lastUserPresentation,
                overlay: overlay,
                behaviorProfiles: mappedV3.settings.behaviorProfiles
            ),
            issues
        )
    }

    static func storedSettings(
        from settings: AppSettings
    ) throws -> StoredAppSettingsV4 {
        guard settings.overlay.movementBoundary.isValid else {
            throw AppSettingsMappingError.invalidSettings(
                "overlay.movementBoundary"
            )
        }
        guard settings.overlay.opacity.isFinite,
              (AppSettingsLimits.minimumOverlayOpacity
                ... AppSettingsLimits.maximumOverlayOpacity)
                .contains(settings.overlay.opacity),
              settings.overlay.pointerOverlapOpacity.isFinite,
              (AppSettingsLimits.minimumPointerOverlapOpacity
                ... AppSettingsLimits.maximumPointerOverlapOpacity)
                .contains(settings.overlay.pointerOverlapOpacity)
        else {
            throw AppSettingsMappingError.invalidSettings(
                "overlay.opacity"
            )
        }
        let storedV3 = try AppSettingsV3Mapper.storedSettings(from: settings)
        let overlay = settings.overlay
        return StoredAppSettingsV4(
            schemaVersion: AppSettingsLimits.schemaVersion,
            selectedPetInstallationID: storedV3.selectedPetInstallationID,
            lastUserPresentation: storedV3.lastUserPresentation,
            overlay: StoredOverlaySettingsV4(
                screenIdentifier: overlay.screenIdentifier,
                originX: overlay.originX,
                originY: overlay.originY,
                width: overlay.width,
                clickThrough: overlay.clickThrough,
                opacity: overlay.opacity,
                pointerOverlapFadeEnabled:
                    overlay.pointerOverlapFadeEnabled,
                pointerOverlapOpacity: overlay.pointerOverlapOpacity,
                movementBoundary: storedMovementBoundary(
                    from: overlay.movementBoundary
                )
            ),
            behaviorProfiles: storedV3.behaviorProfiles
        )
    }

    private static func normalizedMovementBoundary(
        from stored: StoredMovementBoundarySettingsV4,
        issues: inout [SettingsRecoveryIssue]
    ) -> MovementBoundarySettings {
        let mode: MovementBoundaryMode
        switch stored.mode {
        case "allDisplays":
            mode = .allDisplays
        case "selectedDisplay":
            mode = .selectedDisplay
        case "customArea":
            mode = .customArea
        default:
            issues.append(.invalidField("overlay.movementBoundary.mode"))
            return .default
        }

        let screenIdentifier = normalizedIdentifier(stored.screenIdentifier)
        if stored.screenIdentifier != nil,
           screenIdentifier != stored.screenIdentifier {
            issues.append(
                .invalidField("overlay.movementBoundary.screenIdentifier")
            )
        }
        let normalizedRect: NormalizedMovementRect?
        if let storedRect = stored.normalizedRect {
            let candidate = NormalizedMovementRect(
                x: storedRect.x,
                y: storedRect.y,
                width: storedRect.width,
                height: storedRect.height
            )
            if candidate.isValid {
                normalizedRect = candidate
            } else {
                normalizedRect = nil
                issues.append(
                    .invalidField("overlay.movementBoundary.normalizedRect")
                )
            }
        } else {
            normalizedRect = nil
        }

        let boundary = MovementBoundarySettings(
            mode: mode,
            screenIdentifier: screenIdentifier,
            normalizedRect: normalizedRect
        )
        guard boundary.isValid else {
            if mode != .allDisplays, screenIdentifier == nil {
                issues.append(
                    .invalidField("overlay.movementBoundary.screenIdentifier")
                )
            }
            return .default
        }
        return boundary
    }

    private static func storedMovementBoundary(
        from boundary: MovementBoundarySettings
    ) -> StoredMovementBoundarySettingsV4 {
        let mode: String = switch boundary.mode {
        case .allDisplays:
            "allDisplays"
        case .selectedDisplay:
            "selectedDisplay"
        case .customArea:
            "customArea"
        }
        return StoredMovementBoundarySettingsV4(
            mode: mode,
            screenIdentifier: boundary.screenIdentifier,
            normalizedRect: boundary.normalizedRect.map {
                StoredNormalizedMovementRectV4(
                    x: $0.x,
                    y: $0.y,
                    width: $0.width,
                    height: $0.height
                )
            }
        )
    }

    private static func normalizedIdentifier(_ value: String?) -> String? {
        guard let value else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func normalizedDouble(
        _ value: Double,
        range: ClosedRange<Double>,
        fallback: Double,
        field: String,
        issues: inout [SettingsRecoveryIssue]
    ) -> Double {
        guard value.isFinite, range.contains(value) else {
            issues.append(.invalidField(field))
            return fallback
        }
        return value
    }
}
