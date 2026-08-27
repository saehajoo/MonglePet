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
    case cursorAvoidingIdle
    case cursorAvoidingEscaping
    case cursorAvoidingRoamingMoving
    case cursorAvoidingRoamingDwelling
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
    private static let parkedTimerInterval: TimeInterval = 24 * 60 * 60
    private var timer: Timer?
    private var action: (() -> Void)?
    private(set) var timerCreationCount = 0

    func schedule(after delay: Duration, action: @escaping () -> Void) {
        self.action = action
        let timer = reusableTimer()
        timer.fireDate = Date(
            timeIntervalSinceNow: max(delay.timeInterval, 0.001)
        )
    }

    func cancel() {
        timer?.invalidate()
        timer = nil
        action = nil
    }

    @objc
    private func timerDidFire() {
        timer?.fireDate = .distantFuture
        let pendingAction = action
        action = nil
        pendingAction?()
    }

    private func reusableTimer() -> Timer {
        if let timer, timer.isValid {
            return timer
        }
        let timer = Timer(
            timeInterval: Self.parkedTimerInterval,
            target: self,
            selector: #selector(timerDidFire),
            userInfo: nil,
            repeats: true
        )
        timer.fireDate = .distantFuture
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        timerCreationCount += 1
        return timer
    }
}

@MainActor
final class PetMovementController: PetMovementControlling {
    static let defaultTickInterval: Duration = .milliseconds(33)
    static let defaultCursorIdleInterval: Duration = .milliseconds(100)
    static let defaultStopHysteresis: Duration = .milliseconds(150)
    static let defaultRetryInterval: Duration = .seconds(1)
    static let defaultScreenInset = 32.0
    static let movementComparisonTolerance = 0.000_1
    static let transitionAcceptanceTolerance = 1.0

