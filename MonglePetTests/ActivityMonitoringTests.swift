import AppKit
import XCTest
@testable import MonglePet

@MainActor
final class ActivityMonitoringTests: XCTestCase {
    func testFrontmostApplicationMonitorPublishesOnlyChangedBundleIdentifiers() {
        let notificationCenter = NotificationCenter()
        var currentApplicationID: String? = "com.example.Initial"
        let monitor = FrontmostApplicationMonitor(
            notificationCenter: notificationCenter,
            currentApplicationIDProvider: { currentApplicationID },
            activatedApplicationIDProvider: { $0.object as? String }
        )
        var receivedApplicationIDs: [String?] = []

        monitor.start { receivedApplicationIDs.append($0) }
        notificationCenter.post(
            name: NSWorkspace.didActivateApplicationNotification,
            object: "com.example.Initial"
        )
        notificationCenter.post(
            name: NSWorkspace.didActivateApplicationNotification,
            object: "com.example.Next"
        )

        XCTAssertEqual(monitor.currentApplicationID, "com.example.Next")
        XCTAssertEqual(receivedApplicationIDs, ["com.example.Next"])

        monitor.stop()
        currentApplicationID = "com.example.AfterStop"
        notificationCenter.post(
            name: NSWorkspace.didActivateApplicationNotification,
            object: "com.example.AfterStop"
        )
        XCTAssertEqual(receivedApplicationIDs, ["com.example.Next"])
    }

    func testIdleTimeMonitorConvertsSecondsToNonnegativeMilliseconds() {
        var seconds: TimeInterval = 12.3459
        let monitor = IdleTimeMonitor(secondsSinceLastInput: { seconds })

        XCTAssertEqual(monitor.currentIdleDuration(), .milliseconds(12_345))

        seconds = -1
        XCTAssertEqual(monitor.currentIdleDuration(), .zero)

        seconds = .infinity
        XCTAssertEqual(monitor.currentIdleDuration(), .milliseconds(Int64.max))
    }

    func testSystemIdleTimeProviderCanReadWithoutAdditionalPermissionSetup() {
        let monitor = IdleTimeMonitor()

        XCTAssertGreaterThanOrEqual(monitor.currentIdleDuration(), .zero)
    }

