import Foundation

nonisolated enum AppSettingsV7Mapper {
    static func domainSettings(
        from stored: StoredAppSettingsV7
    ) -> (settings: AppSettings, issues: [SettingsRecoveryIssue]) {
        let storedV6 = StoredAppSettingsV6(
            schemaVersion: 6,
            selectedPetInstallationID: stored.selectedPetInstallationID,
            lastUserPresentation: stored.lastUserPresentation,
            overlay: stored.overlay,
            behaviorProfiles: stored.behaviorProfiles.map { profile in
                StoredPetProfileV6(
                    petKey: profile.petKey,
                    mode: profile.mode,
                    manualSequenceID: profile.manualSequenceID,
                    sequences: profile.sequences,
                    automaticRules: profile.automaticRules,
                    movement: profile.movement,
                    pettingMotionID: profile.pettingMotionID
                )
            }
        )
        let mappedV6 = AppSettingsV6Mapper.domainSettings(from: storedV6)
        var issues = mappedV6.issues
        var speechByKey:
            [PetBehaviorKey: (Int, StoredPetSpeechSettingsV7)] = [:]
        for (index, profile) in stored.behaviorProfiles.enumerated() {
            guard
                let key = domainPetKey(from: profile.petKey),
                speechByKey[key] == nil
            else {
                continue
            }
            speechByKey[key] = (index, profile.speech)
        }

        let profiles = mappedV6.settings.behaviorProfiles.map { profile in
            guard let (index, storedSpeech) = speechByKey[profile.petKey] else {
                return profile
            }
            let speech = normalizedSpeech(
                storedSpeech,
                sequenceIDs: Set(profile.sequences.map(\.id)),
                field: "behaviorProfiles.\(index).speech",
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
                speech: speech
            )
        }
        return (
            AppSettings(
                selectedPetInstallationID:
                    mappedV6.settings.selectedPetInstallationID,
                lastUserPresentation:
                    mappedV6.settings.lastUserPresentation,
                overlay: mappedV6.settings.overlay,
                behaviorProfiles: profiles
            ),
            issues
        )
    }

    static func storedSettings(
        from settings: AppSettings
    ) throws -> StoredAppSettingsV7 {
        let storedV6 = try AppSettingsV6Mapper.storedSettings(from: settings)
        let profiles = try zip(
            storedV6.behaviorProfiles,
            settings.behaviorProfiles
        )
        .enumerated()
        .map { index, pair in
            let (storedProfile, profile) = pair
            guard profile.speech.isValid else {
                throw AppSettingsMappingError.invalidSettings(
                    "behaviorProfiles.\(index).speech"
                )
            }
            let sequenceIDs = Set(profile.sequences.map(\.id))
            guard profile.speech.phrases.allSatisfy({
                guard case let .sequence(sequenceID) = $0.trigger else {
                    return true
                }
                return sequenceIDs.contains(sequenceID)
            }) else {
                throw AppSettingsMappingError.invalidSettings(
                    "behaviorProfiles.\(index).speech.phrases"
                )
            }
            return StoredPetProfileV7(
                petKey: storedProfile.petKey,
                mode: storedProfile.mode,
                manualSequenceID: storedProfile.manualSequenceID,
                sequences: storedProfile.sequences,
                automaticRules: storedProfile.automaticRules,
                movement: storedProfile.movement,
                pettingMotionID: storedProfile.pettingMotionID,
                speech: storedSpeech(profile.speech)
            )
        }
        return StoredAppSettingsV7(
            schemaVersion: 7,
            selectedPetInstallationID:
                storedV6.selectedPetInstallationID,
            lastUserPresentation: storedV6.lastUserPresentation,
            overlay: storedV6.overlay,
            behaviorProfiles: profiles
        )
    }

    private static func normalizedSpeech(
        _ stored: StoredPetSpeechSettingsV7,
        sequenceIDs: Set<String>,
        field: String,
        issues: inout [SettingsRecoveryIssue]
    ) -> PetSpeechSettings {
        let interval: Int64
        if (AppSettingsLimits.minimumSpeechPeriodicIntervalMilliseconds
            ... AppSettingsLimits.maximumSpeechPeriodicIntervalMilliseconds)
            .contains(stored.periodicIntervalMilliseconds) {
            interval = stored.periodicIntervalMilliseconds
        } else {
            interval =
                AppSettingsLimits.defaultSpeechPeriodicIntervalMilliseconds
            issues.append(
                .invalidField("\(field).periodicIntervalMilliseconds")
            )
        }

        var seenIDs: Set<UUID> = []
        var phrases: [PetSpeechPhrase] = []
        let storedPhrases = stored.phrases.prefix(
            AppSettingsLimits.maximumSpeechPhrases
        )
        if stored.phrases.count > storedPhrases.count {
            issues.append(.truncatedCollection("\(field).phrases"))
        }
        for (index, storedPhrase) in storedPhrases.enumerated() {
            let phraseField = "\(field).phrases.\(index)"
            guard
                let id = UUID(uuidString: storedPhrase.id),
                seenIDs.insert(id).inserted
            else {
                issues.append(.invalidField("\(phraseField).id"))
                continue
            }
            let trigger: PetSpeechTrigger
            switch storedPhrase.trigger.type {
            case "periodic":
                guard storedPhrase.trigger.sequenceID == nil else {
                    issues.append(.invalidField("\(phraseField).trigger"))
                    continue
                }
                trigger = .periodic
            case "sequence":
                guard
                    let sequenceID = storedPhrase.trigger.sequenceID,
                    sequenceIDs.contains(sequenceID)
                else {
                    issues.append(
                        .invalidField("\(phraseField).trigger.sequenceID")
                    )
                    continue
                }
                trigger = .sequence(sequenceID)
            default:
                issues.append(.invalidField("\(phraseField).trigger.type"))
                continue
            }
            let phrase = PetSpeechPhrase(
                id: id,
                text: storedPhrase.text,
                displayDurationMilliseconds:
                    storedPhrase.displayDurationMilliseconds,
                trigger: trigger
            )
            guard phrase.isValid else {
                issues.append(.invalidField(phraseField))
                continue
            }
            phrases.append(phrase)
        }
        return PetSpeechSettings(
            isEnabled: stored.isEnabled,
            periodicIntervalMilliseconds: interval,
            phrases: phrases
        )
    }

    private static func storedSpeech(
        _ speech: PetSpeechSettings
    ) -> StoredPetSpeechSettingsV7 {
        StoredPetSpeechSettingsV7(
            isEnabled: speech.isEnabled,
            periodicIntervalMilliseconds:
                speech.periodicIntervalMilliseconds,
            phrases: speech.phrases.map { phrase in
                let trigger: StoredPetSpeechTriggerV7 =
                    switch phrase.trigger {
                    case .periodic:
                        StoredPetSpeechTriggerV7(
                            type: "periodic",
                            sequenceID: nil
                        )
                    case let .sequence(sequenceID):
                        StoredPetSpeechTriggerV7(
                            type: "sequence",
                            sequenceID: sequenceID
                        )
                    }
                return StoredPetSpeechPhraseV7(
                    id: phrase.id.uuidString,
                    text: phrase.text,
                    displayDurationMilliseconds:
                        phrase.displayDurationMilliseconds,
                    trigger: trigger
                )
            }
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
