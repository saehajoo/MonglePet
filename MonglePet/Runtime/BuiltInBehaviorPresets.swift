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
        let configuredSequences = settings.sequences.contains(where: {
            $0.id == defaultSequenceID
        }) ? settings.sequences : sequences + settings.sequences

        return BehaviorConfiguration(
            mode: settings.behaviorMode,
            defaultSequenceID: defaultSequenceID,
            manualSequenceID: settings.manualSequenceID ?? defaultManualSequenceID,
            sequences: configuredSequences,
            automaticRules: settings.automaticRules
        )
    }

    static func normalizedDefaults(in settings: AppSettings) -> AppSettings {
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
                movement: settings.movementSettings
            )
        )
    }
}
