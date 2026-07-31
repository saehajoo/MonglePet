import CoreGraphics
import Foundation

@MainActor
final class IdleTimeMonitor: IdleTimeProviding {
    private let secondsSinceLastInput: () -> TimeInterval

    init(
        secondsSinceLastInput: @escaping () -> TimeInterval = {
            CGEventSource.secondsSinceLastEventType(
                .combinedSessionState,
                eventType: CGEventType(rawValue: UInt32.max)!
            )
        }
    ) {
        self.secondsSinceLastInput = secondsSinceLastInput
    }

    func currentIdleDuration() -> Duration {
        let seconds = secondsSinceLastInput()
        guard !seconds.isNaN, seconds >= 0 else {
            return .zero
        }

        guard seconds.isFinite else {
            return .milliseconds(Int64.max)
        }

        let milliseconds = seconds * 1_000
        guard milliseconds < Double(Int64.max) else {
            return .milliseconds(Int64.max)
        }

        return .milliseconds(Int64(milliseconds.rounded(.down)))
    }
}
