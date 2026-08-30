import Foundation

nonisolated enum AppSettingsV15Mapper {
    static func domainSettings(
        from stored: StoredAppSettingsV15,
        idGenerator: () -> UUID = UUID.init
    ) -> (settings: AppSettings, issues: [SettingsRecoveryIssue]) {
        let legacy = StoredAppSettingsV14(
            schemaVersion: 14,
            selectedPetInstanceID: stored.selectedPetInstanceID,
            activePetInstances: stored.activePetInstances,
            behaviorProfiles: stored.behaviorProfiles.map(legacyProfile)
        )
        return AppSettingsV14Mapper.domainSettings(
            from: legacy,
            idGenerator: idGenerator
        )
    }

    static func storedSettings(
        from settings: AppSettings
    ) throws -> StoredAppSettingsV15 {
        let legacy = try AppSettingsV14Mapper.storedSettings(from: settings)
        let profiles = Dictionary(
            uniqueKeysWithValues: settings.petBehaviorProfiles.map {
                ($0.profileID, $0.profile)
            }
        )
        return StoredAppSettingsV15(
            schemaVersion: AppSettingsLimits.schemaVersion,
            selectedPetInstanceID: legacy.selectedPetInstanceID,
            activePetInstances: legacy.activePetInstances,
            behaviorProfiles: legacy.behaviorProfiles.compactMap {
                legacyProfile in
                guard let profileID = UUID(uuidString: legacyProfile.profileID),
                      let profile = profiles[profileID] else {
                    return nil
                }
                return StoredPetProfileV15(
                    profileID: legacyProfile.profileID,
                    petKey: legacyProfile.petKey,
                    stationaryBehaviorMode:
                        profile.stationaryBehaviorMode.rawValue,
                    stationarySequenceID: profile.stationarySequenceID,
                    randomSequenceIDs: profile.randomSequenceIDs,
                    sequences: legacyProfile.sequences,
                    automaticRules: legacyProfile.automaticRules,
                    automaticRulePriorityOrder:
                        legacyProfile.automaticRulePriorityOrder,
                    movement: legacyProfile.movement,
                    pettingBehaviorID: legacyProfile.pettingBehaviorID,
                    speech: legacyProfile.speech
                )
            }
        )
    }

    private static func legacyProfile(
        _ profile: StoredPetProfileV15
    ) -> StoredPetProfileV14 {
        let legacyMode: String
        switch profile.stationaryBehaviorMode {
        case StationaryBehaviorMode.fixed.rawValue:
            legacyMode = profile.stationarySequenceID == nil
                ? BehaviorMode.automatic.rawValue
                : BehaviorMode.manual.rawValue
        case StationaryBehaviorMode.random.rawValue:
            legacyMode = BehaviorMode.random.rawValue
        default:
            legacyMode = profile.stationaryBehaviorMode
        }
        return StoredPetProfileV14(
            profileID: profile.profileID,
            petKey: profile.petKey,
            mode: legacyMode,
            manualSequenceID: profile.stationarySequenceID,
            randomSequenceIDs: profile.randomSequenceIDs,
            sequences: profile.sequences,
            automaticRules: profile.automaticRules,
            automaticRulePriorityOrder: profile.automaticRulePriorityOrder,
            movement: profile.movement,
            pettingBehaviorID: profile.pettingBehaviorID,
            speech: profile.speech
        )
    }
}
