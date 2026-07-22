import Foundation

nonisolated enum BuiltInBehaviorPresets {
    static let defaultSequenceID = "idle"
    static let defaultManualSequenceID = "idle"
    static let stepDuration: Duration = .seconds(3)

    static let sequences = [
        sequence(id: "idle", motionID: "idle"),
        sequence(id: "focus", motionID: "focus"),
        sequence(id: "rest", motionID: "rest"),
        sequence(id: "sleep", motionID: "sleep")
    ]

    static let automaticRules = [
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
        let configuredSequences = settings.sequences.isEmpty
            ? sequences
            : settings.sequences
        let configuredRules = settings.sequences.isEmpty
            ? automaticRules
            : settings.automaticRules

        return BehaviorConfiguration(
            mode: settings.behaviorMode,
            defaultSequenceID: defaultSequenceID,
            manualSequenceID: settings.manualSequenceID,
            sequences: configuredSequences,
            automaticRules: configuredRules
        )
    }

    static func displayName(for sequenceID: String) -> String {
        switch sequenceID {
        case "idle":
            return "기본 움직임"
        case "focus":
            return "집중 중"
        case "rest":
            return "잠시 쉬는 중"
        case "sleep":
            return "자는 중"
        default:
            return sequenceID
        }
    }

    private static func sequence(id: String, motionID: String) -> BehaviorSequence {
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
}