    func testSystemSessionMonitorCombinesSessionScreenAndPowerNotifications() {
        let notificationCenter = NotificationCenter()
        let monitor = SystemSessionMonitor(notificationCenter: notificationCenter)
        var receivedStates: [SystemSessionState] = []
        monitor.start { receivedStates.append($0) }

        notificationCenter.post(
            name: NSWorkspace.sessionDidResignActiveNotification,
            object: nil
        )
        XCTAssertTrue(monitor.currentState.isSessionInactive)
        XCTAssertTrue(monitor.currentState.isScreenUnavailable)

        notificationCenter.post(
            name: NSWorkspace.screensDidSleepNotification,
            object: nil
        )
        notificationCenter.post(
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
        XCTAssertTrue(monitor.currentState.isScreenAsleep)
        XCTAssertTrue(monitor.currentState.isSystemSleeping)
        XCTAssertTrue(monitor.currentState.shouldSuspend)

        notificationCenter.post(
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        notificationCenter.post(
            name: NSWorkspace.screensDidWakeNotification,
            object: nil
        )
        notificationCenter.post(
            name: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil
        )
        XCTAssertEqual(monitor.currentState, .active)
        XCTAssertEqual(receivedStates.count, 6)
    }

    func testSnapshotMonitorPublishesInitialPollingAndApplicationSnapshots() throws {
        let baseInstant = ContinuousClock().now
        let frontmostMonitor = FakeFrontmostApplicationMonitor(
            currentApplicationID: "com.example.Initial"
        )
        let idleProvider = FakeIdleTimeProvider(idleDuration: .seconds(10))
        let sessionMonitor = FakeSystemSessionMonitor(currentState: .active)
        let clock = FakeActivityClock(now: baseInstant)
        let pollScheduler = FakeActivityPollScheduler()
        let monitor = ActivitySnapshotMonitor(
            frontmostApplicationMonitor: frontmostMonitor,
            idleTimeProvider: idleProvider,
            systemSessionMonitor: sessionMonitor,
            clock: clock,
            pollScheduler: pollScheduler
        )
        var snapshots: [ActivitySnapshot] = []

        monitor.start { snapshots.append($0) }

        XCTAssertTrue(monitor.isRunning)
        XCTAssertEqual(snapshots.count, 1)
        XCTAssertEqual(snapshots[0].frontmostApplicationID, "com.example.Initial")
        XCTAssertEqual(snapshots[0].idleDuration, .seconds(10))
        XCTAssertEqual(pollScheduler.scheduledInterval, .seconds(1))

        idleProvider.idleDuration = .seconds(11)
        clock.now = baseInstant.advanced(by: .seconds(1))
        pollScheduler.fire()
        XCTAssertEqual(snapshots.last?.idleDuration, .seconds(11))
        XCTAssertEqual(snapshots.last?.capturedAt, clock.now)

        frontmostMonitor.emit("com.example.Next")
        XCTAssertEqual(snapshots.last?.frontmostApplicationID, "com.example.Next")
        XCTAssertEqual(idleProvider.readCount, 3)

        let latestSnapshot = try XCTUnwrap(monitor.latestSnapshot)
        XCTAssertEqual(latestSnapshot, snapshots.last)
    }

    func testSnapshotMonitorStopsPollingWhileSuspendedAndRefreshesOnResume() {
        let frontmostMonitor = FakeFrontmostApplicationMonitor(
            currentApplicationID: "com.example.Editor"
        )
        let idleProvider = FakeIdleTimeProvider(idleDuration: .seconds(20))
        let sessionMonitor = FakeSystemSessionMonitor(currentState: .active)
        let clock = FakeActivityClock(now: ContinuousClock().now)
        let pollScheduler = FakeActivityPollScheduler()
        let monitor = ActivitySnapshotMonitor(
            frontmostApplicationMonitor: frontmostMonitor,
            idleTimeProvider: idleProvider,
            systemSessionMonitor: sessionMonitor,
            clock: clock,
            pollScheduler: pollScheduler
        )
        var snapshots: [ActivitySnapshot] = []
        monitor.start { snapshots.append($0) }
        XCTAssertEqual(idleProvider.readCount, 1)

        sessionMonitor.emit(
            SystemSessionState(
                isSessionInactive: true,
                isScreenAsleep: false,
                isSystemSleeping: false
            )
        )
        XCTAssertNil(pollScheduler.scheduledInterval)
        XCTAssertTrue(snapshots.last?.isScreenLocked == true)
        XCTAssertEqual(idleProvider.readCount, 1)

        idleProvider.idleDuration = .seconds(1)
        sessionMonitor.emit(.active)
        XCTAssertEqual(pollScheduler.scheduledInterval, .seconds(1))
        XCTAssertFalse(snapshots.last?.isScreenLocked == true)
        XCTAssertEqual(snapshots.last?.idleDuration, .seconds(1))
        XCTAssertEqual(idleProvider.readCount, 2)

        monitor.stop()
        XCTAssertFalse(monitor.isRunning)
        XCTAssertNil(pollScheduler.scheduledInterval)
        XCTAssertEqual(frontmostMonitor.stopCount, 1)
        XCTAssertEqual(sessionMonitor.stopCount, 1)
    }

    func testAppCoordinatorOwnsActivityMonitorLifecycleAndLatestSnapshot() throws {
        let activityMonitor = FakeActivitySnapshotMonitor()
        let settingsDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: settingsDirectoryURL) }
        let coordinator = AppCoordinator(
            settingsStore: AppSettingsStore(
                settingsURL: settingsDirectoryURL.appendingPathComponent("settings.json")
            ),
            activityMonitor: activityMonitor
        )
        coordinator.start()
        defer { coordinator.stop() }

        XCTAssertTrue(activityMonitor.isRunning)
        XCTAssertTrue(coordinator.isPetAwake)
        XCTAssertEqual(
            coordinator.currentSettings.sequences,
            BuiltInBehaviorPresets.sequences
        )
        let activeSnapshot = ActivitySnapshot(
            capturedAt: ContinuousClock().now,
            idleDuration: .seconds(30),
            frontmostApplicationID: "com.example.Editor",
            isScreenLocked: false,
            isSystemSleeping: false
        )
        activityMonitor.emit(activeSnapshot)
        XCTAssertEqual(coordinator.currentMotionID, "idle")

        let snapshot = ActivitySnapshot(
            capturedAt: ContinuousClock().now,
            idleDuration: .seconds(30),
            frontmostApplicationID: "com.example.Editor",
            isScreenLocked: true,
            isSystemSleeping: false
        )
        activityMonitor.emit(snapshot)

        XCTAssertEqual(try XCTUnwrap(coordinator.latestActivitySnapshot), snapshot)

        coordinator.stop()
        XCTAssertFalse(activityMonitor.isRunning)
    }

