import Foundation

nonisolated enum AppSettingsV16Mapper {
    static func domainSettings(
        from stored: StoredAppSettingsV16,
        idGenerator: () -> UUID = UUID.init
    ) -> (settings: AppSettings, issues: [SettingsRecoveryIssue]) {
        let legacy = StoredAppSettingsV15(
            schemaVersion: 15,
            selectedPetInstanceID: stored.selectedPetInstanceID,
            activePetInstances: stored.activePetInstances,
            behaviorProfiles: stored.behaviorProfiles.map(legacyProfile)
        )
        let mapped = AppSettingsV15Mapper.domainSettings(
            from: legacy,
            idGenerator: idGenerator
        )
        let storedByID = Dictionary(
            uniqueKeysWithValues: stored.behaviorProfiles.compactMap {
                profile in
                UUID(uuidString: profile.profileID).map { ($0, profile) }
            }
        )
        let records = mapped.settings.petBehaviorProfiles.map { record in
            guard let storedProfile = storedByID[record.profileID] else {
                return record
            }
            let base = record.profile
            return PetBehaviorProfileSettings(
                profileID: record.profileID,
                profile: BehaviorProfile(
                    petKey: base.petKey,
                    stationaryBehaviorMode:
                        base.stationaryBehaviorMode,
                    stationarySequenceID: base.stationarySequenceID,
                    randomSequenceIDs: base.randomSequenceIDs,
                    sequences: base.sequences,
                    automaticRules: base.automaticRules,
                    automaticRulePriorityOrder:
                        base.automaticRulePriorityOrder,
                    movement: domainMovement(
                        storedProfile.movement,
                        fallback: base.movement
                    ),
                    pettingMotionID: base.pettingMotionID,
                    speech: base.speech
                )
            )
        }
        return (
            AppSettings(
                selectedPetInstanceID:
                    mapped.settings.selectedPetInstanceID,
                activePetInstances: mapped.settings.activePetInstances,
                petBehaviorProfiles: records
            ),
            mapped.issues
        )
    }

    static func storedSettings(
        from settings: AppSettings
    ) throws -> StoredAppSettingsV16 {
        let legacy = try AppSettingsV15Mapper.storedSettings(from: settings)
        let profiles = Dictionary(
            uniqueKeysWithValues: settings.petBehaviorProfiles.map {
                ($0.profileID, $0.profile)
            }
        )
        return StoredAppSettingsV16(
            schemaVersion: AppSettingsLimits.schemaVersion,
            selectedPetInstanceID: legacy.selectedPetInstanceID,
            activePetInstances: legacy.activePetInstances,
            behaviorProfiles: legacy.behaviorProfiles.compactMap {
                legacyProfile in
                guard let id = UUID(uuidString: legacyProfile.profileID),
                      let profile = profiles[id] else {
                    return nil
                }
                return StoredPetProfileV16(
                    profileID: legacyProfile.profileID,
                    petKey: legacyProfile.petKey,
                    stationaryBehaviorMode:
                        legacyProfile.stationaryBehaviorMode,
                    stationarySequenceID:
                        legacyProfile.stationarySequenceID,
                    randomSequenceIDs: legacyProfile.randomSequenceIDs,
                    sequences: legacyProfile.sequences,
                    automaticRules: legacyProfile.automaticRules,
                    automaticRulePriorityOrder:
                        legacyProfile.automaticRulePriorityOrder,
                    movement: storedMovement(profile.movement),
                    pettingBehaviorID: legacyProfile.pettingBehaviorID,
                    speech: legacyProfile.speech
                )
            }
        )
    }

    private static func legacyProfile(
        _ profile: StoredPetProfileV16
    ) -> StoredPetProfileV15 {
        StoredPetProfileV15(
            profileID: profile.profileID,
            petKey: profile.petKey,
            stationaryBehaviorMode: profile.stationaryBehaviorMode,
            stationarySequenceID: profile.stationarySequenceID,
            randomSequenceIDs: profile.randomSequenceIDs,
            sequences: profile.sequences,
            automaticRules: profile.automaticRules,
            automaticRulePriorityOrder:
                profile.automaticRulePriorityOrder,
            movement: legacyMovement(profile.movement),
            pettingBehaviorID: profile.pettingBehaviorID,
            speech: profile.speech
        )
    }

    private static func legacyMovement(
        _ movement: StoredPetMovementSettingsV16
    ) -> StoredPetMovementSettingsV14 {
        StoredPetMovementSettingsV14(
            mode: movement.mode,
            cursorFollowing: movement.cursorFollowing,
            freeRoaming: legacyRoaming(movement.freeRoaming),
            cursorAvoiding: StoredCursorAvoidingMovementSettingsV14(
                idleBehavior: movement.cursorAvoiding.idleBehavior,
                detectionDistance:
                    movement.cursorAvoiding.detectionDistance,
                speed: movement.cursorAvoiding.speed,
                stopRadius: movement.cursorAvoiding.stopRadius,
                behavior: movement.cursorAvoiding.behavior,
                idleFreeRoaming: legacyRoaming(
                    movement.cursorAvoiding.idleFreeRoaming
                )
            )
        )
    }

    private static func legacyRoaming(
        _ roaming: StoredFreeRoamingMovementSettingsV16
    ) -> StoredFreeRoamingMovementSettingsV14 {
        StoredFreeRoamingMovementSettingsV14(
            speed: roaming.speed,
            stopRadius: roaming.stopRadius,
            dwellMilliseconds: roaming.dwellMilliseconds,
            randomizesDwell:
                roaming.dwellMode == FreeRoamingDwellMode.random.rawValue,
            dwellMinimumMilliseconds: roaming.dwellMinimumMilliseconds,
            prefersFrontmostWindow: roaming.prefersFrontmostWindow,
            behavior: roaming.behavior
        )
    }

    private static func domainMovement(
        _ stored: StoredPetMovementSettingsV16,
        fallback: PetMovementSettings
    ) -> PetMovementSettings {
        guard let roaming = domainRoaming(stored.freeRoaming),
              let idleRoaming = domainRoaming(
                  stored.cursorAvoiding.idleFreeRoaming
              ) else {
            return fallback
        }
        let following = CursorFollowingMovementSettings(
            speed: stored.cursorFollowing.speed,
            cursorDistance: stored.cursorFollowing.cursorDistance,
            stopRadius: stored.cursorFollowing.stopRadius,
            animation: animation(stored.cursorFollowing.behavior)
        )
        let avoiding = CursorAvoidingMovementSettings(
            idleBehavior: stored.cursorAvoiding.idleBehavior == "freeRoaming"
                ? .freeRoaming : .stationary,
            detectionDistance: stored.cursorAvoiding.detectionDistance,
            speed: stored.cursorAvoiding.speed,
            stopRadius: stored.cursorAvoiding.stopRadius,
            animation: animation(stored.cursorAvoiding.behavior),
            idleFreeRoaming: idleRoaming
        )
        let result = PetMovementSettings(
            mode: movementMode(stored.mode) ?? fallback.mode,
            cursorFollowing: following,
            freeRoaming: roaming,
            cursorAvoiding: avoiding
        )
        return result.isValid ? result : fallback
    }

    private static func domainRoaming(
        _ stored: StoredFreeRoamingMovementSettingsV16
    ) -> FreeRoamingMovementSettings? {
        guard let dwellMode = FreeRoamingDwellMode(
            rawValue: stored.dwellMode
        ) else {
            return nil
        }
        return FreeRoamingMovementSettings(
            speed: stored.speed,
            stopRadius: stored.stopRadius,
            dwellMilliseconds: stored.dwellMilliseconds,
            dwellMinimumMilliseconds: stored.dwellMinimumMilliseconds,
            prefersFrontmostWindow: stored.prefersFrontmostWindow,
            animation: animation(stored.behavior),
            dwellMode: dwellMode
        )
    }

    private static func storedMovement(
        _ movement: PetMovementSettings
    ) -> StoredPetMovementSettingsV16 {
        StoredPetMovementSettingsV16(
            mode: storedMode(movement.mode),
            cursorFollowing: StoredCursorFollowingMovementSettingsV14(
                speed: movement.cursorFollowing.speed,
                cursorDistance: movement.cursorFollowing.cursorDistance,
                stopRadius: movement.cursorFollowing.stopRadius,
                behavior: behavior(movement.cursorFollowing.animation)
            ),
            freeRoaming: storedRoaming(movement.freeRoaming),
            cursorAvoiding: StoredCursorAvoidingMovementSettingsV16(
                idleBehavior: movement.cursorAvoiding.idleBehavior
                    == .freeRoaming ? "freeRoaming" : "stationary",
                detectionDistance:
                    movement.cursorAvoiding.detectionDistance,
                speed: movement.cursorAvoiding.speed,
                stopRadius: movement.cursorAvoiding.stopRadius,
                behavior: behavior(movement.cursorAvoiding.animation),
                idleFreeRoaming: storedRoaming(
                    movement.cursorAvoiding.idleFreeRoaming
                )
            )
        )
    }

    private static func storedRoaming(
        _ roaming: FreeRoamingMovementSettings
    ) -> StoredFreeRoamingMovementSettingsV16 {
        StoredFreeRoamingMovementSettingsV16(
            speed: roaming.speed,
            stopRadius: roaming.stopRadius,
            dwellMode: roaming.dwellMode.rawValue,
            dwellMilliseconds: roaming.dwellMilliseconds,
            dwellMinimumMilliseconds: roaming.dwellMinimumMilliseconds,
            prefersFrontmostWindow: roaming.prefersFrontmostWindow,
            behavior: behavior(roaming.animation)
        )
    }

    private static func animation(
        _ stored: StoredMovementBehaviorSettingsV12
    ) -> MovementAnimationSettings {
        let directions = stored.directionBehaviorIDs
        return MovementAnimationSettings(
            fallbackMotionID: stored.fallbackBehaviorID,
            usesDirectionalMotions: stored.usesDirectionalBehaviors,
            usesDiagonalMotions: stored.usesDiagonalBehaviors,
            directionMotionIDs: DirectionalMotionIDs(
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

    private static func behavior(
        _ animation: MovementAnimationSettings
    ) -> StoredMovementBehaviorSettingsV12 {
        let directions = animation.directionMotionIDs
        return StoredMovementBehaviorSettingsV12(
            fallbackBehaviorID: animation.fallbackMotionID,
            usesDirectionalBehaviors: animation.usesDirectionalMotions,
            usesDiagonalBehaviors: animation.usesDiagonalMotions,
            directionBehaviorIDs: StoredDirectionalBehaviorIDsV12(
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

    private static func movementMode(_ value: String) -> PetMovementMode? {
        switch value {
        case "fixed": .fixed
        case "cursorFollowing": .cursorFollowing
        case "freeRoaming": .freeRoaming
        case "cursorAvoiding": .cursorAvoiding
        default: nil
        }
    }

    private static func storedMode(_ mode: PetMovementMode) -> String {
        switch mode {
        case .fixed: "fixed"
        case .cursorFollowing: "cursorFollowing"
        case .freeRoaming: "freeRoaming"
        case .cursorAvoiding: "cursorAvoiding"
        }
    }
}
