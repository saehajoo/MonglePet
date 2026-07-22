import XCTest
@testable import MonglePet

final class BehaviorResolverTests: XCTestCase {
    private let baseInstant = ContinuousClock().now

    func testTuckedAwayAndSystemSuspensionTakePriorityOverBehavior() {
        let configuration = makeConfiguration(mode: .manual, manualSequenceID: "manual")
        let lockedSnapshot = snapshot(
            at: .zero,
            idle: .seconds(900),
            applicationID: "com.example.Editor",
            isScreenLocked: true
        )
        var resolver = BehaviorResolver()

        XCTAssertEqual(
            resolver.resolve(
                configuration: configuration,
                snapshot: lockedSnapshot,
                runtimeState: BehaviorRuntimeState(
                    presentation: .tuckedAway,
                    interactionSequenceID: "petting"
                )
            ),
            .tuckedAway
        )
        XCTAssertEqual(
            resolver.resolve(
                configuration: configuration,
                snapshot: lockedSnapshot,
                runtimeState: BehaviorRuntimeState(
                    presentation: .awake,
                    interactionSequenceID: "petting"
                )
            ),
            .suspended
        )
    }

    func testInteractionTakesPriorityOverManualMode() throws {
        let configuration = makeConfiguration(mode: .manual, manualSequenceID: "manual")
        var resolver = BehaviorResolver()

        let decision = resolver.resolve(
            configuration: configuration,
            snapshot: snapshot(at: .zero),
            runtimeState: BehaviorRuntimeState(
                presentation: .awake,
                interactionSequenceID: "petting"
            )
        )

        XCTAssertEqual(try sequence(from: decision).id, "petting")
        XCTAssertEqual(source(from: decision), .interaction)
    }

    func testManualModeIgnoresApplicationAndIdleRules() throws {
        let configuration = makeConfiguration(mode: .manual, manualSequenceID: "manual")
        var resolver = BehaviorResolver()

        let decision = resolver.resolve(
            configuration: configuration,
            snapshot: snapshot(
                at: .zero,
                idle: .seconds(900),
                applicationID: "com.example.Editor"
            ),
            runtimeState: BehaviorRuntimeState(presentation: .awake)
        )

        XCTAssertEqual(try sequence(from: decision).id, "manual")
        XCTAssertEqual(source(from: decision), .manual)
    }

    func testAutomaticPriorityIsLongIdleThenApplicationThenShortIdleThenDefault() throws {
        let configuration = makeConfiguration(mode: .automatic)
        var resolver = BehaviorResolver()

        let defaultDecision = resolver.resolve(
            configuration: configuration,
            snapshot: snapshot(at: .zero, idle: .seconds(119)),
            runtimeState: BehaviorRuntimeState(presentation: .awake)
        )
        XCTAssertEqual(try sequence(from: defaultDecision).id, "idle")

        let shortIdleDecision = resolver.resolve(
            configuration: configuration,
            snapshot: snapshot(at: .seconds(1), idle: .seconds(120)),
            runtimeState: BehaviorRuntimeState(presentation: .awake)
        )
        XCTAssertEqual(try sequence(from: shortIdleDecision).id, "rest")

        let applicationDecision = resolver.resolve(
            configuration: configuration,
            snapshot: snapshot(
                at: .seconds(2),
                idle: .seconds(120),
                applicationID: "com.example.Editor"
            ),
            runtimeState: BehaviorRuntimeState(presentation: .awake)
        )
        XCTAssertEqual(try sequence(from: applicationDecision).id, "focus")

        let longIdleDecision = resolver.resolve(
            configuration: configuration,
            snapshot: snapshot(
                at: .seconds(3),
                idle: .seconds(600),
                applicationID: "com.example.Editor"
            ),
            runtimeState: BehaviorRuntimeState(presentation: .awake)
        )
        XCTAssertEqual(try sequence(from: longIdleDecision).id, "sleep")
    }

    func testRulesUseHigherPriorityThenStableArrayOrder() throws {
        let firstRule = AutomaticRule(
            id: UUID(),
            isEnabled: true,
            priority: 10,
            condition: .application(bundleIdentifier: "com.example.Editor"),
            sequenceID: "focus"
        )
        let samePriorityRule = AutomaticRule(
            id: UUID(),
            isEnabled: true,
            priority: 10,
            condition: .application(bundleIdentifier: "com.example.Editor"),
            sequenceID: "manual"
        )
        let lowerPriorityRule = AutomaticRule(
            id: UUID(),
            isEnabled: true,
            priority: 1,
            condition: .application(bundleIdentifier: "com.example.Editor"),
            sequenceID: "rest"
        )
        let base = makeConfiguration(mode: .automatic)
        let configuration = BehaviorConfiguration(
            mode: .automatic,
            defaultSequenceID: base.defaultSequenceID,
            sequences: base.sequences,
            automaticRules: [firstRule, samePriorityRule, lowerPriorityRule]
        )
        var resolver = BehaviorResolver()

        let decision = resolver.resolve(
            configuration: configuration,
            snapshot: snapshot(
                at: .zero,
                applicationID: "com.example.Editor"
            ),
            runtimeState: BehaviorRuntimeState(presentation: .awake)
        )

        XCTAssertEqual(try sequence(from: decision).id, "focus")
        XCTAssertEqual(source(from: decision), .automaticRule(firstRule.id))
    }

