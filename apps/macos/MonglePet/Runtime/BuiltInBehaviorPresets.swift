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
        sequence(id: "일해라", motionID: "일하는 중")
    ]

    static let mongleAutomaticRules = [
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

    static let mongleMovement = PetMovementSettings(
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

    static let monglePettingMotionID = "해피"
    static let mongleSpeech = PetSpeechSettings.default

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
            mode: normalizedSettings.behaviorMode,
            defaultSequenceID: defaultSequenceID,
            manualSequenceID: normalizedSettings.manualSequenceID
                ?? defaultManualSequenceID,
            sequences: configuredSequences,
            automaticRules: normalizedSettings.automaticRules
        )
    }

    static func normalizedDefaults(in settings: AppSettings) -> AppSettings {
        if shouldApplyMongleDefaults(to: settings) {
            return settings.replacingActiveBehaviorProfile(
                defaultProfile(for: .builtIn)
            )
        }

        let usesUnmodifiedLegacyDefaults = settings.sequences == legacySequences
            && settings.automaticRules == legacyAutomaticRules
        if usesUnmodifiedLegacyDefaults {
            return replacingDefaults(
                in: settings,
                sequences: sequences,
                manualSequenceID: defaultManualSequenceID,
                automaticRules: []
            )
        }

        var normalizedSequences = settings.sequences
        if !normalizedSequences.contains(where: { $0.id == defaultSequenceID }),
           normalizedSequences.count < AppSettingsLimits.maximumSequences {
            normalizedSequences.insert(sequences[0], at: 0)
        }
        let availableIDs = Set(normalizedSequences.map(\.id))
        let normalizedManualSequenceID = settings.manualSequenceID.flatMap {
            availableIDs.contains($0) ? $0 : nil
        } ?? (availableIDs.contains(defaultManualSequenceID)
            ? defaultManualSequenceID
            : normalizedSequences.first?.id)

        return replacingDefaults(
            in: settings,
            sequences: normalizedSequences,
            manualSequenceID: normalizedManualSequenceID,
            automaticRules: settings.automaticRules
        )
    }

    static func defaultProfile(
        for petKey: PetBehaviorKey
    ) -> BehaviorProfile {
        if petKey == .builtIn {
            return BehaviorProfile(
                petKey: petKey,
                mode: .automatic,
                manualSequenceID: defaultManualSequenceID,
                sequences: mongleSequences,
                automaticRules: mongleAutomaticRules,
                movement: mongleMovement,
                pettingMotionID: monglePettingMotionID,
                speech: mongleSpeech
            )
        }
        return BehaviorProfile(
            petKey: petKey,
            mode: .automatic,
            manualSequenceID: defaultManualSequenceID,
            sequences: sequences,
            automaticRules: automaticRules,
            movement: .default,
            pettingMotionID: nil,
            speech: .default
        )
    }

    static func displayName(for sequenceID: String) -> String {
        switch sequenceID {
        case defaultSequenceID:
            return "기본"
        default:
            return sequenceID
        }
    }

    static func motionDisplayName(for motionID: String) -> String {
        motionID == PetMotionReference.currentPetDefault
            ? "현재 펫의 기본 애니메이션"
            : motionID
    }

    private static func sequence(id: String, motionID: String) -> BehaviorSequence {
        BehaviorSequence(
            id: id,
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
        let usesPreviousDefaults = profile.manualSequenceID
                == defaultManualSequenceID
            && profile.sequences == sequences
            && profile.automaticRules == automaticRules
        let usesLegacyDefaults = profile.manualSequenceID
                == legacySequences.first?.id
            && profile.sequences == legacySequences
            && profile.automaticRules == legacyAutomaticRules
        return isUninitialized || usesPreviousDefaults || usesLegacyDefaults
    }

    private static func replacingDefaults(
        in settings: AppSettings,
        sequences: [BehaviorSequence],
        manualSequenceID: String?,
        automaticRules: [AutomaticRule]
    ) -> AppSettings {
        settings.replacingActiveBehaviorProfile(
            BehaviorProfile(
                petKey: settings.selectedPetKey,
                mode: settings.behaviorMode,
                manualSequenceID: manualSequenceID,
                sequences: sequences,
                automaticRules: automaticRules,
                movement: settings.movementSettings,
                pettingMotionID: settings.pettingMotionID,
                speech: settings.speechSettings
            )
        )
    }
}
