import Foundation

@MainActor
protocol BehaviorRuntimeClock: AnyObject {
    var now: ContinuousClock.Instant { get }
}

@MainActor
final class ContinuousBehaviorRuntimeClock: BehaviorRuntimeClock {
    private let clock = ContinuousClock()

    var now: ContinuousClock.Instant {
        clock.now
    }
}

@MainActor
protocol BehaviorTickScheduling: AnyObject {
    func schedule(after delay: Duration, action: @escaping () -> Void)
    func cancel()
}

@MainActor
final class RunLoopBehaviorTickScheduler: NSObject, BehaviorTickScheduling {
    private var timer: Timer?
    private var action: (() -> Void)?

    func schedule(after delay: Duration, action: @escaping () -> Void) {
        cancel()
        self.action = action
        let timer = Timer(
            timeInterval: max(delay.timeInterval, 0.001),
            target: self,
            selector: #selector(timerDidFire),
            userInfo: nil,
            repeats: false
        )
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func cancel() {
        timer?.invalidate()
        timer = nil
        action = nil
    }

    @objc
    private func timerDidFire() {
        timer = nil
        let pendingAction = action
        action = nil
        pendingAction?()
    }
}

@MainActor
final class PetBehaviorRuntime {
    private var resolver = BehaviorResolver()
    private var motionScheduler: MotionScheduler
    private let clock: any BehaviorRuntimeClock
    private let tickScheduler: any BehaviorTickScheduling
    private let onPlaybackChange: (ScheduledMotion?) -> Void
    private let randomIndex: (Int) -> Int
    private var randomSequenceBag: [String] = []
    private var currentRandomSequenceID: String?
    private var previousMode: StationaryBehaviorMode?
    private var latestConfiguration: BehaviorConfiguration?
    private var latestSnapshot: ActivitySnapshot?
    private var latestPresentation: PetPresentation = .awake
    private var isDecisionPaused = false
    private var isMovementPlaybackObscuringBehavior = false
    private var lastAdvancedAt: ContinuousClock.Instant?
    private var hasEmittedPlayback = false
    private(set) var currentPlayback: ScheduledMotion?
    private(set) var latestDecision: BehaviorDecision?

    init(
        petDefinition: PetDefinition,
        clock: any BehaviorRuntimeClock = ContinuousBehaviorRuntimeClock(),
        tickScheduler: any BehaviorTickScheduling = RunLoopBehaviorTickScheduler(),
        randomIndex: @escaping (Int) -> Int = { upperBound in
            Int.random(in: 0..<upperBound)
        },
        onPlaybackChange: @escaping (ScheduledMotion?) -> Void
    ) {
        motionScheduler = MotionScheduler(petDefinition: petDefinition)
        self.clock = clock
        self.tickScheduler = tickScheduler
        self.randomIndex = randomIndex
        self.onPlaybackChange = onPlaybackChange
    }

    var isPaused: Bool {
        motionScheduler.isPaused
    }

    @discardableResult
    func triggerInteraction(motionID: String) -> Bool {
        triggerInteraction(
            sequence: BehaviorSequence(
                id: "__monglepet_petting__",
                displayName: "쓰다듬기",
                steps: [BehaviorStep(motionID: motionID, repeatCount: 1)],
                repeats: false
            )
        )
    }

    @discardableResult
    func triggerInteraction(sequence: BehaviorSequence) -> Bool {
        guard
            !isDecisionPaused,
            !sequence.steps.isEmpty
        else {
            return false
        }
        guard case .playing = motionScheduler.status else {
            return false
        }

        let now = clock.now
        advance(to: now)
        let shouldRestoreMovementPause = isMovementPlaybackObscuringBehavior
        if shouldRestoreMovementPause {
            motionScheduler.resume()
        }
        let onePassSequence = BehaviorSequence(
            id: sequence.id,
            displayName: sequence.displayName,
            steps: sequence.steps,
            repeats: false
        )
        guard motionScheduler.triggerInteraction(onePassSequence) else {
            if shouldRestoreMovementPause {
                motionScheduler.pause()
            }
            return false
        }

        lastAdvancedAt = now
        emitCurrentPlaybackIfNeeded()
        scheduleNextBoundary()
        return true
    }

