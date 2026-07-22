import XCTest
@testable import MonglePet

final class MotionSchedulerTests: XCTestCase {
    private let frameRect = PixelRect(x: 0, y: 0, width: 192, height: 208)

    func testSequenceAdvancesAfterCompleteCyclesAndRepeatCounts() throws {
        var scheduler = MotionScheduler(petDefinition: makePet())
        let sequence = makeSequence(
            id: "work",
            steps: [
                makeStep(motionID: "focus", repeatCount: 2),
                makeStep(motionID: "rest", repeatCount: 1)
            ]
        )

        XCTAssertTrue(scheduler.request(sequence))
        XCTAssertEqual(try playback(from: scheduler).stepIndex, 0)

        scheduler.advance(by: .milliseconds(999))
        XCTAssertEqual(try playback(from: scheduler).stepIndex, 0)
        XCTAssertEqual(scheduler.activeCycleRemainingDuration, .milliseconds(1))

        scheduler.advance(by: .milliseconds(1))
        XCTAssertEqual(try playback(from: scheduler).stepIndex, 0)
        XCTAssertEqual(scheduler.activeCycleRemainingDuration, .seconds(1))

        scheduler.advance(by: .seconds(1))
        XCTAssertEqual(try playback(from: scheduler).stepIndex, 1)
        XCTAssertEqual(scheduler.activeCycleRemainingDuration, .seconds(2))

        scheduler.advance(by: .seconds(2))
        XCTAssertEqual(try playback(from: scheduler).stepIndex, 0)
        XCTAssertEqual(scheduler.activeCycleRemainingDuration, .seconds(1))
    }

    func testDifferentSequenceWaitsOnlyForCurrentAnimationCycleBoundary() throws {
        var scheduler = MotionScheduler(petDefinition: makePet())
        let current = makeSequence(
            id: "current",
            steps: [makeStep(motionID: "focus", repeatCount: 5)]
        )
        let next = makeSequence(
            id: "next",
            steps: [makeStep(motionID: "rest", repeatCount: 2)]
        )

        scheduler.request(current)
        scheduler.advance(by: .milliseconds(250))
        XCTAssertFalse(scheduler.request(current))
        XCTAssertEqual(scheduler.activeCycleRemainingDuration, .milliseconds(750))

        XCTAssertTrue(scheduler.request(next))
        XCTAssertEqual(scheduler.activeSequenceID, "current")
        XCTAssertEqual(scheduler.pendingSequenceID, "next")

        scheduler.advance(by: .milliseconds(749))
        XCTAssertEqual(scheduler.activeSequenceID, "current")
        scheduler.advance(by: .milliseconds(1))
        XCTAssertEqual(scheduler.activeSequenceID, "next")
        XCTAssertEqual(try playback(from: scheduler).motion.id, "rest")
        XCTAssertEqual(scheduler.activeCycleRemainingDuration, .seconds(2))
    }

    func testEditedSequenceWithSameIDAppliesAtNextAnimationCycleBoundary() throws {
        var scheduler = MotionScheduler(petDefinition: makePet())
        let original = makeSequence(
            id: "work",
            steps: [makeStep(motionID: "focus", repeatCount: 5)]
        )
        let edited = makeSequence(
            id: "work",
            steps: [makeStep(motionID: "rest", repeatCount: 3)]
        )

        XCTAssertTrue(scheduler.request(original))
        scheduler.advance(by: .milliseconds(400))

        XCTAssertTrue(scheduler.request(edited))
        XCTAssertEqual(try playback(from: scheduler).motion.id, "focus")
        XCTAssertEqual(scheduler.activeCycleRemainingDuration, .milliseconds(600))
        XCTAssertEqual(scheduler.pendingSequenceID, "work")

        scheduler.advance(by: .milliseconds(600))
        XCTAssertEqual(try playback(from: scheduler).motion.id, "rest")
        XCTAssertEqual(scheduler.activeCycleRemainingDuration, .seconds(2))
        XCTAssertNil(scheduler.pendingSequenceID)
    }

    func testNonRepeatingSequenceHoldsLastStepAndCanSwitchAfterCompletion() throws {
        var scheduler = MotionScheduler(petDefinition: makePet())
        let oneShot = makeSequence(
            id: "one-shot",
            steps: [makeStep(motionID: "rest", repeatCount: 1)],
            repeats: false
        )
        let idle = makeSequence(
            id: "idle-sequence",
            steps: [makeStep(motionID: "idle", repeatCount: 1)]
        )

        scheduler.request(oneShot)
        scheduler.advance(by: .seconds(5))
        XCTAssertEqual(try playback(from: scheduler).motion.id, "rest")
        XCTAssertEqual(scheduler.activeCycleRemainingDuration, .zero)

        XCTAssertTrue(scheduler.request(idle))
        XCTAssertEqual(scheduler.activeSequenceID, "idle-sequence")
        XCTAssertEqual(scheduler.activeCycleRemainingDuration, .seconds(1))
    }

