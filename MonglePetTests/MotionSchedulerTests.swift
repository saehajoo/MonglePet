import XCTest
@testable import MonglePet

final class MotionSchedulerTests: XCTestCase {
    private let frameRect = PixelRect(x: 0, y: 0, width: 192, height: 208)

    func testSequenceAdvancesAtExactBoundariesAndRepeats() throws {
        var scheduler = MotionScheduler(petDefinition: makePet())
        let sequence = makeSequence(
            id: "work",
            steps: [
                makeStep(motionID: "focus", duration: .seconds(2)),
                makeStep(motionID: "rest", duration: .seconds(3))
            ]
        )

        XCTAssertTrue(scheduler.request(sequence))
        XCTAssertEqual(try playback(from: scheduler).stepIndex, 0)

        scheduler.advance(by: .milliseconds(1_999))
        XCTAssertEqual(try playback(from: scheduler).stepIndex, 0)
        XCTAssertEqual(scheduler.activeStepRemainingDuration, .milliseconds(1))

        scheduler.advance(by: .milliseconds(1))
        XCTAssertEqual(try playback(from: scheduler).stepIndex, 1)

        scheduler.advance(by: .seconds(3))
        XCTAssertEqual(try playback(from: scheduler).stepIndex, 0)
        XCTAssertEqual(scheduler.activeStepRemainingDuration, .seconds(2))
    }

    func testSameSequencePreservesProgressAndDifferentSequenceWaitsForStepBoundary() throws {
        var scheduler = MotionScheduler(petDefinition: makePet())
        let current = makeSequence(
            id: "current",
            steps: [makeStep(motionID: "focus", duration: .seconds(5))]
        )
        let next = makeSequence(
            id: "next",
            steps: [makeStep(motionID: "rest", duration: .seconds(4))]
        )

        scheduler.request(current)
        scheduler.advance(by: .seconds(2))
        XCTAssertFalse(scheduler.request(current))
        XCTAssertEqual(scheduler.activeStepRemainingDuration, .seconds(3))

        XCTAssertTrue(scheduler.request(next))
        XCTAssertEqual(scheduler.activeSequenceID, "current")
        XCTAssertEqual(scheduler.pendingSequenceID, "next")

        scheduler.advance(by: .seconds(4))
        XCTAssertEqual(scheduler.activeSequenceID, "next")
        XCTAssertEqual(try playback(from: scheduler).motion.id, "rest")
        XCTAssertEqual(scheduler.activeStepRemainingDuration, .seconds(3))
    }

    func testEditedSequenceWithSameIDAppliesAtNextStepBoundary() throws {
        var scheduler = MotionScheduler(petDefinition: makePet())
        let original = makeSequence(
            id: "work",
            steps: [makeStep(motionID: "focus", duration: .seconds(5))]
        )
        let edited = makeSequence(
            id: "work",
            steps: [makeStep(motionID: "rest", duration: .seconds(3))]
        )

        XCTAssertTrue(scheduler.request(original))
        scheduler.advance(by: .seconds(2))

        XCTAssertTrue(scheduler.request(edited))
        XCTAssertEqual(try playback(from: scheduler).motion.id, "focus")
        XCTAssertEqual(scheduler.activeStepRemainingDuration, .seconds(3))
        XCTAssertEqual(scheduler.pendingSequenceID, "work")

        scheduler.advance(by: .seconds(3))
        XCTAssertEqual(try playback(from: scheduler).motion.id, "rest")
        XCTAssertEqual(scheduler.activeStepRemainingDuration, .seconds(3))
        XCTAssertNil(scheduler.pendingSequenceID)
    }

