import XCTest
@testable import MonglePet

@MainActor
final class PetMovementControllerTests: XCTestCase {
    func testFixedModeDoesNotScheduleOrReadMovementEnvironment() {
        let fixture = Fixture()

        fixture.controller.update(
            settings: fixture.settings(mode: .fixed),
            isMovementAllowed: true
        )

        XCTAssertEqual(fixture.controller.state, .inactive)
        XCTAssertNil(fixture.scheduler.scheduledDelay)
        XCTAssertEqual(fixture.pointerReadCount, 0)
        XCTAssertEqual(fixture.appliedOrigins, [])
    }

    func testCursorFollowingMovesAtConfiguredSpeedAndReportsMotion() {
        let fixture = Fixture()
        fixture.origin = point(100, 100)
        fixture.pointer = point(600, 150)

        fixture.controller.update(
            settings: fixture.settings(
                mode: .cursorFollowing,
                speed: 100,
                cursorDistance: 100,
                stopRadius: 10,
                cursorMotionID: "run"
            ),
            isMovementAllowed: true
        )
        XCTAssertEqual(fixture.scheduler.scheduledDelay, .milliseconds(33))

        fixture.clock.advance(by: .seconds(1))
        fixture.scheduler.fire()

        XCTAssertEqual(fixture.origin, point(200, 100))
        XCTAssertEqual(fixture.controller.activity, movement("run"))
        XCTAssertEqual(fixture.activities, [movement("run")])
        XCTAssertEqual(fixture.scheduler.scheduledDelay, .milliseconds(33))
    }

    func testMovementWithoutConfiguredMotionStillReportsActualMovement() {
        let fixture = Fixture()
        fixture.pointer = point(600, 150)
        fixture.controller.update(
            settings: fixture.settings(
                mode: .cursorFollowing,
                speed: 100,
                cursorDistance: 100,
                stopRadius: 10,
                cursorMotionID: nil
            ),
            isMovementAllowed: true
        )

        fixture.clock.advance(by: .seconds(1))
        fixture.scheduler.fire()

        XCTAssertEqual(fixture.controller.activity, movement(nil))
        XCTAssertTrue(fixture.controller.activity.isMoving)
        XCTAssertNil(fixture.controller.activity.motionID)
    }

    func testCursorFollowingStopsAnimationAfterActualMovementHysteresis() {
        let fixture = Fixture()
        fixture.origin = point(100, 100)
        fixture.pointer = point(600, 150)
        fixture.controller.update(
            settings: fixture.settings(
                mode: .cursorFollowing,
                speed: 100,
                cursorDistance: 100,
                stopRadius: 10,
                cursorMotionID: "run"
            ),
            isMovementAllowed: true
        )

        fixture.clock.advance(by: .seconds(1))
        fixture.scheduler.fire()
        XCTAssertTrue(fixture.controller.activity.isMoving)

        fixture.pointer = point(250, 150)
        fixture.clock.advance(by: .milliseconds(100))
        fixture.scheduler.fire()
        XCTAssertTrue(fixture.controller.activity.isMoving)

        fixture.clock.advance(by: .milliseconds(50))
        fixture.scheduler.fire()
        XCTAssertEqual(fixture.controller.activity, .stationary)
        XCTAssertEqual(fixture.activities, [movement("run"), .stationary])
        XCTAssertEqual(fixture.scheduler.scheduledDelay, .milliseconds(100))
    }

    func testFreeRoamingUsesPreferredWindowThenSettlesAndDwells() {
        let fixture = Fixture()
        fixture.origin = point(0, 0)
        fixture.frontmostWindow.window = PetMovementWindow(
            frame: rect(200, 100, 100, 100)
        )
        fixture.randomSamples = [sample(0, 0, 0)]
        fixture.controller.update(
            settings: fixture.settings(
                mode: .freeRoaming,
                speed: 1_000,
                stopRadius: 1,
                dwellMilliseconds: 6_000,
                freeMotionID: "walk"
            ),
            isMovementAllowed: true
        )

        fixture.clock.advance(by: .seconds(1))
        fixture.scheduler.fire()

        XCTAssertEqual(fixture.origin, point(200, 100))
        XCTAssertEqual(fixture.controller.state, .freeRoamingSettling)
        XCTAssertEqual(fixture.controller.activity, movement("walk"))
        XCTAssertEqual(fixture.scheduler.scheduledDelay, .milliseconds(150))

        fixture.clock.advance(by: .milliseconds(150))
        fixture.scheduler.fire()

        XCTAssertEqual(fixture.controller.state, .freeRoamingDwelling)
        XCTAssertEqual(fixture.controller.activity, .stationary)
        XCTAssertEqual(fixture.scheduler.scheduledDelay, .milliseconds(6_000))
        XCTAssertEqual(fixture.frontmostWindow.readCount, 1)
    }

