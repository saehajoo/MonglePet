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
        XCTAssertEqual(motion.cycleDuration, .milliseconds(600))
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
        XCTAssertNil(emptyMotion.cycleDuration)
        XCTAssertNil(invalidMotion.cycleDuration)
    }

    func testPixelRectContainmentRejectsInvalidOrOverflowingFrames() {
        let atlasSize = PixelSize(width: 100, height: 80)

        XCTAssertTrue(PixelRect(x: 10, y: 10, width: 90, height: 70).isContained(in: atlasSize))
        XCTAssertFalse(PixelRect(x: -1, y: 0, width: 10, height: 10).isContained(in: atlasSize))
        XCTAssertFalse(PixelRect(x: 0, y: 0, width: 0, height: 10).isContained(in: atlasSize))
        XCTAssertFalse(PixelRect(x: 91, y: 0, width: 10, height: 10).isContained(in: atlasSize))
    }

    func testBuiltInMongleFramesStayInsideAtlas() throws {
        let definition = BuiltInPet.mongleDefinition()
        let defaultMotion = try XCTUnwrap(definition.defaultMotion)
        let atlasSizes = Dictionary(
            uniqueKeysWithValues: BuiltInPet.atlasDescriptors.map {
                ($0.id, $0.pixelSize)
            }
        )

        XCTAssertEqual(definition.displayName, "몽글이")
        XCTAssertEqual(definition.id, BuiltInPet.id)
        XCTAssertEqual(defaultMotion.id, "기본")
        XCTAssertEqual(defaultMotion.frames.count, 7)
        XCTAssertEqual(
            definition.motions.map(\.id),
            [
                "기본",
                "위로",
                "일하는 중",
                "정면",
                "자는중",
                "물뿜기",
                "찾는 중",
                "해피",
                "오른쪽",
                "보글보글"
            ]
        )
        XCTAssertEqual(
            definition.motions.map { $0.frames.count },
            [7, 4, 7, 6, 2, 2, 2, 2, 1, 3]
        )
        XCTAssertEqual(
            definition.motions.flatMap(\.frames).count,
            36
        )
        XCTAssertTrue(
            definition.motions
                .flatMap(\.frames)
                .allSatisfy { frame in
                    atlasSizes[frame.atlasID].map {
                        frame.sourceRect.isContained(in: $0)
                    } ?? false
                }
        )
        XCTAssertEqual(
            definition.motion(id: "자는중")?.frames.map(\.duration),
            [.milliseconds(450), .milliseconds(3_000)]
        )
    }

    func testSharedBuiltInMonglePackageMatchesRuntimeContract() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let packageURL = repositoryRoot
            .appendingPathComponent("shared/BuiltInPets/Mongle.monglepet")

        let package = try PetPackageLoader().loadPackage(at: packageURL)

        XCTAssertEqual(package.metadata.id, BuiltInPet.id)
        XCTAssertEqual(package.metadata.displayName, BuiltInPet.displayName)
        XCTAssertEqual(package.metadata.version, BuiltInPet.version)
        XCTAssertEqual(package.metadata.author, BuiltInPet.author)
        XCTAssertEqual(package.metadata.description, BuiltInPet.description)
        XCTAssertEqual(package.definition.defaultMotionID, BuiltInPet.defaultMotionID)
        XCTAssertEqual(
            package.definition.motions.map(\.id),
            BuiltInPet.mongleDefinition().motions.map(\.id)
        )
        XCTAssertEqual(package.definition.motions.flatMap(\.frames).count, 36)
        XCTAssertEqual(
            package.compatibility?.minimumMonglePetVersion,
            SemanticVersion(major: 1, minor: 3, patch: 0)
        )
    }

    @MainActor
    func testPetOverlayViewConvertsTopLeftPixelRectToLayerContentsRect() throws {
        let image = try XCTUnwrap(NSImage(named: "BuiltInMongleDefault"))
        let view = try XCTUnwrap(
            PetOverlayView(atlasID: BuiltInPet.atlasID, image: image)
        )
        let rect = PixelRect(
            x: view.atlasPixelSize.width / 4,
            y: view.atlasPixelSize.height / 4,
            width: view.atlasPixelSize.width / 2,
            height: view.atlasPixelSize.height / 2
        )
        let frame = MotionFrame(
            atlasID: BuiltInPet.atlasID,
            sourceRect: rect,
            duration: .milliseconds(100)
        )

        XCTAssertTrue(view.display(frame))
        let contentsRect = try XCTUnwrap(view.layer).contentsRect
        XCTAssertEqual(
            contentsRect.origin.x,
            CGFloat(rect.x) / CGFloat(view.atlasPixelSize.width),
            accuracy: 0.001
        )
        XCTAssertEqual(
            contentsRect.origin.y,
            CGFloat(view.atlasPixelSize.height - rect.y - rect.height)
                / CGFloat(view.atlasPixelSize.height),
            accuracy: 0.001
        )
        XCTAssertEqual(
            contentsRect.width,
            CGFloat(rect.width) / CGFloat(view.atlasPixelSize.width),
            accuracy: 0.001
        )
        XCTAssertEqual(
            contentsRect.height,
            CGFloat(rect.height) / CGFloat(view.atlasPixelSize.height),
            accuracy: 0.001
        )
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
