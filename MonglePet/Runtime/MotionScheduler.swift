nonisolated struct ScheduledMotion: Equatable, Sendable {
    let sequenceID: String
    let stepIndex: Int
    let requestedMotionID: String
    let motion: PetMotion
    let playbackSpeed: Double
    let isInteraction: Bool

    var usesFallback: Bool {
        requestedMotionID != PetMotionReference.currentPetDefault
            && requestedMotionID != motion.id
    }
}

nonisolated enum MotionSchedulerStatus: Equatable, Sendable {
    case stopped
    case playing(ScheduledMotion)
    case unavailable
}

nonisolated struct MotionScheduler: Sendable {
    private struct ResolvedStep: Equatable, Sendable {
        let source: BehaviorStep
        let motion: PetMotion
        let cycleDuration: Duration
        let repeatCount: Int
        let playbackSpeed: Double
    }

    private struct Cursor: Equatable, Sendable {
        let sequence: BehaviorSequence
        let steps: [ResolvedStep]
        var stepIndex = 0
        var completedCycles = 0
        var remainingCycleDuration: Duration
        var isComplete = false

        init(sequence: BehaviorSequence, steps: [ResolvedStep]) {
            self.sequence = sequence
            self.steps = steps
            remainingCycleDuration = steps[0].cycleDuration
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

    var activeCycleRemainingDuration: Duration? {
        interactionCursor?.remainingCycleDuration
            ?? baseCursor?.remainingCycleDuration
    }

    var isInteractionPlaying: Bool {
        interactionCursor != nil
    }

    @discardableResult
    mutating func request(_ sequence: BehaviorSequence) -> Bool {
        guard let requestedCursor = makeCursor(for: sequence) else {
            return false
        }

        guard var baseCursor else {
            self.baseCursor = requestedCursor
            pendingSequence = nil
            return true
        }

        if baseCursor.sequence == sequence {
            pendingSequence = nil
            return false
        }

        if baseCursor.isComplete {
            baseCursor = requestedCursor
            self.baseCursor = baseCursor
            pendingSequence = nil
            return true
        }

        if baseCursor.sequence.id == sequence.id {
            guard pendingSequence != sequence else {
                return false
            }
            pendingSequence = sequence
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
            let cursor = makeCursor(for: sequence)
        else {
            return false
        }

        interactionCursor = cursor
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
        guard cursor.steps.indices.contains(cursor.stepIndex) else {
            return .unavailable
        }

        let step = cursor.steps[cursor.stepIndex]
        return .playing(
            ScheduledMotion(
                sequenceID: cursor.sequence.id,
                stepIndex: cursor.stepIndex,
                requestedMotionID: step.source.motionID,
                motion: step.motion,
                playbackSpeed: step.playbackSpeed,
                isInteraction: isInteraction
            )
        )
    }

    private mutating func advanceInteraction(by elapsed: Duration) -> Duration {
        var remainingElapsed = elapsed

        while remainingElapsed > .zero, var cursor = interactionCursor {
            if remainingElapsed < cursor.remainingCycleDuration {
                cursor.remainingCycleDuration -= remainingElapsed
                interactionCursor = cursor
                return .zero
            }

            remainingElapsed -= cursor.remainingCycleDuration
            if advanceCursorAfterCycle(&cursor) {
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
            if remainingElapsed < cursor.remainingCycleDuration {
                cursor.remainingCycleDuration -= remainingElapsed
                baseCursor = cursor
                return
            }

            remainingElapsed -= cursor.remainingCycleDuration

            if let pendingSequence, let pendingCursor = makeCursor(for: pendingSequence) {
                baseCursor = pendingCursor
                self.pendingSequence = nil
                continue
            }

            if advanceCursorAfterCycle(&cursor) {
                baseCursor = cursor
            } else {
                cursor.remainingCycleDuration = .zero
                cursor.isComplete = true
                baseCursor = cursor
            }
        }
    }

    private func advanceCursorAfterCycle(_ cursor: inout Cursor) -> Bool {
        let step = cursor.steps[cursor.stepIndex]
        cursor.completedCycles += 1
        if cursor.completedCycles < step.repeatCount {
            cursor.remainingCycleDuration = step.cycleDuration
            return true
        }

        let nextStepIndex = cursor.stepIndex + 1
        if cursor.steps.indices.contains(nextStepIndex) {
            cursor.stepIndex = nextStepIndex
            cursor.completedCycles = 0
            cursor.remainingCycleDuration = cursor.steps[nextStepIndex].cycleDuration
            return true
        }

        guard cursor.sequence.repeats else {
            return false
        }

        cursor.stepIndex = 0
        cursor.completedCycles = 0
        cursor.remainingCycleDuration = cursor.steps[0].cycleDuration
        return true
    }

    private func makeCursor(for sequence: BehaviorSequence) -> Cursor? {
        guard !sequence.steps.isEmpty else {
            return nil
        }

        let resolvedSteps = sequence.steps.compactMap(resolve)
        guard resolvedSteps.count == sequence.steps.count else {
            return nil
        }
        return Cursor(sequence: sequence, steps: resolvedSteps)
    }

    private func resolve(_ step: BehaviorStep) -> ResolvedStep? {
        guard !step.motionID.isEmpty else {
            return nil
        }

        let requestedMotion = step.motionID == PetMotionReference.currentPetDefault
            ? petDefinition.defaultMotion
            : petDefinition.motion(id: step.motionID)
        guard
            let motion = requestedMotion ?? petDefinition.defaultMotion,
            let unadjustedCycleDuration = motion.cycleDuration
        else {
            return nil
        }

        if let legacyTiming = step.legacyTiming {
            guard
                legacyTiming.duration > .zero,
                legacyTiming.playbackSpeed.isFinite,
                legacyTiming.playbackSpeed > 0
            else {
                return nil
            }
            return ResolvedStep(
                source: step,
                motion: motion,
                cycleDuration: legacyTiming.duration,
                repeatCount: 1,
                playbackSpeed: legacyTiming.playbackSpeed
            )
        }

        guard step.repeatCount > 0 else {
            return nil
        }
        return ResolvedStep(
            source: step,
            motion: motion,
            cycleDuration: unadjustedCycleDuration,
            repeatCount: step.repeatCount,
            playbackSpeed: 1
        )
    }

    private mutating func reduceCooldown(by elapsed: Duration) {
        guard cooldownRemaining > .zero, elapsed > .zero else {
            return
        }

        cooldownRemaining = max(cooldownRemaining - elapsed, .zero)
    }

}