    func testIdleExitHysteresisHoldsUntilExactThreeSecondBoundary() throws {
        let configuration = makeConfiguration(mode: .automatic)
        var resolver = BehaviorResolver()
        let runtimeState = BehaviorRuntimeState(presentation: .awake)

        let entered = resolver.resolve(
            configuration: configuration,
            snapshot: snapshot(at: .zero, idle: .seconds(120)),
            runtimeState: runtimeState
        )
        XCTAssertEqual(try sequence(from: entered).id, "rest")

        let recoveryStarted = resolver.resolve(
            configuration: configuration,
            snapshot: snapshot(at: .seconds(1), idle: .zero),
            runtimeState: runtimeState
        )
        XCTAssertEqual(try sequence(from: recoveryStarted).id, "rest")

        let beforeBoundary = resolver.resolve(
            configuration: configuration,
            snapshot: snapshot(at: .milliseconds(3_999), idle: .zero),
            runtimeState: runtimeState
        )
        XCTAssertEqual(try sequence(from: beforeBoundary).id, "rest")

        let atBoundary = resolver.resolve(
            configuration: configuration,
            snapshot: snapshot(at: .seconds(4), idle: .zero),
            runtimeState: runtimeState
        )
        XCTAssertEqual(try sequence(from: atBoundary).id, "idle")
    }

    func testMissingSequenceFallsBackToDefaultAndEmptyConfigurationIsUnavailable() throws {
        let missingRule = AutomaticRule(
            id: UUID(),
            isEnabled: true,
            priority: 1,
            condition: .application(bundleIdentifier: "com.example.Editor"),
            sequenceID: "missing"
        )
        let idle = makeSequence(id: "idle", motionID: "idle")
        let configuration = BehaviorConfiguration(
            mode: .automatic,
            defaultSequenceID: idle.id,
            sequences: [idle],
            automaticRules: [missingRule]
        )
        var resolver = BehaviorResolver()

        let fallback = resolver.resolve(
            configuration: configuration,
            snapshot: snapshot(
                at: .zero,
                applicationID: "com.example.Editor"
            ),
            runtimeState: BehaviorRuntimeState(presentation: .awake)
        )
        XCTAssertEqual(try sequence(from: fallback).id, "idle")
        XCTAssertEqual(source(from: fallback), .defaultBehavior)

        let unavailable = resolver.resolve(
            configuration: BehaviorConfiguration(
                mode: .automatic,
                defaultSequenceID: "missing",
                sequences: []
            ),
            snapshot: snapshot(at: .seconds(1)),
            runtimeState: BehaviorRuntimeState(presentation: .awake)
        )
        XCTAssertEqual(unavailable, .unavailable)
    }

    private func makeConfiguration(
        mode: BehaviorMode,
        manualSequenceID: String? = nil
    ) -> BehaviorConfiguration {
        let sequences = [
            makeSequence(id: "idle", motionID: "idle"),
            makeSequence(id: "manual", motionID: "idle"),
            makeSequence(id: "focus", motionID: "focus"),
            makeSequence(id: "rest", motionID: "rest"),
            makeSequence(id: "sleep", motionID: "sleep"),
            makeSequence(id: "petting", motionID: "petting", repeats: false)
        ]
        let rules = [
            AutomaticRule(
                id: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!,
                isEnabled: true,
                priority: 10,
                condition: .idleAtLeast(milliseconds: 600_000),
                sequenceID: "sleep"
            ),
            AutomaticRule(
                id: UUID(uuidString: "10000000-0000-0000-0000-000000000002")!,
                isEnabled: true,
                priority: 10,
                condition: .application(bundleIdentifier: "com.example.Editor"),
                sequenceID: "focus"
            ),
            AutomaticRule(
                id: UUID(uuidString: "10000000-0000-0000-0000-000000000003")!,
                isEnabled: true,
                priority: 10,
                condition: .idleAtLeast(milliseconds: 120_000),
                sequenceID: "rest"
            )
        ]

        return BehaviorConfiguration(
            mode: mode,
            defaultSequenceID: "idle",
            manualSequenceID: manualSequenceID,
            sequences: sequences,
            automaticRules: rules
        )
    }

    private func makeSequence(
        id: String,
        motionID: String,
        repeats: Bool = true
    ) -> BehaviorSequence {
        BehaviorSequence(
            id: id,
            steps: [
                BehaviorStep(
                    motionID: motionID,
                    duration: .seconds(30),
                    playbackSpeed: 1
                )
            ],
            repeats: repeats
        )
    }

    private func snapshot(
        at offset: Duration,
        idle: Duration = .zero,
        applicationID: String? = nil,
        isScreenLocked: Bool = false,
        isSystemSleeping: Bool = false
    ) -> ActivitySnapshot {
        ActivitySnapshot(
            capturedAt: baseInstant.advanced(by: offset),
            idleDuration: idle,
            frontmostApplicationID: applicationID,
            isScreenLocked: isScreenLocked,
            isSystemSleeping: isSystemSleeping
        )
    }

    private func sequence(from decision: BehaviorDecision) throws -> BehaviorSequence {
        try XCTUnwrap(decision.sequence)
    }

    private func source(from decision: BehaviorDecision) -> BehaviorSource? {
        guard case let .sequence(_, source) = decision else {
            return nil
        }

        return source
    }
}
