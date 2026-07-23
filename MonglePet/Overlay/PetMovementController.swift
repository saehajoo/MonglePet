import AppKit
import Foundation

nonisolated struct PetMovementActivity: Equatable, Sendable {
    let isMoving: Bool
    let motionID: String?

    static let stationary = PetMovementActivity(
        isMoving: false,
        motionID: nil
    )
}

nonisolated enum PetMovementControllerState: Equatable, Sendable {
    case inactive
    case cursorFollowing
    case freeRoamingMoving
    case freeRoamingSettling
    case freeRoamingDwelling
}

@MainActor
protocol PetMovementClock: AnyObject {
    var now: ContinuousClock.Instant { get }
}

@MainActor
final class ContinuousPetMovementClock: PetMovementClock {
    private let clock = ContinuousClock()

    var now: ContinuousClock.Instant {
        clock.now
    }
}

@MainActor
protocol PetMovementTickScheduling: AnyObject {
    func schedule(after delay: Duration, action: @escaping () -> Void)
    func cancel()
}

@MainActor
protocol PetMovementControlling: AnyObject {
    func update(
        settings: PetMovementSettings,
        isMovementAllowed: Bool
    )
    func stop()
    func invalidateEnvironment()
}

@MainActor
final class RunLoopPetMovementTickScheduler: NSObject, PetMovementTickScheduling {
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
final class PetMovementController: PetMovementControlling {
    static let defaultTickInterval: Duration = .milliseconds(33)
    static let defaultCursorIdleInterval: Duration = .milliseconds(100)
    static let defaultStopHysteresis: Duration = .milliseconds(150)
    static let defaultRetryInterval: Duration = .seconds(1)
    static let defaultScreenInset = 32.0

    private let clock: any PetMovementClock
    private let tickScheduler: any PetMovementTickScheduling
    private let frontmostWindowProvider: any FrontmostWindowProviding
    private let originProvider: () -> PetMovementPoint?
    private let petSizeProvider: () -> PetMovementSize?
    private let screensProvider: () -> [PetMovementScreen]
    private let pointerProvider: () -> PetMovementPoint?
    private let randomSampleProvider: () -> PetMovementRandomSample
    private let applyOrigin: (PetMovementPoint) -> Void
    private var onActivityChange: (PetMovementActivity) -> Void
    private let tickInterval: Duration
    private let cursorIdleInterval: Duration
    private let stopHysteresis: Duration
    private let retryInterval: Duration
    private let screenInset: Double
    private var settings: PetMovementSettings = .default
    private var isMovementAllowed = false
    private var lastTickAt: ContinuousClock.Instant?
    private var lastMovedAt: ContinuousClock.Instant?
    private(set) var targetOrigin: PetMovementPoint?
    private(set) var state: PetMovementControllerState = .inactive
    private(set) var activity: PetMovementActivity = .stationary

    init(
        originProvider: @escaping () -> PetMovementPoint?,
        petSizeProvider: @escaping () -> PetMovementSize?,
        applyOrigin: @escaping (PetMovementPoint) -> Void,
        clock: any PetMovementClock = ContinuousPetMovementClock(),
        tickScheduler: any PetMovementTickScheduling = RunLoopPetMovementTickScheduler(),
        frontmostWindowProvider: any FrontmostWindowProviding = FrontmostWindowProvider(),
        screensProvider: @escaping () -> [PetMovementScreen] = {
            AppKitDisplayLayoutReader.currentMovementScreens()
        },
        pointerProvider: @escaping () -> PetMovementPoint? = {
            let location = NSEvent.mouseLocation
            return PetMovementPoint(
                x: Double(location.x),
                y: Double(location.y)
            )
        },
        randomSampleProvider: @escaping () -> PetMovementRandomSample = {
            PetMovementRandomSample(
                screen: Double.random(in: 0...1),
                horizontal: Double.random(in: 0...1),
                vertical: Double.random(in: 0...1)
            )
        },
        tickInterval: Duration = defaultTickInterval,
        cursorIdleInterval: Duration = defaultCursorIdleInterval,
        stopHysteresis: Duration = defaultStopHysteresis,
        retryInterval: Duration = defaultRetryInterval,
        screenInset: Double = defaultScreenInset,
        onActivityChange: @escaping (PetMovementActivity) -> Void = { _ in }
    ) {
        self.originProvider = originProvider
        self.petSizeProvider = petSizeProvider
        self.applyOrigin = applyOrigin
        self.clock = clock
        self.tickScheduler = tickScheduler
        self.frontmostWindowProvider = frontmostWindowProvider
        self.screensProvider = screensProvider
        self.pointerProvider = pointerProvider
        self.randomSampleProvider = randomSampleProvider
        self.tickInterval = max(tickInterval, .milliseconds(1))
        self.cursorIdleInterval = max(cursorIdleInterval, tickInterval)
        self.stopHysteresis = max(stopHysteresis, .zero)
        self.retryInterval = max(retryInterval, .milliseconds(100))
        self.screenInset = max(screenInset, 0)
        self.onActivityChange = onActivityChange
    }

