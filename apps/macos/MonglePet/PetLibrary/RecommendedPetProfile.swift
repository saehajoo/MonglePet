import Foundation

nonisolated struct PortablePetDisplaySettings: Equatable, Sendable {
    let scalePercent: Double
    let clickThrough: Bool
    let opacity: Double
    let pointerOverlapFadeEnabled: Bool
    let pointerOverlapOpacity: Double
    let pixelArtRendering: Bool

    init(
        scalePercent: Double,
        clickThrough: Bool,
        opacity: Double,
        pointerOverlapFadeEnabled: Bool,
        pointerOverlapOpacity: Double,
        pixelArtRendering: Bool
    ) {
        self.scalePercent = scalePercent
        self.clickThrough = clickThrough
        self.opacity = opacity
        self.pointerOverlapFadeEnabled = pointerOverlapFadeEnabled
        self.pointerOverlapOpacity = pointerOverlapOpacity
        self.pixelArtRendering = pixelArtRendering
    }

    init(overlay: OverlaySettings) {
        self.init(
            scalePercent: overlay.width
                / AppSettingsLimits.defaultOverlayWidth * 100,
            clickThrough: overlay.clickThrough,
            opacity: overlay.opacity,
            pointerOverlapFadeEnabled: overlay.pointerOverlapFadeEnabled,
            pointerOverlapOpacity: overlay.pointerOverlapOpacity,
            pixelArtRendering: overlay.pixelArtRendering
        )
    }

    static let `default` = PortablePetDisplaySettings(overlay: .default)

    var isValid: Bool {
        scalePercent.isFinite
            && (AppSettingsLimits.minimumOverlayScalePercent
                ... AppSettingsLimits.maximumOverlayScalePercent)
                .contains(scalePercent)
            && opacity.isFinite
            && (AppSettingsLimits.minimumOverlayOpacity
                ... AppSettingsLimits.maximumOverlayOpacity)
                .contains(opacity)
            && pointerOverlapOpacity.isFinite
            && (AppSettingsLimits.minimumPointerOverlapOpacity
                ... AppSettingsLimits.maximumPointerOverlapOpacity)
                .contains(pointerOverlapOpacity)
    }

    func applying(to overlay: OverlaySettings) -> OverlaySettings {
        OverlaySettings(
            screenIdentifier: overlay.screenIdentifier,
            originX: overlay.originX,
            originY: overlay.originY,
            width: AppSettingsLimits.defaultOverlayWidth
                * scalePercent / 100,
            clickThrough: clickThrough,
            opacity: opacity,
            pointerOverlapFadeEnabled: pointerOverlapFadeEnabled,
            pointerOverlapOpacity: pointerOverlapOpacity,
            pixelArtRendering: pixelArtRendering,
            movementBoundary: overlay.movementBoundary
        )
    }
}

nonisolated struct RecommendedPetProfile: Equatable, Sendable {
    let stationaryBehaviorMode: StationaryBehaviorMode
    let stationarySequenceID: String?
    let randomSequenceIDs: [String]
    let sequences: [BehaviorSequence]
    let automaticRules: [AutomaticRule]
    let automaticRulePriorityOrder: [AutomaticRuleCategory]
    let movement: PetMovementSettings
    let pettingMotionID: String?
    let speech: PetSpeechSettings
    let display: PortablePetDisplaySettings
    /// `false` only for schema-v1...v9 files, which did not contain portable
    /// display settings. Keeping the decoded defaults for summaries and
    /// re-export is useful, but applying them would overwrite unrelated local
    /// display choices that the legacy package never expressed.
    let includesDisplaySettings: Bool

    init(
        stationaryBehaviorMode: StationaryBehaviorMode,
        stationarySequenceID: String?,
        randomSequenceIDs: [String] = [],
        sequences: [BehaviorSequence],
        automaticRules: [AutomaticRule],
        automaticRulePriorityOrder: [AutomaticRuleCategory] =
            AutomaticRuleCategory.defaultPriorityOrder,
        movement: PetMovementSettings,
        pettingMotionID: String?,
        speech: PetSpeechSettings = .default,
        display: PortablePetDisplaySettings = .default,
        includesDisplaySettings: Bool = true
    ) {
        self.stationaryBehaviorMode = stationaryBehaviorMode
        self.stationarySequenceID = stationarySequenceID
        self.randomSequenceIDs = randomSequenceIDs
        self.sequences = sequences
        self.automaticRules = automaticRules
        self.automaticRulePriorityOrder = automaticRulePriorityOrder
        self.movement = movement
        self.pettingMotionID = pettingMotionID
        self.speech = speech
        self.display = display
        self.includesDisplaySettings = includesDisplaySettings
    }

    init(
        mode: BehaviorMode,
        manualSequenceID: String?,
        randomSequenceIDs: [String] = [],
        sequences: [BehaviorSequence],
        automaticRules: [AutomaticRule],
        automaticRulePriorityOrder: [AutomaticRuleCategory] =
            AutomaticRuleCategory.defaultPriorityOrder,
        movement: PetMovementSettings,
        pettingMotionID: String?,
        speech: PetSpeechSettings = .default,
        display: PortablePetDisplaySettings = .default,
        includesDisplaySettings: Bool = true
    ) {
        self.init(
            stationaryBehaviorMode: mode == .random ? .random : .fixed,
            stationarySequenceID: mode == .manual ? manualSequenceID : nil,
            randomSequenceIDs: randomSequenceIDs,
            sequences: sequences,
            automaticRules: automaticRules,
            automaticRulePriorityOrder: automaticRulePriorityOrder,
            movement: movement,
            pettingMotionID: pettingMotionID,
            speech: speech,
            display: display,
            includesDisplaySettings: includesDisplaySettings
        )
    }

    var mode: BehaviorMode {
        switch stationaryBehaviorMode {
        case .fixed:
            stationarySequenceID == nil ? .automatic : .manual
        case .random:
            .random
        }
    }

    var manualSequenceID: String? {
        stationarySequenceID
    }

    func behaviorProfile(for petKey: PetBehaviorKey) -> BehaviorProfile {
        BehaviorProfile(
            petKey: petKey,
            stationaryBehaviorMode: stationaryBehaviorMode,
            stationarySequenceID: stationarySequenceID,
            randomSequenceIDs: randomSequenceIDs,
            sequences: sequences,
            automaticRules: automaticRules,
            automaticRulePriorityOrder: automaticRulePriorityOrder,
            movement: movement,
            pettingMotionID: pettingMotionID,
            speech: speech
        )
    }
}

nonisolated enum RecommendedPetProfileError: Error, Equatable, Sendable {
    case fileTooLarge
    case unreadable
    case unsupportedSchemaVersion(Int)
    case invalidField(String)
}

extension RecommendedPetProfileError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .fileTooLarge:
            "제작자 설정 파일이 1 MiB 제한을 초과합니다."
        case .unreadable:
            "제작자 설정 파일 형식을 읽을 수 없습니다."
        case let .unsupportedSchemaVersion(version):
            "현재 앱에서 지원하지 않는 제작자 설정 버전입니다: \(version)"
        case let .invalidField(field):
            "제작자 설정 값 또는 참조가 올바르지 않습니다: \(field)"
        }
    }
}

