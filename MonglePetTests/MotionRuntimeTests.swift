import XCTest
@testable import MonglePet

final class MotionRuntimeTests: XCTestCase {
    private let frameRect = PixelRect(x: 0, y: 0, width: 192, height: 208)

    func testPetDefinitionUsesDeclaredDefaultMotion() throws {
        let idle = makeMotion(id: "idle", durations: [.milliseconds(100)])
        let focus = makeMotion(id: "focus", durations: [.milliseconds(100)])
        let definition = PetDefinition(
            id: "test.pet",
            displayName: "Test Pet",
            defaultMotionID: "focus",
            motions: [idle, focus]
        )

        XCTAssertEqual(try XCTUnwrap(definition.defaultMotion).id, "focus")
    }

    func testPetDefinitionFallsBackToIdleThenFirstMotion() throws {
        let idle = makeMotion(id: "idle", durations: [.milliseconds(100)])
        let definitionWithIdle = PetDefinition(
            id: "test.pet.idle",
            displayName: "Idle Pet",
            defaultMotionID: "missing",
            motions: [idle]
        )
        let rest = makeMotion(id: "rest", durations: [.milliseconds(100)])
        let definitionWithFirstMotion = PetDefinition(
            id: "test.pet.rest",
            displayName: "Rest Pet",
            defaultMotionID: "missing",
            motions: [rest]
        )

        XCTAssertEqual(try XCTUnwrap(definitionWithIdle.defaultMotion).id, "idle")
        XCTAssertEqual(try XCTUnwrap(definitionWithFirstMotion.defaultMotion).id, "rest")
    }

    func testFrameTimelineUsesExactFrameBoundariesAndLoops() throws {
        let motion = makeMotion(
            id: "idle",
            durations: [.milliseconds(100), .milliseconds(200), .milliseconds(300)]
        )
        let timeline = try XCTUnwrap(FrameTimeline(motion: motion))

        XCTAssertEqual(timeline.totalDuration, .milliseconds(600))
        XCTAssertEqual(timeline.frameIndex(at: .zero), 0)
        XCTAssertEqual(timeline.frameIndex(at: .milliseconds(99)), 0)
        XCTAssertEqual(timeline.frameIndex(at: .milliseconds(100)), 1)
        XCTAssertEqual(timeline.frameIndex(at: .milliseconds(299)), 1)
        XCTAssertEqual(timeline.frameIndex(at: .milliseconds(300)), 2)
        XCTAssertEqual(timeline.frameIndex(at: .milliseconds(599)), 2)
        XCTAssertEqual(timeline.frameIndex(at: .milliseconds(600)), 0)
        XCTAssertEqual(timeline.frameIndex(at: .milliseconds(700)), 1)
    }

    func testNonLoopingTimelineStopsOnLastFrame() throws {
        let motion = makeMotion(
            id: "wake",
            loops: false,
            durations: [.milliseconds(100), .milliseconds(200)]
        )
        let timeline = try XCTUnwrap(FrameTimeline(motion: motion))

        XCTAssertEqual(timeline.frameIndex(at: .milliseconds(299)), 1)
        XCTAssertEqual(timeline.frameIndex(at: .milliseconds(300)), 1)
        XCTAssertEqual(timeline.frameIndex(at: .seconds(30)), 1)
    }

    func testFrameTimelineRejectsEmptyAndNonpositiveFrames() {
        let emptyMotion = PetMotion(id: "empty", loops: true, frames: [])
        let invalidMotion = makeMotion(id: "invalid", durations: [.zero])

        XCTAssertNil(FrameTimeline(motion: emptyMotion))
        XCTAssertNil(FrameTimeline(motion: invalidMotion))
    }

    func testPixelRectContainmentRejectsInvalidOrOverflowingFrames() {
        let atlasSize = PixelSize(width: 100, height: 80)

        XCTAssertTrue(PixelRect(x: 10, y: 10, width: 90, height: 70).isContained(in: atlasSize))
        XCTAssertFalse(PixelRect(x: -1, y: 0, width: 10, height: 10).isContained(in: atlasSize))
        XCTAssertFalse(PixelRect(x: 0, y: 0, width: 0, height: 10).isContained(in: atlasSize))
        XCTAssertFalse(PixelRect(x: 91, y: 0, width: 10, height: 10).isContained(in: atlasSize))
    }

    func testBuiltInMongleFramesStayInsideAtlas() throws {
        let atlasSize = PixelSize(width: 1_254, height: 1_254)
        let definition = BuiltInPet.mongleDefinition(atlasPixelSize: atlasSize)
        let idle = try XCTUnwrap(definition.defaultMotion)

        XCTAssertEqual(definition.displayName, "몽글이")
        XCTAssertEqual(idle.id, "idle")
        XCTAssertEqual(idle.frames.count, 2)
        XCTAssertEqual(definition.motions.map(\.id), ["idle", "focus", "rest", "sleep"])
        XCTAssertTrue(
            definition.motions
                .flatMap(\.frames)
                .allSatisfy { $0.sourceRect.isContained(in: atlasSize) }
        )
    }

