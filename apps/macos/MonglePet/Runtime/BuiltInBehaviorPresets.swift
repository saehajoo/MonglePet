import Foundation

nonisolated enum BuiltInBehaviorPresets {
    static let defaultSequenceID = "__monglepet_default_behavior__"
    static let defaultManualSequenceID = defaultSequenceID
    static let stepDuration: Duration = .seconds(3)

    static let sequences = [
        sequence(
            id: defaultSequenceID,
            motionID: PetMotionReference.currentPetDefault
        )
    ]

    static let automaticRules: [AutomaticRule] = []

    static let mongleSequences = [
        BehaviorSequence(
            id: defaultSequenceID,
            displayName: "기본",
            steps: [
                BehaviorStep(
                    motionID: PetMotionReference.currentPetDefault,
                    repeatCount: 1
                )
            ],
            repeats: true
        ),
        sequence(
            id: "수면 중",
            displayName: "수면 중",
            motionID: "자는 중"
        ),
        sequence(
            id: "일해라",
            displayName: "일하는 중",
            motionID: "일하는 중"
        ),
        sequence(
            id: "__monglepet_motion_behavior__67O06riA67O06riA",
            displayName: "왼쪽 보글보글",
            motionID: "왼쪽 보글보글"
        ),
        sequence(
            id: "__monglepet_motion_behavior__7Jik66W47Kq9",
            displayName: "오른쪽",
            motionID: "오른쪽"
        ),
        sequence(
            id: "__monglepet_motion_behavior__7JyE66Gc",
            displayName: "위",
            motionID: "위"
        ),
        sequence(
            id: "__monglepet_motion_behavior__7KCV66m0",
            displayName: "정면",
            motionID: "정면"
        ),
        sequence(
            id: "__monglepet_motion_behavior__7ZW07ZS8",
            displayName: "행복",
            motionID: "행복"
        ),
        sequence(
            id: "d5c7877d-8417-473a-bfac-8e41c1930ef9",
            displayName: "왼쪽",
            motionID: "왼쪽"
        ),
        sequence(
            id: "5632f8cd-246c-468f-ab32-0b61b9f84ad4",
            displayName: "아래",
            motionID: "아래"
        ),
        sequence(
            id: "14dc998c-074d-44fa-8007-14a976c506dd",
            displayName: "찾는 중",
            motionID: "찾는 중"
        ),
        sequence(
            id: "ec9bd3be-95f5-4a30-981e-d96fa6dbbea1",
            displayName: "오른쪽 보글보글",
            motionID: "오른쪽 보글보글"
        )
    ]

    static let mongleAutomaticRules = [
        AutomaticRule(
            id: UUID(uuidString: "308C8E4B-EDEA-4C71-B354-CC67532AF99C")!,
            isEnabled: true,
            priority: 1,
            condition: .idleAtLeast(milliseconds: 60_000),
            sequenceID: "수면 중"
        )
    ]

    static let mongleMovement = PetMovementSettings(
        mode: .cursorAvoiding,
        speed: 160,
        cursorDistance: 256,
        stopRadius: 16,
        freeRoamingDwellMilliseconds: 6_000,
        prefersFrontmostWindow: false,
        cursorFollowingAnimation: mongleDirectionalMovement,
        freeRoamingAnimation: mongleDirectionalMovement,
        cursorAvoidingIdleBehavior: .freeRoaming,
        cursorAvoidingDetectionDistance: 160,
        cursorAvoidingSpeed: 320,
        cursorAvoidingAnimation: mongleDirectionalMovement,
        randomizesFreeRoamingDwell: true,
        freeRoamingDwellMinimumMilliseconds: 2_000
    )

    static let monglePettingMotionID =
        "__monglepet_motion_behavior__7ZW07ZS8"
    static let mongleSpeech = PetSpeechSettings.default
    static let mongleDisplay = PortablePetDisplaySettings(
        scalePercent: 50,
        clickThrough: true,
        opacity: 1,
        pointerOverlapFadeEnabled: true,
        pointerOverlapOpacity: 0.45,
        pixelArtRendering: false
    )

    private static let mongleDirectionalMovement =
        MovementAnimationSettings(
            usesDirectionalMotions: true,
            usesDiagonalMotions: false,
            directionMotionIDs: DirectionalMotionIDs(
                left: "__monglepet_motion_behavior__67O06riA67O06riA",
                right: "ec9bd3be-95f5-4a30-981e-d96fa6dbbea1",
                up: "__monglepet_motion_behavior__7JyE66Gc",
                down: "5632f8cd-246c-468f-ab32-0b61b9f84ad4"
            )
        )

    /// The exact built-in profile shipped with Mongle 1.0.2. It is retained
    /// only so an untouched profile can be upgraded without overwriting user
    /// edits that happen to use the same pet.
    private static let publishedMongleSequencesV102 = [
        BehaviorSequence(
            id: defaultSequenceID,
            displayName: "기본",
            steps: [BehaviorStep(motionID: "정면", repeatCount: 1)],
            repeats: true
        ),
        sequence(
            id: "2042e543-058b-424b-9d33-4227ca3956a8",
            displayName: "왼쪽",
            motionID: "왼쪽"
        ),
        sequence(
            id: "47a8c5c6-a5e7-4df4-a78f-604a33134609",
            displayName: "위",
            motionID: "위"
        ),
        sequence(
            id: "664453f6-9eff-4b14-ab57-b97442f69f37",
            displayName: "일하는 중",
            motionID: "일하는 중"
        ),
        sequence(
            id: "f00ed734-81de-483a-9ff2-1ebc2ca7fbfa",
            displayName: "정면",
            motionID: "정면"
        ),
        sequence(
            id: "08436158-34b9-4553-8025-d7fa4975efe3",
            displayName: "자는 중",
            motionID: "자는 중"
        ),
        sequence(
            id: "3822f32c-f0ab-4ed9-b084-f0543cf38524",
            displayName: "물 뿜기",
            motionID: "물 뿜기"
        ),
        sequence(
            id: "5c406905-ead9-458f-8b5e-f9dbb841ed3b",
            displayName: "찾는 중",
            motionID: "찾는 중"
        ),
        sequence(
            id: "6a889c56-0907-484a-be75-02c2918a72a0",
            displayName: "해피",
            motionID: "행복"
        ),
        sequence(
            id: "7ba69d3e-3e13-447b-bf2b-6652aff980ee",
            displayName: "보글보글",
            motionID: "왼쪽 보글보글"
        ),
        sequence(
            id: "f4fc1290-702b-40cd-a38d-1e52e6817687",
            displayName: "아래",
            motionID: "아래"
        ),
        sequence(
            id: "151af796-cdad-4134-8ac6-d9284bae6a65",
            displayName: "오른쪽",
            motionID: "오른쪽"
        )
    ]

    private static let publishedMongleRulesV102 = [
        AutomaticRule(
            id: UUID(uuidString: "321BE5B6-9654-402A-8CFF-5A205577E869")!,
            isEnabled: true,
            priority: 0,
            condition: .idleAtLeast(milliseconds: 50_000),
            sequenceID: "08436158-34b9-4553-8025-d7fa4975efe3"
        )
    ]

    private static let publishedMongleDirectionalMovementV102 =
        MovementAnimationSettings(
            usesDirectionalMotions: true,
            usesDiagonalMotions: false,
            directionMotionIDs: DirectionalMotionIDs(
                left: "2042e543-058b-424b-9d33-4227ca3956a8",
                right: "151af796-cdad-4134-8ac6-d9284bae6a65",
                up: "47a8c5c6-a5e7-4df4-a78f-604a33134609",
                down: "f4fc1290-702b-40cd-a38d-1e52e6817687"
            )
        )

    private static let publishedMongleMovementV102 = PetMovementSettings(
        mode: .cursorAvoiding,
        speed: 160,
        cursorDistance: 496,
        stopRadius: 16,
        freeRoamingDwellMilliseconds: 5_000,
        prefersFrontmostWindow: false,
        cursorFollowingAnimation: publishedMongleDirectionalMovementV102,
        freeRoamingAnimation: publishedMongleDirectionalMovementV102,
        cursorAvoidingIdleBehavior: .freeRoaming,
        cursorAvoidingDetectionDistance: 152,
        cursorAvoidingSpeed: 320,
        cursorAvoidingAnimation: publishedMongleDirectionalMovementV102,
        randomizesFreeRoamingDwell: true,
        freeRoamingDwellMinimumMilliseconds: 500
    )

    private static let previousMongleSequences = [
        BehaviorSequence(
            id: defaultSequenceID,
            displayName: "기본",
            steps: [
                BehaviorStep(
                    motionID: PetMotionReference.currentPetDefault,
                    repeatCount: 1
                ),
                BehaviorStep(motionID: "물뿜기", repeatCount: 1),
                BehaviorStep(motionID: "정면", repeatCount: 1)
            ],
            repeats: true
        ),
        sequence(id: "수면 중", motionID: "자는중"),
        sequence(id: "일해라", motionID: "일하는 중"),
        sequence(id: "보글보글", motionID: "보글보글"),
        sequence(id: "오른쪽", motionID: "오른쪽"),
        sequence(id: "위로", motionID: "위로"),
        sequence(id: "정면", motionID: "정면"),
        sequence(id: "해피", motionID: "해피")
    ]

    private static let previousMongleAutomaticRules = [
        AutomaticRule(
            id: UUID(uuidString: "5C8B76B6-3C4F-4D22-86CA-8EFF77CE35F1")!,
            isEnabled: true,
            priority: 0,
            condition: .application(bundleIdentifier: "com.openai.codex"),
            sequenceID: "일해라"
        ),
        AutomaticRule(
            id: UUID(uuidString: "308C8E4B-EDEA-4C71-B354-CC67532AF99C")!,
            isEnabled: true,
            priority: 1,
            condition: .idleAtLeast(milliseconds: 60_000),
            sequenceID: "수면 중"
        )
    ]

    private static let previousMongleMovement = PetMovementSettings(
        mode: .cursorAvoiding,
        speed: 160,
        cursorDistance: 96,
        stopRadius: 16,
        freeRoamingDwellMilliseconds: 6_000,
        prefersFrontmostWindow: true,
        cursorFollowingAnimation: .default,
        freeRoamingAnimation: .default,
        cursorAvoidingIdleBehavior: .stationary,
        cursorAvoidingDetectionDistance: 160,
        cursorAvoidingSpeed: 320,
        cursorAvoidingAnimation: MovementAnimationSettings(
            fallbackMotionID: "보글보글",
            usesDirectionalMotions: true,
            usesDiagonalMotions: false,
            directionMotionIDs: DirectionalMotionIDs(
                left: "보글보글",
                right: "오른쪽",
                up: "위로",
                down: "정면"
            )
        )
    )

    private static let renamedMongleMotionIDs = [
        "위로": "위",
        "자는중": "자는 중",
        "물뿜기": "물 뿜기",
        "해피": "행복",
        "보글보글": "왼쪽 보글보글"
    ]

    static let legacySequences = [
        legacySequence(id: "idle", motionID: "idle"),
        legacySequence(id: "focus", motionID: "focus"),
        legacySequence(id: "rest", motionID: "rest"),
        legacySequence(id: "sleep", motionID: "sleep")
    ]

    static let legacyAutomaticRules = [
        AutomaticRule(
            id: UUID(uuidString: "30000000-0000-0000-0000-000000000001")!,
            isEnabled: true,
            priority: 20,
            condition: .idleAtLeast(milliseconds: 600_000),
            sequenceID: "sleep"
        ),
        AutomaticRule(
            id: UUID(uuidString: "30000000-0000-0000-0000-000000000002")!,
            isEnabled: true,
            priority: 10,
            condition: .idleAtLeast(milliseconds: 120_000),
            sequenceID: "rest"
        )
    ]

    static func configuration(for settings: AppSettings) -> BehaviorConfiguration {
        let normalizedSettings = normalizedDefaults(in: settings)
        let configuredSequences = normalizedSettings.sequences.contains(where: {
            $0.id == defaultSequenceID
        }) ? normalizedSettings.sequences : sequences + normalizedSettings.sequences

        return BehaviorConfiguration(
            stationaryBehaviorMode:
                normalizedSettings.stationaryBehaviorMode,
            defaultSequenceID: defaultSequenceID,
            stationarySequenceID:
                normalizedSettings.stationarySequenceID,
            randomSequenceIDs: normalizedSettings.randomSequenceIDs,
            sequences: configuredSequences,
            automaticRules: normalizedSettings.automaticRules,
            automaticRulePriorityOrder:
                normalizedSettings.automaticRulePriorityOrder
        )
    }

    static func normalizedDefaults(in settings: AppSettings) -> AppSettings {
        let settings = migratingBuiltInProfiles(in: settings)
        if shouldApplyMongleDefaults(to: settings) {
            let initialized = settings.replacingActiveBehaviorProfile(
                defaultProfile(for: .builtIn)
            )
            return applyingMongleDisplayToSelectedInstance(in: initialized)
        }

        let usesUnmodifiedLegacyDefaults = settings.sequences == legacySequences
            && settings.automaticRules == legacyAutomaticRules
        if usesUnmodifiedLegacyDefaults {
            return replacingDefaults(
                in: settings,
                sequences: sequences,
                automaticRules: []
            )
        }

        var normalizedSequences = settings.sequences
        if !normalizedSequences.contains(where: { $0.id == defaultSequenceID }),
           normalizedSequences.count < AppSettingsLimits.maximumSequences {
            normalizedSequences.insert(sequences[0], at: 0)
        }
        let availableIDs = Set(normalizedSequences.map(\.id))
        let normalizedStationarySequenceID = settings.stationarySequenceID.flatMap {
            availableIDs.contains($0) ? $0 : nil
        }

        return replacingDefaults(
            in: settings,
            sequences: normalizedSequences,
            stationarySequenceID: normalizedStationarySequenceID,
            automaticRules: settings.automaticRules
        )
    }

    private static func migratingBuiltInProfiles(
        in settings: AppSettings
    ) -> AppSettings {
        let displayMigrationProfileIDs: Set<UUID> = Set(
            settings.petBehaviorProfiles.compactMap { stored in
                guard stored.profile == previousMongleProfile
                        || stored.profile == publishedMongleProfileV102 else {
                    return nil
                }
                return stored.profileID
            }
        )
        var profileChanged = false
        let profiles = settings.petBehaviorProfiles.map { stored in
            guard stored.profile.petKey == .builtIn else {
                return stored
            }
            let migrated = migratedBuiltInProfile(stored.profile)
            guard migrated != stored.profile else {
                return stored
            }
            profileChanged = true
            return PetBehaviorProfileSettings(
                profileID: stored.profileID,
                profile: migrated
            )
        }
        var migrated = profileChanged
            ? AppSettings(
                selectedPetInstanceID: settings.selectedPetInstanceID,
                activePetInstances: settings.activePetInstances,
                petBehaviorProfiles: profiles
            )
            : settings
        for instance in migrated.activePetInstances where
            displayMigrationProfileIDs.contains(instance.behaviorProfileID)
                && PortablePetDisplaySettings(overlay: instance.overlay)
                    == .default {
            migrated = migrated.replacingOverlay(
                mongleDisplay.applying(to: instance.overlay),
                for: instance.instanceID
            )
        }
        return migrated
    }

    private static func migratedBuiltInProfile(
        _ profile: BehaviorProfile
    ) -> BehaviorProfile {
        if profile == previousMongleProfile {
            return defaultProfile(for: .builtIn)
        }
        if profile == publishedMongleProfileV102 {
            return defaultProfile(for: .builtIn)
        }

        let sequences = profile.sequences.map(migratingMongleMotionIDs)
        guard sequences != profile.sequences else {
            return profile
        }
        return BehaviorProfile(
            petKey: profile.petKey,
            stationaryBehaviorMode: profile.stationaryBehaviorMode,
            stationarySequenceID: profile.stationarySequenceID,
            randomSequenceIDs: profile.randomSequenceIDs,
            sequences: sequences,
            automaticRules: profile.automaticRules,
            automaticRulePriorityOrder:
                profile.automaticRulePriorityOrder,
            movement: profile.movement,
            pettingMotionID: profile.pettingMotionID,
            speech: profile.speech
        )
    }

    private static var previousMongleProfile: BehaviorProfile {
        BehaviorProfile(
            petKey: .builtIn,
            mode: .automatic,
            manualSequenceID: defaultManualSequenceID,
            sequences: previousMongleSequences,
            automaticRules: previousMongleAutomaticRules,
            automaticRulePriorityOrder: [.movement, .idle, .application],
            movement: previousMongleMovement,
            pettingMotionID: "해피",
            speech: .default
        )
    }

    static var publishedMongleProfileV102: BehaviorProfile {
        BehaviorProfile(
            petKey: .builtIn,
            mode: .automatic,
            manualSequenceID: defaultManualSequenceID,
            sequences: publishedMongleSequencesV102,
            automaticRules: publishedMongleRulesV102,
            automaticRulePriorityOrder: [.idle, .application, .movement],
            movement: publishedMongleMovementV102,
            pettingMotionID: "6a889c56-0907-484a-be75-02c2918a72a0",
            speech: .default
        )
    }

    private static func migratingMongleMotionIDs(
        in sequence: BehaviorSequence
    ) -> BehaviorSequence {
        let steps = sequence.steps.map { step in
            guard let renamed = renamedMongleMotionIDs[step.motionID] else {
                return step
            }
            if let legacyTiming = step.legacyTiming {
                return BehaviorStep(
                    motionID: renamed,
                    duration: legacyTiming.duration,
                    playbackSpeed: legacyTiming.playbackSpeed
                )
            }
            return BehaviorStep(
                motionID: renamed,
                repeatCount: step.repeatCount
            )
        }
        let displayName: String
        if sequence.steps.count == 1,
           let motionID = sequence.steps.first?.motionID,
           sequence.displayName == motionID,
           let renamed = renamedMongleMotionIDs[motionID] {
            displayName = renamed
        } else {
            displayName = sequence.displayName
        }
        guard steps != sequence.steps || displayName != sequence.displayName else {
            return sequence
        }
        return BehaviorSequence(
            id: sequence.id,
            displayName: displayName,
            steps: steps,
            repeats: sequence.repeats
        )
    }

    static func defaultProfile(
        for petKey: PetBehaviorKey
    ) -> BehaviorProfile {
        if petKey == .builtIn {
            return BehaviorProfile(
                petKey: petKey,
                stationaryBehaviorMode: .fixed,
                stationarySequenceID: nil,
                sequences: mongleSequences,
                automaticRules: mongleAutomaticRules,
                automaticRulePriorityOrder: [.idle, .application, .movement],
                movement: mongleMovement,
                pettingMotionID: monglePettingMotionID,
                speech: mongleSpeech
            )
        }
        return BehaviorProfile(
            petKey: petKey,
            stationaryBehaviorMode: .fixed,
            stationarySequenceID: nil,
            sequences: sequences,
            automaticRules: automaticRules,
            automaticRulePriorityOrder:
                AutomaticRuleCategory.defaultPriorityOrder,
            movement: .default,
            pettingMotionID: nil,
            speech: .default
        )
    }

    static func displayName(for sequenceID: String) -> String {
        sequences.first(where: { $0.id == sequenceID })?.displayName
            ?? sequenceID
    }

    static func motionDisplayName(for motionID: String) -> String {
        motionID == PetMotionReference.currentPetDefault
            ? "현재 펫의 기본 애니메이션"
            : motionID
    }

    private static func sequence(
        id: String,
        displayName: String? = nil,
        motionID: String
    ) -> BehaviorSequence {
        BehaviorSequence(
            id: id,
            displayName: displayName,
            steps: [
                BehaviorStep(
                    motionID: motionID,
                    repeatCount: 1
                )
            ],
            repeats: true
        )
    }

    private static func legacySequence(
        id: String,
        motionID: String
    ) -> BehaviorSequence {
        BehaviorSequence(
            id: id,
            steps: [
                BehaviorStep(
                    motionID: motionID,
                    duration: stepDuration,
                    playbackSpeed: 1
                )
            ],
            repeats: true
        )
    }

    private static func shouldApplyMongleDefaults(
        to settings: AppSettings
    ) -> Bool {
        guard
            settings.selectedPetKey == .builtIn,
            let profile = settings.activeBehaviorProfile,
            profile.mode == .automatic,
            profile.movement == .default,
            profile.pettingMotionID == nil,
            profile.speech == .default
        else {
            return false
        }

        let isUninitialized = profile.manualSequenceID == nil
            && profile.sequences.isEmpty
            && profile.automaticRules.isEmpty
        let usesPreviousDefaults = profile.stationaryBehaviorMode == .fixed
            && profile.stationarySequenceID == nil
            && profile.sequences == sequences
            && profile.automaticRules == automaticRules
        let usesLegacyDefaults = profile.stationaryBehaviorMode == .fixed
            && profile.stationarySequenceID == nil
            && profile.sequences == legacySequences
            && profile.automaticRules == legacyAutomaticRules
        return isUninitialized || usesPreviousDefaults || usesLegacyDefaults
    }

    private static func applyingMongleDisplayToSelectedInstance(
        in settings: AppSettings
    ) -> AppSettings {
        guard settings.selectedPetKey == .builtIn,
              PortablePetDisplaySettings(overlay: settings.overlay)
                == .default else {
            return settings
        }
        return settings.replacingSelectedOverlay(
            mongleDisplay.applying(to: settings.overlay)
        )
    }

    private static func replacingDefaults(
        in settings: AppSettings,
        sequences: [BehaviorSequence],
        stationarySequenceID: String? = nil,
        automaticRules: [AutomaticRule]
    ) -> AppSettings {
        settings.replacingActiveBehaviorProfile(
            BehaviorProfile(
                petKey: settings.selectedPetKey,
                stationaryBehaviorMode: settings.stationaryBehaviorMode,
                stationarySequenceID: stationarySequenceID,
                randomSequenceIDs: settings.randomSequenceIDs.filter {
                    Set(sequences.map(\.id)).contains($0)
                },
                sequences: sequences,
                automaticRules: automaticRules,
                automaticRulePriorityOrder:
                    settings.automaticRulePriorityOrder,
                movement: settings.movementSettings,
                pettingMotionID: settings.pettingMotionID,
                speech: settings.speechSettings
            )
        )
    }
}