    func testFreeRoamingDwellCreatesANewTarget() {
        let fixture = Fixture()
        fixture.origin = point(32, 32)
        fixture.randomSamples = [
            sample(0, 0, 0),
            sample(0, 1, 1)
        ]
        fixture.controller.update(
            settings: fixture.settings(
                mode: .freeRoaming,
                speed: 1_000,
                stopRadius: 1,
                dwellMilliseconds: 500,
                prefersFrontmostWindow: false
            ),
            isMovementAllowed: true
        )

        fixture.clock.advance(by: .milliseconds(33))
        fixture.scheduler.fire()
        XCTAssertEqual(fixture.controller.state, .freeRoamingDwelling)
        XCTAssertEqual(fixture.scheduler.scheduledDelay, .milliseconds(500))

        fixture.clock.advance(by: .milliseconds(500))
        fixture.scheduler.fire()

        XCTAssertEqual(fixture.controller.state, .freeRoamingMoving)
        XCTAssertEqual(fixture.controller.targetOrigin, point(868, 668))
        XCTAssertEqual(fixture.frontmostWindow.readCount, 0)
        XCTAssertEqual(fixture.scheduler.scheduledDelay, .milliseconds(33))
    }

    func testDisallowingMovementCancelsTimerAndReportsStationary() {
        let fixture = Fixture()
        fixture.pointer = point(600, 150)
        let settings = fixture.settings(
            mode: .cursorFollowing,
            speed: 100,
            cursorMotionID: "run"
        )
        fixture.controller.update(settings: settings, isMovementAllowed: true)
        fixture.clock.advance(by: .seconds(1))
        fixture.scheduler.fire()
        XCTAssertTrue(fixture.controller.activity.isMoving)

        fixture.controller.update(settings: settings, isMovementAllowed: false)

        XCTAssertEqual(fixture.controller.state, .inactive)
        XCTAssertEqual(fixture.controller.activity, .stationary)
        XCTAssertNil(fixture.scheduler.scheduledDelay)
    }

    func testInvalidEnvironmentUsesLowFrequencyRetry() {
        let fixture = Fixture()
        fixture.screens = []
        fixture.controller.update(
            settings: fixture.settings(mode: .cursorFollowing),
            isMovementAllowed: true
        )

        fixture.clock.advance(by: .milliseconds(33))
        fixture.scheduler.fire()

        XCTAssertEqual(fixture.controller.state, .cursorFollowing)
        XCTAssertEqual(fixture.controller.activity, .stationary)
        XCTAssertEqual(fixture.scheduler.scheduledDelay, .seconds(1))
        XCTAssertEqual(fixture.appliedOrigins, [])
    }

    func testChangingModeRestartsTargetAndTimer() {
        let fixture = Fixture()
        fixture.controller.update(
            settings: fixture.settings(mode: .freeRoaming),
            isMovementAllowed: true
        )
        XCTAssertNotNil(fixture.controller.targetOrigin)

        fixture.controller.update(
            settings: fixture.settings(mode: .cursorFollowing),
            isMovementAllowed: true
        )

        XCTAssertEqual(fixture.controller.state, .cursorFollowing)
        XCTAssertNil(fixture.controller.targetOrigin)
        XCTAssertEqual(fixture.scheduler.scheduledDelay, .milliseconds(33))
    }

    func testInvalidateEnvironmentClearsTargetAndInvalidatesWindowCache() {
        let fixture = Fixture()
        fixture.controller.update(
            settings: fixture.settings(mode: .freeRoaming),
            isMovementAllowed: true
        )
        XCTAssertNotNil(fixture.controller.targetOrigin)

        fixture.controller.invalidateEnvironment()

        XCTAssertNil(fixture.controller.targetOrigin)
        XCTAssertEqual(fixture.frontmostWindow.invalidateCount, 1)
        XCTAssertEqual(fixture.controller.state, .freeRoamingMoving)
        XCTAssertEqual(fixture.scheduler.scheduledDelay, .milliseconds(33))
    }