    func setMovementPlaybackObscuresBehavior(_ obscuresBehavior: Bool) {
        guard isMovementPlaybackObscuringBehavior != obscuresBehavior else {
            return
        }

        let now = clock.now
        advance(to: now)
        isMovementPlaybackObscuringBehavior = obscuresBehavior
        lastAdvancedAt = now

        if obscuresBehavior {
            let isRandomMode = latestConfiguration?.mode == .random
            if isRandomMode {
                restartRandomSelectionForMovement(at: now)
            }
            guard !motionScheduler.isInteractionPlaying else {
                return
            }
            tickScheduler.cancel()
            motionScheduler.pause()
            if !isRandomMode {
                emitCurrentPlaybackIfNeeded(force: true)
            }
            return
        }

        guard !isDecisionPaused else {
            return
        }
        motionScheduler.resume()
        scheduleNextBoundary()
    }

    func replacePetDefinition(_ petDefinition: PetDefinition) {
        tickScheduler.cancel()
        motionScheduler.stop()
        motionScheduler = MotionScheduler(petDefinition: petDefinition)
        resolver = BehaviorResolver()
        lastAdvancedAt = nil
        latestDecision = nil
        currentPlayback = nil
        hasEmittedPlayback = false
        isDecisionPaused = false
        isMovementPlaybackObscuringBehavior = false
        resetRandomSelection()
        latestConfiguration = nil
        latestSnapshot = nil
        previousMode = nil
    }

    func update(settings: AppSettings, snapshot: ActivitySnapshot) {
        let now = clock.now
        advance(to: now)

        let effectiveSnapshot = ActivitySnapshot(
            capturedAt: now,
            idleDuration: snapshot.idleDuration,
            frontmostApplicationID: snapshot.frontmostApplicationID,
            isScreenLocked: snapshot.isScreenLocked,
            isSystemSleeping: snapshot.isSystemSleeping
        )
        latestSnapshot = effectiveSnapshot
        let configuration = BuiltInBehaviorPresets.configuration(for: settings)
        latestConfiguration = configuration
        latestPresentation = settings.lastUserPresentation
        if previousMode != configuration.stationaryBehaviorMode {
            resetRandomSelection()
            previousMode = configuration.stationaryBehaviorMode
        }
        prepareRandomSelectionIfNeeded(configuration: configuration)
        let previousDecision = latestDecision
        let decision = resolver.resolve(
            configuration: configuration,
            snapshot: effectiveSnapshot,
            runtimeState: BehaviorRuntimeState(
                presentation: settings.lastUserPresentation,
                randomSequenceID: currentRandomSequenceID
            )
        )
        if configuration.stationaryBehaviorMode == .random,
           case .sequence(_, source: .random) = previousDecision,
           case .sequence(_, source: .automaticRule) = decision {
            prepareNextRandomSelection(configuration: configuration)
        }
        latestDecision = decision
        apply(decision, at: now)
    }

    func stop() {
        tickScheduler.cancel()
        motionScheduler.stop()
        resolver = BehaviorResolver()
        lastAdvancedAt = nil
        latestDecision = nil
        latestConfiguration = nil
        latestSnapshot = nil
        previousMode = nil
        isDecisionPaused = false
        isMovementPlaybackObscuringBehavior = false
        resetRandomSelection()
        emit(playback: nil)
    }

