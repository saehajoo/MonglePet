import Foundation

@MainActor
protocol FrontmostApplicationMonitoring: AnyObject {
    var currentApplicationID: String? { get }

    func start(onChange: @escaping (String?) -> Void)
    func stop()
}

@MainActor
protocol IdleTimeProviding: AnyObject {
    func currentIdleDuration() -> Duration
}

nonisolated struct SystemSessionState: Equatable, Sendable {
    var isSessionInactive: Bool
    var isScreenAsleep: Bool
    var isSystemSleeping: Bool

    static let active = SystemSessionState(
        isSessionInactive: false,
        isScreenAsleep: false,
        isSystemSleeping: false
    )

    var isScreenUnavailable: Bool {
        isSessionInactive || isScreenAsleep
    }

    var shouldSuspend: Bool {
        isScreenUnavailable || isSystemSleeping
    }
}

@MainActor
protocol SystemSessionMonitoring: AnyObject {
    var currentState: SystemSessionState { get }

    func start(onChange: @escaping (SystemSessionState) -> Void)
    func stop()
}

@MainActor
protocol ActivityClock: AnyObject {
    var now: ContinuousClock.Instant { get }
}

@MainActor
final class ContinuousActivityClock: ActivityClock {
    private let clock = ContinuousClock()

    var now: ContinuousClock.Instant {
        clock.now
    }
}

@MainActor
protocol ActivityPollScheduling: AnyObject {
    func schedule(every interval: Duration, action: @escaping () -> Void)
    func cancel()
}

@MainActor
protocol ActivitySnapshotMonitoring: AnyObject {
    var latestSnapshot: ActivitySnapshot? { get }
    var isRunning: Bool { get }

    func start(onSnapshot: @escaping (ActivitySnapshot) -> Void)
    func stop()
}
