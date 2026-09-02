import Foundation

/// 이동 컨트롤러의 짧은 위치 갱신과 행동 프레임 경계를 분리한다.
/// 같은 행동 ID가 반복 전달되면 현재 타임라인과 타이머를 그대로 유지한다.
@MainActor
final class PetMovementBehaviorRuntime {
    private var motionScheduler: MotionScheduler
    private let clock: any BehaviorRuntimeClock
    private let tickScheduler: any BehaviorTickScheduling
    private let onPlaybackChange: (ScheduledMotion?) -> Void
    private var sequencesByID: [String: BehaviorSequence] = [:]
    private var activeBehaviorID: String?
    private var lastAdvancedAt: ContinuousClock.Instant?
    private var hasEmittedPlayback = false
    private(set) var currentPlayback: ScheduledMotion?

    init(
        petDefinition: PetDefinition,
        clock: any BehaviorRuntimeClock = ContinuousBehaviorRuntimeClock(),
        tickScheduler: any BehaviorTickScheduling = RunLoopBehaviorTickScheduler(),
        onPlaybackChange: @escaping (ScheduledMotion?) -> Void
    ) {
        motionScheduler = MotionScheduler(petDefinition: petDefinition)
        self.clock = clock
        self.tickScheduler = tickScheduler
        self.onPlaybackChange = onPlaybackChange
    }

    func updateSequences(_ sequences: [BehaviorSequence]) {
        sequencesByID = Dictionary(
            sequences.map { ($0.id, $0) },
            uniquingKeysWith: { current, _ in current }
        )
        if let activeBehaviorID,
           sequencesByID[activeBehaviorID] == nil {
            setActivity(.stationary)
        }
    }

    func setActivity(_ activity: PetMovementActivity) {
        let requestedBehaviorID = activity.isMoving ? activity.motionID : nil
        guard requestedBehaviorID != activeBehaviorID else {
            return
        }

        let now = clock.now
        advance(to: now)
        guard
            let requestedBehaviorID,
            let sequence = sequencesByID[requestedBehaviorID]
        else {
            stop(at: now)
            return
        }

        activeBehaviorID = requestedBehaviorID
        let loopingSequence = BehaviorSequence(
            id: sequence.id,
            displayName: sequence.displayName,
            steps: sequence.steps,
            repeats: true
        )
        guard motionScheduler.request(loopingSequence) else {
            stop(at: now)
            return
        }
        lastAdvancedAt = now
        emitCurrentPlaybackIfNeeded()
        scheduleNextBoundary()
    }

    func replacePetDefinition(_ petDefinition: PetDefinition) {
        tickScheduler.cancel()
        motionScheduler.stop()
        motionScheduler = MotionScheduler(petDefinition: petDefinition)
        activeBehaviorID = nil
        lastAdvancedAt = nil
        currentPlayback = nil
        hasEmittedPlayback = false
    }

    func stop() {
        stop(at: clock.now)
    }

    private func stop(at now: ContinuousClock.Instant) {
        tickScheduler.cancel()
        motionScheduler.stop()
        activeBehaviorID = nil
        lastAdvancedAt = now
        emit(nil)
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
            let remaining = motionScheduler.activeCycleRemainingDuration,
            remaining > .zero
        else {
            return
        }
        tickScheduler.schedule(after: remaining) { [weak self] in
            self?.boundaryTimerDidFire()
        }
    }

    private func boundaryTimerDidFire() {
        advance(to: clock.now)
        emitCurrentPlaybackIfNeeded(force: true)
        scheduleNextBoundary()
    }

    private func emitCurrentPlaybackIfNeeded(force: Bool = false) {
        switch motionScheduler.status {
        case let .playing(playback):
            emit(playback, force: force)
        case .stopped, .unavailable:
            emit(nil, force: force)
        }
    }

    private func emit(_ playback: ScheduledMotion?, force: Bool = false) {
        guard force || !hasEmittedPlayback || currentPlayback != playback else {
            return
        }
        hasEmittedPlayback = true
        currentPlayback = playback
        onPlaybackChange(playback)
    }
}