    private func apply(
        _ decision: BehaviorDecision,
        at now: ContinuousClock.Instant,
        restartBaseSequence: Bool = false
    ) {
        switch decision {
        case .tuckedAway, .suspended:
            isDecisionPaused = true
            tickScheduler.cancel()
            motionScheduler.pause()
            lastAdvancedAt = now
        case let .sequence(sequence, _):
            isDecisionPaused = false
            motionScheduler.resume()
            // Behavior-level repetition is a legacy storage/package hint.
            // Stationary and rule behavior runs once and holds its last frame;
            // movement owns its separate while-moving looping scheduler.
            let scheduledSequence = BehaviorSequence(
                id: sequence.id,
                displayName: sequence.displayName,
                steps: sequence.steps,
                repeats: false
            )
            if restartBaseSequence {
                _ = motionScheduler.restart(scheduledSequence)
            } else {
                _ = motionScheduler.request(scheduledSequence)
            }
            if isMovementPlaybackObscuringBehavior,
               !motionScheduler.isInteractionPlaying {
                motionScheduler.pause()
            }
            lastAdvancedAt = now
            emitCurrentPlaybackIfNeeded()
            scheduleNextBoundary()
        case .unavailable:
            isDecisionPaused = false
            tickScheduler.cancel()
            motionScheduler.stop()
            lastAdvancedAt = now
            emit(playback: nil)
        }
    }

    private func advance(to instant: ContinuousClock.Instant) {
        guard let lastAdvancedAt else {
            self.lastAdvancedAt = instant
            return
        }

        let elapsed = lastAdvancedAt.duration(to: instant)
        self.lastAdvancedAt = instant
        if elapsed > .zero {
            motionScheduler.advance(by: elapsed)
        }
    }

    private func scheduleNextBoundary() {
        tickScheduler.cancel()
        guard
            !motionScheduler.isPaused,
            let remainingDuration = motionScheduler.activeCycleRemainingDuration,
            remainingDuration > .zero
        else {
            return
        }

        tickScheduler.schedule(after: remainingDuration) { [weak self] in
            self?.boundaryTimerDidFire()
        }
    }

    private func boundaryTimerDidFire() {
        let now = clock.now
        advance(to: now)
        if isMovementPlaybackObscuringBehavior,
           !motionScheduler.isInteractionPlaying {
            tickScheduler.cancel()
            motionScheduler.pause()
            emitCurrentPlaybackIfNeeded(force: true)
            return
        }
        if advanceRandomSelectionIfNeeded(at: now) {
            return
        }
        emitCurrentPlaybackIfNeeded()
        scheduleNextBoundary()
    }

    private func restartRandomSelectionForMovement(
        at now: ContinuousClock.Instant
    ) {
        guard let configuration = latestConfiguration,
              configuration.stationaryBehaviorMode == .random else {
            return
        }
        let validIDs = configuration.randomSequenceIDs.filter { sequenceID in
            configuration.sequences.contains(where: { $0.id == sequenceID })
        }
        let previousPlayback = currentPlayback
        currentRandomSequenceID = nextRandomSequenceID(from: validIDs)
        let snapshot = latestSnapshot ?? ActivitySnapshot(
            capturedAt: now,
            idleDuration: .zero,
            frontmostApplicationID: nil,
            isScreenLocked: false,
            isSystemSleeping: false
        )
        let decision = resolver.resolve(
            configuration: configuration,
            snapshot: snapshot,
            runtimeState: BehaviorRuntimeState(
                presentation: latestPresentation,
                randomSequenceID: currentRandomSequenceID
            )
        )
        latestDecision = decision
        let restartsRandomBase: Bool
        if case .sequence(_, source: .random) = decision {
            restartsRandomBase = true
        } else {
            restartsRandomBase = false
        }
        apply(decision, at: now, restartBaseSequence: restartsRandomBase)
        if !motionScheduler.isInteractionPlaying,
           let previousPlayback,
           let currentPlayback,
           previousPlayback.hasSamePlaybackIdentity(as: currentPlayback) {
            emitCurrentPlaybackIfNeeded(force: true)
        }
    }