    func update(
        settings: PetMovementSettings,
        isMovementAllowed: Bool
    ) {
        let shouldRun = isMovementAllowed
            && settings.isValid
            && settings.mode != .fixed
        guard shouldRun else {
            self.settings = settings
            self.isMovementAllowed = isMovementAllowed
            deactivate()
            return
        }

        let requiresRestart = state == .inactive
            || self.settings != settings
            || !self.isMovementAllowed
        self.settings = settings
        self.isMovementAllowed = true
        guard requiresRestart else {
            return
        }

        resetRuntimeState()
        lastTickAt = clock.now
        switch settings.mode {
        case .fixed:
            deactivate()
        case .cursorFollowing:
            state = .cursorFollowing
            scheduleTick(after: tickInterval)
        case .freeRoaming:
            state = .freeRoamingMoving
            prepareFreeRoamingTargetAndSchedule()
        }
    }

    func stop() {
        isMovementAllowed = false
        deactivate()
    }

    func setActivityChangeHandler(
        _ handler: @escaping (PetMovementActivity) -> Void
    ) {
        onActivityChange = handler
        handler(activity)
    }

    func invalidateEnvironment() {
        frontmostWindowProvider.invalidate()
        targetOrigin = nil
        guard state != .inactive else {
            return
        }
        lastTickAt = clock.now
        if settings.mode == .freeRoaming {
            state = .freeRoamingMoving
            scheduleTick(after: tickInterval)
        }
    }

    private func tick() {
        guard isMovementAllowed, settings.mode != .fixed else {
            deactivate()
            return
        }

        switch settings.mode {
        case .fixed:
            deactivate()
        case .cursorFollowing:
            tickCursorFollowing()
        case .freeRoaming:
            tickFreeRoaming()
        }
    }

    private func tickCursorFollowing() {
        let now = clock.now
        let elapsedSeconds = elapsedSeconds(to: now)
        guard let origin = originProvider(),
              let petSize = petSizeProvider(),
              let pointer = pointerProvider(),
              let target = PetMovementGeometry.cursorFollowingTargetOrigin(
                  pointer: pointer,
                  currentOrigin: origin,
                  petSize: petSize,
                  cursorDistance: settings.cursorDistance,
                  screenInset: screenInset,
                  screens: screensProvider()
              ) else {
            updateStationaryActivityIfNeeded(at: now)
            scheduleTick(after: retryInterval)
            return
        }

        targetOrigin = target
        let advance = PetMovementGeometry.advance(
            from: origin,
            toward: target,
            speed: settings.speed,
            elapsedSeconds: elapsedSeconds,
            stopRadius: settings.stopRadius
        )
        apply(advance, at: now)
        scheduleTick(
            after: advance.didMove || activity.isMoving
                ? tickInterval
                : cursorIdleInterval
        )
    }

    private func tickFreeRoaming() {
        let now = clock.now
        let elapsedSeconds = elapsedSeconds(to: now)
        guard let origin = originProvider(),
              let targetOrigin else {
            prepareFreeRoamingTargetAndSchedule()
            return
        }

        let advance = PetMovementGeometry.advance(
            from: origin,
            toward: targetOrigin,
            speed: settings.speed,
            elapsedSeconds: elapsedSeconds,
            stopRadius: settings.stopRadius
        )
        apply(advance, at: now)

        guard advance.hasArrived else {
            state = .freeRoamingMoving
            scheduleTick(after: tickInterval)
            return
        }

        self.targetOrigin = nil
        if advance.didMove, stopHysteresis > .zero {
            state = .freeRoamingSettling
            scheduleTick(after: stopHysteresis)
        } else {
            beginFreeRoamingDwell()
        }
    }

