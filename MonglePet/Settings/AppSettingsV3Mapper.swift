import Foundation

nonisolated enum AppSettingsV3Mapper {
    static func domainSettings(
        from stored: StoredAppSettingsV3
    ) -> (settings: AppSettings, issues: [SettingsRecoveryIssue]) {
        let v2Settings = StoredAppSettingsV2(
            schemaVersion: 2,
            selectedPetInstallationID: stored.selectedPetInstallationID,
            lastUserPresentation: stored.lastUserPresentation,
            overlay: stored.overlay,
            behaviorProfiles: stored.behaviorProfiles.map { profile in
                StoredBehaviorProfileV2(
                    petKey: profile.petKey,
                    mode: profile.mode,
                    manualSequenceID: profile.manualSequenceID,
                    sequences: profile.sequences,
                    automaticRules: profile.automaticRules
                )
            }
        )
        let mappedV2 = AppSettingsV2Mapper.domainSettings(from: v2Settings)
        var issues = mappedV2.issues
        var storedMovementByKey: [PetBehaviorKey: (Int, StoredPetMovementSettingsV3)] = [:]
        for (index, profile) in stored.behaviorProfiles.enumerated() {
            guard
                let key = domainPetKey(from: profile.petKey),
                storedMovementByKey[key] == nil
            else {
                continue
            }
            storedMovementByKey[key] = (index, profile.movement)
        }

        let profiles = mappedV2.settings.behaviorProfiles.map { profile in
            guard let (index, storedMovement) = storedMovementByKey[profile.petKey] else {
                return profile
            }
            return BehaviorProfile(
                petKey: profile.petKey,
                mode: profile.mode,
                manualSequenceID: profile.manualSequenceID,
                sequences: profile.sequences,
                automaticRules: profile.automaticRules,
                movement: normalizedMovement(
                    from: storedMovement,
                    fieldPath: "behaviorProfiles.\(index).movement",
                    issues: &issues
                ),
                pettingMotionID: normalizedOptionalMotionID(
                    stored.behaviorProfiles[index].pettingMotionID,
                    field: "behaviorProfiles.\(index).pettingMotionID",
                    issues: &issues
                )
            )
        }

        return (
            AppSettings(
                selectedPetInstallationID: mappedV2.settings.selectedPetInstallationID,
                lastUserPresentation: mappedV2.settings.lastUserPresentation,
                overlay: mappedV2.settings.overlay,
                behaviorProfiles: profiles
            ),
            issues
        )
    }

    static func storedSettings(from settings: AppSettings) throws -> StoredAppSettingsV3 {
        let storedV2 = try AppSettingsV2Mapper.storedSettings(from: settings)
        let profiles = try zip(storedV2.behaviorProfiles, settings.behaviorProfiles)
            .enumerated()
            .map { index, pair in
                let (storedProfile, profile) = pair
                guard profile.movement.isValid else {
                    throw AppSettingsMappingError.invalidSettings(
                        "behaviorProfiles.\(index).movement"
                    )
                }
                guard isValidOptionalMotionID(profile.pettingMotionID) else {
                    throw AppSettingsMappingError.invalidSettings(
                        "behaviorProfiles.\(index).pettingMotionID"
                    )
                }
                return StoredPetProfileV3(
                    petKey: storedProfile.petKey,
                    mode: storedProfile.mode,
                    manualSequenceID: storedProfile.manualSequenceID,
                    sequences: storedProfile.sequences,
                    automaticRules: storedProfile.automaticRules,
                    movement: storedMovement(from: profile.movement),
                    pettingMotionID: profile.pettingMotionID
                )
            }

        return StoredAppSettingsV3(
            schemaVersion: AppSettingsLimits.schemaVersion,
            selectedPetInstallationID: storedV2.selectedPetInstallationID,
            lastUserPresentation: storedV2.lastUserPresentation,
            overlay: storedV2.overlay,
            behaviorProfiles: profiles
        )
    }

    private static func normalizedMovement(
        from stored: StoredPetMovementSettingsV3,
        fieldPath: String,
        issues: inout [SettingsRecoveryIssue]
    ) -> PetMovementSettings {
        let mode: PetMovementMode
        switch stored.mode {
        case "fixed":
            mode = .fixed
        case "cursorFollowing":
            mode = .cursorFollowing
        case "freeRoaming":
            mode = .freeRoaming
        default:
            mode = .fixed
            issues.append(.invalidField("\(fieldPath).mode"))
        }

        return PetMovementSettings(
            mode: mode,
            speed: normalizedDouble(
                stored.speed,
                range: AppSettingsLimits.minimumMovementSpeed
                    ... AppSettingsLimits.maximumMovementSpeed,
                fallback: AppSettingsLimits.defaultMovementSpeed,
                field: "\(fieldPath).speed",
                issues: &issues
            ),
            cursorDistance: normalizedDouble(
                stored.cursorDistance,
                range: AppSettingsLimits.minimumCursorDistance
                    ... AppSettingsLimits.maximumCursorDistance,
                fallback: AppSettingsLimits.defaultCursorDistance,
                field: "\(fieldPath).cursorDistance",
                issues: &issues
            ),
            stopRadius: normalizedDouble(
                stored.stopRadius,
                range: AppSettingsLimits.minimumMovementStopRadius
                    ... AppSettingsLimits.maximumMovementStopRadius,
                fallback: AppSettingsLimits.defaultMovementStopRadius,
                field: "\(fieldPath).stopRadius",
                issues: &issues
            ),
            freeRoamingDwellMilliseconds: normalizedInteger(
                stored.freeRoamingDwellMilliseconds,
                range: AppSettingsLimits.minimumFreeRoamingDwellMilliseconds
                    ... AppSettingsLimits.maximumFreeRoamingDwellMilliseconds,
                fallback: AppSettingsLimits.defaultFreeRoamingDwellMilliseconds,
                field: "\(fieldPath).freeRoamingDwellMilliseconds",
                issues: &issues
            ),
            prefersFrontmostWindow: stored.prefersFrontmostWindow,
            cursorFollowingMotionID: normalizedOptionalMotionID(
                stored.cursorFollowingMotionID,
                field: "\(fieldPath).cursorFollowingMotionID",
                issues: &issues
            ),
            freeRoamingMotionID: normalizedOptionalMotionID(
                stored.freeRoamingMotionID,
                field: "\(fieldPath).freeRoamingMotionID",
                issues: &issues
            )
        )
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

    private static func normalizedInteger(
        _ value: Int64,
        range: ClosedRange<Int64>,
        fallback: Int64,
        field: String,
        issues: inout [SettingsRecoveryIssue]
    ) -> Int64 {
        guard range.contains(value) else {
            issues.append(.invalidField(field))
            return fallback
        }
        return value
    }

    private static func normalizedOptionalMotionID(
        _ value: String?,
        field: String,
        issues: inout [SettingsRecoveryIssue]
    ) -> String? {
        guard let value else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed == value else {
            issues.append(.invalidField(field))
            return nil
        }
        return value
    }

    private static func isValidOptionalMotionID(_ value: String?) -> Bool {
        guard let value else {
            return true
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed == value
    }

    private static func storedMovement(
        from movement: PetMovementSettings
    ) -> StoredPetMovementSettingsV3 {
        let mode: String = switch movement.mode {
        case .fixed:
            "fixed"
        case .cursorFollowing:
            "cursorFollowing"
        case .freeRoaming:
            "freeRoaming"
        }
        return StoredPetMovementSettingsV3(
            mode: mode,
            speed: movement.speed,
            cursorDistance: movement.cursorDistance,
            stopRadius: movement.stopRadius,
            freeRoamingDwellMilliseconds: movement.freeRoamingDwellMilliseconds,
            prefersFrontmostWindow: movement.prefersFrontmostWindow,
            cursorFollowingMotionID: movement.cursorFollowingMotionID,
            freeRoamingMotionID: movement.freeRoamingMotionID
        )
    }

    private static func domainPetKey(
        from stored: StoredPetBehaviorKeyV2
    ) -> PetBehaviorKey? {
        switch stored {
        case .builtIn:
            .builtIn
        case let .installed(installationID):
            UUID(uuidString: installationID).map(PetBehaviorKey.installed)
        }
    }
}