    @discardableResult
    private func advanceRandomSelectionIfNeeded(
        at now: ContinuousClock.Instant
    ) -> Bool {
        guard
            !motionScheduler.isInteractionPlaying,
            motionScheduler.isBaseSequenceComplete,
            let configuration = latestConfiguration,
            configuration.stationaryBehaviorMode == .random,
            case .sequence(_, source: .random) = latestDecision
        else {
            return false
        }

        currentRandomSequenceID = nextRandomSequenceID(
            from: configuration.randomSequenceIDs.filter { sequenceID in
                configuration.sequences.contains(where: {
                    $0.id == sequenceID
                })
            }
        )
        let snapshot = latestSnapshot ?? ActivitySnapshot(
            capturedAt: now,
            idleDuration: .zero,
            frontmostApplicationID: nil,
            isScreenLocked: false,
            isSystemSleeping: false
        )
        let decision = resolver.resolve(
            configuration: configuration,
            snapshot: snapshot,
            runtimeState: BehaviorRuntimeState(
                presentation: latestPresentation,
                randomSequenceID: currentRandomSequenceID
            )
        )
        latestDecision = decision
        apply(decision, at: now, restartBaseSequence: true)
        return true
    }

    private func prepareRandomSelectionIfNeeded(
        configuration: BehaviorConfiguration
    ) {
        guard configuration.stationaryBehaviorMode == .random else {
            return
        }
        let validIDs = configuration.randomSequenceIDs.filter { sequenceID in
            configuration.sequences.contains(where: { $0.id == sequenceID })
        }
        guard !validIDs.isEmpty else {
            resetRandomSelection()
            return
        }
        if let currentRandomSequenceID,
           !validIDs.contains(currentRandomSequenceID) {
            self.currentRandomSequenceID = nil
            randomSequenceBag = []
        }
        randomSequenceBag.removeAll { !validIDs.contains($0) }
        let completedCurrentRandomSequence: Bool
        if motionScheduler.isBaseSequenceComplete,
           case .sequence(_, source: .random) = latestDecision {
            completedCurrentRandomSequence = true
        } else {
            completedCurrentRandomSequence = false
        }
        if currentRandomSequenceID == nil || completedCurrentRandomSequence {
            currentRandomSequenceID = nextRandomSequenceID(from: validIDs)
        }
    }

    private func nextRandomSequenceID(from sequenceIDs: [String]) -> String? {
        let uniqueIDs = sequenceIDs.reduce(into: [String]()) { result, id in
            if !result.contains(id) { result.append(id) }
        }
        guard !uniqueIDs.isEmpty else {
            return nil
        }
        if randomSequenceBag.isEmpty {
            randomSequenceBag = uniqueIDs
        }

        var candidates = randomSequenceBag.indices.filter { index in
            randomSequenceBag.count == 1
                || randomSequenceBag[index] != currentRandomSequenceID
        }
        if candidates.isEmpty {
            candidates = Array(randomSequenceBag.indices)
        }
        let rawIndex = randomIndex(candidates.count)
        let candidateIndex = candidates[min(max(rawIndex, 0), candidates.count - 1)]
        return randomSequenceBag.remove(at: candidateIndex)
    }

    private func prepareNextRandomSelection(
        configuration: BehaviorConfiguration
    ) {
        currentRandomSequenceID = nextRandomSequenceID(
            from: configuration.randomSequenceIDs.filter { sequenceID in
                configuration.sequences.contains(where: {
                    $0.id == sequenceID
                })
            }
        )
    }

    private func resetRandomSelection() {
        randomSequenceBag = []
        currentRandomSequenceID = nil
    }

    private func emitCurrentPlaybackIfNeeded(force: Bool = false) {
        switch motionScheduler.status {
        case let .playing(playback):
            emit(playback: playback, force: force)
        case .stopped, .unavailable:
            emit(playback: nil, force: force)
        }
    }

    private func emit(
        playback: ScheduledMotion?,
        force: Bool = false
    ) {
        if hasEmittedPlayback, !force {
            switch (currentPlayback, playback) {
            case (nil, nil):
                return
            case let (current?, next?)
                where current.hasSamePlaybackIdentity(as: next):
                return
            default:
                break
            }
        }

        hasEmittedPlayback = true
        currentPlayback = playback
        onPlaybackChange(playback)
    }
}

private extension Duration {
    var timeInterval: TimeInterval {
        let components = self.components
        return TimeInterval(components.seconds)
            + TimeInterval(components.attoseconds) / 1_000_000_000_000_000_000
    }
}
