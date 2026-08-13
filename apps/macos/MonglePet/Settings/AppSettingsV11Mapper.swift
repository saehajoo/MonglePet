import Foundation

nonisolated enum AppSettingsV11Mapper {
    static func domainSettings(
        from stored: StoredAppSettingsV11,
        idGenerator: () -> UUID = UUID.init
    ) -> (settings: AppSettings, issues: [SettingsRecoveryIssue]) {
        var issues: [SettingsRecoveryIssue] = []
        let profileLimit = min(
            stored.behaviorProfiles.count,
            AppSettingsLimits.maximumStoredBehaviorProfiles
        )
        if profileLimit != stored.behaviorProfiles.count {
            issues.append(.truncatedCollection("behaviorProfiles"))
        }

        var usedProfileIDs = Set<UUID>()
        var firstProfileIDByStoredValue: [String: UUID] = [:]
        var profiles: [PetBehaviorProfileSettings] = []
        for (index, storedProfile) in stored.behaviorProfiles
            .prefix(profileLimit)
            .enumerated() {
            let field = "behaviorProfiles.\(index)"
            guard let petKey = domainPetKey(from: storedProfile.petKey) else {
                issues.append(.invalidField("\(field).petKey"))
                continue
            }

            var profileID = UUID(uuidString: storedProfile.profileID)
            if profileID == nil || usedProfileIDs.contains(profileID!) {
                profileID = uniqueID(
                    excluding: usedProfileIDs,
                    idGenerator: idGenerator
                )
                issues.append(.invalidField("\(field).profileID"))
            }
            let resolvedProfileID = profileID!
            usedProfileIDs.insert(resolvedProfileID)
            if firstProfileIDByStoredValue[storedProfile.profileID] == nil {
                firstProfileIDByStoredValue[storedProfile.profileID] =
                    resolvedProfileID
            }

            let mapped = mapProfile(
                storedProfile,
                petKey: petKey,
                field: field
            )
            issues.append(contentsOf: mapped.issues)
            profiles.append(
                PetBehaviorProfileSettings(
                    profileID: resolvedProfileID,
                    profile: mapped.profile
                )
            )
        }

        let instanceLimit = min(
            stored.activePetInstances.count,
            AppSettingsLimits.maximumStoredPetInstances
        )
        if instanceLimit != stored.activePetInstances.count {
            issues.append(.truncatedCollection("activePetInstances"))
        }

        var usedInstanceIDs = Set<UUID>()
        var firstInstanceIDByStoredValue: [String: UUID] = [:]
        var claimedProfileIDs = Set<UUID>()
        var instances: [(sourceIndex: Int, settings: PetInstanceSettings)] = []
        for (index, storedInstance) in stored.activePetInstances
            .prefix(instanceLimit)
            .enumerated() {
            let field = "activePetInstances.\(index)"
            guard let petKey = domainPetKey(from: storedInstance.petKey) else {
                issues.append(.invalidField("\(field).petKey"))
                continue
            }

            var instanceID = UUID(uuidString: storedInstance.instanceID)
            if instanceID == nil || usedInstanceIDs.contains(instanceID!) {
                instanceID = uniqueID(
                    excluding: usedInstanceIDs,
                    idGenerator: idGenerator
                )
                issues.append(.invalidField("\(field).instanceID"))
            }
            let resolvedInstanceID = instanceID!
            usedInstanceIDs.insert(resolvedInstanceID)
            if firstInstanceIDByStoredValue[storedInstance.instanceID] == nil {
                firstInstanceIDByStoredValue[storedInstance.instanceID] =
                    resolvedInstanceID
            }

            let profileResolution = resolveProfile(
                storedID: storedInstance.behaviorProfileID,
                petKey: petKey,
                profiles: &profiles,
                usedProfileIDs: &usedProfileIDs,
                firstProfileIDByStoredValue: firstProfileIDByStoredValue,
                claimedProfileIDs: &claimedProfileIDs,
                idGenerator: idGenerator
            )
            if profileResolution.didRecover {
                issues.append(
                    .invalidField("\(field).behaviorProfileID")
                )
            }

            let overlayMapping = mapOverlay(
                storedInstance.overlay,
                petKey: petKey,
                field: "\(field).overlay"
            )
            issues.append(contentsOf: overlayMapping.issues)
            let presentation: PetPresentation
            switch storedInstance.presentation {
            case "awake":
                presentation = .awake
            case "tuckedAway":
                presentation = .tuckedAway
            default:
                presentation = .awake
                issues.append(.invalidField("\(field).presentation"))
            }
            let nickname = normalizedNickname(
                storedInstance.nickname,
                field: "\(field).nickname",
                issues: &issues
            )
            instances.append(
                (
                    index,
                    PetInstanceSettings(
                        instanceID: resolvedInstanceID,
                        petKey: petKey,
                        nickname: nickname,
                        presentation: presentation,
                        overlay: overlayMapping.overlay,
                        behaviorProfileID: profileResolution.profileID,
                        displayOrder: storedInstance.displayOrder
                    )
                )
            )
        }

        if instances.isEmpty {
            let profileID = uniqueID(
                excluding: usedProfileIDs,
                idGenerator: idGenerator
            )
            usedProfileIDs.insert(profileID)
            profiles.append(
                PetBehaviorProfileSettings(
                    profileID: profileID,
                    profile: defaultProfile(for: .builtIn)
                )
            )
            let instanceID = uniqueID(
                excluding: usedInstanceIDs,
                idGenerator: idGenerator
            )
            instances = [
                (
                    0,
                    PetInstanceSettings(
                        instanceID: instanceID,
                        petKey: .builtIn,
                        nickname: nil,
                        presentation: .awake,
                        overlay: .default,
                        behaviorProfileID: profileID,
                        displayOrder: 0
                    )
                )
            ]
            issues.append(.invalidField("activePetInstances"))
        }

        instances.sort {
            if $0.settings.displayOrder == $1.settings.displayOrder {
                return $0.sourceIndex < $1.sourceIndex
            }
            return $0.settings.displayOrder < $1.settings.displayOrder
        }
        let orderedInstances = instances.enumerated().map { order, entry in
            if entry.settings.displayOrder != order {
                issues.append(
                    .invalidField(
                        "activePetInstances.\(entry.sourceIndex).displayOrder"
                    )
                )
            }
            return PetInstanceSettings(
                instanceID: entry.settings.instanceID,
                petKey: entry.settings.petKey,
                nickname: entry.settings.nickname,
                presentation: entry.settings.presentation,
                overlay: entry.settings.overlay,
                behaviorProfileID: entry.settings.behaviorProfileID,
                displayOrder: order
            )
        }

        let requestedSelectedID = firstInstanceIDByStoredValue[
            stored.selectedPetInstanceID
        ]
        let selectedPetInstanceID: UUID
        if let requestedSelectedID,
           orderedInstances.contains(where: {
               $0.instanceID == requestedSelectedID
           }) {
            selectedPetInstanceID = requestedSelectedID
        } else {
            selectedPetInstanceID = orderedInstances[0].instanceID
            issues.append(.invalidField("selectedPetInstanceID"))
        }

        return (
            AppSettings(
                selectedPetInstanceID: selectedPetInstanceID,
                activePetInstances: orderedInstances,
                petBehaviorProfiles: profiles
            ),
            issues
        )
    }

    static func storedSettings(
        from settings: AppSettings
    ) throws -> StoredAppSettingsV11 {
        guard
            !settings.activePetInstances.isEmpty,
            settings.activePetInstances.count
                <= AppSettingsLimits.maximumStoredPetInstances
        else {
            throw AppSettingsMappingError.invalidSettings(
                "activePetInstances"
            )
        }
        guard
            !settings.petBehaviorProfiles.isEmpty,
            settings.petBehaviorProfiles.count
                <= AppSettingsLimits.maximumStoredBehaviorProfiles
        else {
            throw AppSettingsMappingError.invalidSettings(
                "behaviorProfiles"
            )
        }
        guard settings.activePetInstances.contains(where: {
            $0.instanceID == settings.selectedPetInstanceID
        }) else {
            throw AppSettingsMappingError.invalidSettings(
                "selectedPetInstanceID"
            )
        }

        var profileIDs = Set<UUID>()
        var storedProfiles: [StoredPetProfileV11] = []
        var profileByID: [UUID: BehaviorProfile] = [:]
        for (index, record) in settings.petBehaviorProfiles.enumerated() {
            guard profileIDs.insert(record.profileID).inserted else {
                throw AppSettingsMappingError.invalidSettings(
                    "behaviorProfiles.\(index).profileID"
                )
            }
            let storedProfile = try storedProfile(
                record.profile,
                profileID: record.profileID,
                field: "behaviorProfiles.\(index)"
            )
            storedProfiles.append(storedProfile)
            profileByID[record.profileID] = record.profile
        }

        let orderedInstances = settings.activePetInstances.sorted {
            $0.displayOrder < $1.displayOrder
        }
        var instanceIDs = Set<UUID>()
        var storedInstances: [StoredPetInstanceV11] = []
        for (index, instance) in orderedInstances.enumerated() {
            guard instanceIDs.insert(instance.instanceID).inserted else {
                throw AppSettingsMappingError.invalidSettings(
                    "activePetInstances.\(index).instanceID"
                )
            }
            guard instance.displayOrder == index else {
                throw AppSettingsMappingError.invalidSettings(
                    "activePetInstances.\(index).displayOrder"
                )
            }
            guard
                let profile = profileByID[instance.behaviorProfileID],
                profile.petKey == instance.petKey
            else {
                throw AppSettingsMappingError.invalidSettings(
                    "activePetInstances.\(index).behaviorProfileID"
                )
            }
            if let nickname = instance.nickname {
                let trimmed = nickname.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                guard
                    !trimmed.isEmpty,
                    trimmed == nickname,
                    nickname.count
                        <= AppSettingsLimits.maximumPetNicknameLength
                else {
                    throw AppSettingsMappingError.invalidSettings(
                        "activePetInstances.\(index).nickname"
                    )
                }
            }
            guard instance.presentation == .awake
                || instance.presentation == .tuckedAway else {
                throw AppSettingsMappingError.invalidSettings(
                    "activePetInstances.\(index).presentation"
                )
            }
            let overlay = try storedOverlay(
                instance.overlay,
                petKey: instance.petKey,
                profile: profile
            )
            storedInstances.append(
                StoredPetInstanceV11(
                    instanceID: instance.instanceID.uuidString,
                    petKey: storedPetKey(instance.petKey),
                    nickname: instance.nickname,
                    presentation: instance.presentation.rawValue,
                    overlay: overlay,
                    behaviorProfileID:
                        instance.behaviorProfileID.uuidString,
                    displayOrder: instance.displayOrder
                )
            )
        }

        return StoredAppSettingsV11(
            schemaVersion: AppSettingsLimits.schemaVersion,
            selectedPetInstanceID: settings.selectedPetInstanceID.uuidString,
            activePetInstances: storedInstances,
            behaviorProfiles: storedProfiles
        )
    }

    private static func mapProfile(
        _ stored: StoredPetProfileV11,
        petKey: PetBehaviorKey,
        field: String
    ) -> (profile: BehaviorProfile, issues: [SettingsRecoveryIssue]) {
        let v10 = StoredAppSettingsV10(
            schemaVersion: 10,
            selectedPetInstallationID: petKey.installationID?.uuidString,
            lastUserPresentation: "awake",
            overlay: defaultStoredOverlay,
            behaviorProfiles: [v10Profile(from: stored)]
        )
        let mapped = AppSettingsV10Mapper.domainSettings(from: v10)
        let profile = mapped.settings.behaviorProfile(for: petKey)
            ?? defaultProfile(for: petKey)
        return (
            profile,
            mapped.issues.map {
                prefixed($0, replacing: "behaviorProfiles.0", with: field)
            }
        )
    }

    private static func mapOverlay(
        _ stored: StoredOverlaySettingsV4,
        petKey: PetBehaviorKey,
        field: String
    ) -> (overlay: OverlaySettings, issues: [SettingsRecoveryIssue]) {
        let v10 = StoredAppSettingsV10(
            schemaVersion: 10,
            selectedPetInstallationID: petKey.installationID?.uuidString,
            lastUserPresentation: "awake",
            overlay: stored,
            behaviorProfiles: []
        )
        let mapped = AppSettingsV10Mapper.domainSettings(from: v10)
        return (
            mapped.settings.overlay,
            mapped.issues.map {
                prefixed($0, replacing: "overlay", with: field)
            }
        )
    }

    private static func resolveProfile(
        storedID: String,
        petKey: PetBehaviorKey,
        profiles: inout [PetBehaviorProfileSettings],
        usedProfileIDs: inout Set<UUID>,
        firstProfileIDByStoredValue: [String: UUID],
        claimedProfileIDs: inout Set<UUID>,
        idGenerator: () -> UUID
    ) -> (profileID: UUID, didRecover: Bool) {
        if let profileID = firstProfileIDByStoredValue[storedID],
           let record = profiles.first(where: {
               $0.profileID == profileID
           }),
           record.profile.petKey == petKey,
           claimedProfileIDs.insert(profileID).inserted {
            return (profileID, false)
        }

        let template = profiles.first(where: {
            $0.profile.petKey == petKey
        })?.profile ?? defaultProfile(for: petKey)
        let profileID = uniqueID(
            excluding: usedProfileIDs,
            idGenerator: idGenerator
        )
        usedProfileIDs.insert(profileID)
        claimedProfileIDs.insert(profileID)
        profiles.append(
            PetBehaviorProfileSettings(
                profileID: profileID,
                profile: template
            )
        )
        return (profileID, true)
    }

    private static func storedProfile(
        _ profile: BehaviorProfile,
        profileID: UUID,
        field: String
    ) throws -> StoredPetProfileV11 {
        let v10 = try AppSettingsV10Mapper.storedSettings(
            from: AppSettings(
                selectedPetInstallationID: profile.petKey.installationID,
                lastUserPresentation: .awake,
                overlay: .default,
                behaviorProfiles: [profile]
            )
        )
        guard let stored = v10.behaviorProfiles.first else {
            throw AppSettingsMappingError.invalidSettings(field)
        }
        return StoredPetProfileV11(
            profileID: profileID,
            profile: stored
        )
    }

    private static func storedOverlay(
        _ overlay: OverlaySettings,
        petKey: PetBehaviorKey,
        profile: BehaviorProfile
    ) throws -> StoredOverlaySettingsV4 {
        try AppSettingsV10Mapper.storedSettings(
            from: AppSettings(
                selectedPetInstallationID: petKey.installationID,
                lastUserPresentation: .awake,
                overlay: overlay,
                behaviorProfiles: [profile]
            )
        ).overlay
    }

    private static func v10Profile(
        from stored: StoredPetProfileV11
    ) -> StoredPetProfileV10 {
        StoredPetProfileV10(
            petKey: stored.petKey,
            mode: stored.mode,
            manualSequenceID: stored.manualSequenceID,
            sequences: stored.sequences,
            automaticRules: stored.automaticRules,
            movement: stored.movement,
            pettingMotionID: stored.pettingMotionID,
            speech: stored.speech
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

    private static func storedPetKey(
        _ key: PetBehaviorKey
    ) -> StoredPetBehaviorKeyV2 {
        switch key {
        case .builtIn:
            .builtIn
        case let .installed(installationID):
            .installed(installationID: installationID.uuidString)
        }
    }

    private static func normalizedNickname(
        _ nickname: String?,
        field: String,
        issues: inout [SettingsRecoveryIssue]
    ) -> String? {
        guard let nickname else {
            return nil
        }
        let trimmed = nickname.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !trimmed.isEmpty else {
            issues.append(.invalidField(field))
            return nil
        }
        let normalized = String(
            trimmed.prefix(AppSettingsLimits.maximumPetNicknameLength)
        )
        if normalized != nickname {
            issues.append(.invalidField(field))
        }
        return normalized
    }

    private static func uniqueID(
        excluding used: Set<UUID>,
        idGenerator: () -> UUID
    ) -> UUID {
        var candidate = idGenerator()
        while used.contains(candidate) {
            candidate = idGenerator()
        }
        return candidate
    }

    private static func defaultProfile(
        for petKey: PetBehaviorKey
    ) -> BehaviorProfile {
        BehaviorProfile(
            petKey: petKey,
            mode: .automatic,
            manualSequenceID: BuiltInBehaviorPresets.defaultManualSequenceID,
            sequences: BuiltInBehaviorPresets.sequences,
            automaticRules: [],
            movement: .default,
            pettingMotionID: nil,
            speech: .default
        )
    }

    private static func prefixed(
        _ issue: SettingsRecoveryIssue,
        replacing oldPrefix: String,
        with newPrefix: String
    ) -> SettingsRecoveryIssue {
        func path(_ value: String) -> String {
            value.hasPrefix(oldPrefix)
                ? newPrefix + value.dropFirst(oldPrefix.count)
                : value
        }
        return switch issue {
        case let .invalidField(value): .invalidField(path(value))
        case let .droppedSequence(value): .droppedSequence(path(value))
        case let .droppedRule(value): .droppedRule(path(value))
        case let .disabledRule(value): .disabledRule(path(value))
        case let .truncatedCollection(value):
            .truncatedCollection(path(value))
        case .corruptFileQuarantined, .newerSchemaVersion:
            issue
        }
    }

    private static let defaultStoredOverlay = StoredOverlaySettingsV4(
        screenIdentifier: nil,
        originX: 0,
        originY: 0,
        width: AppSettingsLimits.defaultOverlayWidth,
        clickThrough: false,
        opacity: AppSettingsLimits.defaultOverlayOpacity,
        pointerOverlapFadeEnabled: false,
        pointerOverlapOpacity:
            AppSettingsLimits.defaultPointerOverlapOpacity,
        pixelArtRendering: false,
        movementBoundary: StoredMovementBoundarySettingsV4(
            mode: "allDisplays",
            screenIdentifier: nil,
            normalizedRect: nil
        )
    )
}
