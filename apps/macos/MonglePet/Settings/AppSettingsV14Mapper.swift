import Foundation

nonisolated enum AppSettingsV14Mapper {
    static func domainSettings(
        from stored: StoredAppSettingsV14,
        idGenerator: () -> UUID = UUID.init
    ) -> (settings: AppSettings, issues: [SettingsRecoveryIssue]) {
        let legacy = StoredAppSettingsV13(
            schemaVersion: 13,
            selectedPetInstanceID: stored.selectedPetInstanceID,
            activePetInstances: stored.activePetInstances,
            behaviorProfiles: stored.behaviorProfiles.map(legacyProfile)
        )
        let mapped = AppSettingsV13Mapper.domainSettings(
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
            let movement = domainMovement(
                storedProfile.movement,
                fallback: base.movement
            )
            return PetBehaviorProfileSettings(
                profileID: record.profileID,
                profile: BehaviorProfile(
                    petKey: base.petKey,
                    mode: base.mode,
                    manualSequenceID: base.manualSequenceID,
                    randomSequenceIDs: base.randomSequenceIDs,
                    sequences: base.sequences,
                    automaticRules: base.automaticRules,
                    automaticRulePriorityOrder:
                        base.automaticRulePriorityOrder,
                    movement: movement,
                    pettingMotionID: base.pettingMotionID,
                    speech: base.speech
                )
            )
        }
        return (
            AppSettings(
                selectedPetInstanceID: mapped.settings.selectedPetInstanceID,
                activePetInstances: mapped.settings.activePetInstances,
                petBehaviorProfiles: records
            ),
            mapped.issues
        )
    }

    static func storedSettings(
        from settings: AppSettings
    ) throws -> StoredAppSettingsV14 {
        let legacy = try AppSettingsV13Mapper.storedSettings(from: settings)
        let profiles = Dictionary(
            uniqueKeysWithValues: settings.petBehaviorProfiles.map {
                ($0.profileID, $0.profile)
            }
        )
        return StoredAppSettingsV14(
            schemaVersion: 14,
            selectedPetInstanceID: legacy.selectedPetInstanceID,
            activePetInstances: legacy.activePetInstances,
            behaviorProfiles: legacy.behaviorProfiles.compactMap {
                legacyProfile in
                guard let id = UUID(uuidString: legacyProfile.profileID),
                      let profile = profiles[id] else {
                    return nil
                }
                return StoredPetProfileV14(
                    profileID: legacyProfile.profileID,
                    petKey: legacyProfile.petKey,
                    mode: legacyProfile.mode,
                    manualSequenceID: legacyProfile.manualSequenceID,
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
        _ profile: StoredPetProfileV14
    ) -> StoredPetProfileV13 {
        let following = profile.movement.cursorFollowing
        let roaming = profile.movement.freeRoaming
        let avoiding = profile.movement.cursorAvoiding
        return StoredPetProfileV13(
            profileID: profile.profileID,
            petKey: profile.petKey,
            mode: profile.mode,
            manualSequenceID: profile.manualSequenceID,
            randomSequenceIDs: profile.randomSequenceIDs,
            sequences: profile.sequences,
            automaticRules: profile.automaticRules,
            automaticRulePriorityOrder:
                profile.automaticRulePriorityOrder,
            movement: StoredPetMovementSettingsV13(
                mode: profile.movement.mode,
                speed: roaming.speed,
                cursorDistance: following.cursorDistance,
                stopRadius: roaming.stopRadius,
                freeRoamingDwellMilliseconds: roaming.dwellMilliseconds,
                randomizesFreeRoamingDwell: roaming.randomizesDwell,
                freeRoamingDwellMinimumMilliseconds:
                    roaming.dwellMinimumMilliseconds,
                prefersFrontmostWindow: roaming.prefersFrontmostWindow,
                cursorFollowingBehavior: following.behavior,
                freeRoamingBehavior: roaming.behavior,
                cursorAvoidingIdleBehavior: avoiding.idleBehavior,
                cursorAvoidingDetectionDistance:
                    avoiding.detectionDistance,
                cursorAvoidingSpeed: avoiding.speed,
                cursorAvoidingBehavior: avoiding.behavior
            ),
            pettingBehaviorID: profile.pettingBehaviorID,
            speech: profile.speech
        )
    }

    private static func domainMovement(
        _ stored: StoredPetMovementSettingsV14,
        fallback: PetMovementSettings
    ) -> PetMovementSettings {
        let following = CursorFollowingMovementSettings(
            speed: stored.cursorFollowing.speed,
            cursorDistance: stored.cursorFollowing.cursorDistance,
            stopRadius: stored.cursorFollowing.stopRadius,
            animation: animation(stored.cursorFollowing.behavior)
        )
        let roaming = domainRoaming(stored.freeRoaming)
        let avoiding = CursorAvoidingMovementSettings(
            idleBehavior: idleBehavior(stored.cursorAvoiding.idleBehavior),
            detectionDistance: stored.cursorAvoiding.detectionDistance,
            speed: stored.cursorAvoiding.speed,
            stopRadius: stored.cursorAvoiding.stopRadius,
            animation: animation(stored.cursorAvoiding.behavior),
            idleFreeRoaming: domainRoaming(
                stored.cursorAvoiding.idleFreeRoaming
            )
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
        _ stored: StoredFreeRoamingMovementSettingsV14
    ) -> FreeRoamingMovementSettings {
        FreeRoamingMovementSettings(
            speed: stored.speed,
            stopRadius: stored.stopRadius,
            dwellMilliseconds: stored.dwellMilliseconds,
            randomizesDwell: stored.randomizesDwell,
            dwellMinimumMilliseconds: stored.dwellMinimumMilliseconds,
            prefersFrontmostWindow: stored.prefersFrontmostWindow,
            animation: animation(stored.behavior)
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

    private static func storedMovement(
        _ movement: PetMovementSettings
    ) -> StoredPetMovementSettingsV14 {
        StoredPetMovementSettingsV14(
            mode: storedMode(movement.mode),
            cursorFollowing: StoredCursorFollowingMovementSettingsV14(
                speed: movement.cursorFollowing.speed,
                cursorDistance: movement.cursorFollowing.cursorDistance,
                stopRadius: movement.cursorFollowing.stopRadius,
                behavior: behavior(movement.cursorFollowing.animation)
            ),
            freeRoaming: storedRoaming(movement.freeRoaming),
            cursorAvoiding: StoredCursorAvoidingMovementSettingsV14(
                idleBehavior: storedIdleBehavior(
                    movement.cursorAvoiding.idleBehavior
                ),
                detectionDistance:
                    movement.cursorAvoiding.detectionDistance,
                speed: movement.cursorAvoiding.speed,
                stopRadius: movement.cursorAvoiding.stopRadius,
                behavior: behavior(movement.cursorAvoiding.animation),
                idleFreeRoaming:
                    storedRoaming(movement.cursorAvoiding.idleFreeRoaming)
            )
        )
    }

    private static func storedRoaming(
        _ roaming: FreeRoamingMovementSettings
    ) -> StoredFreeRoamingMovementSettingsV14 {
        StoredFreeRoamingMovementSettingsV14(
            speed: roaming.speed,
            stopRadius: roaming.stopRadius,
            dwellMilliseconds: roaming.dwellMilliseconds,
            randomizesDwell: roaming.randomizesDwell,
            dwellMinimumMilliseconds: roaming.dwellMinimumMilliseconds,
            prefersFrontmostWindow: roaming.prefersFrontmostWindow,
            behavior: behavior(roaming.animation)
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

    private static func idleBehavior(
        _ value: String
    ) -> CursorAvoidingIdleBehavior {
        value == "freeRoaming" ? .freeRoaming : .stationary
    }

    private static func storedIdleBehavior(
        _ behavior: CursorAvoidingIdleBehavior
    ) -> String {
        behavior == .freeRoaming ? "freeRoaming" : "stationary"
    }
}
