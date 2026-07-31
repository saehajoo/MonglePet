nonisolated struct FrameTimeline: Equatable, Sendable {
    private let frameEndOffsets: [Int64]
    private let totalNanoseconds: Int64
    private let loops: Bool

    init?(motion: PetMotion) {
        guard !motion.frames.isEmpty else {
            return nil
        }

        var frameEndOffsets: [Int64] = []
        var totalNanoseconds: Int64 = 0

        for frame in motion.frames {
            guard
                let durationNanoseconds = Self.nanoseconds(for: frame.duration),
                durationNanoseconds > 0
            else {
                return nil
            }

            let addition = totalNanoseconds.addingReportingOverflow(durationNanoseconds)
            guard !addition.overflow else {
                return nil
            }

            totalNanoseconds = addition.partialValue
            frameEndOffsets.append(totalNanoseconds)
        }

        self.frameEndOffsets = frameEndOffsets
        self.totalNanoseconds = totalNanoseconds
        loops = motion.loops
    }

    var frameCount: Int {
        frameEndOffsets.count
    }

    var totalDuration: Duration {
        .nanoseconds(totalNanoseconds)
    }

    func frameIndex(at elapsed: Duration) -> Int {
        guard let elapsedNanoseconds = Self.nanoseconds(for: elapsed) else {
            return 0
        }

        let nonnegativeElapsed = max(elapsedNanoseconds, 0)
        if !loops, nonnegativeElapsed >= totalNanoseconds {
            return frameEndOffsets.count - 1
        }

        let position = loops
            ? nonnegativeElapsed % totalNanoseconds
            : nonnegativeElapsed

        return frameEndOffsets.firstIndex { position < $0 }
            ?? frameEndOffsets.count - 1
    }

    private static func nanoseconds(for duration: Duration) -> Int64? {
        let components = duration.components
        let seconds = components.seconds.multipliedReportingOverflow(by: 1_000_000_000)
        guard !seconds.overflow else {
            return nil
        }

        let fractionalNanoseconds = components.attoseconds / 1_000_000_000
        let total = seconds.partialValue.addingReportingOverflow(fractionalNanoseconds)
        guard !total.overflow else {
            return nil
        }

        return total.partialValue
    }
}
