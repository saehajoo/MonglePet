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
        coordinator.setMovementPlayback(playback(motionID: "run"))
        coordinator.setBehaviorPlayback(playback(motionID: "rest"))

        XCTAssertEqual(coordinator.currentPlayback?.motion.id, "run")
        XCTAssertTrue(coordinator.currentPlayback?.motion.loops == true)
        XCTAssertEqual(receivedMotionIDs, ["idle", "run"])

        coordinator.setMovementPlayback(nil)

        XCTAssertEqual(coordinator.currentPlayback?.motion.id, "rest")
        XCTAssertEqual(receivedMotionIDs, ["idle", "run", "rest"])
    }

    func testMovementPresentationChangesIgnoreInteractionOverlay() {
        var receivedStates: [Bool] = []
        let coordinator = PetPlaybackCoordinator(
            petDefinition: makePet()
        ) { _ in }
        coordinator.setMovementPresentationChangeHandler {
            receivedStates.append($0)
        }

        coordinator.setBehaviorPlayback(playback(motionID: "idle"))
        coordinator.setMovementPlayback(playback(motionID: "run"))
        coordinator.setBehaviorPlayback(
            playback(motionID: "petting", isInteraction: true)
        )
        coordinator.setBehaviorPlayback(playback(motionID: "rest"))
        coordinator.setMovementPlayback(nil)

        XCTAssertEqual(receivedStates, [true, false])
    }

    func testMissingMovementMotionKeepsBehaviorPlayback() {
        var receivedMotionIDs: [String?] = []
        let coordinator = PetPlaybackCoordinator(
            petDefinition: makePet()
        ) { receivedMotionIDs.append($0?.motion.id) }
        let base = playback(motionID: "idle")

        coordinator.setBehaviorPlayback(base)
        coordinator.setMovementPlayback(nil)
        coordinator.setMovementPlayback(nil)

        XCTAssertEqual(coordinator.currentPlayback, base)
        XCTAssertEqual(receivedMotionIDs, ["idle"])
    }

    func testInteractionTakesPriorityOverMovement() {
        let coordinator = PetPlaybackCoordinator(
            petDefinition: makePet()
        ) { _ in }

        coordinator.setBehaviorPlayback(playback(motionID: "idle"))
        coordinator.setMovementPlayback(playback(motionID: "run"))
        coordinator.setBehaviorPlayback(
            playback(motionID: "petting", isInteraction: true)
        )

        XCTAssertEqual(coordinator.currentPlayback?.motion.id, "petting")

        coordinator.setBehaviorPlayback(playback(motionID: "idle"))

        XCTAssertEqual(coordinator.currentPlayback?.motion.id, "run")
    }

    func testConfiguredPriorityCanShowAutomaticRuleInsteadOfMovementPlayback() {
        let coordinator = PetPlaybackCoordinator(
            petDefinition: makePet()
        ) { _ in }

        coordinator.setBehaviorPlayback(playback(motionID: "rest"))
        coordinator.setMovementPlayback(playback(motionID: "run"))
        XCTAssertEqual(coordinator.currentPlayback?.motion.id, "run")

        coordinator.setMovementTakesPriority(false)
        XCTAssertEqual(coordinator.currentPlayback?.motion.id, "rest")

        coordinator.setMovementTakesPriority(true)
        XCTAssertEqual(coordinator.currentPlayback?.motion.id, "run")
    }

    func testMovementPriorityResolverUsesListOrderForMatchingRule() {
        let ruleID = UUID()
        let rule = AutomaticRule(
            id: ruleID,
            isEnabled: true,
            priority: 10,
            condition: .application(bundleIdentifier: "com.example.Editor"),
            sequenceID: "focus"
        )
        let sequence = BehaviorSequence(
            id: "focus",
            steps: [BehaviorStep(motionID: "rest", repeatCount: 1)],
            repeats: true
        )
        let decision = BehaviorDecision.sequence(
            sequence,
            source: .automaticRule(ruleID)
        )
        let resolver = MovementPlaybackPriorityResolver()

        XCTAssertEqual(
            resolver.resolve(
                mode: .automatic,
                decision: decision,
                rules: [rule],
                order: [.movement, .idle, .application]
            ),
            MovementPriorityResolution(
                movementTakesPriority: true,
                blocksMovement: false
            )
        )
        XCTAssertEqual(
            resolver.resolve(
                mode: .automatic,
                decision: decision,
                rules: [rule],
                order: [.application, .movement, .idle]
            ),
            MovementPriorityResolution(
                movementTakesPriority: false,
                blocksMovement: true
            )
        )
        XCTAssertEqual(
            resolver.resolve(
                mode: .manual,
                decision: decision,
                rules: [rule],
                order: [.application, .movement, .idle]
            ),
            MovementPriorityResolution(
                movementTakesPriority: false,
                blocksMovement: true
            )
        )
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
            cycleElapsedDuration: .zero,
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