    func testEditedNonRepeatingSequenceWithSameIDRestartsAfterCompletion() throws {
        var scheduler = MotionScheduler(petDefinition: makePet())
        let original = makeSequence(
            id: "one-shot",
            steps: [makeStep(motionID: "focus", repeatCount: 1)],
            repeats: false
        )
        let edited = makeSequence(
            id: "one-shot",
            steps: [makeStep(motionID: "rest", repeatCount: 2)],
            repeats: false
        )

        scheduler.request(original)
        scheduler.advance(by: .seconds(1))
        XCTAssertEqual(scheduler.activeCycleRemainingDuration, .zero)

        XCTAssertTrue(scheduler.request(edited))
        XCTAssertEqual(try playback(from: scheduler).motion.id, "rest")
        XCTAssertEqual(scheduler.activeCycleRemainingDuration, .seconds(2))
        XCTAssertNil(scheduler.pendingSequenceID)
    }

    func testPausePreservesCurrentCycleProgressUntilResume() {
        var scheduler = MotionScheduler(petDefinition: makePet())
        scheduler.request(
            makeSequence(
                id: "focus",
                steps: [makeStep(motionID: "focus", repeatCount: 5)]
            )
        )
        scheduler.advance(by: .milliseconds(400))
        scheduler.pause()
        scheduler.advance(by: .seconds(20))

        XCTAssertTrue(scheduler.isPaused)
        XCTAssertEqual(scheduler.activeCycleRemainingDuration, .milliseconds(600))

        scheduler.resume()
        scheduler.advance(by: .milliseconds(100))
        XCTAssertEqual(scheduler.activeCycleRemainingDuration, .milliseconds(500))
    }

    func testMissingMotionUsesPetDefaultMotionCycle() throws {
        let sequence = makeSequence(
            id: "missing-motion",
            steps: [makeStep(motionID: "missing", repeatCount: 2)]
        )
        var fallbackScheduler = MotionScheduler(petDefinition: makePet())
        fallbackScheduler.request(sequence)

        let fallback = try playback(from: fallbackScheduler)
        XCTAssertEqual(fallback.motion.id, "idle")
        XCTAssertTrue(fallback.usesFallback)
        XCTAssertEqual(fallbackScheduler.activeCycleRemainingDuration, .seconds(1))

        let petWithoutIdle = PetDefinition(
            id: "pet.without.idle",
            displayName: "No Idle",
            defaultMotionID: "focus",
            motions: [makeMotion(id: "focus", frameDurations: [.seconds(3)])]
        )
        var defaultMotionScheduler = MotionScheduler(petDefinition: petWithoutIdle)
        defaultMotionScheduler.request(sequence)
        let defaultFallback = try playback(from: defaultMotionScheduler)
        XCTAssertEqual(defaultFallback.motion.id, "focus")
        XCTAssertTrue(defaultFallback.usesFallback)
        XCTAssertEqual(defaultMotionScheduler.activeCycleRemainingDuration, .seconds(3))
    }

    func testCurrentPetDefaultReferenceUsesDeclaredDefaultWithoutFallbackWarning() throws {
        let pet = PetDefinition(
            id: "pet.without.idle",
            displayName: "No Idle",
            defaultMotionID: "focus",
            motions: [makeMotion(id: "focus", frameDurations: [.milliseconds(300), .milliseconds(700)])]
        )
        let sequence = makeSequence(
            id: "current-default",
            steps: [
                makeStep(
                    motionID: PetMotionReference.currentPetDefault,
                    repeatCount: 1
                )
            ]
        )
        var scheduler = MotionScheduler(petDefinition: pet)

        scheduler.request(sequence)

        let playback = try playback(from: scheduler)
        XCTAssertEqual(playback.requestedMotionID, PetMotionReference.currentPetDefault)
        XCTAssertEqual(playback.motion.id, "focus")
        XCTAssertFalse(playback.usesFallback)
        XCTAssertEqual(scheduler.activeCycleRemainingDuration, .seconds(1))
    }

