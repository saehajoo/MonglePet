import Foundation

nonisolated enum AppSettingsV9Mapper {
    static func domainSettings(
        from stored: StoredAppSettingsV9
    ) -> (settings: AppSettings, issues: [SettingsRecoveryIssue]) {
        let storedV8 = StoredAppSettingsV8(
            schemaVersion: 8,
            selectedPetInstallationID: stored.selectedPetInstallationID,
            lastUserPresentation: stored.lastUserPresentation,
            overlay: stored.overlay,
            behaviorProfiles: stored.behaviorProfiles.map { profile in
                StoredPetProfileV8(
                    petKey: profile.petKey,
                    mode: profile.mode,
                    manualSequenceID: profile.manualSequenceID,
                    sequences: profile.sequences,
                    automaticRules: profile.automaticRules,
                    movement: profile.movement,
                    pettingMotionID: profile.pettingMotionID,
                    speech: StoredPetSpeechSettingsV8(
                        isEnabled: profile.speech.isEnabled,
                        periodicIntervalMilliseconds:
                            profile.speech.periodicIntervalMilliseconds,
                        phrases: profile.speech.phrases.map {
                            StoredPetSpeechPhraseV7(
                                id: $0.id,
                                text: $0.text,
                                displayDurationMilliseconds:
                                    $0.displayDurationMilliseconds,
                                trigger: $0.trigger
                            )
                        },
                        theme: profile.speech.theme
                    )
                )
            }
        )
        let mappedV8 = AppSettingsV8Mapper.domainSettings(from: storedV8)
        var issues = mappedV8.issues
        var speechByKey:
            [PetBehaviorKey: (Int, StoredPetSpeechSettingsV9)] = [:]
        for (index, profile) in stored.behaviorProfiles.enumerated() {
            guard
                let key = domainPetKey(from: profile.petKey),
                speechByKey[key] == nil
            else {
                continue
            }
            speechByKey[key] = (index, profile.speech)
        }

        let profiles = mappedV8.settings.behaviorProfiles.map { profile in
            guard let (index, storedSpeech) = speechByKey[profile.petKey] else {
                return profile
            }
            let field = "behaviorProfiles.\(index).speech"
            let periodicOrder: PetSpeechPeriodicOrder
            switch storedSpeech.periodicOrder {
            case "random":
                periodicOrder = .random
            case "sequential":
                periodicOrder = .sequential
            default:
                periodicOrder = .random
                issues.append(.invalidField("\(field).periodicOrder"))
            }
            let behaviorChangePolicy: PetSpeechBehaviorChangePolicy
            switch storedSpeech.behaviorChangePolicy {
            case "dismiss":
                behaviorChangePolicy = .dismiss
            case "keep":
                behaviorChangePolicy = .keep
            default:
                behaviorChangePolicy = .dismiss
                issues.append(
                    .invalidField("\(field).behaviorChangePolicy")
                )
            }

            var displayModes: [UUID: (Int, String)] = [:]
            for (phraseIndex, phrase) in
                storedSpeech.phrases.enumerated() {
                guard
                    let id = UUID(uuidString: phrase.id),
                    displayModes[id] == nil
                else {
                    continue
                }
                displayModes[id] = (phraseIndex, phrase.displayMode)
            }
            let phrases = profile.speech.phrases.map { phrase in
                let storedMode = displayModes[phrase.id]
                let displayMode: PetSpeechDisplayMode
                switch storedMode?.1 {
                case "timed":
                    displayMode = .timed
                case "untilNextPhrase":
                    displayMode = .untilNextPhrase
                default:
                    displayMode = .timed
                    if let phraseIndex = storedMode?.0 {
                        issues.append(
                            .invalidField(
                                "\(field).phrases.\(phraseIndex).displayMode"
                            )
                        )
                    }
                }
                return PetSpeechPhrase(
                    id: phrase.id,
                    text: phrase.text,
                    displayDurationMilliseconds:
                        phrase.displayDurationMilliseconds,
                    trigger: phrase.trigger,
                    displayMode: displayMode
                )
            }
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
                    periodicIsEnabled: storedSpeech.periodicIsEnabled,
                    periodicIntervalMilliseconds:
                        profile.speech.periodicIntervalMilliseconds,
                    periodicOrder: periodicOrder,
                    behaviorChangePolicy: behaviorChangePolicy,
                    phrases: phrases,
                    theme: profile.speech.theme
                )
            )
        }

        return (
            AppSettings(
                selectedPetInstallationID:
                    mappedV8.settings.selectedPetInstallationID,
                lastUserPresentation:
                    mappedV8.settings.lastUserPresentation,
                overlay: mappedV8.settings.overlay,
                behaviorProfiles: profiles
            ),
            issues
        )
    }

    static func storedSettings(
        from settings: AppSettings
    ) throws -> StoredAppSettingsV9 {
        let storedV8 = try AppSettingsV8Mapper.storedSettings(from: settings)
        let profiles = try zip(
            storedV8.behaviorProfiles,
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
            return StoredPetProfileV9(
                petKey: storedProfile.petKey,
                mode: storedProfile.mode,
                manualSequenceID: storedProfile.manualSequenceID,
                sequences: storedProfile.sequences,
                automaticRules: storedProfile.automaticRules,
                movement: storedProfile.movement,
                pettingMotionID: storedProfile.pettingMotionID,
                speech: StoredPetSpeechSettingsV9(
                    isEnabled: profile.speech.isEnabled,
                    periodicIsEnabled:
                        profile.speech.periodicIsEnabled,
                    periodicIntervalMilliseconds:
                        profile.speech.periodicIntervalMilliseconds,
                    periodicOrder: storedPeriodicOrder(
                        profile.speech.periodicOrder
                    ),
                    behaviorChangePolicy: storedBehaviorChangePolicy(
                        profile.speech.behaviorChangePolicy
                    ),
                    phrases: profile.speech.phrases.map(storedPhrase),
                    theme: storedProfile.speech.theme
                )
            )
        }
        return StoredAppSettingsV9(
            schemaVersion: 9,
            selectedPetInstallationID:
                storedV8.selectedPetInstallationID,
            lastUserPresentation: storedV8.lastUserPresentation,
            overlay: storedV8.overlay,
            behaviorProfiles: profiles
        )
    }

    private static func storedPhrase(
        _ phrase: PetSpeechPhrase
    ) -> StoredPetSpeechPhraseV9 {
        let trigger: StoredPetSpeechTriggerV7 = switch phrase.trigger {
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
        return StoredPetSpeechPhraseV9(
            id: phrase.id.uuidString,
            text: phrase.text,
            displayDurationMilliseconds:
                phrase.displayDurationMilliseconds,
            trigger: trigger,
            displayMode: phrase.displayMode == .timed
                ? "timed"
                : "untilNextPhrase"
        )
    }

    private static func storedPeriodicOrder(
        _ order: PetSpeechPeriodicOrder
    ) -> String {
        switch order {
        case .random: "random"
        case .sequential: "sequential"
        }
    }

    private static func storedBehaviorChangePolicy(
        _ policy: PetSpeechBehaviorChangePolicy
    ) -> String {
        switch policy {
        case .dismiss: "dismiss"
        case .keep: "keep"
        }
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