    @MainActor
    func testPetOverlayViewConvertsTopLeftPixelRectToLayerContentsRect() throws {
        let image = try XCTUnwrap(NSImage(named: "PlaceholderPet"))
        let view = try XCTUnwrap(PetOverlayView(atlasID: "main", image: image))
        let rect = PixelRect(
            x: view.atlasPixelSize.width / 4,
            y: view.atlasPixelSize.height / 4,
            width: view.atlasPixelSize.width / 2,
            height: view.atlasPixelSize.height / 2
        )
        let frame = MotionFrame(
            atlasID: "main",
            sourceRect: rect,
            duration: .milliseconds(100)
        )

        XCTAssertTrue(view.display(frame))
        let contentsRect = try XCTUnwrap(view.layer).contentsRect
        XCTAssertEqual(contentsRect.origin.x, 0.25, accuracy: 0.001)
        XCTAssertEqual(contentsRect.origin.y, 0.25, accuracy: 0.001)
        XCTAssertEqual(contentsRect.width, 0.5, accuracy: 0.001)
        XCTAssertEqual(contentsRect.height, 0.5, accuracy: 0.001)
    }

    @MainActor
    func testFramePlayerLoopsAndOnlyPublishesFrameChanges() {
        let scheduler = ManualFrameScheduler()
        let motion = makeMotion(
            id: "idle",
            durations: [.milliseconds(100), .milliseconds(200)]
        )
        var publishedFrames: [MotionFrame] = []
        let player = FramePlayer(scheduler: scheduler) { publishedFrames.append($0) }

        player.play(motion)
        XCTAssertEqual(publishedFrames, [motion.frames[0]])
        XCTAssertEqual(scheduler.scheduledDelay, .milliseconds(100))

        scheduler.fire()
        XCTAssertEqual(publishedFrames, [motion.frames[0], motion.frames[1]])
        XCTAssertEqual(scheduler.scheduledDelay, .milliseconds(200))

        scheduler.fire()
        XCTAssertEqual(publishedFrames, [motion.frames[0], motion.frames[1], motion.frames[0]])
        XCTAssertEqual(player.currentFrameIndex, 0)
    }

    @MainActor
    func testRunLoopFrameSchedulerFiresScheduledAction() async {
        let scheduler = RunLoopFrameScheduler()
        let scheduledAction = expectation(description: "Scheduled frame action fires")

        scheduler.schedule(after: .milliseconds(20)) {
            scheduledAction.fulfill()
        }

        await fulfillment(of: [scheduledAction], timeout: 1)
    }

    @MainActor
    func testFramePlayerPauseResumeAndStopLifecycle() {
        let scheduler = ManualFrameScheduler()
        let motion = makeMotion(
            id: "idle",
            durations: [.milliseconds(100), .milliseconds(200)]
        )
        let player = FramePlayer(scheduler: scheduler) { _ in }

        player.play(motion)
        player.pause()
        XCTAssertFalse(player.isPlaying)
        XCTAssertNil(scheduler.scheduledDelay)

        player.resume()
        XCTAssertTrue(player.isPlaying)
        XCTAssertEqual(scheduler.scheduledDelay, .milliseconds(100))

        player.stop()
        XCTAssertFalse(player.isPlaying)
        XCTAssertEqual(player.currentFrameIndex, 0)
        XCTAssertNil(scheduler.scheduledDelay)
    }

    @MainActor
    func testFramePlayerAppliesPlaybackSpeedToFrameDelay() {
        let scheduler = ManualFrameScheduler()
        let motion = makeMotion(
            id: "focus",
            durations: [.milliseconds(100), .milliseconds(240)]
        )
        let player = FramePlayer(scheduler: scheduler) { _ in }

        player.play(motion, playbackSpeed: 2)
        XCTAssertEqual(player.playbackSpeed, 2)
        XCTAssertEqual(scheduler.scheduledDelay, .milliseconds(50))

        scheduler.fire()
        XCTAssertEqual(scheduler.scheduledDelay, .milliseconds(120))

        player.play(motion, playbackSpeed: 0)
        XCTAssertEqual(player.playbackSpeed, 1)
        XCTAssertEqual(scheduler.scheduledDelay, .milliseconds(100))
    }

    @MainActor
    func testNonLoopingFramePlayerStopsAfterLastFrameDuration() {
        let scheduler = ManualFrameScheduler()
        let motion = makeMotion(
            id: "wake",
            loops: false,
            durations: [.milliseconds(100), .milliseconds(200)]
        )
        var publishedFrames: [MotionFrame] = []
        let player = FramePlayer(scheduler: scheduler) { publishedFrames.append($0) }

        player.play(motion)
        scheduler.fire()
        scheduler.fire()

        XCTAssertEqual(publishedFrames, motion.frames)
        XCTAssertFalse(player.isPlaying)
        XCTAssertEqual(player.currentFrameIndex, 1)
        XCTAssertNil(scheduler.scheduledDelay)
    }

    private func makeMotion(
        id: String,
        loops: Bool = true,
        durations: [Duration]
    ) -> PetMotion {
        PetMotion(
            id: id,
            loops: loops,
            frames: durations.map {
                MotionFrame(atlasID: "main", sourceRect: frameRect, duration: $0)
            }
        )
    }
}

@MainActor
private final class ManualFrameScheduler: FrameScheduling {
    private var action: (() -> Void)?
    private(set) var scheduledDelay: Duration?

    func schedule(after delay: Duration, action: @escaping () -> Void) {
        scheduledDelay = delay
        self.action = action
    }

    func cancel() {
        scheduledDelay = nil
        action = nil
    }

    func fire() {
        let pendingAction = action
        action = nil
        scheduledDelay = nil
        pendingAction?()
    }
}
