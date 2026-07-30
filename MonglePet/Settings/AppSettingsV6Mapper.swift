import Foundation

nonisolated enum AppSettingsV6Mapper {
    static func domainSettings(
        from stored: StoredAppSettingsV6
    ) -> (settings: AppSettings, issues: [SettingsRecoveryIssue]) {
        let storedV5 = StoredAppSettingsV5(
            schemaVersion: 5,
            selectedPetInstallationID: stored.selectedPetInstallationID,
            lastUserPresentation: stored.lastUserPresentation,
            overlay: stored.overlay,
            behaviorProfiles: stored.behaviorProfiles.map { profile in
                let movement = profile.movement
                return StoredPetProfileV5(
                    petKey: profile.petKey,
                    mode: profile.mode,
                    manualSequenceID: profile.manualSequenceID,
                    sequences: profile.sequences,
                    automaticRules: profile.automaticRules,
                    movement: StoredPetMovementSettingsV5(
                        mode: movement.mode == "cursorAvoiding"
                            ? "fixed"
                            : movement.mode,
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
                            movement.freeRoamingAnimation
                    ),
                    pettingMotionID: profile.pettingMotionID
                )
            }
        )
        let mappedV5 = AppSettingsV5Mapper.domainSettings(from: storedV5)
        var issues = mappedV5.issues
        var movementByKey:
            [PetBehaviorKey: (Int, StoredPetMovementSettingsV6)] = [:]
        for (index, profile) in stored.behaviorProfiles.enumerated() {
            guard
                let key = domainPetKey(from: profile.petKey),
                movementByKey[key] == nil
            else {
                continue
            }
            movementByKey[key] = (index, profile.movement)
        }

        let profiles = mappedV5.settings.behaviorProfiles.map { profile in
            guard let (index, storedMovement) =
                movementByKey[profile.petKey] else {
                return profile
            }
            let path = "behaviorProfiles.\(index).movement"
            let base = profile.movement
            return BehaviorProfile(
                petKey: profile.petKey,
                mode: profile.mode,
                manualSequenceID: profile.manualSequenceID,
                sequences: profile.sequences,
                automaticRules: profile.automaticRules,
                movement: PetMovementSettings(
                    mode: normalizedMode(
                        storedMovement.mode,
                        field: "\(path).mode",
                        issues: &issues
                    ),
                    speed: base.speed,
                    cursorDistance: base.cursorDistance,
                    stopRadius: base.stopRadius,
                    freeRoamingDwellMilliseconds:
                        base.freeRoamingDwellMilliseconds,
                    prefersFrontmostWindow:
                        base.prefersFrontmostWindow,
                    cursorFollowingAnimation:
                        base.cursorFollowingAnimation,
                    freeRoamingAnimation: base.freeRoamingAnimation,
                    cursorAvoidingIdleBehavior:
                        normalizedAvoidingIdleBehavior(
                            storedMovement.cursorAvoidingIdleBehavior,
                            field:
                                "\(path).cursorAvoidingIdleBehavior",
                            issues: &issues
                        ),
                    cursorAvoidingDetectionDistance: normalizedDouble(
                        storedMovement.cursorAvoidingDetectionDistance,
                        range:
                            AppSettingsLimits
                                .minimumCursorAvoidingDetectionDistance
                            ... AppSettingsLimits
                                .maximumCursorAvoidingDetectionDistance,
                        fallback:
                            AppSettingsLimits
                                .defaultCursorAvoidingDetectionDistance,
                        field:
                            "\(path).cursorAvoidingDetectionDistance",
                        issues: &issues
                    ),
                    cursorAvoidingSpeed: normalizedDouble(
                        storedMovement.cursorAvoidingSpeed,
                        range: AppSettingsLimits.minimumMovementSpeed
                            ... AppSettingsLimits.maximumMovementSpeed,
                        fallback:
                            AppSettingsLimits.defaultCursorAvoidingSpeed,
                        field: "\(path).cursorAvoidingSpeed",
                        issues: &issues
                    ),
                    cursorAvoidingAnimation: normalizedAnimation(
                        storedMovement.cursorAvoidingAnimation,
                        field: "\(path).cursorAvoidingAnimation",
                        issues: &issues
                    )
                ),
                pettingMotionID: profile.pettingMotionID
            )
        }
        return (
            AppSettings(
                selectedPetInstallationID:
                    mappedV5.settings.selectedPetInstallationID,
                lastUserPresentation:
                    mappedV5.settings.lastUserPresentation,
                overlay: mappedV5.settings.overlay,
                behaviorProfiles: profiles
            ),
            issues
        )
    }

    static func storedSettings(
        from settings: AppSettings
    ) throws -> StoredAppSettingsV6 {
        let storedV5 = try AppSettingsV5Mapper.storedSettings(from: settings)
        let profiles = try zip(
            storedV5.behaviorProfiles,
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
            return StoredPetProfileV6(
                petKey: storedProfile.petKey,
                mode: storedProfile.mode,
                manualSequenceID: storedProfile.manualSequenceID,
                sequences: storedProfile.sequences,
                automaticRules: storedProfile.automaticRules,
                movement: storedMovement(profile.movement),
                pettingMotionID: storedProfile.pettingMotionID
            )
        }
        return StoredAppSettingsV6(
            schemaVersion: AppSettingsLimits.schemaVersion,
            selectedPetInstallationID:
                storedV5.selectedPetInstallationID,
            lastUserPresentation: storedV5.lastUserPresentation,
            overlay: storedV5.overlay,
            behaviorProfiles: profiles
        )
    }

    private static func storedMovement(
        _ movement: PetMovementSettings
    ) -> StoredPetMovementSettingsV6 {
        let mode: String = switch movement.mode {
        case .fixed: "fixed"
        case .cursorFollowing: "cursorFollowing"
        case .freeRoaming: "freeRoaming"
        case .cursorAvoiding: "cursorAvoiding"
        }
        return StoredPetMovementSettingsV6(
            mode: mode,
            speed: movement.speed,
            cursorDistance: movement.cursorDistance,
            stopRadius: movement.stopRadius,
            freeRoamingDwellMilliseconds:
                movement.freeRoamingDwellMilliseconds,
            prefersFrontmostWindow: movement.prefersFrontmostWindow,
            cursorFollowingAnimation: storedAnimation(
                movement.cursorFollowingAnimation
            ),
            freeRoamingAnimation: storedAnimation(
                movement.freeRoamingAnimation
            ),
            cursorAvoidingIdleBehavior:
                movement.cursorAvoidingIdleBehavior == .stationary
                ? "stationary"
                : "freeRoaming",
            cursorAvoidingDetectionDistance:
                movement.cursorAvoidingDetectionDistance,
            cursorAvoidingSpeed: movement.cursorAvoidingSpeed,
            cursorAvoidingAnimation: storedAnimation(
                movement.cursorAvoidingAnimation
            )
        )
    }

    private static func normalizedMode(
        _ value: String,
        field: String,
        issues: inout [SettingsRecoveryIssue]
    ) -> PetMovementMode {
        switch value {
        case "fixed": .fixed
        case "cursorFollowing": .cursorFollowing
        case "freeRoaming": .freeRoaming
        case "cursorAvoiding": .cursorAvoiding
        default:
            recover(.fixed, field: field, issues: &issues)
        }
    }

    private static func normalizedAvoidingIdleBehavior(
        _ value: String,
        field: String,
        issues: inout [SettingsRecoveryIssue]
    ) -> CursorAvoidingIdleBehavior {
        switch value {
        case "stationary": .stationary
        case "freeRoaming": .freeRoaming
        default:
            recover(.stationary, field: field, issues: &issues)
        }
    }

    private static func normalizedDouble(
        _ value: Double,
        range: ClosedRange<Double>,
        fallback: Double,
        field: String,
        issues: inout [SettingsRecoveryIssue]
    ) -> Double {
        guard value.isFinite, range.contains(value) else {
            return recover(fallback, field: field, issues: &issues)
        }
        return value
    }

    private static func normalizedAnimation(
        _ stored: StoredMovementAnimationSettingsV5,
        field: String,
        issues: inout [SettingsRecoveryIssue]
    ) -> MovementAnimationSettings {
        var usesDiagonals = stored.usesDiagonalMotions
        if usesDiagonals, !stored.usesDirectionalMotions {
            usesDiagonals = false
            issues.append(.invalidField("\(field).usesDiagonalMotions"))
        }
        return MovementAnimationSettings(
            fallbackMotionID: normalizedMotionID(
                stored.fallbackMotionID,
                field: "\(field).fallbackMotionID",
                issues: &issues
            ),
            usesDirectionalMotions: stored.usesDirectionalMotions,
            usesDiagonalMotions: usesDiagonals,
            directionMotionIDs: DirectionalMotionIDs(
                left: normalizedMotionID(
                    stored.directionMotionIDs.left,
                    field: "\(field).directionMotionIDs.left",
                    issues: &issues
                ),
                right: normalizedMotionID(
                    stored.directionMotionIDs.right,
                    field: "\(field).directionMotionIDs.right",
                    issues: &issues
                ),
                up: normalizedMotionID(
                    stored.directionMotionIDs.up,
                    field: "\(field).directionMotionIDs.up",
                    issues: &issues
                ),
                down: normalizedMotionID(
                    stored.directionMotionIDs.down,
                    field: "\(field).directionMotionIDs.down",
                    issues: &issues
                ),
                upLeft: normalizedMotionID(
                    stored.directionMotionIDs.upLeft,
                    field: "\(field).directionMotionIDs.upLeft",
                    issues: &issues
                ),
                upRight: normalizedMotionID(
                    stored.directionMotionIDs.upRight,
                    field: "\(field).directionMotionIDs.upRight",
                    issues: &issues
                ),
                downLeft: normalizedMotionID(
                    stored.directionMotionIDs.downLeft,
                    field: "\(field).directionMotionIDs.downLeft",
                    issues: &issues
                ),
                downRight: normalizedMotionID(
                    stored.directionMotionIDs.downRight,
                    field: "\(field).directionMotionIDs.downRight",
                    issues: &issues
                )
            )
        )
    }

    private static func normalizedMotionID(
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

    private static func storedAnimation(
        _ animation: MovementAnimationSettings
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

    private static func recover<T>(
        _ fallback: T,
        field: String,
        issues: inout [SettingsRecoveryIssue]
    ) -> T {
        issues.append(.invalidField(field))
        return fallback
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