    func testAppCoordinatorRestoresUserPresentationFromSettings() throws {
        let settingsDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: settingsDirectoryURL) }
        let store = AppSettingsStore(
            settingsURL: settingsDirectoryURL.appendingPathComponent("settings.json")
        )
        let savedSettings = AppSettings(
            selectedPetInstallationID: nil,
            lastUserPresentation: .tuckedAway,
            behaviorMode: .manual,
            overlay: OverlaySettings(
                screenIdentifier: nil,
                originX: 100,
                originY: 100,
                width: 256,
                clickThrough: true
            ),
            manualSequenceID: nil,
            sequences: [],
            automaticRules: []
        )
        try store.save(savedSettings)
        let coordinator = AppCoordinator(
            settingsStore: store,
            activityMonitor: FakeActivitySnapshotMonitor()
        )

        coordinator.start()
        defer { coordinator.stop() }

        XCTAssertEqual(
            coordinator.currentSettings.lastUserPresentation,
            savedSettings.lastUserPresentation
        )
        XCTAssertEqual(coordinator.currentSettings.behaviorMode, savedSettings.behaviorMode)
        XCTAssertEqual(
            coordinator.currentSettings.overlay.width,
            savedSettings.overlay.width
        )
        XCTAssertEqual(
            coordinator.currentSettings.overlay.clickThrough,
            savedSettings.overlay.clickThrough
        )
        XCTAssertFalse(coordinator.isPetAwake)
    }
}

@MainActor
private final class FakeFrontmostApplicationMonitor: FrontmostApplicationMonitoring {
    private var onChange: ((String?) -> Void)?
    private(set) var stopCount = 0
    var currentApplicationID: String?

    init(currentApplicationID: String?) {
        self.currentApplicationID = currentApplicationID
    }

    func start(onChange: @escaping (String?) -> Void) {
        self.onChange = onChange
    }

    func stop() {
        stopCount += 1
        onChange = nil
    }

    func emit(_ applicationID: String?) {
        currentApplicationID = applicationID
        onChange?(applicationID)
    }
}

@MainActor
private final class FakeIdleTimeProvider: IdleTimeProviding {
    var idleDuration: Duration
    private(set) var readCount = 0

    init(idleDuration: Duration) {
        self.idleDuration = idleDuration
    }

    func currentIdleDuration() -> Duration {
        readCount += 1
        return idleDuration
    }
}

@MainActor
private final class FakeSystemSessionMonitor: SystemSessionMonitoring {
    private var onChange: ((SystemSessionState) -> Void)?
    private(set) var stopCount = 0
    var currentState: SystemSessionState

    init(currentState: SystemSessionState) {
        self.currentState = currentState
    }

    func start(onChange: @escaping (SystemSessionState) -> Void) {
        self.onChange = onChange
    }

    func stop() {
        stopCount += 1
        onChange = nil
    }

    func emit(_ state: SystemSessionState) {
        currentState = state
        onChange?(state)
    }
}

@MainActor
private final class FakeActivityClock: ActivityClock {
    var now: ContinuousClock.Instant

    init(now: ContinuousClock.Instant) {
        self.now = now
    }
}

@MainActor
private final class FakeActivityPollScheduler: ActivityPollScheduling {
    private var action: (() -> Void)?
    private(set) var scheduledInterval: Duration?

    func schedule(every interval: Duration, action: @escaping () -> Void) {
        scheduledInterval = interval
        self.action = action
    }

    func cancel() {
        scheduledInterval = nil
        action = nil
    }

    func fire() {
        action?()
    }
}

@MainActor
private final class FakeActivitySnapshotMonitor: ActivitySnapshotMonitoring {
    private var onSnapshot: ((ActivitySnapshot) -> Void)?
    private(set) var latestSnapshot: ActivitySnapshot?
    private(set) var isRunning = false

    func start(onSnapshot: @escaping (ActivitySnapshot) -> Void) {
        self.onSnapshot = onSnapshot
        isRunning = true
    }

    func stop() {
        onSnapshot = nil
        isRunning = false
    }

    func emit(_ snapshot: ActivitySnapshot) {
        latestSnapshot = snapshot
        onSnapshot?(snapshot)
    }
}
