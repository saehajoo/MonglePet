import Foundation

nonisolated enum AppSettingsV12Mapper {
    static func domainSettings(
        from stored: StoredAppSettingsV12,
        idGenerator: () -> UUID = UUID.init
    ) -> (settings: AppSettings, issues: [SettingsRecoveryIssue]) {
        let legacy = StoredAppSettingsV11(
            schemaVersion: 11,
            selectedPetInstanceID: stored.selectedPetInstanceID,
            activePetInstances: stored.activePetInstances,
            behaviorProfiles: stored.behaviorProfiles.map(legacyProfile)
        )
        let mapped = AppSettingsV11Mapper.domainSettings(
            from: legacy,
            idGenerator: idGenerator
        )
        var storedProfilesByID: [UUID: StoredPetProfileV12] = [:]
        for profile in stored.behaviorProfiles {
            if let id = UUID(uuidString: profile.profileID),
               storedProfilesByID[id] == nil {
                storedProfilesByID[id] = profile
            }
        }
        let records = mapped.settings.petBehaviorProfiles.map { record in
            guard let storedProfile = storedProfilesByID[record.profileID]
            else {
                return record
            }
            var names: [String: String] = [:]
            for sequence in storedProfile.sequences where names[sequence.id] == nil {
                let name = sequence.displayName.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                names[sequence.id] = name.isEmpty ? sequence.id : name
            }
            let profile = record.profile
            return PetBehaviorProfileSettings(
                profileID: record.profileID,
                profile: BehaviorProfile(
                    petKey: profile.petKey,
                    mode: profile.mode,
                    manualSequenceID: profile.manualSequenceID,
                    sequences: profile.sequences.map { sequence in
                        BehaviorSequence(
                            id: sequence.id,
                            displayName: names[sequence.id],
                            steps: sequence.steps,
                            repeats: sequence.repeats
                        )
                    },
                    automaticRules: profile.automaticRules,
                    automaticRulePriorityOrder: normalizedPriorityOrder(
                        storedProfile.automaticRulePriorityOrder
                    ),
                    movement: profile.movement,
                    pettingMotionID: profile.pettingMotionID,
                    speech: profile.speech
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
    ) throws -> StoredAppSettingsV12 {
        let legacy = try AppSettingsV11Mapper.storedSettings(from: settings)
        let profilesByID = Dictionary(
            uniqueKeysWithValues: settings.petBehaviorProfiles.map {
                ($0.profileID, $0.profile)
            }
        )
        let profiles = legacy.behaviorProfiles.map { storedProfile in
            guard
                let id = UUID(uuidString: storedProfile.profileID),
                let profile = profilesByID[id]
            else {
                return profileFromLegacy(storedProfile)
            }
            let legacyMovement = storedProfile.movement
            return StoredPetProfileV12(
                profileID: storedProfile.profileID,
                petKey: storedProfile.petKey,
                mode: storedProfile.mode,
                manualSequenceID: storedProfile.manualSequenceID,
                sequences: zip(storedProfile.sequences, profile.sequences)
                    .map { storedSequence, sequence in
                        StoredBehaviorSequenceV12(
                            id: storedSequence.id,
                            displayName: sequence.displayName,
                            steps: storedSequence.steps,
                            repeats: storedSequence.repeats
                        )
                    },
                automaticRules: storedProfile.automaticRules,
                automaticRulePriorityOrder:
                    profile.automaticRulePriorityOrder.map(\.rawValue),
                movement: behaviorMovement(from: legacyMovement),
                pettingBehaviorID: storedProfile.pettingMotionID,
                speech: storedProfile.speech
            )
        }
        return StoredAppSettingsV12(
            schemaVersion: 12,
            selectedPetInstanceID: legacy.selectedPetInstanceID,
            activePetInstances: legacy.activePetInstances,
            behaviorProfiles: profiles
        )
    }

    private static func legacyProfile(
        _ profile: StoredPetProfileV12
    ) -> StoredPetProfileV11 {
        let movement = profile.movement
        return StoredPetProfileV11(
            profileID: profile.profileID,
            petKey: profile.petKey,
            mode: profile.mode,
            manualSequenceID: profile.manualSequenceID,
            sequences: profile.sequences.map {
                StoredBehaviorSequenceV2(
                    id: $0.id,
                    steps: $0.steps,
                    repeats: $0.repeats
                )
            },
            automaticRules: profile.automaticRules,
            movement: StoredPetMovementSettingsV6(
                mode: movement.mode,
                speed: movement.speed,
                cursorDistance: movement.cursorDistance,
                stopRadius: movement.stopRadius,
                freeRoamingDwellMilliseconds:
                    movement.freeRoamingDwellMilliseconds,
                prefersFrontmostWindow: movement.prefersFrontmostWindow,
                cursorFollowingAnimation: legacyBehavior(
                    from: movement.cursorFollowingBehavior
                ),
                freeRoamingAnimation: legacyBehavior(
                    from: movement.freeRoamingBehavior
                ),
                cursorAvoidingIdleBehavior:
                    movement.cursorAvoidingIdleBehavior,
                cursorAvoidingDetectionDistance:
                    movement.cursorAvoidingDetectionDistance,
                cursorAvoidingSpeed: movement.cursorAvoidingSpeed,
                cursorAvoidingAnimation: legacyBehavior(
                    from: movement.cursorAvoidingBehavior
                )
            ),
            pettingMotionID: profile.pettingBehaviorID,
            speech: profile.speech
        )
    }

    private static func profileFromLegacy(
        _ profile: StoredPetProfileV11
    ) -> StoredPetProfileV12 {
        StoredPetProfileV12(
            profileID: profile.profileID,
            petKey: profile.petKey,
            mode: profile.mode,
            manualSequenceID: profile.manualSequenceID,
            sequences: profile.sequences.map {
                StoredBehaviorSequenceV12(
                    id: $0.id,
                    displayName: $0.id,
                    steps: $0.steps,
                    repeats: $0.repeats
                )
            },
            automaticRules: profile.automaticRules,
            automaticRulePriorityOrder:
                AutomaticRuleCategory.defaultPriorityOrder.map(\.rawValue),
            movement: behaviorMovement(from: profile.movement),
            pettingBehaviorID: profile.pettingMotionID,
            speech: profile.speech
        )
    }

    private static func behaviorMovement(
        from movement: StoredPetMovementSettingsV6
    ) -> StoredPetMovementSettingsV12 {
        StoredPetMovementSettingsV12(
            mode: movement.mode,
            speed: movement.speed,
            cursorDistance: movement.cursorDistance,
            stopRadius: movement.stopRadius,
            freeRoamingDwellMilliseconds:
                movement.freeRoamingDwellMilliseconds,
            prefersFrontmostWindow: movement.prefersFrontmostWindow,
            cursorFollowingBehavior: behavior(
                from: movement.cursorFollowingAnimation
            ),
            freeRoamingBehavior: behavior(
                from: movement.freeRoamingAnimation
            ),
            cursorAvoidingIdleBehavior:
                movement.cursorAvoidingIdleBehavior,
            cursorAvoidingDetectionDistance:
                movement.cursorAvoidingDetectionDistance,
            cursorAvoidingSpeed: movement.cursorAvoidingSpeed,
            cursorAvoidingBehavior: behavior(
                from: movement.cursorAvoidingAnimation
            )
        )
    }

    private static func behavior(
        from legacy: StoredMovementAnimationSettingsV5
    ) -> StoredMovementBehaviorSettingsV12 {
        let directions = legacy.directionMotionIDs
        return StoredMovementBehaviorSettingsV12(
            fallbackBehaviorID: legacy.fallbackMotionID,
            usesDirectionalBehaviors: legacy.usesDirectionalMotions,
            usesDiagonalBehaviors: legacy.usesDiagonalMotions,
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

    private static func legacyBehavior(
        from stored: StoredMovementBehaviorSettingsV12
    ) -> StoredMovementAnimationSettingsV5 {
        let directions = stored.directionBehaviorIDs
        return StoredMovementAnimationSettingsV5(
            fallbackMotionID: stored.fallbackBehaviorID,
            usesDirectionalMotions: stored.usesDirectionalBehaviors,
            usesDiagonalMotions: stored.usesDiagonalBehaviors,
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

    private static func normalizedPriorityOrder(
        _ values: [String]
    ) -> [AutomaticRuleCategory] {
        var result: [AutomaticRuleCategory] = []
        for value in values {
            guard
                let category = AutomaticRuleCategory(rawValue: value),
                !result.contains(category)
            else {
                continue
            }
            result.append(category)
        }
        if !result.contains(.movement) {
            result.insert(.movement, at: 0)
        }
        for category in AutomaticRuleCategory.defaultPriorityOrder
            where !result.contains(category) {
            result.append(category)
        }
        return result
    }
}