    func testNonRepeatingSequenceHoldsLastStepAndCanSwitchImmediatelyAfterCompletion() throws {
        var scheduler = MotionScheduler(petDefinition: makePet())
        let oneShot = makeSequence(
            id: "one-shot",
            steps: [makeStep(motionID: "rest", duration: .seconds(1))],
            repeats: false
        )
        let idle = makeSequence(
            id: "idle-sequence",
            steps: [makeStep(motionID: "idle", duration: .seconds(3))]
        )

        scheduler.request(oneShot)
        scheduler.advance(by: .seconds(5))
        XCTAssertEqual(try playback(from: scheduler).motion.id, "rest")
        XCTAssertEqual(scheduler.activeStepRemainingDuration, .zero)

        XCTAssertTrue(scheduler.request(idle))
        XCTAssertEqual(scheduler.activeSequenceID, "idle-sequence")
        XCTAssertEqual(scheduler.activeStepRemainingDuration, .seconds(3))
    }

    func testEditedNonRepeatingSequenceWithSameIDRestartsAfterCompletion() throws {
        var scheduler = MotionScheduler(petDefinition: makePet())
        let original = makeSequence(
            id: "one-shot",
            steps: [makeStep(motionID: "focus", duration: .seconds(1))],
            repeats: false
        )
        let edited = makeSequence(
            id: "one-shot",
            steps: [makeStep(motionID: "rest", duration: .seconds(2))],
            repeats: false
        )

        scheduler.request(original)
        scheduler.advance(by: .seconds(1))
        XCTAssertEqual(scheduler.activeStepRemainingDuration, .zero)

        XCTAssertTrue(scheduler.request(edited))
        XCTAssertEqual(try playback(from: scheduler).motion.id, "rest")
        XCTAssertEqual(scheduler.activeStepRemainingDuration, .seconds(2))
        XCTAssertNil(scheduler.pendingSequenceID)
    }

    func testPausePreservesRemainingTimeUntilResume() {
        var scheduler = MotionScheduler(petDefinition: makePet())
        scheduler.request(
            makeSequence(
                id: "focus",
                steps: [makeStep(motionID: "focus", duration: .seconds(5))]
            )
        )
        scheduler.advance(by: .seconds(2))
        scheduler.pause()
        scheduler.advance(by: .seconds(20))

        XCTAssertTrue(scheduler.isPaused)
        XCTAssertEqual(scheduler.activeStepRemainingDuration, .seconds(3))

        scheduler.resume()
        scheduler.advance(by: .seconds(1))
        XCTAssertEqual(scheduler.activeStepRemainingDuration, .seconds(2))
    }

    func testMissingMotionUsesPetDefaultMotion() throws {
        let sequence = makeSequence(
            id: "missing-motion",
            steps: [makeStep(motionID: "missing", duration: .seconds(1))]
        )
        var fallbackScheduler = MotionScheduler(petDefinition: makePet())
        fallbackScheduler.request(sequence)

        let fallback = try playback(from: fallbackScheduler)
        XCTAssertEqual(fallback.motion.id, "idle")
        XCTAssertTrue(fallback.usesFallback)

        let petWithoutIdle = PetDefinition(
            id: "pet.without.idle",
            displayName: "No Idle",
            defaultMotionID: "focus",
            motions: [makeMotion(id: "focus")]
        )
        var defaultMotionScheduler = MotionScheduler(petDefinition: petWithoutIdle)
        defaultMotionScheduler.request(sequence)
        let defaultFallback = try playback(from: defaultMotionScheduler)
        XCTAssertEqual(defaultFallback.motion.id, "focus")
        XCTAssertTrue(defaultFallback.usesFallback)
    }

    func testCurrentPetDefaultReferenceUsesDeclaredDefaultWithoutFallbackWarning() throws {
        let pet = PetDefinition(
            id: "pet.without.idle",
            displayName: "No Idle",
            defaultMotionID: "focus",
            motions: [makeMotion(id: "focus")]
        )
        let sequence = makeSequence(
            id: "current-default",
            steps: [
                makeStep(
                    motionID: PetMotionReference.currentPetDefault,
                    duration: .seconds(1)
                )
            ]
        )
        var scheduler = MotionScheduler(petDefinition: pet)

        scheduler.request(sequence)

        let playback = try playback(from: scheduler)
        XCTAssertEqual(playback.requestedMotionID, PetMotionReference.currentPetDefault)
        XCTAssertEqual(playback.motion.id, "focus")
        XCTAssertFalse(playback.usesFallback)
    }

