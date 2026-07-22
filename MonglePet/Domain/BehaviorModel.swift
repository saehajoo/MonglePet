import Foundation

nonisolated enum PetPresentation: String, Equatable, Sendable {
    case awake
    case tuckedAway
    case suspended
}

nonisolated enum BehaviorMode: String, Equatable, Sendable {
    case automatic
    case manual
}

nonisolated struct BehaviorStep: Equatable, Sendable {
    let motionID: String
    let duration: Duration
    let playbackSpeed: Double
}

nonisolated struct BehaviorSequence: Equatable, Identifiable, Sendable {
    let id: String
    let steps: [BehaviorStep]
    let repeats: Bool
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
}

nonisolated struct ActivitySnapshot: Equatable, Sendable {
    let capturedAt: ContinuousClock.Instant
    let idleDuration: Duration
    let frontmostApplicationID: String?
    let isScreenLocked: Bool
    let isSystemSleeping: Bool
}

nonisolated struct BehaviorConfiguration: Equatable, Sendable {
    static let defaultLongIdleThreshold: Duration = .seconds(600)
    static let defaultIdleExitDelay: Duration = .seconds(3)

    let mode: BehaviorMode
    let defaultSequenceID: String
    let manualSequenceID: String?
    let sequences: [BehaviorSequence]
    let automaticRules: [AutomaticRule]
    let longIdleThreshold: Duration
    let idleExitDelay: Duration

    init(
        mode: BehaviorMode,
        defaultSequenceID: String,
        manualSequenceID: String? = nil,
        sequences: [BehaviorSequence],
        automaticRules: [AutomaticRule] = [],
        longIdleThreshold: Duration = Self.defaultLongIdleThreshold,
        idleExitDelay: Duration = Self.defaultIdleExitDelay
    ) {
        self.mode = mode
        self.defaultSequenceID = defaultSequenceID
        self.manualSequenceID = manualSequenceID
        self.sequences = sequences
        self.automaticRules = automaticRules
        self.longIdleThreshold = longIdleThreshold
        self.idleExitDelay = idleExitDelay
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

    init(
        presentation: PetPresentation,
        interactionSequenceID: String? = nil
    ) {
        self.presentation = presentation
        self.interactionSequenceID = interactionSequenceID
    }
}

nonisolated enum BehaviorSource: Equatable, Sendable {
    case interaction
    case manual
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
