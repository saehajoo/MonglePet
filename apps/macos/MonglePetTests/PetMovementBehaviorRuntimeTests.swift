import XCTest
@testable import MonglePet

@MainActor
final class PetMovementBehaviorRuntimeTests: XCTestCase {
    func testRepeatedMovementTicksKeepOneBehaviorTimelineAndTimer() {
        let clock = MovementBehaviorTestClock()
        let scheduler = MovementBehaviorTestScheduler()
        let runtime = PetMovementBehaviorRuntime(
            petDefinition: makePet(),
            clock: clock,
            tickScheduler: scheduler
        ) { _ in }
        runtime.updateSequences([
            BehaviorSequence(
                id: "walk",
                displayName: "걷기",
                steps: [BehaviorStep(motionID: "left", repeatCount: 1)],
                repeats: true
            )
        ])

        let activity = PetMovementActivity(isMoving: true, motionID: "walk")
        runtime.setActivity(activity)
        for _ in 0..<100 {
            runtime.setActivity(activity)
        }

        XCTAssertEqual(runtime.currentPlayback?.sequenceID, "walk")
        XCTAssertEqual(runtime.currentPlayback?.motion.id, "left")
        XCTAssertEqual(scheduler.scheduleCount, 1)
    }

    func testMovementBehaviorAdvancesStepsAndStopsWhenStationary() {
        let clock = MovementBehaviorTestClock()
        let scheduler = MovementBehaviorTestScheduler()
        var received: [String?] = []
        let runtime = PetMovementBehaviorRuntime(
            petDefinition: makePet(),
            clock: clock,
            tickScheduler: scheduler
        ) { received.append($0?.motion.id) }
        runtime.updateSequences([
            BehaviorSequence(
                id: "escape",
                displayName: "도망가기",
                steps: [
                    BehaviorStep(motionID: "left", repeatCount: 1),
                    BehaviorStep(motionID: "right", repeatCount: 1)
                ],
                repeats: true
            )
        ])

        runtime.setActivity(
            PetMovementActivity(isMoving: true, motionID: "escape")
        )
        clock.advance(by: .milliseconds(100))
        scheduler.fire()
        XCTAssertEqual(runtime.currentPlayback?.motion.id, "right")

        runtime.setActivity(.stationary)
        XCTAssertNil(runtime.currentPlayback)
        XCTAssertEqual(received, ["left", "right", nil])
    }

    private func makePet() -> PetDefinition {
        PetDefinition(
            id: "test.pet",
            displayName: "Test",
            defaultMotionID: "left",
            motions: ["left", "right"].map { id in
                PetMotion(
                    id: id,
                    loops: true,
                    frames: [
                        MotionFrame(
                            atlasID: "main",
                            sourceRect: PixelRect(
                                x: 0,
                                y: 0,
                                width: 10,
                                height: 10
                            ),
                            duration: .milliseconds(100)
                        )
                    ]
                )
            }
        )
    }
}

@MainActor
private final class MovementBehaviorTestClock: BehaviorRuntimeClock {
    private let clock = ContinuousClock()
    private var offset = Duration.zero
    var now: ContinuousClock.Instant { clock.now + offset }
    func advance(by duration: Duration) { offset += duration }
}

@MainActor
private final class MovementBehaviorTestScheduler: BehaviorTickScheduling {
    private var action: (() -> Void)?
    private(set) var scheduleCount = 0
    func schedule(after delay: Duration, action: @escaping () -> Void) {
        self.action = action
        scheduleCount += 1
    }
    func cancel() { action = nil }
    func fire() {
        let pending = action
        action = nil
        pending?()
    }
}
