import Foundation

nonisolated enum AppSettingsV10Mapper {
    static func domainSettings(
        from stored: StoredAppSettingsV10
    ) -> (settings: AppSettings, issues: [SettingsRecoveryIssue]) {
        let storedV9 = StoredAppSettingsV9(
            schemaVersion: 9,
            selectedPetInstallationID: stored.selectedPetInstallationID,
            lastUserPresentation: stored.lastUserPresentation,
            overlay: stored.overlay,
            behaviorProfiles: stored.behaviorProfiles.map { profile in
                StoredPetProfileV9(
                    petKey: profile.petKey,
                    mode: profile.mode,
                    manualSequenceID: profile.manualSequenceID,
                    sequences: profile.sequences,
                    automaticRules: profile.automaticRules,
                    movement: profile.movement,
                    pettingMotionID: profile.pettingMotionID,
                    speech: StoredPetSpeechSettingsV9(
                        isEnabled: profile.speech.isEnabled,
                        periodicIsEnabled:
                            profile.speech.periodicIsEnabled,
                        periodicIntervalMilliseconds:
                            profile.speech.periodicIntervalMilliseconds,
                        periodicOrder: profile.speech.periodicOrder,
                        behaviorChangePolicy:
                            profile.speech.behaviorChangePolicy,
                        phrases: profile.speech.phrases,
                        theme: profile.speech.theme
                    )
                )
            }
        )
        let mappedV9 = AppSettingsV9Mapper.domainSettings(from: storedV9)
        var issues = mappedV9.issues
        var placementsByKey:
            [PetBehaviorKey: (Int, StoredPetSpeechBubblePlacementV10)] = [:]
        for (index, profile) in stored.behaviorProfiles.enumerated() {
            guard
                let key = domainPetKey(from: profile.petKey),
                placementsByKey[key] == nil
            else {
                continue
            }
            placementsByKey[key] = (index, profile.speech.placement)
        }

        let profiles = mappedV9.settings.behaviorProfiles.map { profile in
            guard
                let (index, storedPlacement) =
                    placementsByKey[profile.petKey]
            else {
                return profile
            }
            let field =
                "behaviorProfiles.\(index).speech.placement"
            let preferredPosition: PetSpeechBubblePreferredPosition
            switch storedPlacement.preferredPosition {
            case "automatic":
                preferredPosition = .automatic
            case "above":
                preferredPosition = .above
            case "below":
                preferredPosition = .below
            default:
                preferredPosition = .automatic
                issues.append(
                    .invalidField("\(field).preferredPosition")
                )
            }
            let horizontalOffset = normalized(
                storedPlacement.horizontalOffset,
                range:
                    AppSettingsLimits.minimumSpeechBubbleHorizontalOffset
                    ... AppSettingsLimits
                        .maximumSpeechBubbleHorizontalOffset,
                fallback:
                    AppSettingsLimits.defaultSpeechBubbleHorizontalOffset,
                field: "\(field).horizontalOffset",
                issues: &issues
            )
            let gap = normalized(
                storedPlacement.gap,
                range: AppSettingsLimits.minimumSpeechBubbleGap
                    ... AppSettingsLimits.maximumSpeechBubbleGap,
                fallback: AppSettingsLimits.defaultSpeechBubbleGap,
                field: "\(field).gap",
                issues: &issues
            )
            return BehaviorProfile(
                petKey: profile.petKey,
                mode: profile.mode,
                manualSequenceID: profile.manualSequenceID,
                sequences: profile.sequences,
                automaticRules: profile.automaticRules,
                movement: profile.movement,
                pettingMotionID: profile.pettingMotionID,
                speech: PetSpeechSettings(
                    isEnabled: profile.speech.isEnabled,
                    periodicIsEnabled:
                        profile.speech.periodicIsEnabled,
                    periodicIntervalMilliseconds:
                        profile.speech.periodicIntervalMilliseconds,
                    periodicOrder: profile.speech.periodicOrder,
                    behaviorChangePolicy:
                        profile.speech.behaviorChangePolicy,
                    phrases: profile.speech.phrases,
                    theme: profile.speech.theme,
                    placement: PetSpeechBubblePlacementSettings(
                        preferredPosition: preferredPosition,
                        horizontalOffset: horizontalOffset,
                        gap: gap
                    )
                )
            )
        }
        return (
            AppSettings(
                selectedPetInstallationID:
                    mappedV9.settings.selectedPetInstallationID,
                lastUserPresentation:
                    mappedV9.settings.lastUserPresentation,
                overlay: mappedV9.settings.overlay,
                behaviorProfiles: profiles
            ),
            issues
        )
    }

    static func storedSettings(
        from settings: AppSettings
    ) throws -> StoredAppSettingsV10 {
        let storedV9 = try AppSettingsV9Mapper.storedSettings(
            from: settings
        )
        let profiles = try zip(
            storedV9.behaviorProfiles,
            settings.behaviorProfiles
        )
        .enumerated()
        .map { index, pair in
            let (storedProfile, profile) = pair
            guard profile.speech.placement.isValid else {
                throw AppSettingsMappingError.invalidSettings(
                    "behaviorProfiles.\(index).speech.placement"
                )
            }
            return StoredPetProfileV10(
                petKey: storedProfile.petKey,
                mode: storedProfile.mode,
                manualSequenceID: storedProfile.manualSequenceID,
                sequences: storedProfile.sequences,
                automaticRules: storedProfile.automaticRules,
                movement: storedProfile.movement,
                pettingMotionID: storedProfile.pettingMotionID,
                speech: StoredPetSpeechSettingsV10(
                    isEnabled: storedProfile.speech.isEnabled,
                    periodicIsEnabled:
                        storedProfile.speech.periodicIsEnabled,
                    periodicIntervalMilliseconds:
                        storedProfile.speech
                            .periodicIntervalMilliseconds,
                    periodicOrder: storedProfile.speech.periodicOrder,
                    behaviorChangePolicy:
                        storedProfile.speech.behaviorChangePolicy,
                    phrases: storedProfile.speech.phrases,
                    theme: storedProfile.speech.theme,
                    placement: storedPlacement(
                        profile.speech.placement
                    )
                )
            )
        }
        return StoredAppSettingsV10(
            schemaVersion: 10,
            selectedPetInstallationID:
                storedV9.selectedPetInstallationID,
            lastUserPresentation: storedV9.lastUserPresentation,
            overlay: storedV9.overlay,
            behaviorProfiles: profiles
        )
    }

    private static func storedPlacement(
        _ placement: PetSpeechBubblePlacementSettings
    ) -> StoredPetSpeechBubblePlacementV10 {
        let preferredPosition: String =
            switch placement.preferredPosition {
            case .automatic: "automatic"
            case .above: "above"
            case .below: "below"
            }
        return StoredPetSpeechBubblePlacementV10(
            preferredPosition: preferredPosition,
            horizontalOffset: placement.horizontalOffset,
            gap: placement.gap
        )
    }

    private static func normalized(
        _ value: Double,
        range: ClosedRange<Double>,
        fallback: Double,
        field: String,
        issues: inout [SettingsRecoveryIssue]
    ) -> Double {
        guard value.isFinite else {
            issues.append(.invalidField(field))
            return fallback
        }
        let normalized = min(max(value, range.lowerBound), range.upperBound)
        if normalized != value {
            issues.append(.invalidField(field))
        }
        return normalized
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
