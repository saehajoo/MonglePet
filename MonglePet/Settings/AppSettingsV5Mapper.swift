import Foundation

nonisolated enum AppSettingsV5Mapper {
    static func domainSettings(
        from stored: StoredAppSettingsV5
    ) -> (settings: AppSettings, issues: [SettingsRecoveryIssue]) {
        let storedV4 = StoredAppSettingsV4(
            schemaVersion: 4,
            selectedPetInstallationID: stored.selectedPetInstallationID,
            lastUserPresentation: stored.lastUserPresentation,
            overlay: stored.overlay,
            behaviorProfiles: stored.behaviorProfiles.map { profile in
                StoredPetProfileV3(
                    petKey: profile.petKey,
                    mode: profile.mode,
                    manualSequenceID: profile.manualSequenceID,
                    sequences: profile.sequences,
                    automaticRules: profile.automaticRules,
                    movement: legacyMovement(from: profile.movement),
                    pettingMotionID: profile.pettingMotionID
                )
            }
        )
        let mappedV4 = AppSettingsV4Mapper.domainSettings(from: storedV4)
        var issues = mappedV4.issues
        var storedMovementByKey:
            [PetBehaviorKey: (Int, StoredPetMovementSettingsV5)] = [:]
        for (index, profile) in stored.behaviorProfiles.enumerated() {
            guard
                let key = domainPetKey(from: profile.petKey),
                storedMovementByKey[key] == nil
            else {
                continue
            }
            storedMovementByKey[key] = (index, profile.movement)
        }

        let profiles = mappedV4.settings.behaviorProfiles.map { profile in
            guard let (index, storedMovement) =
                storedMovementByKey[profile.petKey] else {
                return profile
            }
            let baseMovement = profile.movement
            return BehaviorProfile(
                petKey: profile.petKey,
                mode: profile.mode,
                manualSequenceID: profile.manualSequenceID,
                sequences: profile.sequences,
                automaticRules: profile.automaticRules,
                movement: PetMovementSettings(
                    mode: baseMovement.mode,
                    speed: baseMovement.speed,
                    cursorDistance: baseMovement.cursorDistance,
                    stopRadius: baseMovement.stopRadius,
                    freeRoamingDwellMilliseconds:
                        baseMovement.freeRoamingDwellMilliseconds,
                    prefersFrontmostWindow:
                        baseMovement.prefersFrontmostWindow,
                    cursorFollowingAnimation: normalizedAnimation(
                        from: storedMovement.cursorFollowingAnimation,
                        fieldPath:
                            "behaviorProfiles.\(index).movement.cursorFollowingAnimation",
                        issues: &issues
                    ),
                    freeRoamingAnimation: normalizedAnimation(
                        from: storedMovement.freeRoamingAnimation,
                        fieldPath:
                            "behaviorProfiles.\(index).movement.freeRoamingAnimation",
                        issues: &issues
                    )
                ),
                pettingMotionID: profile.pettingMotionID
            )
        }

        return (
            AppSettings(
                selectedPetInstallationID:
                    mappedV4.settings.selectedPetInstallationID,
                lastUserPresentation:
                    mappedV4.settings.lastUserPresentation,
                overlay: mappedV4.settings.overlay,
                behaviorProfiles: profiles
            ),
            issues
        )
    }

    static func storedSettings(
        from settings: AppSettings
    ) throws -> StoredAppSettingsV5 {
        let storedV4 = try AppSettingsV4Mapper.storedSettings(from: settings)
        let profiles = try zip(
            storedV4.behaviorProfiles,
            settings.behaviorProfiles
        )
        .enumerated()
        .map { index, pair in
            let (storedProfile, profile) = pair
            guard profile.movement.isValid else {
                throw AppSettingsMappingError.invalidSettings(
                    "behaviorProfiles.\(index).movement"
                )
            }
            return StoredPetProfileV5(
                petKey: storedProfile.petKey,
                mode: storedProfile.mode,
                manualSequenceID: storedProfile.manualSequenceID,
                sequences: storedProfile.sequences,
                automaticRules: storedProfile.automaticRules,
                movement: storedMovement(from: profile.movement),
                pettingMotionID: storedProfile.pettingMotionID
            )
        }

        return StoredAppSettingsV5(
            schemaVersion: AppSettingsLimits.schemaVersion,
            selectedPetInstallationID: storedV4.selectedPetInstallationID,
            lastUserPresentation: storedV4.lastUserPresentation,
            overlay: storedV4.overlay,
            behaviorProfiles: profiles
        )
    }

    private static func normalizedAnimation(
        from stored: StoredMovementAnimationSettingsV5,
        fieldPath: String,
        issues: inout [SettingsRecoveryIssue]
    ) -> MovementAnimationSettings {
        var usesDiagonalMotions = stored.usesDiagonalMotions
        if usesDiagonalMotions, !stored.usesDirectionalMotions {
            usesDiagonalMotions = false
            issues.append(
                .invalidField("\(fieldPath).usesDiagonalMotions")
            )
        }
        return MovementAnimationSettings(
            fallbackMotionID: normalizedOptionalMotionID(
                stored.fallbackMotionID,
                field: "\(fieldPath).fallbackMotionID",
                issues: &issues
            ),
            usesDirectionalMotions: stored.usesDirectionalMotions,
            usesDiagonalMotions: usesDiagonalMotions,
            directionMotionIDs: DirectionalMotionIDs(
                left: normalizedOptionalMotionID(
                    stored.directionMotionIDs.left,
                    field: "\(fieldPath).directionMotionIDs.left",
                    issues: &issues
                ),
                right: normalizedOptionalMotionID(
                    stored.directionMotionIDs.right,
                    field: "\(fieldPath).directionMotionIDs.right",
                    issues: &issues
                ),
                up: normalizedOptionalMotionID(
                    stored.directionMotionIDs.up,
                    field: "\(fieldPath).directionMotionIDs.up",
                    issues: &issues
                ),
                down: normalizedOptionalMotionID(
                    stored.directionMotionIDs.down,
                    field: "\(fieldPath).directionMotionIDs.down",
                    issues: &issues
                ),
                upLeft: normalizedOptionalMotionID(
                    stored.directionMotionIDs.upLeft,
                    field: "\(fieldPath).directionMotionIDs.upLeft",
                    issues: &issues
                ),
                upRight: normalizedOptionalMotionID(
                    stored.directionMotionIDs.upRight,
                    field: "\(fieldPath).directionMotionIDs.upRight",
                    issues: &issues
                ),
                downLeft: normalizedOptionalMotionID(
                    stored.directionMotionIDs.downLeft,
                    field: "\(fieldPath).directionMotionIDs.downLeft",
                    issues: &issues
                ),
                downRight: normalizedOptionalMotionID(
                    stored.directionMotionIDs.downRight,
                    field: "\(fieldPath).directionMotionIDs.downRight",
                    issues: &issues
                )
            )
        )
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

    private static func legacyMovement(
        from movement: StoredPetMovementSettingsV5
    ) -> StoredPetMovementSettingsV3 {
        StoredPetMovementSettingsV3(
            mode: movement.mode,
            speed: movement.speed,
            cursorDistance: movement.cursorDistance,
            stopRadius: movement.stopRadius,
            freeRoamingDwellMilliseconds:
                movement.freeRoamingDwellMilliseconds,
            prefersFrontmostWindow: movement.prefersFrontmostWindow,
            cursorFollowingMotionID:
                movement.cursorFollowingAnimation.fallbackMotionID,
            freeRoamingMotionID:
                movement.freeRoamingAnimation.fallbackMotionID
        )
    }

    private static func storedMovement(
        from movement: PetMovementSettings
    ) -> StoredPetMovementSettingsV5 {
        let mode: String = switch movement.mode {
        case .fixed:
            "fixed"
        case .cursorFollowing:
            "cursorFollowing"
        case .freeRoaming:
            "freeRoaming"
        }
        return StoredPetMovementSettingsV5(
            mode: mode,
            speed: movement.speed,
            cursorDistance: movement.cursorDistance,
            stopRadius: movement.stopRadius,
            freeRoamingDwellMilliseconds:
                movement.freeRoamingDwellMilliseconds,
            prefersFrontmostWindow: movement.prefersFrontmostWindow,
            cursorFollowingAnimation: storedAnimation(
                from: movement.cursorFollowingAnimation
            ),
            freeRoamingAnimation: storedAnimation(
                from: movement.freeRoamingAnimation
            )
        )
    }

    private static func storedAnimation(
        from animation: MovementAnimationSettings
    ) -> StoredMovementAnimationSettingsV5 {
        let directions = animation.directionMotionIDs
        return StoredMovementAnimationSettingsV5(
            fallbackMotionID: animation.fallbackMotionID,
            usesDirectionalMotions: animation.usesDirectionalMotions,
            usesDiagonalMotions: animation.usesDiagonalMotions,
            directionMotionIDs: StoredDirectionalMotionIDsV5(
                left: directions.left,
                right: directions.right,
                up: directions.up,
                down: directions.down,
                upLeft: directions.upLeft,
                upRight: directions.upRight,
                downLeft: directions.downLeft,
                downRight: directions.downRight
            )
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
