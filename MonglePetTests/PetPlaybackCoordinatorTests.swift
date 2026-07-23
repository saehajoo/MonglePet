import XCTest
@testable import MonglePet

@MainActor
final class PetPlaybackCoordinatorTests: XCTestCase {
    func testMovementTemporarilyOverridesBehaviorAndRestoresLatestBehavior() {
        var receivedMotionIDs: [String?] = []
        let coordinator = PetPlaybackCoordinator(
            petDefinition: makePet()
        ) { receivedMotionIDs.append($0?.motion.id) }

        coordinator.setBehaviorPlayback(playback(motionID: "idle"))
        coordinator.setMovementActivity(
            PetMovementActivity(isMoving: true, motionID: "run")
        )
        coordinator.setBehaviorPlayback(playback(motionID: "rest"))

        XCTAssertEqual(coordinator.currentPlayback?.motion.id, "run")
        XCTAssertTrue(coordinator.currentPlayback?.motion.loops == true)
        XCTAssertEqual(receivedMotionIDs, ["idle", "run"])

        coordinator.setMovementActivity(.stationary)

        XCTAssertEqual(coordinator.currentPlayback?.motion.id, "rest")
        XCTAssertEqual(receivedMotionIDs, ["idle", "run", "rest"])
    }

    func testMissingMovementMotionKeepsBehaviorPlayback() {
        var receivedMotionIDs: [String?] = []
        let coordinator = PetPlaybackCoordinator(
            petDefinition: makePet()
        ) { receivedMotionIDs.append($0?.motion.id) }
        let base = playback(motionID: "idle")

        coordinator.setBehaviorPlayback(base)
        coordinator.setMovementActivity(
            PetMovementActivity(isMoving: true, motionID: nil)
        )
        coordinator.setMovementActivity(
            PetMovementActivity(isMoving: true, motionID: "missing")
        )

        XCTAssertEqual(coordinator.currentPlayback, base)
        XCTAssertEqual(receivedMotionIDs, ["idle"])
    }

    func testInteractionTakesPriorityOverMovement() {
        let coordinator = PetPlaybackCoordinator(
            petDefinition: makePet()
        ) { _ in }

        coordinator.setBehaviorPlayback(playback(motionID: "idle"))
        coordinator.setMovementActivity(
            PetMovementActivity(isMoving: true, motionID: "run")
        )
        coordinator.setBehaviorPlayback(
            playback(motionID: "petting", isInteraction: true)
        )

        XCTAssertEqual(coordinator.currentPlayback?.motion.id, "petting")

        coordinator.setBehaviorPlayback(playback(motionID: "idle"))

        XCTAssertEqual(coordinator.currentPlayback?.motion.id, "run")
    }

    private func playback(
        motionID: String,
        isInteraction: Bool = false
    ) -> ScheduledMotion {
        ScheduledMotion(
            sequenceID: "sequence",
            stepIndex: 0,
            requestedMotionID: motionID,
            motion: makePet().motion(id: motionID)!,
            playbackSpeed: 1,
            isInteraction: isInteraction
        )
    }

    private func makePet() -> PetDefinition {
        PetDefinition(
            id: "test.pet",
            displayName: "Test Pet",
            defaultMotionID: "idle",
            motions: ["idle", "rest", "run", "petting"].map {
                PetMotion(
                    id: $0,
                    loops: $0 != "petting",
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
