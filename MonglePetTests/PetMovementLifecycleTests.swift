import XCTest
@testable import MonglePet

@MainActor
final class PetMovementLifecycleTests: XCTestCase {
    func testMovementRequiresAwakeAndActiveSystemState() {
        let controller = RecordingPetMovementController()
        let lifecycle = PetMovementLifecycle(controller: controller)
        let settings = cursorFollowingSettings()

        lifecycle.setSettings(settings)
        lifecycle.setAwake(true)

        XCTAssertFalse(lifecycle.isMovementAllowed)
        XCTAssertEqual(controller.updates.last, Update(settings, false))

        lifecycle.setSystemSuspended(false)

        XCTAssertTrue(lifecycle.isMovementAllowed)
        XCTAssertEqual(controller.updates.last, Update(settings, true))

        lifecycle.setAwake(false)

        XCTAssertFalse(lifecycle.isMovementAllowed)
        XCTAssertEqual(controller.updates.last, Update(settings, false))
    }

    func testUserDragAndReduceMotionOverrideAutomaticMovement() {
        let controller = RecordingPetMovementController()
        let lifecycle = PetMovementLifecycle(controller: controller)
        let settings = cursorFollowingSettings()
        lifecycle.setSettings(settings)
        lifecycle.setAwake(true)
        lifecycle.setSystemSuspended(false)
        XCTAssertTrue(lifecycle.isMovementAllowed)

        lifecycle.setUserDragging(true)
        XCTAssertFalse(lifecycle.isMovementAllowed)
        XCTAssertEqual(controller.updates.last, Update(settings, false))

        lifecycle.setUserDragging(false)
        XCTAssertTrue(lifecycle.isMovementAllowed)
        XCTAssertEqual(controller.updates.last, Update(settings, true))

        lifecycle.setReduceMotion(true)
        XCTAssertFalse(lifecycle.isMovementAllowed)
        XCTAssertEqual(controller.updates.last, Update(settings, false))

        lifecycle.setReduceMotion(false)
        XCTAssertTrue(lifecycle.isMovementAllowed)
        XCTAssertEqual(controller.updates.last, Update(settings, true))
    }

    func testEnvironmentInvalidationAndStopAreForwarded() {
        let controller = RecordingPetMovementController()
        let lifecycle = PetMovementLifecycle(controller: controller)

        lifecycle.invalidateEnvironment()
        lifecycle.stop()

        XCTAssertEqual(controller.invalidationCount, 1)
        XCTAssertEqual(controller.stopCount, 1)
    }

    private func cursorFollowingSettings() -> PetMovementSettings {
        PetMovementSettings(
            mode: .cursorFollowing,
            speed: 160,
            cursorDistance: 96,
            stopRadius: 16,
            freeRoamingDwellMilliseconds: 6_000,
            prefersFrontmostWindow: true,
            cursorFollowingMotionID: "run"
        )
    }
}

private struct Update: Equatable {
    let settings: PetMovementSettings
    let isAllowed: Bool

    init(_ settings: PetMovementSettings, _ isAllowed: Bool) {
        self.settings = settings
        self.isAllowed = isAllowed
    }
}

@MainActor
private final class RecordingPetMovementController: PetMovementControlling {
    private(set) var updates: [Update] = []
    private(set) var stopCount = 0
    private(set) var invalidationCount = 0

    func update(
        settings: PetMovementSettings,
        isMovementAllowed: Bool
    ) {
        updates.append(Update(settings, isMovementAllowed))
    }

    func stop() {
        stopCount += 1
    }

    func invalidateEnvironment() {
        invalidationCount += 1
    }
}