    private func prepareFreeRoamingTargetAndSchedule() {
        guard let petSize = petSizeProvider() else {
            scheduleTick(after: retryInterval)
            return
        }
        let preferredWindow = settings.prefersFrontmostWindow
            ? frontmostWindowProvider.representativeWindow()
            : nil
        targetOrigin = PetMovementGeometry.freeRoamingTargetOrigin(
            screens: screensProvider(),
            petSize: petSize,
            screenInset: screenInset,
            preferredWindow: preferredWindow,
            sample: randomSampleProvider()
        )
        lastTickAt = clock.now
        guard targetOrigin != nil else {
            scheduleTick(after: retryInterval)
            return
        }
        state = .freeRoamingMoving
        scheduleTick(after: tickInterval)
    }

    private func beginFreeRoamingDwell() {
        emit(activity: .stationary)
        state = .freeRoamingDwelling
        lastMovedAt = nil
        scheduleTick(
            after: .milliseconds(settings.freeRoamingDwellMilliseconds)
        )
    }

    private func freeRoamingDelayDidFinish() {
        guard isMovementAllowed, settings.mode == .freeRoaming else {
            deactivate()
            return
        }
        if state == .freeRoamingSettling {
            beginFreeRoamingDwell()
        } else if state == .freeRoamingDwelling {
            prepareFreeRoamingTargetAndSchedule()
        }
    }

    private func apply(
        _ advance: PetMovementAdvance,
        at now: ContinuousClock.Instant
    ) {
        if advance.didMove {
            applyOrigin(advance.origin)
            lastMovedAt = now
            emit(
                activity: PetMovementActivity(
                    isMoving: true,
                    motionID: movementMotionID
                )
            )
        } else {
            updateStationaryActivityIfNeeded(at: now)
        }
    }

    private func updateStationaryActivityIfNeeded(
        at now: ContinuousClock.Instant
    ) {
        guard activity.isMoving else {
            return
        }
        guard let lastMovedAt else {
            emit(activity: .stationary)
            return
        }
        if lastMovedAt.duration(to: now) >= stopHysteresis {
            emit(activity: .stationary)
            self.lastMovedAt = nil
        }
    }

    private var movementMotionID: String? {
        switch settings.mode {
        case .fixed:
            nil
        case .cursorFollowing:
            settings.cursorFollowingMotionID
        case .freeRoaming:
            settings.freeRoamingMotionID
        }
    }

    private func elapsedSeconds(
        to now: ContinuousClock.Instant
    ) -> TimeInterval {
        guard let lastTickAt else {
            self.lastTickAt = now
            return 0
        }
        let elapsed = lastTickAt.duration(to: now)
        self.lastTickAt = now
        return max(elapsed.timeInterval, 0)
    }

    private func scheduleTick(after delay: Duration) {
        tickScheduler.schedule(after: delay) { [weak self] in
            guard let self else {
                return
            }
            if self.state == .freeRoamingSettling
                || self.state == .freeRoamingDwelling {
                self.freeRoamingDelayDidFinish()
            } else {
                self.tick()
            }
        }
    }

    private func deactivate() {
        resetRuntimeState()
        state = .inactive
    }

    private func resetRuntimeState() {
        tickScheduler.cancel()
        targetOrigin = nil
        lastTickAt = nil
        lastMovedAt = nil
        emit(activity: .stationary)
    }

    private func emit(activity: PetMovementActivity) {
        guard activity != self.activity else {
            return
        }
        self.activity = activity
        onActivityChange(activity)
    }
}

private extension Duration {
    var timeInterval: TimeInterval {
        let components = self.components
        return TimeInterval(components.seconds)
            + TimeInterval(components.attoseconds) / 1_000_000_000_000_000_000
    }
}
