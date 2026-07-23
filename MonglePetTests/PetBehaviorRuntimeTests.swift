import Foundation
import XCTest
@testable import MonglePet

@MainActor
final class PetBehaviorRuntimeTests: XCTestCase {
    private let frameRect = PixelRect(x: 0, y: 0, width: 100, height: 100)

    func testManualSequenceSwitchesAtCurrentStepBoundary() throws {
        let clock = ManualBehaviorRuntimeClock()
        let tickScheduler = ManualBehaviorTickScheduler()
        var receivedPlaybacks: [ScheduledMotion?] = []
        let runtime = PetBehaviorRuntime(
            petDefinition: makePet(),
            clock: clock,
            tickScheduler: tickScheduler
        ) { receivedPlaybacks.append($0) }
        var settings = makeSettings(mode: .manual, manualSequenceID: "focus")

        runtime.update(settings: settings, snapshot: snapshot())
        XCTAssertEqual(runtime.currentPlayback?.motion.id, "focus")
        XCTAssertEqual(tickScheduler.scheduledDelay, .seconds(3))

        settings = makeSettings(mode: .manual, manualSequenceID: "rest")
        runtime.update(settings: settings, snapshot: snapshot())
        XCTAssertEqual(runtime.currentPlayback?.motion.id, "focus")
        XCTAssertEqual(receivedPlaybacks.compactMap { $0 }.count, 1)

        clock.advance(by: .seconds(3))
        tickScheduler.fire()
        XCTAssertEqual(runtime.currentPlayback?.motion.id, "rest")
        XCTAssertEqual(tickScheduler.scheduledDelay, .seconds(3))
        XCTAssertEqual(receivedPlaybacks.compactMap { $0 }.map(\.motion.id), ["focus", "rest"])
    }

    func testAutomaticModeWithoutRulesKeepsCurrentPetDefaultMotion() {
        let clock = ManualBehaviorRuntimeClock()
        let tickScheduler = ManualBehaviorTickScheduler()
        let runtime = PetBehaviorRuntime(
            petDefinition: makePet(),
            clock: clock,
            tickScheduler: tickScheduler
        ) { _ in }
        let settings = makeSettings(mode: .automatic)

        runtime.update(settings: settings, snapshot: snapshot(idle: .zero))
        XCTAssertEqual(runtime.currentPlayback?.motion.id, "idle")

        runtime.update(settings: settings, snapshot: snapshot(idle: .seconds(600)))
        clock.advance(by: .seconds(3))
        tickScheduler.fire()
        XCTAssertEqual(runtime.currentPlayback?.motion.id, "idle")
    }

    func testCycleStepSchedulesEachFullCycleAndAdvancesAfterRepeatCount() {
        let clock = ManualBehaviorRuntimeClock()
        let tickScheduler = ManualBehaviorTickScheduler()
        let runtime = PetBehaviorRuntime(
            petDefinition: makePet(),
            clock: clock,
            tickScheduler: tickScheduler
        ) { _ in }
        let sequence = BehaviorSequence(
            id: "cycle-routine",
            steps: [
                BehaviorStep(motionID: "focus", repeatCount: 2),
                BehaviorStep(motionID: "rest", repeatCount: 1)
            ],
            repeats: false
        )
        let settings = AppSettings(
            selectedPetInstallationID: nil,
            lastUserPresentation: .awake,
            behaviorMode: .manual,
            overlay: .default,
            manualSequenceID: sequence.id,
            sequences: [sequence],
            automaticRules: []
        )

        runtime.update(settings: settings, snapshot: snapshot())
        XCTAssertEqual(runtime.currentPlayback?.motion.id, "focus")
        XCTAssertEqual(tickScheduler.scheduledDelay, .milliseconds(100))

        clock.advance(by: .milliseconds(100))
        tickScheduler.fire()
        XCTAssertEqual(runtime.currentPlayback?.motion.id, "focus")
        XCTAssertEqual(tickScheduler.scheduledDelay, .milliseconds(100))

        clock.advance(by: .milliseconds(100))
        tickScheduler.fire()
        XCTAssertEqual(runtime.currentPlayback?.motion.id, "rest")
        XCTAssertEqual(tickScheduler.scheduledDelay, .milliseconds(100))
    }

    func testSuspensionCancelsTickAndPreservesRemainingStepTime() {
        let clock = ManualBehaviorRuntimeClock()
        let tickScheduler = ManualBehaviorTickScheduler()
        let runtime = PetBehaviorRuntime(
            petDefinition: makePet(),
            clock: clock,
            tickScheduler: tickScheduler
        ) { _ in }
        let sequence = BehaviorSequence(
            id: "cycle-routine",
            steps: [BehaviorStep(motionID: "idle", repeatCount: 3)],
            repeats: true
        )
        let settings = AppSettings(
            selectedPetInstallationID: nil,
            lastUserPresentation: .awake,
            behaviorMode: .manual,
            overlay: .default,
            manualSequenceID: sequence.id,
            sequences: [sequence],
            automaticRules: []
        )

        runtime.update(settings: settings, snapshot: snapshot())
        clock.advance(by: .milliseconds(40))
        runtime.update(
            settings: settings,
            snapshot: snapshot(isScreenLocked: true)
        )

        XCTAssertTrue(runtime.isPaused)
        XCTAssertNil(tickScheduler.scheduledDelay)

        clock.advance(by: .seconds(100))
        runtime.update(settings: settings, snapshot: snapshot())

        XCTAssertFalse(runtime.isPaused)
        XCTAssertEqual(runtime.currentPlayback?.motion.id, "idle")
        XCTAssertEqual(tickScheduler.scheduledDelay, .milliseconds(60))
    }