    func testStopIsIdempotentAndLeavesNoScheduledWork() {
        let fixture = Fixture()
        fixture.controller.update(
            settings: fixture.settings(mode: .cursorFollowing),
            isMovementAllowed: true
        )

        fixture.controller.stop()
        fixture.controller.stop()

        XCTAssertEqual(fixture.controller.state, .inactive)
        XCTAssertEqual(fixture.controller.activity, .stationary)
        XCTAssertNil(fixture.scheduler.scheduledDelay)
    }
}

@MainActor
private final class Fixture {
    let clock = ManualPetMovementClock()
    let scheduler = ManualPetMovementTickScheduler()
    let frontmostWindow = FakeFrontmostWindowProvider()
    var origin = point(100, 100)
    var petSize = PetMovementSize(width: 100, height: 100)
    var screens = [screen("main", 0, 0, 1_000, 800)]
    var pointer = point(500, 150)
    var randomSamples = [sample(0, 0.5, 0.5)]
    var pointerReadCount = 0
    var appliedOrigins: [PetMovementPoint] = []
    var activities: [PetMovementActivity] = []
    lazy var controller = PetMovementController(
        originProvider: { [weak self] in self?.origin },
        petSizeProvider: { [weak self] in self?.petSize },
        applyOrigin: { [weak self] origin in
            self?.origin = origin
            self?.appliedOrigins.append(origin)
        },
        clock: clock,
        tickScheduler: scheduler,
        frontmostWindowProvider: frontmostWindow,
        screensProvider: { [weak self] in self?.screens ?? [] },
        pointerProvider: { [weak self] in
            self?.pointerReadCount += 1
            return self?.pointer
        },
        randomSampleProvider: { [weak self] in
            guard let self, !self.randomSamples.isEmpty else {
                return sample(0, 0.5, 0.5)
            }
            return self.randomSamples.removeFirst()
        },
        onActivityChange: { [weak self] in self?.activities.append($0) }
    )

    func settings(
        mode: PetMovementMode,
        speed: Double = 160,
        cursorDistance: Double = 96,
        stopRadius: Double = 16,
        dwellMilliseconds: Int64 = 6_000,
        prefersFrontmostWindow: Bool = true,
        cursorMotionID: String? = nil,
        freeMotionID: String? = nil
    ) -> PetMovementSettings {
        PetMovementSettings(
            mode: mode,
            speed: speed,
            cursorDistance: cursorDistance,
            stopRadius: stopRadius,
            freeRoamingDwellMilliseconds: dwellMilliseconds,
            prefersFrontmostWindow: prefersFrontmostWindow,
            cursorFollowingMotionID: cursorMotionID,
            freeRoamingMotionID: freeMotionID
        )
    }
}

@MainActor
private final class ManualPetMovementClock: PetMovementClock {
    private(set) var now = ContinuousClock().now

    func advance(by duration: Duration) {
        now = now.advanced(by: duration)
    }
}

@MainActor
private final class ManualPetMovementTickScheduler: PetMovementTickScheduling {
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

@MainActor
private final class FakeFrontmostWindowProvider: FrontmostWindowProviding {
    var window: PetMovementWindow?
    private(set) var readCount = 0
    private(set) var invalidateCount = 0

    func representativeWindow() -> PetMovementWindow? {
        readCount += 1
        return window
    }

    func invalidate() {
        invalidateCount += 1
    }
}

private func movement(_ motionID: String?) -> PetMovementActivity {
    PetMovementActivity(isMoving: true, motionID: motionID)
}

private func point(_ x: Double, _ y: Double) -> PetMovementPoint {
    PetMovementPoint(x: x, y: y)
}

private func rect(
    _ x: Double,
    _ y: Double,
    _ width: Double,
    _ height: Double
) -> PetMovementRect {
    PetMovementRect(x: x, y: y, width: width, height: height)
}

private func screen(
    _ id: String,
    _ x: Double,
    _ y: Double,
    _ width: Double,
    _ height: Double
) -> PetMovementScreen {
    PetMovementScreen(
        id: id,
        visibleFrame: rect(x, y, width, height)
    )
}

private func sample(
    _ screen: Double,
    _ horizontal: Double,
    _ vertical: Double
) -> PetMovementRandomSample {
    PetMovementRandomSample(
        screen: screen,
        horizontal: horizontal,
        vertical: vertical
    )
}
