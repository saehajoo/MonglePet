nonisolated struct ScheduledMotion: Equatable, Sendable {
    let sequenceID: String
    let stepIndex: Int
    let requestedMotionID: String
    let motion: PetMotion
    let playbackSpeed: Double
    let isInteraction: Bool

    var usesIdleFallback: Bool {
        requestedMotionID != motion.id
    }
}

nonisolated enum MotionSchedulerStatus: Equatable, Sendable {
    case stopped
    case playing(ScheduledMotion)
    case unavailable
}

nonisolated struct MotionScheduler: Sendable {
    private struct Cursor: Equatable, Sendable {
        let sequence: BehaviorSequence
        var stepIndex: Int
        var remainingDuration: Duration
        var isComplete: Bool

        init(sequence: BehaviorSequence) {
            self.sequence = sequence
            stepIndex = 0
            remainingDuration = sequence.steps[0].duration
            isComplete = false
        }
    }

    private let petDefinition: PetDefinition
    private let interactionCooldown: Duration
    private var baseCursor: Cursor?
    private var pendingSequence: BehaviorSequence?
    private var interactionCursor: Cursor?
    private var cooldownRemaining: Duration = .zero
    private(set) var isPaused = false

    init(
        petDefinition: PetDefinition,
        interactionCooldown: Duration = .milliseconds(500)
    ) {
        self.petDefinition = petDefinition
        self.interactionCooldown = max(interactionCooldown, .zero)
    }

    var status: MotionSchedulerStatus {
        if let interactionCursor {
            return status(for: interactionCursor, isInteraction: true)
        }

        guard let baseCursor else {
            return .stopped
        }

        return status(for: baseCursor, isInteraction: false)
    }

    var activeSequenceID: String? {
        interactionCursor?.sequence.id ?? baseCursor?.sequence.id
    }

    var pendingSequenceID: String? {
        pendingSequence?.id
    }

    var activeStepRemainingDuration: Duration? {
        interactionCursor?.remainingDuration ?? baseCursor?.remainingDuration
    }

    var isInteractionPlaying: Bool {
        interactionCursor != nil
    }

    @discardableResult
    mutating func request(_ sequence: BehaviorSequence) -> Bool {
        guard Self.isValid(sequence) else {
            return false
        }

        guard var baseCursor else {
            self.baseCursor = Cursor(sequence: sequence)
            pendingSequence = nil
            return true
        }

        if baseCursor.sequence.id == sequence.id {
            pendingSequence = nil
            return false
        }

        if baseCursor.isComplete {
            baseCursor = Cursor(sequence: sequence)
            self.baseCursor = baseCursor
            pendingSequence = nil
            return true
        }

        guard pendingSequence?.id != sequence.id else {
            return false
        }

        pendingSequence = sequence
        return true
    }

    @discardableResult
    mutating func triggerInteraction(_ sequence: BehaviorSequence) -> Bool {
        guard
            interactionCursor == nil,
            cooldownRemaining <= .zero,
            Self.isValid(sequence)
        else {
            return false
        }

        interactionCursor = Cursor(sequence: sequence)
        return true
    }

    mutating func advance(by elapsed: Duration) {
        guard !isPaused, elapsed > .zero else {
            return
        }

        var remainingElapsed = elapsed
        if interactionCursor != nil {
            remainingElapsed = advanceInteraction(by: remainingElapsed)
            guard interactionCursor == nil else {
                return
            }
        }

        reduceCooldown(by: remainingElapsed)
        advanceBase(by: remainingElapsed)
    }

    mutating func pause() {
        isPaused = true
    }

    mutating func resume() {
        isPaused = false
    }

    mutating func stop() {
        baseCursor = nil
        pendingSequence = nil
        interactionCursor = nil
        cooldownRemaining = .zero
        isPaused = false
    }

    private func status(
        for cursor: Cursor,
        isInteraction: Bool
    ) -> MotionSchedulerStatus {
        guard cursor.sequence.steps.indices.contains(cursor.stepIndex) else {
            return .unavailable
        }

        let step = cursor.sequence.steps[cursor.stepIndex]
        guard let motion = petDefinition.motion(id: step.motionID)
            ?? petDefinition.motion(id: "idle")
        else {
            return .unavailable
        }

        return .playing(
            ScheduledMotion(
                sequenceID: cursor.sequence.id,
                stepIndex: cursor.stepIndex,
                requestedMotionID: step.motionID,
                motion: motion,
                playbackSpeed: step.playbackSpeed,
                isInteraction: isInteraction
            )
        )
    }

    private mutating func advanceInteraction(by elapsed: Duration) -> Duration {
        var remainingElapsed = elapsed

        while remainingElapsed > .zero, var cursor = interactionCursor {
            if remainingElapsed < cursor.remainingDuration {
                cursor.remainingDuration -= remainingElapsed
                interactionCursor = cursor
                return .zero
            }

            remainingElapsed -= cursor.remainingDuration
            let nextStepIndex = cursor.stepIndex + 1
            if cursor.sequence.steps.indices.contains(nextStepIndex) {
                cursor.stepIndex = nextStepIndex
                cursor.remainingDuration = cursor.sequence.steps[nextStepIndex].duration
                interactionCursor = cursor
            } else {
                interactionCursor = nil
                cooldownRemaining = interactionCooldown
            }
        }

        return remainingElapsed
    }

    private mutating func advanceBase(by elapsed: Duration) {
        var remainingElapsed = elapsed

        while remainingElapsed > .zero, var cursor = baseCursor, !cursor.isComplete {
            if remainingElapsed < cursor.remainingDuration {
                cursor.remainingDuration -= remainingElapsed
                baseCursor = cursor
                return
            }

            remainingElapsed -= cursor.remainingDuration

            if let pendingSequence {
                baseCursor = Cursor(sequence: pendingSequence)
                self.pendingSequence = nil
                continue
            }

            let nextStepIndex = cursor.stepIndex + 1
            if cursor.sequence.steps.indices.contains(nextStepIndex) {
                cursor.stepIndex = nextStepIndex
                cursor.remainingDuration = cursor.sequence.steps[nextStepIndex].duration
            } else if cursor.sequence.repeats {
                cursor.stepIndex = 0
                cursor.remainingDuration = cursor.sequence.steps[0].duration
            } else {
                cursor.remainingDuration = .zero
                cursor.isComplete = true
            }

            baseCursor = cursor
        }
    }

    private mutating func reduceCooldown(by elapsed: Duration) {
        guard cooldownRemaining > .zero, elapsed > .zero else {
            return
        }

        cooldownRemaining = max(cooldownRemaining - elapsed, .zero)
    }

    private static func isValid(_ sequence: BehaviorSequence) -> Bool {
        !sequence.steps.isEmpty && sequence.steps.allSatisfy {
            !$0.motionID.isEmpty
                && $0.duration > .zero
                && $0.playbackSpeed.isFinite
                && $0.playbackSpeed > 0
        }
    }
}