    func testInteractionCoalescesInputRestoresRemainingTimeAndUsesCooldown() throws {
        var scheduler = MotionScheduler(
            petDefinition: makePet(),
            interactionCooldown: .milliseconds(500)
        )
        let focus = makeSequence(
            id: "focus-sequence",
            steps: [makeStep(motionID: "focus", duration: .seconds(10))]
        )
        let petting = makeSequence(
            id: "petting-sequence",
            steps: [
                makeStep(motionID: "petting", duration: .seconds(1)),
                makeStep(motionID: "rest", duration: .seconds(1))
            ],
            repeats: false
        )

        scheduler.request(focus)
        scheduler.advance(by: .seconds(4))
        XCTAssertEqual(scheduler.activeStepRemainingDuration, .seconds(6))

        XCTAssertTrue(scheduler.triggerInteraction(petting))
        XCTAssertFalse(scheduler.triggerInteraction(petting))
        XCTAssertTrue(try playback(from: scheduler).isInteraction)

        scheduler.advance(by: .milliseconds(1_500))
        XCTAssertEqual(try playback(from: scheduler).stepIndex, 1)
        XCTAssertEqual(scheduler.activeStepRemainingDuration, .milliseconds(500))

        scheduler.advance(by: .milliseconds(500))
        XCTAssertFalse(scheduler.isInteractionPlaying)
        XCTAssertEqual(scheduler.activeSequenceID, "focus-sequence")
        XCTAssertEqual(scheduler.activeStepRemainingDuration, .seconds(6))
        XCTAssertFalse(scheduler.triggerInteraction(petting))

        scheduler.advance(by: .milliseconds(499))
        XCTAssertFalse(scheduler.triggerInteraction(petting))
        scheduler.advance(by: .milliseconds(1))
        XCTAssertTrue(scheduler.triggerInteraction(petting))
    }

    func testInvalidSequenceIsRejectedWithoutReplacingCurrentSequence() {
        var scheduler = MotionScheduler(petDefinition: makePet())
        let valid = makeSequence(
            id: "valid",
            steps: [makeStep(motionID: "idle", duration: .seconds(2))]
        )
        let invalid = makeSequence(
            id: "invalid",
            steps: [makeStep(motionID: "idle", duration: .zero)]
        )

        XCTAssertTrue(scheduler.request(valid))
        XCTAssertFalse(scheduler.request(invalid))
        XCTAssertEqual(scheduler.activeSequenceID, "valid")
        XCTAssertNil(scheduler.pendingSequenceID)
    }

    private func makePet() -> PetDefinition {
        PetDefinition(
            id: "test.pet",
            displayName: "Test Pet",
            defaultMotionID: "idle",
            motions: [
                makeMotion(id: "idle"),
                makeMotion(id: "focus"),
                makeMotion(id: "rest"),
                makeMotion(id: "sleep"),
                makeMotion(id: "petting", loops: false)
            ]
        )
    }

    private func makeMotion(id: String, loops: Bool = true) -> PetMotion {
        PetMotion(
            id: id,
            loops: loops,
            frames: [
                MotionFrame(
                    atlasID: "main",
                    sourceRect: frameRect,
                    duration: .milliseconds(100)
                )
            ]
        )
    }

    private func makeSequence(
        id: String,
        steps: [BehaviorStep],
        repeats: Bool = true
    ) -> BehaviorSequence {
        BehaviorSequence(id: id, steps: steps, repeats: repeats)
    }

    private func makeStep(motionID: String, duration: Duration) -> BehaviorStep {
        BehaviorStep(motionID: motionID, duration: duration, playbackSpeed: 1)
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