    private let clock: any PetMovementClock
    private let tickScheduler: any PetMovementTickScheduling
    private let frontmostWindowProvider: any FrontmostWindowProviding
    private let originProvider: () -> PetMovementPoint?
    private let petSizeProvider: () -> PetMovementSize?
    private let screensProvider: () -> [PetMovementScreen]
    private let movementBoundaryProvider: () -> MovementBoundarySettings
    private let pointerProvider: () -> PetMovementPoint?
    private let randomSampleProvider: () -> PetMovementRandomSample
    private let randomDwellUnitProvider: () -> Double
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
    private var cursorAvoidingDwellStartedAt: ContinuousClock.Instant?
    private var cursorAvoidingDwellDuration: Duration?
    private var directionClassifier = MovementDirectionClassifier()
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
        movementBoundaryProvider: @escaping () -> MovementBoundarySettings = {
            .default
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
        randomDwellUnitProvider: @escaping () -> Double = {
            Double.random(in: 0...1)
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
        self.movementBoundaryProvider = movementBoundaryProvider
        self.pointerProvider = pointerProvider
        self.randomSampleProvider = randomSampleProvider
        self.randomDwellUnitProvider = randomDwellUnitProvider
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
        case .cursorAvoiding:
            prepareCursorAvoidingBaselineAndSchedule()
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
        lastMovedAt = nil
        emit(activity: .stationary)
        guard state != .inactive else {
            return
        }
        lastTickAt = clock.now
        if settings.mode == .freeRoaming {
            state = .freeRoamingMoving
            scheduleTick(after: tickInterval)
        } else if settings.mode == .cursorAvoiding {
            cursorAvoidingDwellStartedAt = nil
            cursorAvoidingDwellDuration = nil
            prepareCursorAvoidingBaselineAndSchedule()
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
        case .cursorAvoiding:
            tickCursorAvoiding()
        }
    }

    private func tickCursorFollowing() {
        let now = clock.now
        let elapsedSeconds = elapsedSeconds(to: now)
        guard let origin = originProvider(),
              let petSize = petSizeProvider(),
              let pointer = pointerProvider(),
              let route = PetMovementGeometry.cursorFollowingRoute(
                  pointer: pointer,
                  currentOrigin: origin,
                  petSize: petSize,
                  cursorDistance: settings.cursorDistance,
                  screenInset: screenInset,
                  screens: screensProvider(),
                  boundary: movementBoundaryProvider()
              ) else {
            updateStationaryActivityIfNeeded(at: now)
            scheduleTick(after: retryInterval)
            return
        }

        targetOrigin = route.targetOrigin
        if let transition = route.transition {
            let exitAdvance = PetMovementGeometry.advance(
                from: origin,
                toward: transition.exitOrigin,
                speed: settings.speed,
                elapsedSeconds: elapsedSeconds,
                stopRadius: 0
            )
            if exitAdvance.didMove {
                let didMove = apply(exitAdvance, at: now)
                if !didMove {
                    applyScreenTransition(
                        transition,
                        finalTarget: route.targetOrigin,
                        from: origin,
                        at: now
                    )
                }
            } else if exitAdvance.hasArrived {
                applyScreenTransition(
                    transition,
                    finalTarget: route.targetOrigin,
                    from: origin,
                    at: now
                )
            } else {
                updateStationaryActivityIfNeeded(at: now)
            }
            scheduleTick(after: tickInterval)
            return
        }

        let advance = PetMovementGeometry.advance(
            from: origin,
            toward: route.targetOrigin,
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
              let targetOrigin,
              let petSize = petSizeProvider() else {
            prepareFreeRoamingTargetAndSchedule()
            return
        }

        if let transition = PetMovementGeometry.screenTransition(
            from: origin,
            toward: targetOrigin,
            petSize: petSize,
            screens: screensProvider()
        ) {
            let exitAdvance = PetMovementGeometry.advance(
                from: origin,
                toward: transition.exitOrigin,
                speed: settings.speed,
                elapsedSeconds: elapsedSeconds,
                stopRadius: 0
            )
            if exitAdvance.didMove {
                let didMove = apply(exitAdvance, at: now)
                if !didMove {
                    applyScreenTransition(
                        transition,
                        finalTarget: targetOrigin,
                        from: origin,
                        at: now
                    )
                }
            } else if exitAdvance.hasArrived {
                applyScreenTransition(
                    transition,
                    finalTarget: targetOrigin,
                    from: origin,
                    at: now
                )
            } else {
                updateStationaryActivityIfNeeded(at: now)
            }
            state = .freeRoamingMoving
            scheduleTick(after: tickInterval)
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

    private func tickCursorAvoiding() {
        let now = clock.now
        let elapsedSeconds = elapsedSeconds(to: now)
        guard let origin = originProvider(),
              let petSize = petSizeProvider(),
              let pointer = pointerProvider(),
              let pointerDistance = PetMovementGeometry.distance(
                  from: pointer,
                  toPetAt: origin,
                  petSize: petSize
              ) else {
            updateStationaryActivityIfNeeded(at: now)
            scheduleTick(after: retryInterval)
            return
        }

        let releaseDistance =
            settings.cursorAvoidingDetectionDistance
            + max(64, settings.stopRadius * 2)
        let isEscaping = state == .cursorAvoidingEscaping
        if pointerDistance <= settings.cursorAvoidingDetectionDistance
            || (isEscaping && pointerDistance < releaseDistance) {
            cursorAvoidingDwellStartedAt = nil
            cursorAvoidingDwellDuration = nil
            guard let route = PetMovementGeometry.cursorAvoidingRoute(
                pointer: pointer,
                currentOrigin: origin,
                petSize: petSize,
                safeDistance: releaseDistance,
                screenInset: screenInset,
                screens: screensProvider(),
                boundary: movementBoundaryProvider()
            ) else {
                updateStationaryActivityIfNeeded(at: now)
                scheduleTick(after: retryInterval)
                return
            }
            state = .cursorAvoidingEscaping
            targetOrigin = route.targetOrigin
            move(
                along: route,
                from: origin,
                speed: settings.cursorAvoidingSpeed,
                elapsedSeconds: elapsedSeconds,
                at: now
            )
            scheduleTick(
                after: activity.isMoving
                    ? tickInterval
                    : cursorIdleInterval
            )
            return
        }

        if isEscaping {
            targetOrigin = nil
            lastTickAt = now
        }
        switch settings.cursorAvoidingIdleBehavior {
        case .stationary:
            state = .cursorAvoidingIdle
            updateStationaryActivityIfNeeded(at: now)
            scheduleTick(after: cursorIdleInterval)
        case .freeRoaming:
            tickCursorAvoidingFreeRoaming(
                now: now,
                elapsedSeconds: elapsedSeconds,
                origin: origin,
                petSize: petSize
            )
        }
    }

    private func tickCursorAvoidingFreeRoaming(
        now: ContinuousClock.Instant,
        elapsedSeconds: TimeInterval,
        origin: PetMovementPoint,
        petSize: PetMovementSize
    ) {
        if let dwellStartedAt = cursorAvoidingDwellStartedAt {
            let dwell = cursorAvoidingDwellDuration
                ?? sampledFreeRoamingDwellDuration()
            guard dwellStartedAt.duration(to: now) >= dwell else {
                state = .cursorAvoidingRoamingDwelling
                updateStationaryActivityIfNeeded(at: now)
                scheduleTick(after: cursorIdleInterval)
                return
            }
            cursorAvoidingDwellStartedAt = nil
            cursorAvoidingDwellDuration = nil
        }

        guard let targetOrigin else {
            prepareCursorAvoidingRoamingTargetAndSchedule()
            return
        }
        state = .cursorAvoidingRoamingMoving
        let route = PetMovementCursorRoute(
            targetOrigin: targetOrigin,
            transition: PetMovementGeometry.screenTransition(
                from: origin,
                toward: targetOrigin,
                petSize: petSize,
                screens: screensProvider()
            )
        )
        let advance = move(
            along: route,
            from: origin,
            speed: settings.speed,
            elapsedSeconds: elapsedSeconds,
            at: now
        )
        guard advance.hasArrived else {
            scheduleTick(after: tickInterval)
            return
        }
        self.targetOrigin = nil
        cursorAvoidingDwellStartedAt = now
        cursorAvoidingDwellDuration = sampledFreeRoamingDwellDuration()
        state = .cursorAvoidingRoamingDwelling
        scheduleTick(after: cursorIdleInterval)
    }

    private func prepareCursorAvoidingBaselineAndSchedule() {
        switch settings.cursorAvoidingIdleBehavior {
        case .stationary:
            state = .cursorAvoidingIdle
            scheduleTick(after: cursorIdleInterval)
        case .freeRoaming:
            prepareCursorAvoidingRoamingTargetAndSchedule()
        }
    }

    private func prepareCursorAvoidingRoamingTargetAndSchedule() {
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
            sample: randomSampleProvider(),
            boundary: movementBoundaryProvider()
        )
        lastTickAt = clock.now
        guard targetOrigin != nil else {
            scheduleTick(after: retryInterval)
            return
        }
        state = .cursorAvoidingRoamingMoving
        scheduleTick(after: tickInterval)
    }

    @discardableResult
    private func move(
        along route: PetMovementCursorRoute,
        from origin: PetMovementPoint,
        speed: Double,
        elapsedSeconds: TimeInterval,
        at now: ContinuousClock.Instant
    ) -> PetMovementAdvance {
        if let transition = route.transition {
            let exitAdvance = PetMovementGeometry.advance(
                from: origin,
                toward: transition.exitOrigin,
                speed: speed,
                elapsedSeconds: elapsedSeconds,
                stopRadius: 0
            )
            if exitAdvance.didMove {
                if !apply(exitAdvance, at: now) {
                    applyScreenTransition(
                        transition,
                        finalTarget: route.targetOrigin,
                        from: origin,
                        at: now
                    )
                }
            } else if exitAdvance.hasArrived {
                applyScreenTransition(
                    transition,
                    finalTarget: route.targetOrigin,
                    from: origin,
                    at: now
                )
            } else {
                updateStationaryActivityIfNeeded(at: now)
            }
            return PetMovementAdvance(
                origin: exitAdvance.origin,
                didMove: exitAdvance.didMove,
                hasArrived: false
            )
        }
        let advance = PetMovementGeometry.advance(
            from: origin,
            toward: route.targetOrigin,
            speed: speed,
            elapsedSeconds: elapsedSeconds,
            stopRadius: settings.stopRadius
        )
        apply(advance, at: now)
        return advance
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
            sample: randomSampleProvider(),
            boundary: movementBoundaryProvider()
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
            after: sampledFreeRoamingDwellDuration()
        )
    }

    private func sampledFreeRoamingDwellDuration() -> Duration {
        let maximum = settings.freeRoamingDwellMilliseconds
        guard settings.randomizesFreeRoamingDwell else {
            return .milliseconds(maximum)
        }
        let minimum = settings.freeRoamingDwellMinimumMilliseconds
        let unit = min(max(randomDwellUnitProvider(), 0), 1)
        let span = Double(maximum - minimum)
        let milliseconds = minimum + Int64((span * unit).rounded())
        return .milliseconds(milliseconds)
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

    @discardableResult
    private func apply(
        _ advance: PetMovementAdvance,
        at now: ContinuousClock.Instant
    ) -> Bool {
        if advance.didMove {
            let originBeforeRequest = originProvider()
            applyOrigin(advance.origin)
            let actualOrigin = originProvider() ?? advance.origin
            guard
                originBeforeRequest.map({
                    !originsAreNear(
                        $0,
                        actualOrigin,
                        tolerance: Self.movementComparisonTolerance
                    )
                }) ?? true
            else {
                updateStationaryActivityIfNeeded(at: now)
                return false
            }
            lastMovedAt = now
            let directionOrigin = originBeforeRequest ?? advance.origin
            emit(activity: movingActivity(from: directionOrigin, to: actualOrigin))
            return true
        } else {
            updateStationaryActivityIfNeeded(at: now)
            return false
        }
    }

    private func applyScreenTransition(
        _ transition: PetMovementScreenTransition,
        finalTarget: PetMovementPoint,
        from origin: PetMovementPoint,
        at now: ContinuousClock.Instant
    ) {
        applyOrigin(transition.entryOrigin)
        var actualOrigin = originProvider() ?? transition.entryOrigin
        if !originsAreNear(
            actualOrigin,
            transition.entryOrigin,
            tolerance: Self.transitionAcceptanceTolerance
        ) {
            applyOrigin(finalTarget)
            actualOrigin = originProvider() ?? finalTarget
        }

        guard !originsAreNear(
            origin,
            actualOrigin,
            tolerance: Self.movementComparisonTolerance
        ) else {
            updateStationaryActivityIfNeeded(at: now)
            return
        }
        lastMovedAt = now
        emit(activity: movingActivity(from: origin, to: actualOrigin))
    }

    private func originsAreNear(
        _ lhs: PetMovementPoint,
        _ rhs: PetMovementPoint,
        tolerance: Double
    ) -> Bool {
        hypot(lhs.x - rhs.x, lhs.y - rhs.y)
            <= tolerance
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

    private func movingActivity(
        from origin: PetMovementPoint,
        to actualOrigin: PetMovementPoint
    ) -> PetMovementActivity {
        let deltaX = actualOrigin.x - origin.x
        let deltaY = actualOrigin.y - origin.y
        let animation: MovementAnimationSettings? =
            if settings.mode == .cursorAvoiding,
               state == .cursorAvoidingRoamingMoving {
                settings.freeRoamingAnimation
            } else {
                settings.animationSettings(for: settings.mode)
            }
        let direction = directionClassifier.classify(
            deltaX: deltaX,
            deltaY: deltaY,
            usesDiagonals: animation?.usesDirectionalMotions == true
                && animation?.usesDiagonalMotions == true
        )
        return PetMovementActivity(
            isMoving: true,
            motionID: animation?.resolvedMotionID(
                for: direction,
                deltaX: deltaX,
                deltaY: deltaY
            )
        )
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
        cursorAvoidingDwellStartedAt = nil
        cursorAvoidingDwellDuration = nil
        directionClassifier.reset()
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