    func testBuiltInFallbackConfigurationProvidesUsableDefaults() {
        let configuration = BuiltInBehaviorPresets.configuration(for: .default)

        XCTAssertEqual(
            configuration.defaultSequenceID,
            BuiltInBehaviorPresets.defaultSequenceID
        )
        XCTAssertEqual(configuration.sequences, BuiltInBehaviorPresets.sequences)
        XCTAssertTrue(configuration.automaticRules.isEmpty)
        XCTAssertEqual(
            configuration.manualSequenceID,
            BuiltInBehaviorPresets.defaultSequenceID
        )
    }

    func testReplacingPetDefinitionRestartsDecisionWithIdleFallback() {
        let clock = ManualBehaviorRuntimeClock()
        let tickScheduler = ManualBehaviorTickScheduler()
        var receivedMotionIDs: [String?] = []
        let runtime = PetBehaviorRuntime(
            petDefinition: makePet(),
            clock: clock,
            tickScheduler: tickScheduler
        ) { receivedMotionIDs.append($0?.motion.id) }
        let settings = makeSettings(mode: .manual, manualSequenceID: "focus")

        runtime.update(settings: settings, snapshot: snapshot())
        XCTAssertEqual(runtime.currentPlayback?.motion.id, "focus")

        runtime.replacePetDefinition(makeIdleOnlyPet())
        XCTAssertNil(runtime.currentPlayback)
        runtime.update(settings: settings, snapshot: snapshot())

        XCTAssertEqual(runtime.currentPlayback?.requestedMotionID, "focus")
        XCTAssertEqual(runtime.currentPlayback?.motion.id, "idle")
        XCTAssertTrue(runtime.currentPlayback?.usesFallback == true)
        XCTAssertEqual(receivedMotionIDs, ["focus", "idle"])
    }

    func testPettingInteractionRestoresBaseCycleRemainingTime() {
        let clock = ManualBehaviorRuntimeClock()
        let tickScheduler = ManualBehaviorTickScheduler()
        var receivedMotionIDs: [String?] = []
        let runtime = PetBehaviorRuntime(
            petDefinition: makePet(),
            clock: clock,
            tickScheduler: tickScheduler
        ) { receivedMotionIDs.append($0?.motion.id) }
        let sequence = BehaviorSequence(
            id: "base",
            steps: [BehaviorStep(motionID: "idle", repeatCount: 1)],
            repeats: true
        )
        let settings = AppSettings(
            selectedPetInstallationID: nil,
            lastUserPresentation: .awake,
            behaviorMode: .manual,
            overlay: .default,
            manualSequenceID: sequence.id,
            sequences: [sequence],
            automaticRules: []
        )

        runtime.update(settings: settings, snapshot: snapshot())
        clock.advance(by: .milliseconds(40))

        XCTAssertTrue(runtime.triggerInteraction(motionID: "petting"))
        XCTAssertFalse(runtime.triggerInteraction(motionID: "petting"))
        XCTAssertEqual(runtime.currentPlayback?.motion.id, "petting")
        XCTAssertTrue(runtime.currentPlayback?.isInteraction == true)
        XCTAssertEqual(tickScheduler.scheduledDelay, .milliseconds(100))

        clock.advance(by: .milliseconds(100))
        tickScheduler.fire()

        XCTAssertEqual(runtime.currentPlayback?.motion.id, "idle")
        XCTAssertFalse(runtime.currentPlayback?.isInteraction == true)
        XCTAssertEqual(tickScheduler.scheduledDelay, .milliseconds(60))
        XCTAssertEqual(receivedMotionIDs, ["idle", "petting", "idle"])
    }

    private func makeSettings(
        mode: BehaviorMode,
        manualSequenceID: String? = nil
    ) -> AppSettings {
        AppSettings(
            selectedPetInstallationID: nil,
            lastUserPresentation: .awake,
            behaviorMode: mode,
            overlay: .default,
            manualSequenceID: manualSequenceID,
            sequences: BuiltInBehaviorPresets.legacySequences,
            automaticRules: []
        )
    }

    private func makePet() -> PetDefinition {
        PetDefinition(
            id: "test.pet",
            displayName: "Test Pet",
            defaultMotionID: "idle",
            motions: ["idle", "focus", "rest", "sleep", "petting"].map { motionID in
                PetMotion(
                    id: motionID,
                    loops: true,
                    frames: [
                        MotionFrame(
                            atlasID: "main",
                            sourceRect: frameRect,
                            duration: .milliseconds(100)
                        )
                    ]
                )
            }
        )
    }

    private func makeIdleOnlyPet() -> PetDefinition {
        PetDefinition(
            id: "idle-only.pet",
            displayName: "Idle Only",
            defaultMotionID: "idle",
            motions: [
                PetMotion(
                    id: "idle",
                    loops: true,
                    frames: [
                        MotionFrame(
                            atlasID: "main",
                            sourceRect: frameRect,
                            duration: .milliseconds(100)
                        )
                    ]
                )
            ]
        )
    }

    private func snapshot(
        idle: Duration = .zero,
        isScreenLocked: Bool = false
    ) -> ActivitySnapshot {
        ActivitySnapshot(
            capturedAt: ContinuousClock().now,
            idleDuration: idle,
            frontmostApplicationID: nil,
            isScreenLocked: isScreenLocked,
            isSystemSleeping: false
        )
    }
}

@MainActor
private final class ManualBehaviorRuntimeClock: BehaviorRuntimeClock {
    private(set) var now = ContinuousClock().now

    func advance(by duration: Duration) {
        now = now.advanced(by: duration)
    }
}

@MainActor
private final class ManualBehaviorTickScheduler: BehaviorTickScheduling {
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