nonisolated enum RecommendedPetProfileCodec {
    static let schemaVersion = 12
    static let maximumFileSize = 1 * 1_024 * 1_024

    static func encode(
        _ profile: RecommendedPetProfile,
        for definition: PetDefinition
    ) throws -> Data {
        let profile = normalizingCurrentProfile(profile)
        try validate(profile, for: definition)
        let stored = StoredRecommendedPetProfileV12(
            schemaVersion: schemaVersion,
            behavior: StoredRecommendedBehaviorV11(
                stationaryBehaviorMode:
                    profile.stationaryBehaviorMode.rawValue,
                stationarySequenceID: profile.stationarySequenceID,
                randomSequenceIDs: profile.randomSequenceIDs,
                sequences: profile.sequences.map { sequence in
                    StoredBehaviorSequenceV12(
                        id: sequence.id,
                        displayName: sequence.displayName,
                        steps: sequence.steps.map {
                            StoredBehaviorStepV2(
                                motionID: $0.motionID,
                                repeatCount: $0.repeatCount
                            )
                        },
                        repeats: sequence.repeats
                    )
                }
            ),
            movement: storedMovementV12(profile.movement),
            pettingBehaviorID: profile.pettingMotionID,
            automaticRules: profile.automaticRules.map(storedRule),
            automaticRulePriorityOrder:
                profile.automaticRulePriorityOrder.map(\.rawValue),
            speech: storedSpeechV7(profile.speech),
            display: StoredPortablePetDisplayV10(
                scalePercent: profile.display.scalePercent,
                clickThrough: profile.display.clickThrough,
                opacity: profile.display.opacity,
                pointerOverlapFadeEnabled:
                    profile.display.pointerOverlapFadeEnabled,
                pointerOverlapOpacity:
                    profile.display.pointerOverlapOpacity,
                pixelArtRendering: profile.display.pixelArtRendering
            )
        )

        let data: Data
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [
                .prettyPrinted,
                .sortedKeys,
                .withoutEscapingSlashes
            ]
            data = try encoder.encode(stored)
        } catch {
            throw RecommendedPetProfileError.unreadable
        }
        guard data.count <= maximumFileSize else {
            throw RecommendedPetProfileError.fileTooLarge
        }
        return data
    }

    private static func normalizingCurrentProfile(
        _ profile: RecommendedPetProfile
    ) -> RecommendedPetProfile {
        let sequenceIDs = Set(profile.sequences.map(\.id))
        let animations = [
            profile.movement.cursorFollowing.animation,
            profile.movement.freeRoaming.animation,
            profile.movement.cursorAvoiding.animation,
            profile.movement.cursorAvoiding.idleFreeRoaming.animation
        ]
        let contextIDs = animations.map(\.fallbackMotionID) + [
            profile.pettingMotionID
        ] + MovementDirection.allCases.flatMap { direction in
            animations.map { $0.directionMotionIDs[direction] }
        }
        let needsPromotion = contextIDs.compactMap { $0 }.contains {
            !sequenceIDs.contains($0)
        }
        return needsPromotion
            ? promotingContextMotionReferences(in: profile)
            : profile
    }

    static func decode(
        _ data: Data,
        for definition: PetDefinition
    ) throws -> RecommendedPetProfile {
        guard data.count <= maximumFileSize else {
            throw RecommendedPetProfileError.fileTooLarge
        }

        let decoder = JSONDecoder()
        let envelope: StoredRecommendedPetProfileEnvelope
        do {
            envelope = try decoder.decode(
                StoredRecommendedPetProfileEnvelope.self,
                from: data
            )
        } catch {
            throw RecommendedPetProfileError.unreadable
        }
        let profile: RecommendedPetProfile
        switch envelope.schemaVersion {
        case 1:
            do {
                profile = try domainProfile(
                    from: decoder.decode(
                        StoredRecommendedPetProfileV1.self,
                        from: data
                    )
                )
            } catch let error as RecommendedPetProfileError {
                throw error
            } catch {
                throw RecommendedPetProfileError.unreadable
            }
        case 2:
            do {
                profile = try domainProfile(
                    from: decoder.decode(
                        StoredRecommendedPetProfileV2.self,
                        from: data
                    )
                )
            } catch let error as RecommendedPetProfileError {
                throw error
            } catch {
                throw RecommendedPetProfileError.unreadable
            }
        case 3:
            do {
                profile = try domainProfile(
                    from: decoder.decode(
                        StoredRecommendedPetProfileV3.self,
                        from: data
                    )
                )
            } catch let error as RecommendedPetProfileError {
                throw error
            } catch {
                throw RecommendedPetProfileError.unreadable
            }
        case 4:
            do {
                profile = try domainProfile(
                    from: decoder.decode(
                        StoredRecommendedPetProfileV4.self,
                        from: data
                    )
                )
            } catch let error as RecommendedPetProfileError {
                throw error
            } catch {
                throw RecommendedPetProfileError.unreadable
            }
        case 5:
            do {
                profile = try domainProfile(
                    from: decoder.decode(
                        StoredRecommendedPetProfileV5.self,
                        from: data
                    )
                )
            } catch let error as RecommendedPetProfileError {
                throw error
            } catch {
                throw RecommendedPetProfileError.unreadable
            }
        case 6:
            do {
                profile = try domainProfile(
                    from: decoder.decode(
                        StoredRecommendedPetProfileV6.self,
                        from: data
                    )
                )
            } catch let error as RecommendedPetProfileError {
                throw error
            } catch {
                throw RecommendedPetProfileError.unreadable
            }
        case 7:
            do {
                profile = try domainProfile(
                    from: decoder.decode(
                        StoredRecommendedPetProfileV7.self,
                        from: data
                    )
                )
            } catch let error as RecommendedPetProfileError {
                throw error
            } catch {
                throw RecommendedPetProfileError.unreadable
            }
        case 8:
            do {
                profile = try domainProfile(
                    from: decoder.decode(
                        StoredRecommendedPetProfileV8.self,
                        from: data
                    )
                )
            } catch let error as RecommendedPetProfileError {
                throw error
            } catch {
                throw RecommendedPetProfileError.unreadable
            }
        case 9:
            do {
                profile = try domainProfile(
                    from: decoder.decode(
                        StoredRecommendedPetProfileV9.self,
                        from: data
                    )
                )
            } catch let error as RecommendedPetProfileError {
                throw error
            } catch {
                throw RecommendedPetProfileError.unreadable
            }
        case 10:
            do {
                profile = try domainProfile(
                    from: decoder.decode(
                        StoredRecommendedPetProfileV10.self,
                        from: data
                    )
                )
            } catch let error as RecommendedPetProfileError {
                throw error
            } catch {
                throw RecommendedPetProfileError.unreadable
            }
        case 11:
            do {
                profile = try domainProfile(
                    from: decoder.decode(
                        StoredRecommendedPetProfileV11.self,
                        from: data
                    )
                )
            } catch let error as RecommendedPetProfileError {
                throw error
            } catch {
                throw RecommendedPetProfileError.unreadable
            }
        case schemaVersion:
            do {
                profile = try domainProfile(
                    from: decoder.decode(
                        StoredRecommendedPetProfileV12.self,
                        from: data
                    )
                )
            } catch let error as RecommendedPetProfileError {
                throw error
            } catch {
                throw RecommendedPetProfileError.unreadable
            }
        default:
            throw RecommendedPetProfileError.unsupportedSchemaVersion(
                envelope.schemaVersion
            )
        }
        var normalizedProfile = envelope.schemaVersion < 10
            ? promotingContextMotionReferences(in: profile)
            : profile
        if envelope.schemaVersion < 11 {
            normalizedProfile = migratingLegacyRuleActivation(
                in: normalizedProfile
            )
        }
        if envelope.schemaVersion < 10 {
            normalizedProfile = replacingDisplayApplication(
                in: normalizedProfile,
                includesDisplaySettings: false
            )
        }
        try validate(normalizedProfile, for: definition)
        return normalizedProfile
    }

    private static func replacingDisplayApplication(
        in profile: RecommendedPetProfile,
        includesDisplaySettings: Bool
    ) -> RecommendedPetProfile {
        RecommendedPetProfile(
            stationaryBehaviorMode: profile.stationaryBehaviorMode,
            stationarySequenceID: profile.stationarySequenceID,
            randomSequenceIDs: profile.randomSequenceIDs,
            sequences: profile.sequences,
            automaticRules: profile.automaticRules,
            automaticRulePriorityOrder: profile.automaticRulePriorityOrder,
            movement: profile.movement,
            pettingMotionID: profile.pettingMotionID,
            speech: profile.speech,
            display: profile.display,
            includesDisplaySettings: includesDisplaySettings
        )
    }

    private static func migratingLegacyRuleActivation(
        in profile: RecommendedPetProfile
    ) -> RecommendedPetProfile {
        let rules = profile.mode == .automatic
            ? profile.automaticRules
            : profile.automaticRules.map { rule in
                AutomaticRule(
                    id: rule.id,
                    isEnabled: false,
                    priority: rule.priority,
                    condition: rule.condition,
                    sequenceID: rule.sequenceID
                )
            }
        return RecommendedPetProfile(
            stationaryBehaviorMode: profile.stationaryBehaviorMode,
            stationarySequenceID: profile.stationarySequenceID,
            randomSequenceIDs: profile.randomSequenceIDs,
            sequences: profile.sequences,
            automaticRules: rules,
            automaticRulePriorityOrder: profile.automaticRulePriorityOrder,
            movement: profile.movement,
            pettingMotionID: profile.pettingMotionID,
            speech: profile.speech,
            display: profile.display,
            includesDisplaySettings: profile.includesDisplaySettings
        )
    }

    private static func domainProfile(
        from stored: StoredRecommendedPetProfileV1
    ) throws -> RecommendedPetProfile {
        let mode: BehaviorMode = switch stored.behavior.mode {
        case "automatic": .automatic
        case "manual": .manual
        default:
            throw RecommendedPetProfileError.invalidField("behavior.mode")
        }

        let sequences = stored.behavior.sequences.map { sequence in
            BehaviorSequence(
                id: sequence.id,
                steps: sequence.steps.map {
                    BehaviorStep(
                        motionID: $0.motionID,
                        repeatCount: $0.repeatCount
                    )
                },
                repeats: sequence.repeats
            )
        }
        let movementMode: PetMovementMode = switch stored.movement.mode {
        case "fixed": .fixed
        case "cursorFollowing": .cursorFollowing
        case "freeRoaming": .freeRoaming
        default:
            throw RecommendedPetProfileError.invalidField("movement.mode")
        }
        let automaticRules = try stored.automaticRules.enumerated().map { index, rule in
            guard let id = UUID(uuidString: rule.id) else {
                throw RecommendedPetProfileError.invalidField(
                    "automaticRules.\(index).id"
                )
            }
            let condition: RuleCondition = switch rule.condition {
            case let .application(bundleIdentifier):
                .application(bundleIdentifier: bundleIdentifier)
            case let .idleAtLeast(milliseconds):
                .idleAtLeast(milliseconds: milliseconds)
            case let .unsupported(type):
                .unsupported(type: type)
            }
            return AutomaticRule(
                id: id,
                isEnabled: rule.isEnabled,
                priority: rule.priority,
                condition: condition,
                sequenceID: rule.sequenceID
            )
        }

        return RecommendedPetProfile(
            mode: mode,
            manualSequenceID: stored.behavior.manualSequenceID,
            sequences: sequences,
            automaticRules: automaticRules,
            movement: PetMovementSettings(
                mode: movementMode,
                speed: stored.movement.speed,
                cursorDistance: stored.movement.cursorDistance,
                stopRadius: stored.movement.stopRadius,
                freeRoamingDwellMilliseconds:
                    stored.movement.freeRoamingDwellMilliseconds,
                prefersFrontmostWindow: stored.movement.prefersFrontmostWindow,
                cursorFollowingMotionID:
                    stored.movement.cursorFollowingMotionID,
                freeRoamingMotionID: stored.movement.freeRoamingMotionID
            ),
            pettingMotionID: stored.pettingMotionID
        )
    }

    private static func domainProfile(
        from stored: StoredRecommendedPetProfileV2
    ) throws -> RecommendedPetProfile {
        let baseProfile = try domainProfile(
            from: StoredRecommendedPetProfileV1(
                schemaVersion: 1,
                behavior: stored.behavior,
                movement: StoredRecommendedMovementV1(
                    mode: stored.movement.mode,
                    speed: stored.movement.speed,
                    cursorDistance: stored.movement.cursorDistance,
                    stopRadius: stored.movement.stopRadius,
                    freeRoamingDwellMilliseconds:
                        stored.movement.freeRoamingDwellMilliseconds,
                    prefersFrontmostWindow:
                        stored.movement.prefersFrontmostWindow,
                    cursorFollowingMotionID:
                        stored.movement.cursorFollowingAnimation
                            .fallbackMotionID,
                    freeRoamingMotionID:
                        stored.movement.freeRoamingAnimation.fallbackMotionID
                ),
                pettingMotionID: stored.pettingMotionID,
                automaticRules: stored.automaticRules
            )
        )
        return RecommendedPetProfile(
            mode: baseProfile.mode,
            manualSequenceID: baseProfile.manualSequenceID,
            sequences: baseProfile.sequences,
            automaticRules: baseProfile.automaticRules,
            movement: PetMovementSettings(
                mode: baseProfile.movement.mode,
                speed: baseProfile.movement.speed,
                cursorDistance: baseProfile.movement.cursorDistance,
                stopRadius: baseProfile.movement.stopRadius,
                freeRoamingDwellMilliseconds:
                    baseProfile.movement.freeRoamingDwellMilliseconds,
                prefersFrontmostWindow:
                    baseProfile.movement.prefersFrontmostWindow,
                cursorFollowingAnimation: domainAnimation(
                    from: stored.movement.cursorFollowingAnimation
                ),
                freeRoamingAnimation: domainAnimation(
                    from: stored.movement.freeRoamingAnimation
                )
            ),
            pettingMotionID: baseProfile.pettingMotionID
        )
    }

    private static func domainProfile(
        from stored: StoredRecommendedPetProfileV3
    ) throws -> RecommendedPetProfile {
        let movementMode: PetMovementMode = switch stored.movement.mode {
        case "fixed": .fixed
        case "cursorFollowing": .cursorFollowing
        case "freeRoaming": .freeRoaming
        case "cursorAvoiding": .cursorAvoiding
        default:
            throw RecommendedPetProfileError.invalidField("movement.mode")
        }
        let baseProfile = try domainProfile(
            from: StoredRecommendedPetProfileV2(
                schemaVersion: 2,
                behavior: stored.behavior,
                movement: StoredRecommendedMovementV2(
                    mode: movementMode == .cursorAvoiding
                        ? "fixed"
                        : stored.movement.mode,
                    speed: stored.movement.speed,
                    cursorDistance: stored.movement.cursorDistance,
                    stopRadius: stored.movement.stopRadius,
                    freeRoamingDwellMilliseconds:
                        stored.movement.freeRoamingDwellMilliseconds,
                    prefersFrontmostWindow:
                        stored.movement.prefersFrontmostWindow,
                    cursorFollowingAnimation:
                        stored.movement.cursorFollowingAnimation,
                    freeRoamingAnimation:
                        stored.movement.freeRoamingAnimation
                ),
                pettingMotionID: stored.pettingMotionID,
                automaticRules: stored.automaticRules
            )
        )
        let idleBehavior: CursorAvoidingIdleBehavior =
            switch stored.movement.cursorAvoidingIdleBehavior {
            case "stationary": .stationary
            case "freeRoaming": .freeRoaming
            default:
                throw RecommendedPetProfileError.invalidField(
                    "movement.cursorAvoidingIdleBehavior"
                )
            }
        return RecommendedPetProfile(
            mode: baseProfile.mode,
            manualSequenceID: baseProfile.manualSequenceID,
            sequences: baseProfile.sequences,
            automaticRules: baseProfile.automaticRules,
            movement: PetMovementSettings(
                mode: movementMode,
                speed: baseProfile.movement.speed,
                cursorDistance: baseProfile.movement.cursorDistance,
                stopRadius: baseProfile.movement.stopRadius,
                freeRoamingDwellMilliseconds:
                    baseProfile.movement.freeRoamingDwellMilliseconds,
                prefersFrontmostWindow:
                    baseProfile.movement.prefersFrontmostWindow,
                cursorFollowingAnimation:
                    baseProfile.movement.cursorFollowingAnimation,
                freeRoamingAnimation:
                    baseProfile.movement.freeRoamingAnimation,
                cursorAvoidingIdleBehavior: idleBehavior,
                cursorAvoidingDetectionDistance:
                    stored.movement.cursorAvoidingDetectionDistance,
                cursorAvoidingSpeed:
                    stored.movement.cursorAvoidingSpeed,
                cursorAvoidingAnimation: domainAnimation(
                    from: stored.movement.cursorAvoidingAnimation
                )
            ),
            pettingMotionID: baseProfile.pettingMotionID
        )
    }

    private static func domainProfile(
        from stored: StoredRecommendedPetProfileV4
    ) throws -> RecommendedPetProfile {
        let baseProfile = try domainProfile(
            from: StoredRecommendedPetProfileV3(
                schemaVersion: 3,
                behavior: stored.behavior,
                movement: stored.movement,
                pettingMotionID: stored.pettingMotionID,
                automaticRules: stored.automaticRules
            )
        )
        let phrases = try stored.speech.phrases.enumerated().map {
            index,
            phrase -> PetSpeechPhrase in
            guard let id = UUID(uuidString: phrase.id) else {
                throw RecommendedPetProfileError.invalidField(
                    "speech.phrases.\(index).id"
                )
            }
            let trigger: PetSpeechTrigger = switch phrase.trigger.type {
            case "periodic":
                if phrase.trigger.sequenceID == nil {
                    .periodic
                } else {
                    throw RecommendedPetProfileError.invalidField(
                        "speech.phrases.\(index).trigger"
                    )
                }
            case "sequence":
                if let sequenceID = phrase.trigger.sequenceID {
                    .sequence(sequenceID)
                } else {
                    throw RecommendedPetProfileError.invalidField(
                        "speech.phrases.\(index).trigger"
                    )
                }
            default:
                throw RecommendedPetProfileError.invalidField(
                    "speech.phrases.\(index).trigger"
                )
            }
            return PetSpeechPhrase(
                id: id,
                text: phrase.text,
                displayDurationMilliseconds:
                    phrase.displayDurationMilliseconds,
                trigger: trigger
            )
        }
        return RecommendedPetProfile(
            mode: baseProfile.mode,
            manualSequenceID: baseProfile.manualSequenceID,
            sequences: baseProfile.sequences,
            automaticRules: baseProfile.automaticRules,
            movement: baseProfile.movement,
            pettingMotionID: baseProfile.pettingMotionID,
            speech: PetSpeechSettings(
                isEnabled: stored.speech.isEnabled,
                periodicIsEnabled: phrases.contains {
                    $0.trigger == .periodic
                },
                periodicIntervalMilliseconds:
                    stored.speech.periodicIntervalMilliseconds,
                periodicOrder: .random,
                behaviorChangePolicy: .dismiss,
                phrases: phrases
            )
        )
    }

    private static func domainProfile(
        from stored: StoredRecommendedPetProfileV5
    ) throws -> RecommendedPetProfile {
        let baseProfile = try domainProfile(
            from: StoredRecommendedPetProfileV4(
                schemaVersion: 4,
                behavior: stored.behavior,
                movement: stored.movement,
                pettingMotionID: stored.pettingMotionID,
                automaticRules: stored.automaticRules,
                speech: StoredRecommendedSpeechV4(
                    isEnabled: stored.speech.isEnabled,
                    periodicIntervalMilliseconds:
                        stored.speech.periodicIntervalMilliseconds,
                    phrases: stored.speech.phrases
                )
            )
        )
        return RecommendedPetProfile(
            mode: baseProfile.mode,
            manualSequenceID: baseProfile.manualSequenceID,
            sequences: baseProfile.sequences,
            automaticRules: baseProfile.automaticRules,
            movement: baseProfile.movement,
            pettingMotionID: baseProfile.pettingMotionID,
            speech: PetSpeechSettings(
                isEnabled: baseProfile.speech.isEnabled,
                periodicIsEnabled:
                    baseProfile.speech.periodicIsEnabled,
                periodicIntervalMilliseconds:
                    baseProfile.speech.periodicIntervalMilliseconds,
                periodicOrder: .random,
                behaviorChangePolicy: .dismiss,
                phrases: baseProfile.speech.phrases,
                theme: try domainTheme(from: stored.speech.theme)
            )
        )
    }

    private static func domainProfile(
        from stored: StoredRecommendedPetProfileV6
    ) throws -> RecommendedPetProfile {
        let baseProfile = try domainProfile(
            from: StoredRecommendedPetProfileV5(
                schemaVersion: 5,
                behavior: stored.behavior,
                movement: stored.movement,
                pettingMotionID: stored.pettingMotionID,
                automaticRules: stored.automaticRules,
                speech: StoredRecommendedSpeechV5(
                    isEnabled: stored.speech.isEnabled,
                    periodicIntervalMilliseconds:
                        stored.speech.periodicIntervalMilliseconds,
                    phrases: stored.speech.phrases.map {
                        StoredRecommendedSpeechPhraseV4(
                            id: $0.id,
                            text: $0.text,
                            displayDurationMilliseconds:
                                $0.displayDurationMilliseconds,
                            trigger: $0.trigger
                        )
                    },
                    theme: stored.speech.theme
                )
            )
        )
        let periodicOrder: PetSpeechPeriodicOrder =
            switch stored.speech.periodicOrder {
            case "random": .random
            case "sequential": .sequential
            default:
                throw RecommendedPetProfileError.invalidField(
                    "speech.periodicOrder"
                )
            }
        let behaviorChangePolicy: PetSpeechBehaviorChangePolicy =
            switch stored.speech.behaviorChangePolicy {
            case "dismiss": .dismiss
            case "keep": .keep
            default:
                throw RecommendedPetProfileError.invalidField(
                    "speech.behaviorChangePolicy"
                )
            }
        let displayModes = try stored.speech.phrases.enumerated().map {
            index,
            phrase -> PetSpeechDisplayMode in
            switch phrase.displayMode {
            case "timed":
                .timed
            case "untilNextPhrase":
                .untilNextPhrase
            default:
                throw RecommendedPetProfileError.invalidField(
                    "speech.phrases.\(index).displayMode"
                )
            }
        }
        let phrases = zip(baseProfile.speech.phrases, displayModes).map {
            phrase,
            displayMode in
            PetSpeechPhrase(
                id: phrase.id,
                text: phrase.text,
                displayDurationMilliseconds:
                    phrase.displayDurationMilliseconds,
                trigger: phrase.trigger,
                displayMode: displayMode
            )
        }
        return RecommendedPetProfile(
            mode: baseProfile.mode,
            manualSequenceID: baseProfile.manualSequenceID,
            sequences: baseProfile.sequences,
            automaticRules: baseProfile.automaticRules,
            movement: baseProfile.movement,
            pettingMotionID: baseProfile.pettingMotionID,
            speech: PetSpeechSettings(
                isEnabled: baseProfile.speech.isEnabled,
                periodicIsEnabled: stored.speech.periodicIsEnabled,
                periodicIntervalMilliseconds:
                    baseProfile.speech.periodicIntervalMilliseconds,
                periodicOrder: periodicOrder,
                behaviorChangePolicy: behaviorChangePolicy,
                phrases: phrases,
                theme: baseProfile.speech.theme
            )
        )
    }

    private static func domainProfile(
        from stored: StoredRecommendedPetProfileV7
    ) throws -> RecommendedPetProfile {
        let baseProfile = try domainProfile(
            from: StoredRecommendedPetProfileV6(
                schemaVersion: 6,
                behavior: stored.behavior,
                movement: stored.movement,
                pettingMotionID: stored.pettingMotionID,
                automaticRules: stored.automaticRules,
                speech: stored.speech.base
            )
        )
        let preferredPosition: PetSpeechBubblePreferredPosition =
            switch stored.speech.placement.preferredPosition {
            case "automatic": .automatic
            case "above": .above
            case "below": .below
            default:
                throw RecommendedPetProfileError.invalidField(
                    "speech.placement.preferredPosition"
                )
            }
        let placement = PetSpeechBubblePlacementSettings(
            preferredPosition: preferredPosition,
            horizontalOffset:
                stored.speech.placement.horizontalOffset,
            gap: stored.speech.placement.gap
        )
        guard placement.isValid else {
            throw RecommendedPetProfileError.invalidField(
                "speech.placement"
            )
        }
        return RecommendedPetProfile(
            mode: baseProfile.mode,
            manualSequenceID: baseProfile.manualSequenceID,
            sequences: baseProfile.sequences,
            automaticRules: baseProfile.automaticRules,
            movement: baseProfile.movement,
            pettingMotionID: baseProfile.pettingMotionID,
            speech: PetSpeechSettings(
                isEnabled: baseProfile.speech.isEnabled,
                periodicIsEnabled:
                    baseProfile.speech.periodicIsEnabled,
                periodicIntervalMilliseconds:
                    baseProfile.speech.periodicIntervalMilliseconds,
                periodicOrder: baseProfile.speech.periodicOrder,
                behaviorChangePolicy:
                    baseProfile.speech.behaviorChangePolicy,
                phrases: baseProfile.speech.phrases,
                theme: baseProfile.speech.theme,
                placement: placement
            )
        )
    }

    private static func domainProfile(
        from stored: StoredRecommendedPetProfileV8
    ) throws -> RecommendedPetProfile {
        let movement = stored.movement
        let legacy = StoredRecommendedPetProfileV7(
            schemaVersion: 7,
            behavior: StoredRecommendedBehaviorV1(
                mode: stored.behavior.mode,
                manualSequenceID: stored.behavior.manualSequenceID,
                sequences: stored.behavior.sequences.map { sequence in
                    StoredRecommendedBehaviorSequenceV1(
                        id: sequence.id,
                        steps: sequence.steps.map {
                            StoredRecommendedBehaviorStepV1(
                                motionID: $0.motionID,
                                repeatCount: $0.repeatCount
                            )
                        },
                        repeats: sequence.repeats
                    )
                }
            ),
            movement: StoredRecommendedMovementV3(
                mode: movement.mode,
                speed: movement.speed,
                cursorDistance: movement.cursorDistance,
                stopRadius: movement.stopRadius,
                freeRoamingDwellMilliseconds:
                    movement.freeRoamingDwellMilliseconds,
                prefersFrontmostWindow: movement.prefersFrontmostWindow,
                cursorFollowingAnimation: legacyAnimation(
                    movement.cursorFollowingBehavior
                ),
                freeRoamingAnimation: legacyAnimation(
                    movement.freeRoamingBehavior
                ),
                cursorAvoidingIdleBehavior:
                    movement.cursorAvoidingIdleBehavior,
                cursorAvoidingDetectionDistance:
                    movement.cursorAvoidingDetectionDistance,
                cursorAvoidingSpeed: movement.cursorAvoidingSpeed,
                cursorAvoidingAnimation: legacyAnimation(
                    movement.cursorAvoidingBehavior
                )
            ),
            pettingMotionID: stored.pettingBehaviorID,
            automaticRules: stored.automaticRules,
            speech: stored.speech
        )
        let base = try domainProfile(from: legacy)
        var displayNames: [String: String] = [:]
        for sequence in stored.behavior.sequences
            where displayNames[sequence.id] == nil {
            displayNames[sequence.id] = sequence.displayName
        }
        let priorityOrder = try decodedPriorityOrder(
            stored.automaticRulePriorityOrder
        )
        return RecommendedPetProfile(
            mode: base.mode,
            manualSequenceID: base.manualSequenceID,
            sequences: base.sequences.map { sequence in
                BehaviorSequence(
                    id: sequence.id,
                    displayName: displayNames[sequence.id],
                    steps: sequence.steps,
                    repeats: sequence.repeats
                )
            },
            automaticRules: base.automaticRules,
            automaticRulePriorityOrder: priorityOrder,
            movement: base.movement,
            pettingMotionID: base.pettingMotionID,
            speech: base.speech
        )
    }

    private static func domainProfile(
        from stored: StoredRecommendedPetProfileV9
    ) throws -> RecommendedPetProfile {
        let mode: BehaviorMode = switch stored.behavior.mode {
        case "automatic": .automatic
        case "manual": .manual
        case "random": .random
        default:
            throw RecommendedPetProfileError.invalidField("behavior.mode")
        }
        let movement = stored.movement
        let legacy = StoredRecommendedPetProfileV8(
            schemaVersion: 8,
            behavior: StoredRecommendedBehaviorV8(
                mode: mode == .random ? "automatic" : stored.behavior.mode,
                manualSequenceID: stored.behavior.manualSequenceID,
                sequences: stored.behavior.sequences
            ),
            movement: StoredPetMovementSettingsV12(
                mode: movement.mode,
                speed: movement.speed,
                cursorDistance: movement.cursorDistance,
                stopRadius: movement.stopRadius,
                freeRoamingDwellMilliseconds:
                    movement.freeRoamingDwellMilliseconds,
                prefersFrontmostWindow: movement.prefersFrontmostWindow,
                cursorFollowingBehavior:
                    movement.cursorFollowingBehavior,
                freeRoamingBehavior: movement.freeRoamingBehavior,
                cursorAvoidingIdleBehavior:
                    movement.cursorAvoidingIdleBehavior,
                cursorAvoidingDetectionDistance:
                    movement.cursorAvoidingDetectionDistance,
                cursorAvoidingSpeed: movement.cursorAvoidingSpeed,
                cursorAvoidingBehavior: movement.cursorAvoidingBehavior
            ),
            pettingBehaviorID: stored.pettingBehaviorID,
            automaticRules: stored.automaticRules,
            automaticRulePriorityOrder:
                stored.automaticRulePriorityOrder,
            speech: stored.speech
        )
        let base = try domainProfile(from: legacy)
        return RecommendedPetProfile(
            mode: mode,
            manualSequenceID: base.manualSequenceID,
            randomSequenceIDs: stored.behavior.randomSequenceIDs,
            sequences: base.sequences,
            automaticRules: base.automaticRules,
            automaticRulePriorityOrder:
                base.automaticRulePriorityOrder,
            movement: PetMovementSettings(
                mode: base.movement.mode,
                speed: base.movement.speed,
                cursorDistance: base.movement.cursorDistance,
                stopRadius: base.movement.stopRadius,
                freeRoamingDwellMilliseconds:
                    movement.freeRoamingDwellMilliseconds,
                prefersFrontmostWindow:
                    base.movement.prefersFrontmostWindow,
                cursorFollowingAnimation:
                    base.movement.cursorFollowingAnimation,
                freeRoamingAnimation:
                    base.movement.freeRoamingAnimation,
                cursorAvoidingIdleBehavior:
                    base.movement.cursorAvoidingIdleBehavior,
                cursorAvoidingDetectionDistance:
                    base.movement.cursorAvoidingDetectionDistance,
                cursorAvoidingSpeed: base.movement.cursorAvoidingSpeed,
                cursorAvoidingAnimation:
                    base.movement.cursorAvoidingAnimation,
                randomizesFreeRoamingDwell:
                    movement.randomizesFreeRoamingDwell,
                freeRoamingDwellMinimumMilliseconds:
                    movement.freeRoamingDwellMinimumMilliseconds
            ),
            pettingMotionID: base.pettingMotionID,
            speech: base.speech
        )
    }

    private static func domainProfile(
        from stored: StoredRecommendedPetProfileV10
    ) throws -> RecommendedPetProfile {
        let movement = stored.movement
        let roaming = movement.freeRoaming
        let following = movement.cursorFollowing
        let avoiding = movement.cursorAvoiding
        let legacy = StoredRecommendedPetProfileV9(
            schemaVersion: 9,
            behavior: stored.behavior,
            movement: StoredPetMovementSettingsV13(
                mode: movement.mode,
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
            pettingBehaviorID: stored.pettingBehaviorID,
            automaticRules: stored.automaticRules,
            automaticRulePriorityOrder:
                stored.automaticRulePriorityOrder,
            speech: stored.speech
        )
        let base = try domainProfile(from: legacy)
        let independentMovement = PetMovementSettings(
            mode: base.movement.mode,
            cursorFollowing: CursorFollowingMovementSettings(
                speed: following.speed,
                cursorDistance: following.cursorDistance,
                stopRadius: following.stopRadius,
                animation: domainAnimation(
                    from: legacyAnimation(following.behavior)
                )
            ),
            freeRoaming: domainRoamingV10(roaming),
            cursorAvoiding: CursorAvoidingMovementSettings(
                idleBehavior: avoiding.idleBehavior == "freeRoaming"
                    ? .freeRoaming
                    : .stationary,
                detectionDistance: avoiding.detectionDistance,
                speed: avoiding.speed,
                stopRadius: avoiding.stopRadius,
                animation: domainAnimation(
                    from: legacyAnimation(avoiding.behavior)
                ),
                idleFreeRoaming: domainRoamingV10(
                    avoiding.idleFreeRoaming
                )
            )
        )
        let display = PortablePetDisplaySettings(
            scalePercent: stored.display.scalePercent,
            clickThrough: stored.display.clickThrough,
            opacity: stored.display.opacity,
            pointerOverlapFadeEnabled:
                stored.display.pointerOverlapFadeEnabled,
            pointerOverlapOpacity: stored.display.pointerOverlapOpacity,
            pixelArtRendering: stored.display.pixelArtRendering
        )
        return RecommendedPetProfile(
            mode: base.mode,
            manualSequenceID: base.manualSequenceID,
            randomSequenceIDs: base.randomSequenceIDs,
            sequences: base.sequences,
            automaticRules: base.automaticRules,
            automaticRulePriorityOrder:
                base.automaticRulePriorityOrder,
            movement: independentMovement,
            pettingMotionID: base.pettingMotionID,
            speech: base.speech,
            display: display
        )
    }

    private static func domainProfile(
        from stored: StoredRecommendedPetProfileV11
    ) throws -> RecommendedPetProfile {
        let legacyMode: String
        switch stored.behavior.stationaryBehaviorMode {
        case StationaryBehaviorMode.fixed.rawValue:
            legacyMode = stored.behavior.stationarySequenceID == nil
                ? BehaviorMode.automatic.rawValue
                : BehaviorMode.manual.rawValue
        case StationaryBehaviorMode.random.rawValue:
            legacyMode = BehaviorMode.random.rawValue
        default:
            throw RecommendedPetProfileError.invalidField(
                "behavior.stationaryBehaviorMode"
            )
        }
        let base = try domainProfile(
            from: StoredRecommendedPetProfileV10(
                schemaVersion: 10,
                behavior: StoredRecommendedBehaviorV9(
                    mode: legacyMode,
                    manualSequenceID:
                        stored.behavior.stationarySequenceID,
                    randomSequenceIDs:
                        stored.behavior.randomSequenceIDs,
                    sequences: stored.behavior.sequences
                ),
                movement: stored.movement,
                pettingBehaviorID: stored.pettingBehaviorID,
                automaticRules: stored.automaticRules,
                automaticRulePriorityOrder:
                    stored.automaticRulePriorityOrder,
                speech: stored.speech,
                display: stored.display
            )
        )
        return RecommendedPetProfile(
            stationaryBehaviorMode:
                stored.behavior.stationaryBehaviorMode == "random"
                    ? .random : .fixed,
            stationarySequenceID: stored.behavior.stationarySequenceID,
            randomSequenceIDs: base.randomSequenceIDs,
            sequences: base.sequences,
            automaticRules: base.automaticRules,
            automaticRulePriorityOrder:
                base.automaticRulePriorityOrder,
            movement: base.movement,
            pettingMotionID: base.pettingMotionID,
            speech: base.speech,
            display: base.display,
            includesDisplaySettings: true
        )
    }

    private static func domainProfile(
        from stored: StoredRecommendedPetProfileV12
    ) throws -> RecommendedPetProfile {
        let base = try domainProfile(
            from: StoredRecommendedPetProfileV11(
                schemaVersion: 11,
                behavior: stored.behavior,
                movement: legacyMovementV12(stored.movement),
                pettingBehaviorID: stored.pettingBehaviorID,
                automaticRules: stored.automaticRules,
                automaticRulePriorityOrder:
                    stored.automaticRulePriorityOrder,
                speech: stored.speech,
                display: stored.display
            )
        )
        return RecommendedPetProfile(
            stationaryBehaviorMode: base.stationaryBehaviorMode,
            stationarySequenceID: base.stationarySequenceID,
            randomSequenceIDs: base.randomSequenceIDs,
            sequences: base.sequences,
            automaticRules: base.automaticRules,
            automaticRulePriorityOrder:
                base.automaticRulePriorityOrder,
            movement: try domainMovementV12(stored.movement),
            pettingMotionID: base.pettingMotionID,
            speech: base.speech,
            display: base.display,
            includesDisplaySettings: true
        )
    }

    private static func domainMovementV12(
        _ stored: StoredPetMovementSettingsV16
    ) throws -> PetMovementSettings {
        guard let mode = movementMode(stored.mode),
              let roaming = domainRoamingV12(stored.freeRoaming),
              let idleRoaming = domainRoamingV12(
                  stored.cursorAvoiding.idleFreeRoaming
              ) else {
            throw RecommendedPetProfileError.invalidField("movement")
        }
        let movement = PetMovementSettings(
            mode: mode,
            cursorFollowing: CursorFollowingMovementSettings(
                speed: stored.cursorFollowing.speed,
                cursorDistance: stored.cursorFollowing.cursorDistance,
                stopRadius: stored.cursorFollowing.stopRadius,
                animation: domainAnimation(
                    from: legacyAnimation(stored.cursorFollowing.behavior)
                )
            ),
            freeRoaming: roaming,
            cursorAvoiding: CursorAvoidingMovementSettings(
                idleBehavior: stored.cursorAvoiding.idleBehavior
                    == "freeRoaming" ? .freeRoaming : .stationary,
                detectionDistance:
                    stored.cursorAvoiding.detectionDistance,
                speed: stored.cursorAvoiding.speed,
                stopRadius: stored.cursorAvoiding.stopRadius,
                animation: domainAnimation(
                    from: legacyAnimation(stored.cursorAvoiding.behavior)
                ),
                idleFreeRoaming: idleRoaming
            )
        )
        guard movement.isValid else {
            throw RecommendedPetProfileError.invalidField("movement")
        }
        return movement
    }

    private static func domainRoamingV12(
        _ stored: StoredFreeRoamingMovementSettingsV16
    ) -> FreeRoamingMovementSettings? {
        guard let mode = FreeRoamingDwellMode(rawValue: stored.dwellMode)
        else {
            return nil
        }
        return FreeRoamingMovementSettings(
            speed: stored.speed,
            stopRadius: stored.stopRadius,
            dwellMilliseconds: stored.dwellMilliseconds,
            dwellMinimumMilliseconds: stored.dwellMinimumMilliseconds,
            prefersFrontmostWindow: stored.prefersFrontmostWindow,
            animation: domainAnimation(
                from: legacyAnimation(stored.behavior)
            ),
            dwellMode: mode
        )
    }

    private static func legacyMovementV12(
        _ stored: StoredPetMovementSettingsV16
    ) -> StoredPetMovementSettingsV14 {
        StoredPetMovementSettingsV14(
            mode: stored.mode,
            cursorFollowing: stored.cursorFollowing,
            freeRoaming: legacyRoamingV12(stored.freeRoaming),
            cursorAvoiding: StoredCursorAvoidingMovementSettingsV14(
                idleBehavior: stored.cursorAvoiding.idleBehavior,
                detectionDistance:
                    stored.cursorAvoiding.detectionDistance,
                speed: stored.cursorAvoiding.speed,
                stopRadius: stored.cursorAvoiding.stopRadius,
                behavior: stored.cursorAvoiding.behavior,
                idleFreeRoaming: legacyRoamingV12(
                    stored.cursorAvoiding.idleFreeRoaming
                )
            )
        )
    }

    private static func legacyRoamingV12(
        _ stored: StoredFreeRoamingMovementSettingsV16
    ) -> StoredFreeRoamingMovementSettingsV14 {
        StoredFreeRoamingMovementSettingsV14(
            speed: stored.speed,
            stopRadius: stored.stopRadius,
            dwellMilliseconds: stored.dwellMilliseconds,
            randomizesDwell:
                stored.dwellMode == FreeRoamingDwellMode.random.rawValue,
            dwellMinimumMilliseconds: stored.dwellMinimumMilliseconds,
            prefersFrontmostWindow: stored.prefersFrontmostWindow,
            behavior: stored.behavior
        )
    }

    private static func domainRoamingV10(
        _ stored: StoredFreeRoamingMovementSettingsV14
    ) -> FreeRoamingMovementSettings {
        FreeRoamingMovementSettings(
            speed: stored.speed,
            stopRadius: stored.stopRadius,
            dwellMilliseconds: stored.dwellMilliseconds,
            randomizesDwell: stored.randomizesDwell,
            dwellMinimumMilliseconds: stored.dwellMinimumMilliseconds,
            prefersFrontmostWindow: stored.prefersFrontmostWindow,
            animation: domainAnimation(
                from: legacyAnimation(stored.behavior)
            )
        )
    }

    private static func legacyAnimation(
        _ behavior: StoredMovementBehaviorSettingsV12
    ) -> StoredRecommendedMovementAnimationV2 {
        let directions = behavior.directionBehaviorIDs
        return StoredRecommendedMovementAnimationV2(
            fallbackMotionID: behavior.fallbackBehaviorID,
            usesDirectionalMotions: behavior.usesDirectionalBehaviors,
            usesDiagonalMotions: behavior.usesDiagonalBehaviors,
            directionMotionIDs: StoredRecommendedDirectionalMotionIDsV2(
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

    private static func promotingContextMotionReferences(
        in profile: RecommendedPetProfile
    ) -> RecommendedPetProfile {
        var sequences = profile.sequences
        var promotedIDs: [String: String] = [:]
        func behaviorID(for motionID: String?) -> String? {
            guard let motionID else { return nil }
            if let existing = promotedIDs[motionID] { return existing }
            if let existing = sequences.first(where: {
                $0.id == motionID
                    && $0.steps.count == 1
                    && $0.steps[0].motionID == motionID
                    && $0.steps[0].repeatCount == 1
            }) {
                promotedIDs[motionID] = existing.id
                return existing.id
            }
            if let existing = sequences.first(where: {
                $0.steps.count == 1
                    && $0.steps[0].motionID == motionID
                    && $0.steps[0].repeatCount == 1
            }) {
                promotedIDs[motionID] = existing.id
                return existing.id
            }
            let encoded = Data(motionID.utf8).base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
            var id = "__monglepet_motion_behavior__\(encoded)"
            var suffix = 2
            while sequences.contains(where: { $0.id == id }) {
                id = "__monglepet_motion_behavior__\(encoded)-\(suffix)"
                suffix += 1
            }
            sequences.append(
                BehaviorSequence(
                    id: id,
                    displayName: motionID,
                    steps: [BehaviorStep(motionID: motionID, repeatCount: 1)],
                    repeats: true
                )
            )
            promotedIDs[motionID] = id
            return id
        }
        func promote(
            _ animation: MovementAnimationSettings
        ) -> MovementAnimationSettings {
            var directions = DirectionalMotionIDs()
            for direction in MovementDirection.allCases {
                directions = directions.replacing(
                    direction,
                    with: behaviorID(
                        for: animation.directionMotionIDs[direction]
                    )
                )
            }
            return MovementAnimationSettings(
                fallbackMotionID: behaviorID(for: animation.fallbackMotionID),
                usesDirectionalMotions: animation.usesDirectionalMotions,
                usesDiagonalMotions: animation.usesDiagonalMotions,
                directionMotionIDs: directions
            )
        }
        func promoteRoaming(
            _ roaming: FreeRoamingMovementSettings
        ) -> FreeRoamingMovementSettings {
            FreeRoamingMovementSettings(
                speed: roaming.speed,
                stopRadius: roaming.stopRadius,
                dwellMilliseconds: roaming.dwellMilliseconds,
                randomizesDwell: roaming.randomizesDwell,
                dwellMinimumMilliseconds: roaming.dwellMinimumMilliseconds,
                prefersFrontmostWindow: roaming.prefersFrontmostWindow,
                animation: promote(roaming.animation)
            )
        }
        let movement = PetMovementSettings(
            mode: profile.movement.mode,
            cursorFollowing: CursorFollowingMovementSettings(
                speed: profile.movement.cursorFollowing.speed,
                cursorDistance:
                    profile.movement.cursorFollowing.cursorDistance,
                stopRadius: profile.movement.cursorFollowing.stopRadius,
                animation: promote(
                    profile.movement.cursorFollowing.animation
                )
            ),
            freeRoaming: promoteRoaming(profile.movement.freeRoaming),
            cursorAvoiding: CursorAvoidingMovementSettings(
                idleBehavior: profile.movement.cursorAvoiding.idleBehavior,
                detectionDistance:
                    profile.movement.cursorAvoiding.detectionDistance,
                speed: profile.movement.cursorAvoiding.speed,
                stopRadius: profile.movement.cursorAvoiding.stopRadius,
                animation: promote(profile.movement.cursorAvoiding.animation),
                idleFreeRoaming: promoteRoaming(
                    profile.movement.cursorAvoiding.idleFreeRoaming
                )
            )
        )
        let pettingBehaviorID = behaviorID(for: profile.pettingMotionID)
        return RecommendedPetProfile(
            mode: profile.mode,
            manualSequenceID: profile.manualSequenceID,
            randomSequenceIDs: profile.randomSequenceIDs,
            sequences: sequences,
            automaticRules: profile.automaticRules,
            automaticRulePriorityOrder: profile.automaticRulePriorityOrder,
            movement: movement,
            pettingMotionID: pettingBehaviorID,
            speech: profile.speech,
            display: profile.display,
            includesDisplaySettings: profile.includesDisplaySettings
        )
    }

    private static func priorityOrder(
        for rules: [AutomaticRule]
    ) -> [AutomaticRuleCategory] {
        let idle = rules.filter { $0.category == .idle }.map(\.priority).max()
            ?? Int.min
        let application = rules.filter { $0.category == .application }
            .map(\.priority).max() ?? Int.min
        return idle >= application
            ? [.movement, .idle, .application]
            : [.movement, .application, .idle]
    }

    private static func decodedPriorityOrder(
        _ values: [String]
    ) throws -> [AutomaticRuleCategory] {
        let parsed = values.compactMap(AutomaticRuleCategory.init(rawValue:))
        guard parsed.count == values.count,
              Set(parsed).count == parsed.count else {
            throw RecommendedPetProfileError.invalidField(
                "automaticRulePriorityOrder"
            )
        }

        let parsedSet = Set(parsed)
        let legacySet: Set<AutomaticRuleCategory> = [.idle, .application]
        if parsedSet == legacySet {
            return [.movement] + parsed
        }
        guard parsedSet == Set(AutomaticRuleCategory.allCases) else {
            throw RecommendedPetProfileError.invalidField(
                "automaticRulePriorityOrder"
            )
        }
        return parsed
    }

    private static func domainTheme(
        from stored: StoredRecommendedSpeechThemeV5
    ) throws -> PetSpeechBubbleTheme {
        let colorStyle: PetSpeechBubbleColorStyle =
            switch stored.colorStyle {
            case "system": .system
            case "cream": .cream
            case "midnight": .midnight
            case "mint": .mint
            case "peach": .peach
            case "custom": .custom
            default:
                throw RecommendedPetProfileError.invalidField(
                    "speech.theme.colorStyle"
                )
            }
        let tailAlignment: PetSpeechBubbleTailAlignment =
            switch stored.tailAlignment {
            case "leading": .leading
            case "center": .center
            case "trailing": .trailing
            default:
                throw RecommendedPetProfileError.invalidField(
                    "speech.theme.tailAlignment"
                )
            }
        let theme = PetSpeechBubbleTheme(
            colorStyle: colorStyle,
            customBackgroundColor: PetSpeechColor(
                red: stored.customBackgroundColor.red,
                green: stored.customBackgroundColor.green,
                blue: stored.customBackgroundColor.blue
            ),
            customTextColor: PetSpeechColor(
                red: stored.customTextColor.red,
                green: stored.customTextColor.green,
                blue: stored.customTextColor.blue
            ),
            backgroundOpacity: stored.backgroundOpacity,
            fontSize: stored.fontSize,
            contentPadding: stored.contentPadding,
            cornerRadius: stored.cornerRadius,
            showsTail: stored.showsTail,
            tailAlignment: tailAlignment
        )
        guard theme.isValid else {
            throw RecommendedPetProfileError.invalidField("speech.theme")
        }
        return theme
    }

    private static func domainAnimation(
        from stored: StoredRecommendedMovementAnimationV2
    ) -> MovementAnimationSettings {
        MovementAnimationSettings(
            fallbackMotionID: stored.fallbackMotionID,
            usesDirectionalMotions: stored.usesDirectionalMotions,
            usesDiagonalMotions: stored.usesDiagonalMotions,
            directionMotionIDs: DirectionalMotionIDs(
                left: stored.directionMotionIDs.left,
                right: stored.directionMotionIDs.right,
                up: stored.directionMotionIDs.up,
                down: stored.directionMotionIDs.down,
                upLeft: stored.directionMotionIDs.upLeft,
                upRight: stored.directionMotionIDs.upRight,
                downLeft: stored.directionMotionIDs.downLeft,
                downRight: stored.directionMotionIDs.downRight
            )
        )
    }

    private static func validate(
        _ profile: RecommendedPetProfile,
        for definition: PetDefinition
    ) throws {
        guard
            !profile.sequences.isEmpty,
            profile.sequences.count <= AppSettingsLimits.maximumSequences
        else {
            throw RecommendedPetProfileError.invalidField("behavior.sequences")
        }

        var sequenceIDs: Set<String> = []
        for (sequenceIndex, sequence) in profile.sequences.enumerated() {
            let sequencePath = "behavior.sequences.\(sequenceIndex)"
            guard
                isNormalizedIdentifier(sequence.id),
                isNormalizedIdentifier(sequence.displayName),
                sequenceIDs.insert(sequence.id).inserted,
                !sequence.steps.isEmpty,
                sequence.steps.count <= AppSettingsLimits.maximumStepsPerSequence
            else {
                throw RecommendedPetProfileError.invalidField(sequencePath)
            }
            for (stepIndex, step) in sequence.steps.enumerated() {
                guard
                    isKnownBehaviorMotion(step.motionID, in: definition),
                    step.legacyTiming == nil,
                    (1...AppSettingsLimits.maximumRepeatCount)
                        .contains(step.repeatCount)
                else {
                    throw RecommendedPetProfileError.invalidField(
                        "\(sequencePath).steps.\(stepIndex)"
                    )
                }
            }
        }

        if let manualSequenceID = profile.manualSequenceID {
            guard
                isNormalizedIdentifier(manualSequenceID),
                sequenceIDs.contains(manualSequenceID)
            else {
                throw RecommendedPetProfileError.invalidField(
                    "behavior.manualSequenceID"
                )
            }
        } else if profile.mode == .manual {
            throw RecommendedPetProfileError.invalidField(
                "behavior.manualSequenceID"
            )
        }

        var randomIDs = Set<String>()
        for (index, sequenceID) in profile.randomSequenceIDs.enumerated() {
            guard isNormalizedIdentifier(sequenceID),
                  sequenceIDs.contains(sequenceID),
                  randomIDs.insert(sequenceID).inserted else {
                throw RecommendedPetProfileError.invalidField(
                    "behavior.randomSequenceIDs.\(index)"
                )
            }
        }

        guard profile.automaticRules.count <= AppSettingsLimits.maximumAutomaticRules else {
            throw RecommendedPetProfileError.invalidField("automaticRules")
        }
        guard
            profile.automaticRulePriorityOrder.count
                == AutomaticRuleCategory.allCases.count,
            Set(profile.automaticRulePriorityOrder)
                == Set(AutomaticRuleCategory.allCases),
            profile.automaticRules.filter({ $0.category == .idle }).count <= 1
        else {
            throw RecommendedPetProfileError.invalidField(
                "automaticRulePriorityOrder"
            )
        }
        var ruleIDs: Set<UUID> = []
        for (ruleIndex, rule) in profile.automaticRules.enumerated() {
            let rulePath = "automaticRules.\(ruleIndex)"
            guard
                ruleIDs.insert(rule.id).inserted,
                isNormalizedIdentifier(rule.sequenceID),
                sequenceIDs.contains(rule.sequenceID)
            else {
                throw RecommendedPetProfileError.invalidField(rulePath)
            }
            switch rule.condition {
            case let .application(bundleIdentifier):
                guard isNormalizedIdentifier(bundleIdentifier) else {
                    throw RecommendedPetProfileError.invalidField(
                        "\(rulePath).condition"
                    )
                }
            case let .idleAtLeast(milliseconds):
                guard
                    (1...AppSettingsLimits.maximumDurationMilliseconds)
                        .contains(milliseconds)
                else {
                    throw RecommendedPetProfileError.invalidField(
                        "\(rulePath).condition"
                    )
                }
            case .unsupported:
                throw RecommendedPetProfileError.invalidField(
                    "\(rulePath).condition"
                )
            }
        }

        guard profile.movement.isValid else {
            throw RecommendedPetProfileError.invalidField("movement")
        }
        try validateAnimation(
            profile.movement.cursorFollowing.animation,
            field: "movement.cursorFollowing.behavior",
            sequenceIDs: sequenceIDs
        )
        try validateAnimation(
            profile.movement.freeRoaming.animation,
            field: "movement.freeRoaming.behavior",
            sequenceIDs: sequenceIDs
        )
        try validateAnimation(
            profile.movement.cursorAvoiding.animation,
            field: "movement.cursorAvoiding.behavior",
            sequenceIDs: sequenceIDs
        )
        try validateAnimation(
            profile.movement.cursorAvoiding.idleFreeRoaming.animation,
            field: "movement.cursorAvoiding.idleFreeRoaming.behavior",
            sequenceIDs: sequenceIDs
        )
        try validateOptionalBehavior(
            profile.pettingMotionID,
            field: "pettingBehaviorID",
            sequenceIDs: sequenceIDs
        )
        guard profile.speech.isValid else {
            throw RecommendedPetProfileError.invalidField("speech")
        }
        guard profile.display.isValid else {
            throw RecommendedPetProfileError.invalidField("display")
        }
        for (index, phrase) in profile.speech.phrases.enumerated() {
            if case let .sequence(sequenceID) = phrase.trigger,
               !sequenceIDs.contains(sequenceID) {
                throw RecommendedPetProfileError.invalidField(
                    "speech.phrases.\(index).trigger"
                )
            }
        }
    }

    private static func validateAnimation(
        _ animation: MovementAnimationSettings,
        field: String,
        sequenceIDs: Set<String>
    ) throws {
        guard animation.isValid else {
            throw RecommendedPetProfileError.invalidField(field)
        }
        try validateOptionalBehavior(
            animation.fallbackMotionID,
            field: "\(field).fallbackMotionID",
            sequenceIDs: sequenceIDs
        )
        for direction in MovementDirection.allCases {
            try validateOptionalBehavior(
                animation.directionMotionIDs[direction],
                field: "\(field).directionMotionIDs.\(direction.rawValue)",
                sequenceIDs: sequenceIDs
            )
        }
    }

    private static func validateOptionalBehavior(
        _ behaviorID: String?,
        field: String,
        sequenceIDs: Set<String>
    ) throws {
        guard let behaviorID else { return }
        guard isNormalizedIdentifier(behaviorID),
              sequenceIDs.contains(behaviorID) else {
            throw RecommendedPetProfileError.invalidField(field)
        }
    }

    private static func validateOptionalMotion(
        _ motionID: String?,
        field: String,
        definition: PetDefinition
    ) throws {
        guard let motionID else {
            return
        }
        guard isConcreteMotion(motionID, in: definition) else {
            throw RecommendedPetProfileError.invalidField(field)
        }
    }

    private static func isKnownBehaviorMotion(
        _ motionID: String,
        in definition: PetDefinition
    ) -> Bool {
        motionID == PetMotionReference.currentPetDefault
            || isConcreteMotion(motionID, in: definition)
    }

    private static func isConcreteMotion(
        _ motionID: String,
        in definition: PetDefinition
    ) -> Bool {
        isNormalizedIdentifier(motionID)
            && definition.motion(id: motionID) != nil
    }

    private static func isNormalizedIdentifier(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed == value
    }

    private static func storedMode(_ mode: BehaviorMode) -> String {
        switch mode {
        case .automatic: "automatic"
        case .manual: "manual"
        case .random: "random"
        }
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

    private static func storedMovement(
        _ movement: PetMovementSettings
    ) -> StoredRecommendedMovementV3 {
        let mode: String = switch movement.mode {
        case .fixed: "fixed"
        case .cursorFollowing: "cursorFollowing"
        case .freeRoaming: "freeRoaming"
        case .cursorAvoiding: "cursorAvoiding"
        }
        return StoredRecommendedMovementV3(
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

    private static func storedMovementV8(
        _ movement: PetMovementSettings
    ) -> StoredPetMovementSettingsV12 {
        let legacy = storedMovement(movement)
        return StoredPetMovementSettingsV12(
            mode: legacy.mode,
            speed: legacy.speed,
            cursorDistance: legacy.cursorDistance,
            stopRadius: legacy.stopRadius,
            freeRoamingDwellMilliseconds:
                legacy.freeRoamingDwellMilliseconds,
            prefersFrontmostWindow: legacy.prefersFrontmostWindow,
            cursorFollowingBehavior: storedBehaviorV8(
                legacy.cursorFollowingAnimation
            ),
            freeRoamingBehavior: storedBehaviorV8(
                legacy.freeRoamingAnimation
            ),
            cursorAvoidingIdleBehavior:
                legacy.cursorAvoidingIdleBehavior,
            cursorAvoidingDetectionDistance:
                legacy.cursorAvoidingDetectionDistance,
            cursorAvoidingSpeed: legacy.cursorAvoidingSpeed,
            cursorAvoidingBehavior: storedBehaviorV8(
                legacy.cursorAvoidingAnimation
            )
        )
    }

    private static func storedMovementV9(
        _ movement: PetMovementSettings
    ) -> StoredPetMovementSettingsV13 {
        let legacy = storedMovementV8(movement)
        return StoredPetMovementSettingsV13(
            mode: legacy.mode,
            speed: legacy.speed,
            cursorDistance: legacy.cursorDistance,
            stopRadius: legacy.stopRadius,
            freeRoamingDwellMilliseconds:
                legacy.freeRoamingDwellMilliseconds,
            randomizesFreeRoamingDwell:
                movement.randomizesFreeRoamingDwell,
            freeRoamingDwellMinimumMilliseconds:
                movement.freeRoamingDwellMinimumMilliseconds,
            prefersFrontmostWindow: legacy.prefersFrontmostWindow,
            cursorFollowingBehavior: legacy.cursorFollowingBehavior,
            freeRoamingBehavior: legacy.freeRoamingBehavior,
            cursorAvoidingIdleBehavior: legacy.cursorAvoidingIdleBehavior,
            cursorAvoidingDetectionDistance:
                legacy.cursorAvoidingDetectionDistance,
            cursorAvoidingSpeed: legacy.cursorAvoidingSpeed,
            cursorAvoidingBehavior: legacy.cursorAvoidingBehavior
        )
    }

    private static func storedMovementV10(
        _ movement: PetMovementSettings
    ) -> StoredPetMovementSettingsV14 {
        let mode: String = switch movement.mode {
        case .fixed: "fixed"
        case .cursorFollowing: "cursorFollowing"
        case .freeRoaming: "freeRoaming"
        case .cursorAvoiding: "cursorAvoiding"
        }
        return StoredPetMovementSettingsV14(
            mode: mode,
            cursorFollowing: StoredCursorFollowingMovementSettingsV14(
                speed: movement.cursorFollowing.speed,
                cursorDistance: movement.cursorFollowing.cursorDistance,
                stopRadius: movement.cursorFollowing.stopRadius,
                behavior: storedBehaviorV8(
                    storedAnimation(movement.cursorFollowing.animation)
                )
            ),
            freeRoaming: storedRoamingV10(movement.freeRoaming),
            cursorAvoiding: StoredCursorAvoidingMovementSettingsV14(
                idleBehavior:
                    movement.cursorAvoiding.idleBehavior == .freeRoaming
                    ? "freeRoaming"
                    : "stationary",
                detectionDistance:
                    movement.cursorAvoiding.detectionDistance,
                speed: movement.cursorAvoiding.speed,
                stopRadius: movement.cursorAvoiding.stopRadius,
                behavior: storedBehaviorV8(
                    storedAnimation(movement.cursorAvoiding.animation)
                ),
                idleFreeRoaming: storedRoamingV10(
                    movement.cursorAvoiding.idleFreeRoaming
                )
            )
        )
    }

    private static func storedMovementV12(
        _ movement: PetMovementSettings
    ) -> StoredPetMovementSettingsV16 {
        let legacy = storedMovementV10(movement)
        return StoredPetMovementSettingsV16(
            mode: legacy.mode,
            cursorFollowing: legacy.cursorFollowing,
            freeRoaming: storedRoamingV12(movement.freeRoaming),
            cursorAvoiding: StoredCursorAvoidingMovementSettingsV16(
                idleBehavior: legacy.cursorAvoiding.idleBehavior,
                detectionDistance:
                    legacy.cursorAvoiding.detectionDistance,
                speed: legacy.cursorAvoiding.speed,
                stopRadius: legacy.cursorAvoiding.stopRadius,
                behavior: legacy.cursorAvoiding.behavior,
                idleFreeRoaming: storedRoamingV12(
                    movement.cursorAvoiding.idleFreeRoaming
                )
            )
        )
    }

    private static func storedRoamingV12(
        _ roaming: FreeRoamingMovementSettings
    ) -> StoredFreeRoamingMovementSettingsV16 {
        StoredFreeRoamingMovementSettingsV16(
            speed: roaming.speed,
            stopRadius: roaming.stopRadius,
            dwellMode: roaming.dwellMode.rawValue,
            dwellMilliseconds: roaming.dwellMilliseconds,
            dwellMinimumMilliseconds: roaming.dwellMinimumMilliseconds,
            prefersFrontmostWindow: roaming.prefersFrontmostWindow,
            behavior: storedBehaviorV8(storedAnimation(roaming.animation))
        )
    }

    private static func storedRoamingV10(
        _ roaming: FreeRoamingMovementSettings
    ) -> StoredFreeRoamingMovementSettingsV14 {
        StoredFreeRoamingMovementSettingsV14(
            speed: roaming.speed,
            stopRadius: roaming.stopRadius,
            dwellMilliseconds: roaming.dwellMilliseconds,
            randomizesDwell: roaming.randomizesDwell,
            dwellMinimumMilliseconds: roaming.dwellMinimumMilliseconds,
            prefersFrontmostWindow: roaming.prefersFrontmostWindow,
            behavior: storedBehaviorV8(storedAnimation(roaming.animation))
        )
    }

    private static func storedBehaviorV8(
        _ animation: StoredRecommendedMovementAnimationV2
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

    private static func storedAnimation(
        _ animation: MovementAnimationSettings
    ) -> StoredRecommendedMovementAnimationV2 {
        let directions = animation.directionMotionIDs
        return StoredRecommendedMovementAnimationV2(
            fallbackMotionID: animation.fallbackMotionID,
            usesDirectionalMotions: animation.usesDirectionalMotions,
            usesDiagonalMotions: animation.usesDiagonalMotions,
            directionMotionIDs: StoredRecommendedDirectionalMotionIDsV2(
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

    private static func storedSequence(
        _ sequence: BehaviorSequence
    ) -> StoredRecommendedBehaviorSequenceV1 {
        StoredRecommendedBehaviorSequenceV1(
            id: sequence.id,
            steps: sequence.steps.map {
                StoredRecommendedBehaviorStepV1(
                    motionID: $0.motionID,
                    repeatCount: $0.repeatCount
                )
            },
            repeats: sequence.repeats
        )
    }

    private static func storedRule(
        _ rule: AutomaticRule
    ) -> StoredRecommendedAutomaticRuleV1 {
        let condition: StoredRecommendedRuleConditionV1 = switch rule.condition {
        case let .application(bundleIdentifier):
            .application(bundleIdentifier: bundleIdentifier)
        case let .idleAtLeast(milliseconds):
            .idleAtLeast(milliseconds: milliseconds)
        case let .unsupported(type):
            .unsupported(type: type)
        }
        return StoredRecommendedAutomaticRuleV1(
            id: rule.id.uuidString,
            isEnabled: rule.isEnabled,
            priority: rule.priority,
            condition: condition,
            sequenceID: rule.sequenceID
        )
    }

    private static func storedSpeech(
        _ speech: PetSpeechSettings
    ) -> StoredRecommendedSpeechV6 {
        StoredRecommendedSpeechV6(
            isEnabled: speech.isEnabled,
            periodicIsEnabled: speech.periodicIsEnabled,
            periodicIntervalMilliseconds:
                speech.periodicIntervalMilliseconds,
            periodicOrder: speech.periodicOrder == .random
                ? "random"
                : "sequential",
            behaviorChangePolicy:
                speech.behaviorChangePolicy == .dismiss
                ? "dismiss"
                : "keep",
            phrases: speech.phrases.map { phrase in
                let trigger: StoredRecommendedSpeechTriggerV4 =
                    switch phrase.trigger {
                    case .periodic:
                        StoredRecommendedSpeechTriggerV4(
                            type: "periodic",
                            sequenceID: nil
                        )
                    case let .sequence(sequenceID):
                        StoredRecommendedSpeechTriggerV4(
                            type: "sequence",
                            sequenceID: sequenceID
                        )
                    }
                return StoredRecommendedSpeechPhraseV6(
                    id: phrase.id.uuidString,
                    text: phrase.text,
                    displayDurationMilliseconds:
                        phrase.displayDurationMilliseconds,
                    trigger: trigger,
                    displayMode: phrase.displayMode == .timed
                        ? "timed"
                        : "untilNextPhrase"
                )
            },
            theme: storedTheme(speech.theme)
        )
    }

    private static func storedSpeechV7(
        _ speech: PetSpeechSettings
    ) -> StoredRecommendedSpeechV7 {
        let placement = speech.placement
        let preferredPosition: String =
            switch placement.preferredPosition {
            case .automatic: "automatic"
            case .above: "above"
            case .below: "below"
            }
        return StoredRecommendedSpeechV7(
            base: storedSpeech(speech),
            placement: StoredRecommendedSpeechPlacementV7(
                preferredPosition: preferredPosition,
                horizontalOffset: placement.horizontalOffset,
                gap: placement.gap
            )
        )
    }

    private static func storedTheme(
        _ theme: PetSpeechBubbleTheme
    ) -> StoredRecommendedSpeechThemeV5 {
        let colorStyle: String = switch theme.colorStyle {
        case .system: "system"
        case .cream: "cream"
        case .midnight: "midnight"
        case .mint: "mint"
        case .peach: "peach"
        case .custom: "custom"
        }
        let tailAlignment: String = switch theme.tailAlignment {
        case .leading: "leading"
        case .center: "center"
        case .trailing: "trailing"
        }
        return StoredRecommendedSpeechThemeV5(
            colorStyle: colorStyle,
            customBackgroundColor: StoredRecommendedSpeechColorV5(
                red: theme.customBackgroundColor.red,
                green: theme.customBackgroundColor.green,
                blue: theme.customBackgroundColor.blue
            ),
            customTextColor: StoredRecommendedSpeechColorV5(
                red: theme.customTextColor.red,
                green: theme.customTextColor.green,
                blue: theme.customTextColor.blue
            ),
            backgroundOpacity: theme.backgroundOpacity,
            fontSize: theme.fontSize,
            contentPadding: theme.contentPadding,
            cornerRadius: theme.cornerRadius,
            showsTail: theme.showsTail,
            tailAlignment: tailAlignment
        )
    }
}

private nonisolated struct StoredRecommendedPetProfileEnvelope: Decodable {
    let schemaVersion: Int
}

private nonisolated struct StoredRecommendedPetProfileV1: Codable {
    let schemaVersion: Int
    let behavior: StoredRecommendedBehaviorV1
    let movement: StoredRecommendedMovementV1
    let pettingMotionID: String?
    let automaticRules: [StoredRecommendedAutomaticRuleV1]
}

private nonisolated struct StoredRecommendedPetProfileV2: Codable {
    let schemaVersion: Int
    let behavior: StoredRecommendedBehaviorV1
    let movement: StoredRecommendedMovementV2
    let pettingMotionID: String?
    let automaticRules: [StoredRecommendedAutomaticRuleV1]
}

private nonisolated struct StoredRecommendedPetProfileV3: Codable {
    let schemaVersion: Int
    let behavior: StoredRecommendedBehaviorV1
    let movement: StoredRecommendedMovementV3
    let pettingMotionID: String?
    let automaticRules: [StoredRecommendedAutomaticRuleV1]
}

private nonisolated struct StoredRecommendedPetProfileV4: Codable {
    let schemaVersion: Int
    let behavior: StoredRecommendedBehaviorV1
    let movement: StoredRecommendedMovementV3
    let pettingMotionID: String?
    let automaticRules: [StoredRecommendedAutomaticRuleV1]
    let speech: StoredRecommendedSpeechV4
}

private nonisolated struct StoredRecommendedPetProfileV5: Codable {
    let schemaVersion: Int
    let behavior: StoredRecommendedBehaviorV1
    let movement: StoredRecommendedMovementV3
    let pettingMotionID: String?
    let automaticRules: [StoredRecommendedAutomaticRuleV1]
    let speech: StoredRecommendedSpeechV5
}

private nonisolated struct StoredRecommendedPetProfileV6: Codable {
    let schemaVersion: Int
    let behavior: StoredRecommendedBehaviorV1
    let movement: StoredRecommendedMovementV3
    let pettingMotionID: String?
    let automaticRules: [StoredRecommendedAutomaticRuleV1]
    let speech: StoredRecommendedSpeechV6
}

private nonisolated struct StoredRecommendedPetProfileV7: Codable {
    let schemaVersion: Int
    let behavior: StoredRecommendedBehaviorV1
    let movement: StoredRecommendedMovementV3
    let pettingMotionID: String?
    let automaticRules: [StoredRecommendedAutomaticRuleV1]
    let speech: StoredRecommendedSpeechV7
}

private nonisolated struct StoredRecommendedPetProfileV8: Codable {
    let schemaVersion: Int
    let behavior: StoredRecommendedBehaviorV8
    let movement: StoredPetMovementSettingsV12
    let pettingBehaviorID: String?
    let automaticRules: [StoredRecommendedAutomaticRuleV1]
    let automaticRulePriorityOrder: [String]
    let speech: StoredRecommendedSpeechV7
}

private nonisolated struct StoredRecommendedBehaviorV8: Codable {
    let mode: String
    let manualSequenceID: String?
    let sequences: [StoredBehaviorSequenceV12]
}

private nonisolated struct StoredRecommendedPetProfileV9: Codable {
    let schemaVersion: Int
    let behavior: StoredRecommendedBehaviorV9
    let movement: StoredPetMovementSettingsV13
    let pettingBehaviorID: String?
    let automaticRules: [StoredRecommendedAutomaticRuleV1]
    let automaticRulePriorityOrder: [String]
    let speech: StoredRecommendedSpeechV7
}

private nonisolated struct StoredRecommendedPetProfileV10: Codable {
    let schemaVersion: Int
    let behavior: StoredRecommendedBehaviorV9
    let movement: StoredPetMovementSettingsV14
    let pettingBehaviorID: String?
    let automaticRules: [StoredRecommendedAutomaticRuleV1]
    let automaticRulePriorityOrder: [String]
    let speech: StoredRecommendedSpeechV7
    let display: StoredPortablePetDisplayV10
}

private nonisolated struct StoredRecommendedPetProfileV11: Codable {
    let schemaVersion: Int
    let behavior: StoredRecommendedBehaviorV11
    let movement: StoredPetMovementSettingsV14
    let pettingBehaviorID: String?
    let automaticRules: [StoredRecommendedAutomaticRuleV1]
    let automaticRulePriorityOrder: [String]
    let speech: StoredRecommendedSpeechV7
    let display: StoredPortablePetDisplayV10
}

private nonisolated struct StoredRecommendedPetProfileV12: Codable {
    let schemaVersion: Int
    let behavior: StoredRecommendedBehaviorV11
    let movement: StoredPetMovementSettingsV16
    let pettingBehaviorID: String?
    let automaticRules: [StoredRecommendedAutomaticRuleV1]
    let automaticRulePriorityOrder: [String]
    let speech: StoredRecommendedSpeechV7
    let display: StoredPortablePetDisplayV10
}

private nonisolated struct StoredRecommendedBehaviorV11: Codable {
    let stationaryBehaviorMode: String
    let stationarySequenceID: String?
    let randomSequenceIDs: [String]
    let sequences: [StoredBehaviorSequenceV12]
}

private nonisolated struct StoredPortablePetDisplayV10: Codable {
    let scalePercent: Double
    let clickThrough: Bool
    let opacity: Double
    let pointerOverlapFadeEnabled: Bool
    let pointerOverlapOpacity: Double
    let pixelArtRendering: Bool
}

private nonisolated struct StoredRecommendedBehaviorV9: Codable {
    let mode: String
    let manualSequenceID: String?
    let randomSequenceIDs: [String]
    let sequences: [StoredBehaviorSequenceV12]
}

private nonisolated struct StoredRecommendedSpeechV4: Codable {
    let isEnabled: Bool
    let periodicIntervalMilliseconds: Int64
    let phrases: [StoredRecommendedSpeechPhraseV4]
}

private nonisolated struct StoredRecommendedSpeechV5: Codable {
    let isEnabled: Bool
    let periodicIntervalMilliseconds: Int64
    let phrases: [StoredRecommendedSpeechPhraseV4]
    let theme: StoredRecommendedSpeechThemeV5
}

private nonisolated struct StoredRecommendedSpeechV6: Codable {
    let isEnabled: Bool
    let periodicIsEnabled: Bool
    let periodicIntervalMilliseconds: Int64
    let periodicOrder: String
    let behaviorChangePolicy: String
    let phrases: [StoredRecommendedSpeechPhraseV6]
    let theme: StoredRecommendedSpeechThemeV5
}

private nonisolated struct StoredRecommendedSpeechV7: Codable {
    let isEnabled: Bool
    let periodicIsEnabled: Bool
    let periodicIntervalMilliseconds: Int64
    let periodicOrder: String
    let behaviorChangePolicy: String
    let phrases: [StoredRecommendedSpeechPhraseV6]
    let theme: StoredRecommendedSpeechThemeV5
    let placement: StoredRecommendedSpeechPlacementV7

    init(
        base: StoredRecommendedSpeechV6,
        placement: StoredRecommendedSpeechPlacementV7
    ) {
        isEnabled = base.isEnabled
        periodicIsEnabled = base.periodicIsEnabled
        periodicIntervalMilliseconds =
            base.periodicIntervalMilliseconds
        periodicOrder = base.periodicOrder
        behaviorChangePolicy = base.behaviorChangePolicy
        phrases = base.phrases
        theme = base.theme
        self.placement = placement
    }

    var base: StoredRecommendedSpeechV6 {
        StoredRecommendedSpeechV6(
            isEnabled: isEnabled,
            periodicIsEnabled: periodicIsEnabled,
            periodicIntervalMilliseconds:
                periodicIntervalMilliseconds,
            periodicOrder: periodicOrder,
            behaviorChangePolicy: behaviorChangePolicy,
            phrases: phrases,
            theme: theme
        )
    }
}

private nonisolated struct StoredRecommendedSpeechPlacementV7:
    Codable
{
    let preferredPosition: String
    let horizontalOffset: Double
    let gap: Double
}

private nonisolated struct StoredRecommendedSpeechThemeV5: Codable {
    let colorStyle: String
    let customBackgroundColor: StoredRecommendedSpeechColorV5
    let customTextColor: StoredRecommendedSpeechColorV5
    let backgroundOpacity: Double
    let fontSize: Double
    let contentPadding: Double
    let cornerRadius: Double
    let showsTail: Bool
    let tailAlignment: String
}

private nonisolated struct StoredRecommendedSpeechColorV5: Codable {
    let red: Double
    let green: Double
    let blue: Double
}

private nonisolated struct StoredRecommendedSpeechPhraseV4: Codable {
    let id: String
    let text: String
    let displayDurationMilliseconds: Int64
    let trigger: StoredRecommendedSpeechTriggerV4
}

private nonisolated struct StoredRecommendedSpeechPhraseV6: Codable {
    let id: String
    let text: String
    let displayDurationMilliseconds: Int64
    let trigger: StoredRecommendedSpeechTriggerV4
    let displayMode: String
}

private nonisolated struct StoredRecommendedSpeechTriggerV4: Codable {
    let type: String
    let sequenceID: String?
}

private nonisolated struct StoredRecommendedBehaviorV1: Codable {
    let mode: String
    let manualSequenceID: String?
    let sequences: [StoredRecommendedBehaviorSequenceV1]
}

private nonisolated struct StoredRecommendedBehaviorSequenceV1: Codable {
    let id: String
    let steps: [StoredRecommendedBehaviorStepV1]
    let repeats: Bool
}

private nonisolated struct StoredRecommendedBehaviorStepV1: Codable {
    let motionID: String
    let repeatCount: Int
}

private nonisolated struct StoredRecommendedMovementV1: Codable {
    let mode: String
    let speed: Double
    let cursorDistance: Double
    let stopRadius: Double
    let freeRoamingDwellMilliseconds: Int64
    let prefersFrontmostWindow: Bool
    let cursorFollowingMotionID: String?
    let freeRoamingMotionID: String?
}

private nonisolated struct StoredRecommendedMovementV2: Codable {
    let mode: String
    let speed: Double
    let cursorDistance: Double
    let stopRadius: Double
    let freeRoamingDwellMilliseconds: Int64
    let prefersFrontmostWindow: Bool
    let cursorFollowingAnimation: StoredRecommendedMovementAnimationV2
    let freeRoamingAnimation: StoredRecommendedMovementAnimationV2
}

private nonisolated struct StoredRecommendedMovementV3: Codable {
    let mode: String
    let speed: Double
    let cursorDistance: Double
    let stopRadius: Double
    let freeRoamingDwellMilliseconds: Int64
    let prefersFrontmostWindow: Bool
    let cursorFollowingAnimation: StoredRecommendedMovementAnimationV2
    let freeRoamingAnimation: StoredRecommendedMovementAnimationV2
    let cursorAvoidingIdleBehavior: String
    let cursorAvoidingDetectionDistance: Double
    let cursorAvoidingSpeed: Double
    let cursorAvoidingAnimation: StoredRecommendedMovementAnimationV2
}

private nonisolated struct StoredRecommendedMovementAnimationV2: Codable {
    let fallbackMotionID: String?
    let usesDirectionalMotions: Bool
    let usesDiagonalMotions: Bool
    let directionMotionIDs: StoredRecommendedDirectionalMotionIDsV2
}

private nonisolated struct StoredRecommendedDirectionalMotionIDsV2: Codable {
    let left: String?
    let right: String?
    let up: String?
    let down: String?
    let upLeft: String?
    let upRight: String?
    let downLeft: String?
    let downRight: String?
}

private nonisolated struct StoredRecommendedAutomaticRuleV1: Codable {
    let id: String
    let isEnabled: Bool
    let priority: Int
    let condition: StoredRecommendedRuleConditionV1
    let sequenceID: String
}

private nonisolated enum StoredRecommendedRuleConditionV1: Equatable {
    case application(bundleIdentifier: String)
    case idleAtLeast(milliseconds: Int64)
    case unsupported(type: String)
}

extension StoredRecommendedRuleConditionV1: Codable {
    private enum CodingKeys: String, CodingKey {
        case type
        case bundleIdentifier
        case milliseconds
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "application":
            self = .application(
                bundleIdentifier: try container.decode(
                    String.self,
                    forKey: .bundleIdentifier
                )
            )
        case "idleAtLeast":
            self = .idleAtLeast(
                milliseconds: try container.decode(
                    Int64.self,
                    forKey: .milliseconds
                )
            )
        default:
            self = .unsupported(type: type)
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .application(bundleIdentifier):
            try container.encode("application", forKey: .type)
            try container.encode(bundleIdentifier, forKey: .bundleIdentifier)
        case let .idleAtLeast(milliseconds):
            try container.encode("idleAtLeast", forKey: .type)
            try container.encode(milliseconds, forKey: .milliseconds)
        case let .unsupported(type):
            try container.encode(type, forKey: .type)
        }
    }
}
