import Foundation

nonisolated struct PetPointerObservation: Equatable, Sendable {
    let screenLocation: CGPoint
    let isInsidePanel: Bool
    let isOverVisibleContent: Bool
}

@MainActor
protocol PetPointerOverlapScheduling: AnyObject {
    func schedule(after delay: Duration, action: @escaping () -> Void)
    func cancel()
}

@MainActor
final class RunLoopPetPointerOverlapScheduler: NSObject,
    PetPointerOverlapScheduling {
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
final class PetPointerOverlapLifecycle {
    static let pollingInterval = Duration.milliseconds(100)
    static let pettingDwellSampleCount = 3
    static let pointerMovementThreshold = 1.0

    private let scheduler: any PetPointerOverlapScheduling
    private let observePointer: () -> PetPointerObservation
    private let applyOpacity: (_ opacity: Double, _ animated: Bool) -> Void
    private var requestPetting: () -> Void
    private var settings: OverlaySettings = .default
    private var isAwake = false
    private var isSystemSuspended = false
    private var shouldReduceMotion = false
    private var isPettingEnabled = false
    private var isUserDragging = false
    private var isPolling = false
    private var lastOverlapState: Bool?
    private var lastAppliedOpacity: Double?
    private var previousPointerLocation: CGPoint?
    private var pettingHoverState = PettingHoverState.needsExit

    init(
        scheduler: any PetPointerOverlapScheduling =
            RunLoopPetPointerOverlapScheduler(),
        observePointer: @escaping () -> PetPointerObservation,
        applyOpacity: @escaping (_ opacity: Double, _ animated: Bool) -> Void,
        requestPetting: @escaping () -> Void = {}
    ) {
        self.scheduler = scheduler
        self.observePointer = observePointer
        self.applyOpacity = applyOpacity
        self.requestPetting = requestPetting
    }

    var isMonitoring: Bool {
        shouldMonitor && isPolling
    }

    func setSettings(_ settings: OverlaySettings) {
        self.settings = settings
        reconcile()
    }

    func setAwake(_ isAwake: Bool) {
        self.isAwake = isAwake
        reconcile()
    }

    func setSystemSuspended(_ isSystemSuspended: Bool) {
        self.isSystemSuspended = isSystemSuspended
        reconcile()
    }

    func setReduceMotion(_ shouldReduceMotion: Bool) {
        self.shouldReduceMotion = shouldReduceMotion
        reconcile()
    }

    func setPettingEnabled(_ isEnabled: Bool) {
        guard isEnabled != isPettingEnabled else {
            return
        }
        isPettingEnabled = isEnabled
        resetPettingHover()
        reconcile()
    }

    func setPettingRequestHandler(_ handler: @escaping () -> Void) {
        requestPetting = handler
    }

    func setUserDragging(_ isDragging: Bool) {
        guard isDragging != isUserDragging else {
            return
        }
        isUserDragging = isDragging
        pettingHoverState = .needsExit
        reconcile()
    }

    func stop() {
        scheduler.cancel()
        isPolling = false
        lastOverlapState = nil
        resetPettingHover()
        apply(settings.opacity, animated: false)
    }

    private var shouldMonitor: Bool {
        shouldMonitorOpacity || shouldMonitorPetting
    }

    private var shouldMonitorOpacity: Bool {
        settings.clickThrough
            && settings.pointerOverlapFadeEnabled
            && isAwake
            && !isSystemSuspended
            && !shouldReduceMotion
    }

    private var shouldMonitorPetting: Bool {
        isPettingEnabled
            && isAwake
            && !isSystemSuspended
    }

    private func reconcile() {
        scheduler.cancel()
        isPolling = false
        guard shouldMonitor else {
            let shouldAnimate = lastOverlapState == true
                && isAwake
                && !isSystemSuspended
                && !shouldReduceMotion
            lastOverlapState = nil
            resetPettingHover()
            apply(settings.opacity, animated: shouldAnimate)
            return
        }

        if !shouldMonitorOpacity {
            let shouldAnimate = lastOverlapState == true
                && isAwake
                && !isSystemSuspended
                && !shouldReduceMotion
            lastOverlapState = nil
            apply(settings.opacity, animated: shouldAnimate)
        }
        if !shouldMonitorPetting {
            resetPettingHover()
        }
        evaluateAndSchedule(advancesDwell: false)
    }

    private func evaluateAndSchedule(advancesDwell: Bool) {
        guard shouldMonitor else {
            reconcile()
            return
        }

        let observation = observePointer()
        if shouldMonitorOpacity {
            updateOpacity(isOverlapping: observation.isOverVisibleContent)
        }
        if shouldMonitorPetting {
            updatePetting(
                with: observation,
                advancesDwell: advancesDwell
            )
        }

        isPolling = true
        scheduler.schedule(after: Self.pollingInterval) { [weak self] in
            self?.evaluateAndSchedule(advancesDwell: true)
        }
    }

    private func updateOpacity(isOverlapping: Bool) {
        let shouldAnimate = lastOverlapState != nil
            && lastOverlapState != isOverlapping
        lastOverlapState = isOverlapping
        let targetOpacity = isOverlapping
            ? min(settings.opacity, settings.pointerOverlapOpacity)
            : settings.opacity
        apply(targetOpacity, animated: shouldAnimate)
    }

    private func updatePetting(
        with observation: PetPointerObservation,
        advancesDwell: Bool
    ) {
        defer {
            previousPointerLocation = observation.screenLocation
        }

        guard !isUserDragging else {
            pettingHoverState = observation.isInsidePanel
                ? .needsExit
                : .armed
            return
        }

        switch pettingHoverState {
        case .needsExit:
            if !observation.isInsidePanel {
                pettingHoverState = .armed
            }
        case .armed:
            guard observation.isOverVisibleContent else {
                return
            }
            guard didPointerMove(to: observation.screenLocation) else {
                pettingHoverState = .needsExit
                return
            }
            pettingHoverState = .dwelling(sampleCount: 0)
        case let .dwelling(sampleCount):
            guard observation.isInsidePanel else {
                pettingHoverState = .armed
                return
            }
            guard observation.isOverVisibleContent else {
                pettingHoverState = .needsExit
                return
            }
            guard advancesDwell else {
                return
            }
            let nextSampleCount = sampleCount + 1
            guard nextSampleCount >= Self.pettingDwellSampleCount else {
                pettingHoverState = .dwelling(
                    sampleCount: nextSampleCount
                )
                return
            }
            pettingHoverState = .needsExit
            requestPetting()
        }
    }

    private func didPointerMove(to location: CGPoint) -> Bool {
        guard let previousPointerLocation else {
            return false
        }
        return hypot(
            location.x - previousPointerLocation.x,
            location.y - previousPointerLocation.y
        ) >= Self.pointerMovementThreshold
    }

    private func resetPettingHover() {
        previousPointerLocation = nil
        pettingHoverState = .needsExit
    }

    private func apply(_ opacity: Double, animated: Bool) {
        guard opacity != lastAppliedOpacity else {
            return
        }
        lastAppliedOpacity = opacity
        applyOpacity(opacity, animated)
    }
}

private enum PettingHoverState: Equatable {
    case needsExit
    case armed
    case dwelling(sampleCount: Int)
}

private extension Duration {
    var timeInterval: TimeInterval {
        let components = self.components
        return TimeInterval(components.seconds)
            + TimeInterval(components.attoseconds)
                / 1_000_000_000_000_000_000
    }
}
