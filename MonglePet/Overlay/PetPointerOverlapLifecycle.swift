import Foundation

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

    private let scheduler: any PetPointerOverlapScheduling
    private let isPointerOverVisibleContent: () -> Bool
    private let applyOpacity: (_ opacity: Double, _ animated: Bool) -> Void
    private var settings: OverlaySettings = .default
    private var isAwake = false
    private var isSystemSuspended = false
    private var shouldReduceMotion = false
    private var lastOverlapState: Bool?
    private var lastAppliedOpacity: Double?

    init(
        scheduler: any PetPointerOverlapScheduling =
            RunLoopPetPointerOverlapScheduler(),
        isPointerOverVisibleContent: @escaping () -> Bool,
        applyOpacity: @escaping (_ opacity: Double, _ animated: Bool) -> Void
    ) {
        self.scheduler = scheduler
        self.isPointerOverVisibleContent = isPointerOverVisibleContent
        self.applyOpacity = applyOpacity
    }

    var isMonitoring: Bool {
        shouldMonitor && lastOverlapState != nil
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

    func stop() {
        scheduler.cancel()
        lastOverlapState = nil
        apply(settings.opacity, animated: false)
    }

    private var shouldMonitor: Bool {
        settings.clickThrough
            && settings.pointerOverlapFadeEnabled
            && isAwake
            && !isSystemSuspended
            && !shouldReduceMotion
    }

    private func reconcile() {
        scheduler.cancel()
        guard shouldMonitor else {
            let shouldAnimate = lastOverlapState == true
                && isAwake
                && !isSystemSuspended
                && !shouldReduceMotion
            lastOverlapState = nil
            apply(settings.opacity, animated: shouldAnimate)
            return
        }

        evaluateAndSchedule()
    }

    private func evaluateAndSchedule() {
        guard shouldMonitor else {
            reconcile()
            return
        }

        let isOverlapping = isPointerOverVisibleContent()
        let shouldAnimate = lastOverlapState != nil
            && lastOverlapState != isOverlapping
        lastOverlapState = isOverlapping
        let targetOpacity = isOverlapping
            ? min(settings.opacity, settings.pointerOverlapOpacity)
            : settings.opacity
        apply(targetOpacity, animated: shouldAnimate)

        scheduler.schedule(after: Self.pollingInterval) { [weak self] in
            self?.evaluateAndSchedule()
        }
    }

    private func apply(_ opacity: Double, animated: Bool) {
        guard opacity != lastAppliedOpacity else {
            return
        }
        lastAppliedOpacity = opacity
        applyOpacity(opacity, animated)
    }
}

private extension Duration {
    var timeInterval: TimeInterval {
        let components = self.components
        return TimeInterval(components.seconds)
            + TimeInterval(components.attoseconds)
                / 1_000_000_000_000_000_000
    }
}
