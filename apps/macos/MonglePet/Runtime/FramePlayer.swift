import Foundation

@MainActor
protocol FrameScheduling: AnyObject {
    func schedule(after delay: Duration, action: @escaping () -> Void)
    func cancel()
}

@MainActor
final class RunLoopFrameScheduler: NSObject, FrameScheduling {
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
final class FramePlayer {
    private let scheduler: any FrameScheduling
    private let onFrameChange: (MotionFrame) -> Void
    private var motion: PetMotion?
    private var currentFrameRemainingDuration: Duration?
    private var loopsCurrentMotion = false
    private(set) var currentFrameIndex = 0
    private(set) var isPlaying = false
    private(set) var playbackSpeed = 1.0

    init(
        scheduler: any FrameScheduling = RunLoopFrameScheduler(),
        onFrameChange: @escaping (MotionFrame) -> Void
    ) {
        self.scheduler = scheduler
        self.onFrameChange = onFrameChange
    }

    func play(
        _ motion: PetMotion,
        playbackSpeed: Double = 1,
        cycleElapsedDuration: Duration = .zero,
        loops: Bool? = nil
    ) {
        scheduler.cancel()
        self.motion = motion
        loopsCurrentMotion = loops ?? motion.loops
        self.playbackSpeed = playbackSpeed.isFinite && playbackSpeed > 0
            ? playbackSpeed
            : 1
        let position = framePosition(
            in: motion,
            at: max(cycleElapsedDuration, .zero)
        )
        currentFrameIndex = position.index
        currentFrameRemainingDuration = position.remainingDuration

        guard motion.frames.indices.contains(currentFrameIndex) else {
            isPlaying = false
            return
        }

        isPlaying = true
        onFrameChange(motion.frames[currentFrameIndex])
        scheduleCurrentFrameIfNeeded()
    }

    func pause() {
        guard isPlaying else {
            return
        }

        scheduler.cancel()
        isPlaying = false
    }

    func resume() {
        guard !isPlaying, motion?.frames.indices.contains(currentFrameIndex) == true else {
            return
        }

        isPlaying = true
        scheduleCurrentFrameIfNeeded()
    }

    func stop() {
        scheduler.cancel()
        motion = nil
        currentFrameIndex = 0
        currentFrameRemainingDuration = nil
        loopsCurrentMotion = false
        isPlaying = false
        playbackSpeed = 1
    }

    private func scheduleCurrentFrameIfNeeded() {
        guard
            isPlaying,
            let motion,
            motion.frames.count > 1
        else {
            return
        }

        let adjustedDuration = currentFrameRemainingDuration
            ?? motion.frames[currentFrameIndex].duration / playbackSpeed
        currentFrameRemainingDuration = nil
        scheduler.schedule(after: adjustedDuration) { [weak self] in
            self?.advanceFrame()
        }
    }

    private func advanceFrame() {
        guard isPlaying, let motion else {
            return
        }

        let nextFrameIndex = currentFrameIndex + 1
        if nextFrameIndex < motion.frames.count {
            currentFrameIndex = nextFrameIndex
        } else if loopsCurrentMotion {
            currentFrameIndex = 0
        } else {
            isPlaying = false
            return
        }

        onFrameChange(motion.frames[currentFrameIndex])
        scheduleCurrentFrameIfNeeded()
    }

    private func framePosition(
        in motion: PetMotion,
        at elapsedDuration: Duration
    ) -> (index: Int, remainingDuration: Duration?) {
        guard !motion.frames.isEmpty else {
            return (0, nil)
        }

        var remainingElapsed = elapsedDuration
        for (index, frame) in motion.frames.enumerated() {
            let frameDuration = frame.duration / playbackSpeed
            if remainingElapsed < frameDuration {
                return (index, frameDuration - remainingElapsed)
            }
            remainingElapsed -= frameDuration
        }

        let lastIndex = motion.frames.index(before: motion.frames.endIndex)
        return (
            lastIndex,
            motion.frames[lastIndex].duration / playbackSpeed
        )
    }
}

private extension Duration {
    var timeInterval: TimeInterval {
        let components = self.components
        return TimeInterval(components.seconds)
            + TimeInterval(components.attoseconds) / 1_000_000_000_000_000_000
    }
}