    func testInteractionRestoresBaseCycleProgressAndUsesCooldown() throws {
        var scheduler = MotionScheduler(
            petDefinition: makePet(),
            interactionCooldown: .milliseconds(500)
        )
        let focus = makeSequence(
            id: "focus-sequence",
            steps: [makeStep(motionID: "focus", repeatCount: 10)]
        )
        let petting = makeSequence(
            id: "petting-sequence",
            steps: [
                makeStep(motionID: "petting", repeatCount: 1),
                makeStep(motionID: "rest", repeatCount: 1)
            ],
            repeats: false
        )

        scheduler.request(focus)
        scheduler.advance(by: .milliseconds(400))
        XCTAssertEqual(scheduler.activeCycleRemainingDuration, .milliseconds(600))

        XCTAssertTrue(scheduler.triggerInteraction(petting))
        XCTAssertFalse(scheduler.triggerInteraction(petting))
        XCTAssertTrue(try playback(from: scheduler).isInteraction)

        scheduler.advance(by: .milliseconds(1_500))
        XCTAssertEqual(try playback(from: scheduler).stepIndex, 1)
        XCTAssertEqual(scheduler.activeCycleRemainingDuration, .milliseconds(1_500))

        scheduler.advance(by: .milliseconds(1_500))
        XCTAssertFalse(scheduler.isInteractionPlaying)
        XCTAssertEqual(scheduler.activeSequenceID, "focus-sequence")
        XCTAssertEqual(scheduler.activeCycleRemainingDuration, .milliseconds(600))
        XCTAssertFalse(scheduler.triggerInteraction(petting))

        scheduler.advance(by: .milliseconds(499))
        XCTAssertFalse(scheduler.triggerInteraction(petting))
        scheduler.advance(by: .milliseconds(1))
        XCTAssertTrue(scheduler.triggerInteraction(petting))
    }

    func testLegacyTimingKeepsV1StepBoundaryUntilSchemaV2Migration() throws {
        var scheduler = MotionScheduler(petDefinition: makePet())
        let legacyStep = BehaviorStep(
            motionID: "focus",
            duration: .milliseconds(2_600),
            playbackSpeed: 2
        )

        XCTAssertTrue(
            scheduler.request(
                makeSequence(id: "legacy", steps: [legacyStep], repeats: false)
            )
        )
        XCTAssertEqual(try playback(from: scheduler).playbackSpeed, 2)
        XCTAssertEqual(scheduler.activeCycleRemainingDuration, .milliseconds(2_600))

        scheduler.advance(by: .seconds(2))
        XCTAssertEqual(scheduler.activeCycleRemainingDuration, .milliseconds(600))
        scheduler.advance(by: .milliseconds(600))
        XCTAssertEqual(scheduler.activeCycleRemainingDuration, .zero)
    }

    func testInvalidRepeatCountAndEmptyMotionAreRejected() {
        var scheduler = MotionScheduler(petDefinition: makePet())
        let valid = makeSequence(
            id: "valid",
            steps: [makeStep(motionID: "idle", repeatCount: 1)]
        )
        let zeroRepeats = makeSequence(
            id: "zero",
            steps: [makeStep(motionID: "idle", repeatCount: 0)]
        )
        let emptyMotion = makeSequence(
            id: "empty",
            steps: [makeStep(motionID: "", repeatCount: 1)]
        )

        XCTAssertTrue(scheduler.request(valid))
        XCTAssertFalse(scheduler.request(zeroRepeats))
        XCTAssertFalse(scheduler.request(emptyMotion))
        XCTAssertEqual(scheduler.activeSequenceID, "valid")
        XCTAssertNil(scheduler.pendingSequenceID)
    }

    private func makePet() -> PetDefinition {
        PetDefinition(
            id: "test.pet",
            displayName: "Test Pet",
            defaultMotionID: "idle",
            motions: [
                makeMotion(id: "idle", frameDurations: [.seconds(1)]),
                makeMotion(
                    id: "focus",
                    frameDurations: [.milliseconds(400), .milliseconds(600)]
                ),
                makeMotion(id: "rest", frameDurations: [.milliseconds(750), .milliseconds(1_250)]),
                makeMotion(id: "sleep", frameDurations: [.seconds(3)]),
                makeMotion(id: "petting", loops: false, frameDurations: [.seconds(1)])
            ]
        )
    }

    private func makeMotion(
        id: String,
        loops: Bool = true,
        frameDurations: [Duration]
    ) -> PetMotion {
        PetMotion(
            id: id,
            loops: loops,
            frames: frameDurations.map {
                MotionFrame(
                    atlasID: "main",
                    sourceRect: frameRect,
                    duration: $0
                )
            }
        )
    }

    private func makeSequence(
        id: String,
        steps: [BehaviorStep],
        repeats: Bool = true
    ) -> BehaviorSequence {
        BehaviorSequence(id: id, steps: steps, repeats: repeats)
    }

    private func makeStep(motionID: String, repeatCount: Int) -> BehaviorStep {
        BehaviorStep(motionID: motionID, repeatCount: repeatCount)
    }

    private func playback(from scheduler: MotionScheduler) throws -> ScheduledMotion {
        guard case let .playing(playback) = scheduler.status else {
            XCTFail("Expected the scheduler to be playing, got \(scheduler.status)")
            throw TestError.expectedPlayback
        }

        return playback
    }

    private enum TestError: Error {
        case expectedPlayback
    }
}
