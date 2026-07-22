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
    private var lastAdvancedAt: ContinuousClock.Instant?
    private var hasEmittedPlayback = false
    private(set) var currentPlayback: ScheduledMotion?
    private(set) var latestDecision: BehaviorDecision?

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

    var isPaused: Bool {
        motionScheduler.isPaused
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
        let decision = resolver.resolve(
            configuration: BuiltInBehaviorPresets.configuration(for: settings),
            snapshot: effectiveSnapshot,
            runtimeState: BehaviorRuntimeState(
                presentation: settings.lastUserPresentation
            )
        )
        latestDecision = decision
        apply(decision, at: now)
    }

    func stop() {
        tickScheduler.cancel()
        motionScheduler.stop()
        resolver = BehaviorResolver()
        lastAdvancedAt = nil
        latestDecision = nil
        emit(playback: nil)
    }

    private func apply(
        _ decision: BehaviorDecision,
        at now: ContinuousClock.Instant
    ) {
        switch decision {
        case .tuckedAway, .suspended:
            tickScheduler.cancel()
            motionScheduler.pause()
            lastAdvancedAt = now
        case let .sequence(sequence, _):
            motionScheduler.resume()
            _ = motionScheduler.request(sequence)
            lastAdvancedAt = now
            emitCurrentPlaybackIfNeeded()
            scheduleNextBoundary()
        case .unavailable:
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
            let remainingDuration = motionScheduler.activeStepRemainingDuration,
            remainingDuration > .zero
        else {
            return
        }

        tickScheduler.schedule(after: remainingDuration) { [weak self] in
            self?.boundaryTimerDidFire()
        }
    }

    private func boundaryTimerDidFire() {
        advance(to: clock.now)
        emitCurrentPlaybackIfNeeded()
        scheduleNextBoundary()
    }

    private func emitCurrentPlaybackIfNeeded() {
        switch motionScheduler.status {
        case let .playing(playback):
            emit(playback: playback)
        case .stopped, .unavailable:
            emit(playback: nil)
        }
    }

    private func emit(playback: ScheduledMotion?) {
        guard !hasEmittedPlayback || playback != currentPlayback else {
            return
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
