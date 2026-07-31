import Foundation

@MainActor
final class RunLoopActivityPollScheduler: NSObject, ActivityPollScheduling {
    private var timer: Timer?
    private var action: (() -> Void)?

    func schedule(every interval: Duration, action: @escaping () -> Void) {
        cancel()
        self.action = action
        let timer = Timer(
            timeInterval: max(interval.timeInterval, 0.1),
            target: self,
            selector: #selector(timerDidFire),
            userInfo: nil,
            repeats: true
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
        action?()
    }
}

@MainActor
final class ActivitySnapshotMonitor: ActivitySnapshotMonitoring {
    static let defaultPollInterval: Duration = .seconds(1)

    private let frontmostApplicationMonitor: any FrontmostApplicationMonitoring
    private let idleTimeProvider: any IdleTimeProviding
    private let systemSessionMonitor: any SystemSessionMonitoring
    private let clock: any ActivityClock
    private let pollScheduler: any ActivityPollScheduling
    private let pollInterval: Duration
    private var onSnapshot: ((ActivitySnapshot) -> Void)?
    private var currentApplicationID: String?
    private var currentSessionState: SystemSessionState = .active
    private var lastIdleDuration: Duration = .zero
    private(set) var latestSnapshot: ActivitySnapshot?
    private(set) var isRunning = false

    init(
        frontmostApplicationMonitor: any FrontmostApplicationMonitoring = FrontmostApplicationMonitor(),
        idleTimeProvider: any IdleTimeProviding = IdleTimeMonitor(),
        systemSessionMonitor: any SystemSessionMonitoring = SystemSessionMonitor(),
        clock: any ActivityClock = ContinuousActivityClock(),
        pollScheduler: any ActivityPollScheduling = RunLoopActivityPollScheduler(),
        pollInterval: Duration = defaultPollInterval
    ) {
        self.frontmostApplicationMonitor = frontmostApplicationMonitor
        self.idleTimeProvider = idleTimeProvider
        self.systemSessionMonitor = systemSessionMonitor
        self.clock = clock
        self.pollScheduler = pollScheduler
        self.pollInterval = max(pollInterval, .milliseconds(100))
    }

    func start(onSnapshot: @escaping (ActivitySnapshot) -> Void) {
        guard !isRunning else {
            return
        }

        self.onSnapshot = onSnapshot
        frontmostApplicationMonitor.start { [weak self] applicationID in
            self?.applicationDidChange(applicationID)
        }
        systemSessionMonitor.start { [weak self] state in
            self?.sessionStateDidChange(state)
        }

        currentApplicationID = frontmostApplicationMonitor.currentApplicationID
        currentSessionState = systemSessionMonitor.currentState
        isRunning = true
        publishSnapshot(readIdleTime: !currentSessionState.shouldSuspend)
        updatePollingState()
    }

    func stop() {
        guard isRunning else {
            return
        }

        pollScheduler.cancel()
        frontmostApplicationMonitor.stop()
        systemSessionMonitor.stop()
        onSnapshot = nil
        isRunning = false
    }

    private func applicationDidChange(_ applicationID: String?) {
        guard isRunning else {
            return
        }

        currentApplicationID = applicationID
        publishSnapshot(readIdleTime: !currentSessionState.shouldSuspend)
    }

    private func sessionStateDidChange(_ state: SystemSessionState) {
        guard isRunning else {
            return
        }

        currentSessionState = state
        updatePollingState()
        publishSnapshot(readIdleTime: !state.shouldSuspend)
    }

    private func updatePollingState() {
        pollScheduler.cancel()
        guard isRunning, !currentSessionState.shouldSuspend else {
            return
        }

        pollScheduler.schedule(every: pollInterval) { [weak self] in
            self?.publishSnapshot(readIdleTime: true)
        }
    }

    private func publishSnapshot(readIdleTime: Bool) {
        if readIdleTime {
            lastIdleDuration = max(idleTimeProvider.currentIdleDuration(), .zero)
        }

        let snapshot = ActivitySnapshot(
            capturedAt: clock.now,
            idleDuration: lastIdleDuration,
            frontmostApplicationID: currentApplicationID,
            isScreenLocked: currentSessionState.isScreenUnavailable,
            isSystemSleeping: currentSessionState.isSystemSleeping
        )
        latestSnapshot = snapshot
        onSnapshot?(snapshot)
    }
}

private extension Duration {
    var timeInterval: TimeInterval {
        let components = self.components
        return TimeInterval(components.seconds)
            + TimeInterval(components.attoseconds) / 1_000_000_000_000_000_000
    }
}
