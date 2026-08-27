import Foundation

nonisolated enum PetPresentation: String, Equatable, Sendable {
    case awake
    case tuckedAway
    case suspended
}

nonisolated enum BehaviorMode: String, Equatable, Sendable {
    case automatic
    case manual
    case random
}

nonisolated struct BehaviorStep: Equatable, Sendable {
    let motionID: String
    let repeatCount: Int
    let legacyTiming: LegacyBehaviorStepTiming?

    init(motionID: String, repeatCount: Int) {
        self.motionID = motionID
        self.repeatCount = repeatCount
        legacyTiming = nil
    }

    init(
        motionID: String,
        duration: Duration,
        playbackSpeed: Double
    ) {
        self.motionID = motionID
        repeatCount = 1
        legacyTiming = LegacyBehaviorStepTiming(
            duration: duration,
            playbackSpeed: playbackSpeed
        )
    }

    var duration: Duration {
        legacyTiming?.duration ?? .zero
    }

    var playbackSpeed: Double {
        legacyTiming?.playbackSpeed ?? 1
    }
}

nonisolated struct LegacyBehaviorStepTiming: Equatable, Sendable {
    let duration: Duration
    let playbackSpeed: Double
}

nonisolated struct BehaviorSequence: Equatable, Identifiable, Sendable {
    let id: String
    let displayName: String
    let steps: [BehaviorStep]
    let repeats: Bool

    init(
        id: String,
        displayName: String? = nil,
        steps: [BehaviorStep],
        repeats: Bool
    ) {
        self.id = id
        self.displayName = displayName
            ?? (id == "__monglepet_default_behavior__" ? "기본" : id)
        self.steps = steps
        self.repeats = repeats
    }
}

nonisolated enum AutomaticRuleCategory:
    String,
    CaseIterable,
    Equatable,
    Sendable
{
    case movement
    case idle
    case application

    static let defaultPriorityOrder: [AutomaticRuleCategory] = [
        .movement,
        .idle,
        .application
    ]
}

nonisolated enum RuleCondition: Equatable, Sendable {
    case application(bundleIdentifier: String)
    case idleAtLeast(milliseconds: Int64)
    case unsupported(type: String)
}

nonisolated struct AutomaticRule: Equatable, Identifiable, Sendable {
    let id: UUID
    let isEnabled: Bool
    let priority: Int
    let condition: RuleCondition
    let sequenceID: String

    var category: AutomaticRuleCategory? {
        switch condition {
        case .application:
            .application
        case .idleAtLeast:
            .idle
        case .unsupported:
            nil
        }
    }
}

nonisolated struct ActivitySnapshot: Equatable, Sendable {
    let capturedAt: ContinuousClock.Instant
    let idleDuration: Duration
    let frontmostApplicationID: String?
    let isScreenLocked: Bool
    let isSystemSleeping: Bool
}

nonisolated struct BehaviorConfiguration: Equatable, Sendable {
    let mode: BehaviorMode
    let defaultSequenceID: String
    let manualSequenceID: String?
    let randomSequenceIDs: [String]
    let sequences: [BehaviorSequence]
    let automaticRules: [AutomaticRule]
    let automaticRulePriorityOrder: [AutomaticRuleCategory]

    init(
        mode: BehaviorMode,
        defaultSequenceID: String,
        manualSequenceID: String? = nil,
        randomSequenceIDs: [String] = [],
        sequences: [BehaviorSequence],
        automaticRules: [AutomaticRule] = [],
        automaticRulePriorityOrder: [AutomaticRuleCategory] =
            AutomaticRuleCategory.defaultPriorityOrder
    ) {
        self.mode = mode
        self.defaultSequenceID = defaultSequenceID
        self.manualSequenceID = manualSequenceID
        self.randomSequenceIDs = randomSequenceIDs
        self.sequences = sequences
        self.automaticRules = automaticRules
        self.automaticRulePriorityOrder = automaticRulePriorityOrder
    }

    func sequence(id: String) -> BehaviorSequence? {
        sequences.first { $0.id == id }
    }

    var defaultSequence: BehaviorSequence? {
        sequence(id: defaultSequenceID) ?? sequences.first
    }
}

nonisolated struct BehaviorRuntimeState: Equatable, Sendable {
    let presentation: PetPresentation
    let interactionSequenceID: String?
    let randomSequenceID: String?

    init(
        presentation: PetPresentation,
        interactionSequenceID: String? = nil,
        randomSequenceID: String? = nil
    ) {
        self.presentation = presentation
        self.interactionSequenceID = interactionSequenceID
        self.randomSequenceID = randomSequenceID
    }
}

nonisolated enum BehaviorSource: Equatable, Sendable {
    case interaction
    case manual
    case random
    case automaticRule(UUID)
    case defaultBehavior
}

nonisolated enum BehaviorDecision: Equatable, Sendable {
    case tuckedAway
    case suspended
    case sequence(BehaviorSequence, source: BehaviorSource)
    case unavailable

    var sequence: BehaviorSequence? {
        guard case let .sequence(sequence, _) = self else {
            return nil
        }

        return sequence
    }
}
