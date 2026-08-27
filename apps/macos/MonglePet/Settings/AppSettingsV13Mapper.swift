import Foundation

nonisolated enum AppSettingsV13Mapper {
    static func domainSettings(
        from stored: StoredAppSettingsV13,
        idGenerator: () -> UUID = UUID.init
    ) -> (settings: AppSettings, issues: [SettingsRecoveryIssue]) {
        let legacy = StoredAppSettingsV12(
            schemaVersion: 12,
            selectedPetInstanceID: stored.selectedPetInstanceID,
            activePetInstances: stored.activePetInstances,
            behaviorProfiles: stored.behaviorProfiles.map(legacyProfile)
        )
        let mapped = AppSettingsV12Mapper.domainSettings(
            from: legacy,
            idGenerator: idGenerator
        )
        var storedProfiles: [UUID: StoredPetProfileV13] = [:]
        for profile in stored.behaviorProfiles {
            if let id = UUID(uuidString: profile.profileID),
               storedProfiles[id] == nil {
                storedProfiles[id] = profile
            }
        }
        let records = mapped.settings.petBehaviorProfiles.map { record in
            guard let storedProfile = storedProfiles[record.profileID] else {
                return record
            }
            let profile = record.profile
            let sequenceIDs = Set(profile.sequences.map(\.id))
            var seen = Set<String>()
            let randomSequenceIDs = storedProfile.randomSequenceIDs.filter {
                sequenceIDs.contains($0) && seen.insert($0).inserted
            }
            let movement = profile.movement
            let storedMovement = storedProfile.movement
            let normalizedMaximum = min(
                max(
                    storedMovement.freeRoamingDwellMilliseconds,
                    AppSettingsLimits.minimumFreeRoamingDwellMilliseconds
                ),
                AppSettingsLimits.maximumFreeRoamingDwellMilliseconds
            )
            let normalizedMinimum = min(
                normalizedMaximum,
                max(
                    storedMovement.freeRoamingDwellMinimumMilliseconds,
                    AppSettingsLimits.minimumFreeRoamingDwellMilliseconds
                )
            )
            return PetBehaviorProfileSettings(
                profileID: record.profileID,
                profile: BehaviorProfile(
                    petKey: profile.petKey,
                    mode: BehaviorMode(rawValue: storedProfile.mode)
                        ?? profile.mode,
                    manualSequenceID: profile.manualSequenceID,
                    randomSequenceIDs: randomSequenceIDs,
                    sequences: profile.sequences,
                    automaticRules: profile.automaticRules,
                    automaticRulePriorityOrder:
                        profile.automaticRulePriorityOrder,
                    movement: PetMovementSettings(
                        mode: movement.mode,
                        speed: movement.speed,
                        cursorDistance: movement.cursorDistance,
                        stopRadius: movement.stopRadius,
                        freeRoamingDwellMilliseconds: normalizedMaximum,
                        prefersFrontmostWindow:
                            movement.prefersFrontmostWindow,
                        cursorFollowingAnimation:
                            movement.cursorFollowingAnimation,
                        freeRoamingAnimation:
                            movement.freeRoamingAnimation,
                        cursorAvoidingIdleBehavior:
                            movement.cursorAvoidingIdleBehavior,
                        cursorAvoidingDetectionDistance:
                            movement.cursorAvoidingDetectionDistance,
                        cursorAvoidingSpeed: movement.cursorAvoidingSpeed,
                        cursorAvoidingAnimation:
                            movement.cursorAvoidingAnimation,
                        randomizesFreeRoamingDwell:
                            storedMovement.randomizesFreeRoamingDwell,
                        freeRoamingDwellMinimumMilliseconds:
                            normalizedMinimum
                    ),
                    pettingMotionID: profile.pettingMotionID,
                    speech: profile.speech
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
    ) throws -> StoredAppSettingsV13 {
        for (index, record) in settings.petBehaviorProfiles.enumerated() {
            let sequenceIDs = Set(record.profile.sequences.map(\.id))
            let randomIDs = record.profile.randomSequenceIDs
            guard Set(randomIDs).count == randomIDs.count,
                  randomIDs.allSatisfy(sequenceIDs.contains) else {
                throw AppSettingsMappingError.invalidSettings(
                    "behaviorProfiles.\(index).randomSequenceIDs"
                )
            }
        }
        let legacy = try AppSettingsV12Mapper.storedSettings(from: settings)
        let profiles = Dictionary(
            uniqueKeysWithValues: settings.petBehaviorProfiles.map {
                ($0.profileID, $0.profile)
            }
        )
        return StoredAppSettingsV13(
            schemaVersion: 13,
            selectedPetInstanceID: legacy.selectedPetInstanceID,
            activePetInstances: legacy.activePetInstances,
            behaviorProfiles: legacy.behaviorProfiles.map { storedProfile in
                guard let id = UUID(uuidString: storedProfile.profileID),
                      let profile = profiles[id] else {
                    return profileFromLegacy(storedProfile)
                }
                let movement = storedProfile.movement
                return StoredPetProfileV13(
                    profileID: storedProfile.profileID,
                    petKey: storedProfile.petKey,
                    mode: profile.mode.rawValue,
                    manualSequenceID: storedProfile.manualSequenceID,
                    randomSequenceIDs: profile.randomSequenceIDs,
                    sequences: storedProfile.sequences,
                    automaticRules: storedProfile.automaticRules,
                    automaticRulePriorityOrder:
                        storedProfile.automaticRulePriorityOrder,
                    movement: movementV13(
                        movement,
                        domain: profile.movement
                    ),
                    pettingBehaviorID: storedProfile.pettingBehaviorID,
                    speech: storedProfile.speech
                )
            }
        )
    }

    private static func legacyProfile(
        _ profile: StoredPetProfileV13
    ) -> StoredPetProfileV12 {
        StoredPetProfileV12(
            profileID: profile.profileID,
            petKey: profile.petKey,
            mode: profile.mode == BehaviorMode.random.rawValue
                ? BehaviorMode.automatic.rawValue
                : profile.mode,
            manualSequenceID: profile.manualSequenceID,
            sequences: profile.sequences,
            automaticRules: profile.automaticRules,
            automaticRulePriorityOrder: profile.automaticRulePriorityOrder,
            movement: movementV12(profile.movement),
            pettingBehaviorID: profile.pettingBehaviorID,
            speech: profile.speech
        )
    }

    private static func profileFromLegacy(
        _ profile: StoredPetProfileV12
    ) -> StoredPetProfileV13 {
        let movement = profile.movement
        let maximum = movement.freeRoamingDwellMilliseconds
        return StoredPetProfileV13(
            profileID: profile.profileID,
            petKey: profile.petKey,
            mode: profile.mode,
            manualSequenceID: profile.manualSequenceID,
            randomSequenceIDs: [],
            sequences: profile.sequences,
            automaticRules: profile.automaticRules,
            automaticRulePriorityOrder: profile.automaticRulePriorityOrder,
            movement: movementV13(
                movement,
                randomizes: false,
                minimum: min(
                    maximum,
                    max(
                        AppSettingsLimits.minimumFreeRoamingDwellMilliseconds,
                        maximum / 2
                    )
                )
            ),
            pettingBehaviorID: profile.pettingBehaviorID,
            speech: profile.speech
        )
    }

    private static func movementV12(
        _ movement: StoredPetMovementSettingsV13
    ) -> StoredPetMovementSettingsV12 {
        StoredPetMovementSettingsV12(
            mode: movement.mode,
            speed: movement.speed,
            cursorDistance: movement.cursorDistance,
            stopRadius: movement.stopRadius,
            freeRoamingDwellMilliseconds:
                movement.freeRoamingDwellMilliseconds,
            prefersFrontmostWindow: movement.prefersFrontmostWindow,
            cursorFollowingBehavior: movement.cursorFollowingBehavior,
            freeRoamingBehavior: movement.freeRoamingBehavior,
            cursorAvoidingIdleBehavior: movement.cursorAvoidingIdleBehavior,
            cursorAvoidingDetectionDistance:
                movement.cursorAvoidingDetectionDistance,
            cursorAvoidingSpeed: movement.cursorAvoidingSpeed,
            cursorAvoidingBehavior: movement.cursorAvoidingBehavior
        )
    }

    private static func movementV13(
        _ movement: StoredPetMovementSettingsV12,
        domain: PetMovementSettings
    ) -> StoredPetMovementSettingsV13 {
        movementV13(
            movement,
            randomizes: domain.randomizesFreeRoamingDwell,
            minimum: domain.freeRoamingDwellMinimumMilliseconds
        )
    }

    private static func movementV13(
        _ movement: StoredPetMovementSettingsV12,
        randomizes: Bool,
        minimum: Int64
    ) -> StoredPetMovementSettingsV13 {
        StoredPetMovementSettingsV13(
            mode: movement.mode,
            speed: movement.speed,
            cursorDistance: movement.cursorDistance,
            stopRadius: movement.stopRadius,
            freeRoamingDwellMilliseconds:
                movement.freeRoamingDwellMilliseconds,
            randomizesFreeRoamingDwell: randomizes,
            freeRoamingDwellMinimumMilliseconds: minimum,
            prefersFrontmostWindow: movement.prefersFrontmostWindow,
            cursorFollowingBehavior: movement.cursorFollowingBehavior,
            freeRoamingBehavior: movement.freeRoamingBehavior,
            cursorAvoidingIdleBehavior: movement.cursorAvoidingIdleBehavior,
            cursorAvoidingDetectionDistance:
                movement.cursorAvoidingDetectionDistance,
            cursorAvoidingSpeed: movement.cursorAvoidingSpeed,
            cursorAvoidingBehavior: movement.cursorAvoidingBehavior
        )
    }
}
