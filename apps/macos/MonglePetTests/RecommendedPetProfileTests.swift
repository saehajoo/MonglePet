import Foundation
import XCTest
@testable import MonglePet

final class RecommendedPetProfileTests: XCTestCase {
    func testCodecRoundTripsShareableBehaviorMovementAndInteractionSettings() throws {
        let profile = makeProfile()

        let data = try RecommendedPetProfileCodec.encode(
            profile,
            for: petDefinition
        )
        let decoded = try RecommendedPetProfileCodec.decode(
            data,
            for: petDefinition
        )

        XCTAssertEqual(decoded, profile)
        XCTAssertEqual(
            decoded.behaviorProfile(for: .builtIn),
            BehaviorProfile(
                petKey: .builtIn,
                mode: profile.mode,
                manualSequenceID: profile.manualSequenceID,
                randomSequenceIDs: profile.randomSequenceIDs,
                sequences: profile.sequences,
                automaticRules: profile.automaticRules,
                automaticRulePriorityOrder:
                    profile.automaticRulePriorityOrder,
                movement: profile.movement,
                pettingMotionID: profile.pettingMotionID,
                speech: profile.speech
            )
        )

        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        XCTAssertEqual(object["schemaVersion"] as? Int, 11)
        XCTAssertNotNil(object["behavior"])
        XCTAssertNotNil(object["movement"])
        XCTAssertNotNil(object["automaticRules"])
        let speech = try XCTUnwrap(object["speech"] as? [String: Any])
        let placement = try XCTUnwrap(
            speech["placement"] as? [String: Any]
        )
        XCTAssertEqual(
            placement["preferredPosition"] as? String,
            "above"
        )
        XCTAssertEqual(placement["horizontalOffset"] as? Double, -36)
        XCTAssertEqual(placement["gap"] as? Double, 20)
        XCTAssertNil(object["petKey"])
        XCTAssertNil(object["installationID"])
        XCTAssertNil(object["selectedPetInstallationID"])
        XCTAssertNil(object["overlay"])
        XCTAssertNil(object["screenIdentifier"])
        XCTAssertNil(object["lastUserPresentation"])
        XCTAssertNotNil(object["display"])
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        for forbiddenKey in [
            "installationID",
            "petKey",
            "originX",
            "originY",
            "screenIdentifier",
            "lastUserPresentation",
            "movementBoundary",
            "screenIdentifier"
        ] {
            XCTAssertFalse(json.contains(forbiddenKey))
        }
    }

    func testCodecAllowsReservedCurrentPetDefaultMotionReference() throws {
        let profile = RecommendedPetProfile(
            mode: .manual,
            manualSequenceID: "default",
            sequences: [
                BehaviorSequence(
                    id: "default",
                    steps: [
                        BehaviorStep(
                            motionID: PetMotionReference.currentPetDefault,
                            repeatCount: 1
                        )
                    ],
                    repeats: true
                )
            ],
            automaticRules: [],
            movement: .default,
            pettingMotionID: nil
        )

        let data = try RecommendedPetProfileCodec.encode(
            profile,
            for: petDefinition
        )

        XCTAssertEqual(
            try RecommendedPetProfileCodec.decode(data, for: petDefinition),
            profile
        )
    }

    func testSchemaV9RoundTripsRandomBehaviorAndDwellRange() throws {
        let profile = RecommendedPetProfile(
            mode: .random,
            manualSequenceID: "idle",
            randomSequenceIDs: ["idle", "run"],
            sequences: [
                BehaviorSequence(
                    id: "idle",
                    steps: [BehaviorStep(motionID: "idle", repeatCount: 2)],
                    repeats: true
                ),
                BehaviorSequence(
                    id: "run",
                    steps: [BehaviorStep(motionID: "run", repeatCount: 1)],
                    repeats: true
                )
            ],
            automaticRules: [],
            movement: PetMovementSettings(
                mode: .freeRoaming,
                speed: 120,
                cursorDistance: 80,
                stopRadius: 24,
                freeRoamingDwellMilliseconds: 6_000,
                prefersFrontmostWindow: true,
                randomizesFreeRoamingDwell: true,
                freeRoamingDwellMinimumMilliseconds: 2_000
            ),
            pettingMotionID: nil
        )

        let data = try RecommendedPetProfileCodec.encode(
            profile,
            for: petDefinition
        )
        let decoded = try RecommendedPetProfileCodec.decode(
            data,
            for: petDefinition
        )

        XCTAssertEqual(decoded, profile)
        XCTAssertEqual(decoded.randomSequenceIDs, ["idle", "run"])
        XCTAssertTrue(decoded.movement.randomizesFreeRoamingDwell)
        XCTAssertEqual(
            decoded.movement.freeRoamingDwellMinimumMilliseconds,
            2_000
        )
    }

    func testSchemaV10RoundTripsIndependentMovementAndDisplayOptions() throws {
        let movement = PetMovementSettings(
            mode: .cursorAvoiding,
            cursorFollowing: CursorFollowingMovementSettings(
                speed: 110,
                cursorDistance: 70,
                stopRadius: 10,
                animation: .single("run")
            ),
            freeRoaming: FreeRoamingMovementSettings(
                speed: 180,
                stopRadius: 20,
                dwellMilliseconds: 7_000,
                randomizesDwell: true,
                dwellMinimumMilliseconds: 1_000,
                prefersFrontmostWindow: true,
                animation: .single("idle")
            ),
            cursorAvoiding: CursorAvoidingMovementSettings(
                idleBehavior: .freeRoaming,
                detectionDistance: 260,
                speed: 520,
                stopRadius: 30,
                animation: .single("run"),
                idleFreeRoaming: FreeRoamingMovementSettings(
                    speed: 90,
                    stopRadius: 14,
                    dwellMilliseconds: 15_000,
                    randomizesDwell: false,
                    dwellMinimumMilliseconds: 4_000,
                    prefersFrontmostWindow: false,
                    animation: .single("rest")
                )
            )
        )
        let profile = makeProfile(movement: movement)

        let data = try RecommendedPetProfileCodec.encode(
            profile,
            for: petDefinition
        )
        let decoded = try RecommendedPetProfileCodec.decode(
            data,
            for: petDefinition
        )

        XCTAssertEqual(decoded, profile)
        XCTAssertNotEqual(
            decoded.movement.freeRoaming,
            decoded.movement.cursorAvoiding.idleFreeRoaming
        )
        XCTAssertEqual(decoded.display.scalePercent, 135)
        XCTAssertTrue(decoded.display.clickThrough)
        XCTAssertTrue(decoded.display.pixelArtRendering)
    }

    func testSchemaV10ManualProfileKeepsSelectionButDisablesDormantRules() throws {
        let encoded = try RecommendedPetProfileCodec.encode(
            makeProfile(),
            for: petDefinition
        )
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object["schemaVersion"] = 10
        var behavior = try XCTUnwrap(object["behavior"] as? [String: Any])
        behavior["mode"] = "manual"
        behavior["manualSequenceID"] = behavior["stationarySequenceID"]
        behavior.removeValue(forKey: "stationaryBehaviorMode")
        behavior.removeValue(forKey: "stationarySequenceID")
        object["behavior"] = behavior
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let decoded = try RecommendedPetProfileCodec.decode(
            legacyData,
            for: petDefinition
        )

        XCTAssertEqual(decoded.stationaryBehaviorMode, .fixed)
        XCTAssertEqual(decoded.stationarySequenceID, "default")
        XCTAssertTrue(decoded.automaticRules.allSatisfy { !$0.isEnabled })
    }

    func testCodecKeepsMovementFirstForEarlySchemaV8PriorityLists() throws {
        let encoded = try RecommendedPetProfileCodec.encode(
            makeProfile(),
            for: petDefinition
        )
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object["automaticRulePriorityOrder"] = ["application", "idle"]
        let legacyV8 = try JSONSerialization.data(withJSONObject: object)

        let decoded = try RecommendedPetProfileCodec.decode(
            legacyV8,
            for: petDefinition
        )

        XCTAssertEqual(
            decoded.automaticRulePriorityOrder,
            [.movement, .application, .idle]
        )
    }

    func testCodecRejectsUnknownMotionReferences() {
        let profile = RecommendedPetProfile(
            mode: .manual,
            manualSequenceID: "default",
            sequences: [
                BehaviorSequence(
                    id: "default",
                    steps: [
                        BehaviorStep(motionID: "missing", repeatCount: 1)
                    ],
                    repeats: true
                )
            ],
            automaticRules: [],
            movement: .default,
            pettingMotionID: nil
        )

        XCTAssertThrowsError(
            try RecommendedPetProfileCodec.encode(profile, for: petDefinition)
        ) { error in
            XCTAssertEqual(
                error as? RecommendedPetProfileError,
                .invalidField("behavior.sequences.0.steps.0")
            )
        }
    }

    func testCodecRejectsDuplicateSequenceIDsAndBrokenReferences() {
        let duplicateSequence = BehaviorSequence(
            id: "default",
            steps: [BehaviorStep(motionID: "idle", repeatCount: 1)],
            repeats: true
        )
        let profile = RecommendedPetProfile(
            mode: .automatic,
            manualSequenceID: "missing",
            sequences: [duplicateSequence, duplicateSequence],
            automaticRules: [],
            movement: .default,
            pettingMotionID: nil
        )

        XCTAssertThrowsError(
            try RecommendedPetProfileCodec.encode(profile, for: petDefinition)
        ) { error in
            XCTAssertEqual(
                error as? RecommendedPetProfileError,
                .invalidField("behavior.sequences.1")
            )
        }
    }

    func testCodecAllowsFixedModeWithoutSelectionAsDefaultFallback() throws {
        let profile = RecommendedPetProfile(
            mode: .manual,
            manualSequenceID: nil,
            sequences: [
                BehaviorSequence(
                    id: "default",
                    steps: [BehaviorStep(motionID: "idle", repeatCount: 1)],
                    repeats: true
                )
            ],
            automaticRules: [],
            movement: .default,
            pettingMotionID: nil
        )

        let data = try RecommendedPetProfileCodec.encode(
            profile,
            for: petDefinition
        )
        let decoded = try RecommendedPetProfileCodec.decode(
            data,
            for: petDefinition
        )
        XCTAssertEqual(decoded.stationaryBehaviorMode, .fixed)
        XCTAssertNil(decoded.stationarySequenceID)
    }

    func testCodecRejectsInvalidMovementRangeAndMotionReferences() {
        let invalidRange = makeProfile(
            movement: PetMovementSettings(
                mode: .freeRoaming,
                speed: 0,
                cursorDistance: 80,
                stopRadius: 24,
                freeRoamingDwellMilliseconds: 8_000,
                prefersFrontmostWindow: true,
                cursorFollowingMotionID: "run",
                freeRoamingMotionID: "idle"
            )
        )
        XCTAssertThrowsError(
            try RecommendedPetProfileCodec.encode(
                invalidRange,
                for: petDefinition
            )
        ) { error in
            XCTAssertEqual(
                error as? RecommendedPetProfileError,
                .invalidField("movement")
            )
        }

        let unknownInteraction = makeProfile(pettingMotionID: "missing")
        XCTAssertThrowsError(
            try RecommendedPetProfileCodec.encode(
                unknownInteraction,
                for: petDefinition
            )
        ) { error in
            XCTAssertEqual(
                error as? RecommendedPetProfileError,
                .invalidField("behavior.sequences.5.steps.0")
            )
        }

        let reservedMovementReference = makeProfile(
            movement: PetMovementSettings(
                mode: .cursorFollowing,
                speed: 120,
                cursorDistance: 80,
                stopRadius: 24,
                freeRoamingDwellMilliseconds: 8_000,
                prefersFrontmostWindow: true,
                cursorFollowingMotionID:
                    PetMotionReference.currentPetDefault,
                freeRoamingMotionID: nil
            )
        )
        XCTAssertNoThrow(
            try RecommendedPetProfileCodec.encode(
                reservedMovementReference,
                for: petDefinition
            )
        )
    }

    func testCodecRejectsRuleWithUnknownSequence() {
        let profile = makeProfile(
            automaticRules: [
                AutomaticRule(
                    id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
                    isEnabled: true,
                    priority: 10,
                    condition: .idleAtLeast(milliseconds: 60_000),
                    sequenceID: "missing"
                )
            ]
        )

        XCTAssertThrowsError(
            try RecommendedPetProfileCodec.encode(profile, for: petDefinition)
        ) { error in
            XCTAssertEqual(
                error as? RecommendedPetProfileError,
                .invalidField("automaticRules.0")
            )
        }
    }

    func testCodecRejectsPeriodicSpeechTriggerWithSequenceID() throws {
        let data = try RecommendedPetProfileCodec.encode(
            makeProfile(),
            for: petDefinition
        )
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        var speech = try XCTUnwrap(object["speech"] as? [String: Any])
        var phrases = try XCTUnwrap(
            speech["phrases"] as? [[String: Any]]
        )
        var phrase = try XCTUnwrap(phrases.first)
        var trigger = try XCTUnwrap(
            phrase["trigger"] as? [String: Any]
        )
        trigger["type"] = "periodic"
        trigger["sequenceID"] = "default"
        phrase["trigger"] = trigger
        phrases[0] = phrase
        speech["phrases"] = phrases
        object["speech"] = speech
        let invalidData = try JSONSerialization.data(withJSONObject: object)

        XCTAssertThrowsError(
            try RecommendedPetProfileCodec.decode(
                invalidData,
                for: petDefinition
            )
        ) { error in
            XCTAssertEqual(
                error as? RecommendedPetProfileError,
                .invalidField("speech.phrases.0.trigger")
            )
        }
    }

    func testCodecDistinguishesFutureSchemaFromUnreadableData() throws {
        let data = try RecommendedPetProfileCodec.encode(
            makeProfile(),
            for: petDefinition
        )
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        object["schemaVersion"] = 12
        let futureData = try JSONSerialization.data(withJSONObject: object)

        XCTAssertThrowsError(
            try RecommendedPetProfileCodec.decode(
                futureData,
                for: petDefinition
            )
        ) { error in
            XCTAssertEqual(
                error as? RecommendedPetProfileError,
                .unsupportedSchemaVersion(12)
            )
        }
        XCTAssertThrowsError(
            try RecommendedPetProfileCodec.decode(
                Data("not json".utf8),
                for: petDefinition
            )
        ) { error in
            XCTAssertEqual(
                error as? RecommendedPetProfileError,
                .unreadable
            )
        }
    }

    func testCodecRejectsOversizedDataBeforeDecoding() {
        let data = Data(
            repeating: 0,
            count: RecommendedPetProfileCodec.maximumFileSize + 1
        )

        XCTAssertThrowsError(
            try RecommendedPetProfileCodec.decode(data, for: petDefinition)
        ) { error in
            XCTAssertEqual(
                error as? RecommendedPetProfileError,
                .fileTooLarge
            )
        }
    }

    func testCodecDecodesSchemaV1SingleMovementMotionsAsFallbacks() throws {
        let encodedV2 = try RecommendedPetProfileCodec.encode(
            makeProfile(),
            for: petDefinition
        )
        var object = try legacyObject(from: encodedV2, schemaVersion: 1)
        var movement = try XCTUnwrap(
            object["movement"] as? [String: Any]
        )
        movement.removeValue(forKey: "cursorFollowingAnimation")
        movement.removeValue(forKey: "freeRoamingAnimation")
        movement["cursorFollowingMotionID"] = "run"
        movement["freeRoamingMotionID"] = "idle"
        object["movement"] = movement
        let v1Data = try JSONSerialization.data(withJSONObject: object)

        let decoded = try RecommendedPetProfileCodec.decode(
            v1Data,
            for: petDefinition
        )

        XCTAssertEqual(decoded.movement.cursorFollowingMotionID, "run")
        XCTAssertEqual(decoded.movement.freeRoamingMotionID, "idle")
        XCTAssertFalse(
            decoded.movement.cursorFollowingAnimation
                .usesDirectionalMotions
        )
        XCTAssertFalse(
            decoded.movement.freeRoamingAnimation
                .usesDirectionalMotions
        )
        XCTAssertFalse(decoded.includesDisplaySettings)
    }

    func testCodecDecodesSchemaV2WithSafeAvoidingDefaults() throws {
        let encodedV3 = try RecommendedPetProfileCodec.encode(
            makeProfile(),
            for: petDefinition
        )
        var object = try legacyObject(from: encodedV3, schemaVersion: 2)
        var movement = try XCTUnwrap(
            object["movement"] as? [String: Any]
        )
        movement.removeValue(forKey: "cursorAvoidingIdleBehavior")
        movement.removeValue(forKey: "cursorAvoidingDetectionDistance")
        movement.removeValue(forKey: "cursorAvoidingSpeed")
        movement.removeValue(forKey: "cursorAvoidingAnimation")
        object["movement"] = movement
        let v2Data = try JSONSerialization.data(withJSONObject: object)

        let decoded = try RecommendedPetProfileCodec.decode(
            v2Data,
            for: petDefinition
        )

        XCTAssertEqual(
            decoded.movement.cursorAvoidingIdleBehavior,
            .stationary
        )
        XCTAssertEqual(
            decoded.movement.cursorAvoidingDetectionDistance,
            AppSettingsLimits.defaultCursorAvoidingDetectionDistance
        )
        XCTAssertEqual(
            decoded.movement.cursorAvoidingSpeed,
            AppSettingsLimits.defaultCursorAvoidingSpeed
        )
        XCTAssertEqual(
            decoded.movement.cursorAvoidingAnimation,
            .single(nil)
        )
    }

    func testCodecDecodesSchemaV4WithLegacyCompatibleSpeechTheme() throws {
        let encodedV5 = try RecommendedPetProfileCodec.encode(
            makeProfile(),
            for: petDefinition
        )
        let object = try legacyObject(from: encodedV5, schemaVersion: 4)
        let v4Data = try JSONSerialization.data(withJSONObject: object)

        let decoded = try RecommendedPetProfileCodec.decode(
            v4Data,
            for: petDefinition
        )

        XCTAssertEqual(decoded.speech.theme, .default)
    }

    func testCodecDecodesSchemaV5WithLegacySpeechPolicies() throws {
        let encodedV6 = try RecommendedPetProfileCodec.encode(
            makeProfile(),
            for: petDefinition
        )
        var object = try legacyObject(from: encodedV6, schemaVersion: 5)
        var speech = try XCTUnwrap(
            object["speech"] as? [String: Any]
        )
        speech.removeValue(forKey: "periodicIsEnabled")
        speech.removeValue(forKey: "periodicOrder")
        speech.removeValue(forKey: "behaviorChangePolicy")
        var phrases = try XCTUnwrap(
            speech["phrases"] as? [[String: Any]]
        )
        for index in phrases.indices {
            phrases[index].removeValue(forKey: "displayMode")
        }
        speech["phrases"] = phrases
        object["speech"] = speech
        let v5Data = try JSONSerialization.data(withJSONObject: object)

        let decoded = try RecommendedPetProfileCodec.decode(
            v5Data,
            for: petDefinition
        )

        XCTAssertTrue(decoded.speech.periodicIsEnabled)
        XCTAssertEqual(decoded.speech.periodicOrder, .random)
        XCTAssertEqual(decoded.speech.behaviorChangePolicy, .dismiss)
        XCTAssertTrue(
            decoded.speech.phrases.allSatisfy {
                $0.displayMode == .timed
            }
        )
    }

    func testSharedSummaryCoversEveryRecommendedProfileField() {
        let profile = makeProfile()

        let summary = RecommendedProfileSummary(profile: profile)

        XCTAssertEqual(summary.mode, profile.mode)
        XCTAssertEqual(
            summary.manualSequenceID,
            profile.manualSequenceID
        )
        XCTAssertEqual(
            summary.randomSequenceIDs,
            profile.randomSequenceIDs
        )
        XCTAssertEqual(summary.sequences, profile.sequences)
        XCTAssertEqual(summary.automaticRules, profile.automaticRules)
        XCTAssertEqual(
            summary.automaticRulePriorityOrder,
            profile.automaticRulePriorityOrder
        )
        XCTAssertEqual(summary.movement, profile.movement)
        XCTAssertEqual(
            summary.includesDisplaySettings,
            profile.includesDisplaySettings
        )
        XCTAssertEqual(
            summary.pettingMotionID,
            profile.pettingMotionID
        )
        XCTAssertEqual(summary.speech, profile.speech)
        XCTAssertEqual(summary.display, profile.display)
        XCTAssertEqual(
            summary.behaviorDisplayName(for: profile.sequences[0].id),
            profile.sequences[0].displayName
        )
        XCTAssertEqual(
            summary.behaviorDisplayName(for: "missing-behavior"),
            "찾을 수 없는 행동"
        )
        XCTAssertEqual(
            summary.conditionRuleDescription,
            "2개 · 사용 2개"
        )
        XCTAssertEqual(
            summary.automaticRulePriorityDescription,
            "이동 → 입력 없음 → 앱 사용"
        )
    }

    private var petDefinition: PetDefinition {
        PetDefinition(
            id: "test.pet",
            displayName: "Test Pet",
            defaultMotionID: "idle",
            motions: [
                makeMotion(id: "idle"),
                makeMotion(id: "run"),
                makeMotion(id: "petting")
            ]
        )
    }

    private func makeProfile(
        automaticRules: [AutomaticRule]? = nil,
        movement: PetMovementSettings? = nil,
        pettingMotionID: String? = "petting",
        speech: PetSpeechSettings? = nil,
        display: PortablePetDisplaySettings = PortablePetDisplaySettings(
            scalePercent: 135,
            clickThrough: true,
            opacity: 0.72,
            pointerOverlapFadeEnabled: true,
            pointerOverlapOpacity: 0.18,
            pixelArtRendering: true
        )
    ) -> RecommendedPetProfile {
        RecommendedPetProfile(
            mode: .manual,
            manualSequenceID: "default",
            sequences: [
                BehaviorSequence(
                    id: "default",
                    steps: [
                        BehaviorStep(motionID: "idle", repeatCount: 2),
                        BehaviorStep(motionID: "run", repeatCount: 3)
                    ],
                    repeats: true
                ),
                BehaviorSequence(
                    id: "rest",
                    steps: [
                        BehaviorStep(motionID: "idle", repeatCount: 1)
                    ],
                    repeats: false
                ),
                BehaviorSequence(
                    id: "idle",
                    steps: [BehaviorStep(motionID: "idle", repeatCount: 1)],
                    repeats: true
                ),
                BehaviorSequence(
                    id: "run",
                    steps: [BehaviorStep(motionID: "run", repeatCount: 1)],
                    repeats: true
                ),
                BehaviorSequence(
                    id: "petting",
                    steps: [
                        BehaviorStep(motionID: "petting", repeatCount: 1)
                    ],
                    repeats: true
                )
            ],
            automaticRules: automaticRules ?? [
                AutomaticRule(
                    id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
                    isEnabled: true,
                    priority: 10,
                    condition: .application(
                        bundleIdentifier: "com.apple.dt.Xcode"
                    ),
                    sequenceID: "default"
                ),
                AutomaticRule(
                    id: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!,
                    isEnabled: true,
                    priority: 5,
                    condition: .idleAtLeast(milliseconds: 60_000),
                    sequenceID: "rest"
                )
            ],
            movement: movement ?? PetMovementSettings(
                mode: .freeRoaming,
                speed: 120,
                cursorDistance: 80,
                stopRadius: 24,
                freeRoamingDwellMilliseconds: 8_000,
                prefersFrontmostWindow: true,
                cursorFollowingAnimation: MovementAnimationSettings(
                    fallbackMotionID: "run",
                    usesDirectionalMotions: true,
                    usesDiagonalMotions: true,
                    directionMotionIDs: DirectionalMotionIDs(
                        left: "run",
                        right: "run",
                        up: "idle",
                        down: "idle",
                        upLeft: "run",
                        upRight: "run",
                        downLeft: "idle",
                        downRight: "idle"
                    )
                ),
                freeRoamingAnimation: MovementAnimationSettings(
                    fallbackMotionID: "idle",
                    usesDirectionalMotions: true,
                    directionMotionIDs: DirectionalMotionIDs(
                        left: "run",
                        right: "run",
                        up: "idle",
                        down: "idle"
                    )
                ),
                cursorAvoidingIdleBehavior: .freeRoaming,
                cursorAvoidingDetectionDistance: 180,
                cursorAvoidingSpeed: 360,
                cursorAvoidingAnimation: MovementAnimationSettings(
                    fallbackMotionID: "run",
                    usesDirectionalMotions: true,
                    directionMotionIDs: DirectionalMotionIDs(
                        left: "run",
                        right: "run",
                        up: "idle",
                        down: "idle"
                    )
                )
            ),
            pettingMotionID: pettingMotionID,
            speech: speech ?? PetSpeechSettings(
                isEnabled: true,
                periodicIsEnabled: true,
                periodicIntervalMilliseconds: 30_000,
                periodicOrder: .sequential,
                behaviorChangePolicy: .keep,
                phrases: [
                    PetSpeechPhrase(
                        id: UUID(
                            uuidString:
                                "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC"
                        )!,
                        text: "함께 산책할까요?",
                        trigger: .periodic,
                        displayMode: .untilNextPhrase
                    ),
                    PetSpeechPhrase(
                        id: UUID(
                            uuidString:
                                "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD"
                        )!,
                        text: "잠깐 쉬어 가요.",
                        displayDurationMilliseconds: 4_000,
                        trigger: .sequence("rest")
                    )
                ],
                theme: PetSpeechBubbleTheme(
                    colorStyle: .peach,
                    backgroundOpacity: 0.88,
                    fontSize: 17,
                    contentPadding: 15,
                    cornerRadius: 19,
                    showsTail: true,
                    tailAlignment: .leading
                ),
                placement: PetSpeechBubblePlacementSettings(
                    preferredPosition: .above,
                    horizontalOffset: -36,
                    gap: 20
                )
            ),
            display: display
        )
    }

    private func legacyObject(
        from data: Data,
        schemaVersion: Int
    ) throws -> [String: Any] {
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        object["schemaVersion"] = schemaVersion
        object.removeValue(forKey: "automaticRulePriorityOrder")
        object["pettingMotionID"] = object.removeValue(
            forKey: "pettingBehaviorID"
        )

        var behavior = try XCTUnwrap(object["behavior"] as? [String: Any])
        let stationaryMode = behavior["stationaryBehaviorMode"] as? String
        let stationaryID = behavior["stationarySequenceID"] as? String
        behavior["mode"] = stationaryMode == "random"
            ? "random"
            : (stationaryID == nil ? "automatic" : "manual")
        if let stationaryID {
            behavior["manualSequenceID"] = stationaryID
        }
        behavior.removeValue(forKey: "stationaryBehaviorMode")
        behavior.removeValue(forKey: "stationarySequenceID")
        var sequences = try XCTUnwrap(
            behavior["sequences"] as? [[String: Any]]
        )
        for index in sequences.indices {
            sequences[index].removeValue(forKey: "displayName")
        }
        behavior["sequences"] = sequences
        object["behavior"] = behavior

        var movement = try XCTUnwrap(object["movement"] as? [String: Any])
        if let following = movement["cursorFollowing"] as? [String: Any],
           let roaming = movement["freeRoaming"] as? [String: Any],
           let avoiding = movement["cursorAvoiding"] as? [String: Any] {
            movement = [
                "mode": movement["mode"] as Any,
                "speed": roaming["speed"] as Any,
                "cursorDistance": following["cursorDistance"] as Any,
                "stopRadius": roaming["stopRadius"] as Any,
                "freeRoamingDwellMilliseconds":
                    roaming["dwellMilliseconds"] as Any,
                "prefersFrontmostWindow":
                    roaming["prefersFrontmostWindow"] as Any,
                "cursorFollowingBehavior": following["behavior"] as Any,
                "freeRoamingBehavior": roaming["behavior"] as Any,
                "cursorAvoidingIdleBehavior":
                    avoiding["idleBehavior"] as Any,
                "cursorAvoidingDetectionDistance":
                    avoiding["detectionDistance"] as Any,
                "cursorAvoidingSpeed": avoiding["speed"] as Any,
                "cursorAvoidingBehavior": avoiding["behavior"] as Any
            ]
        }
        for (behaviorKey, animationKey) in [
            ("cursorFollowingBehavior", "cursorFollowingAnimation"),
            ("freeRoamingBehavior", "freeRoamingAnimation"),
            ("cursorAvoidingBehavior", "cursorAvoidingAnimation")
        ] {
            guard var value = movement.removeValue(forKey: behaviorKey)
                as? [String: Any] else { continue }
            value["fallbackMotionID"] = value.removeValue(
                forKey: "fallbackBehaviorID"
            )
            value["usesDirectionalMotions"] = value.removeValue(
                forKey: "usesDirectionalBehaviors"
            )
            value["usesDiagonalMotions"] = value.removeValue(
                forKey: "usesDiagonalBehaviors"
            )
            value["directionMotionIDs"] = value.removeValue(
                forKey: "directionBehaviorIDs"
            )
            movement[animationKey] = value
        }
        object["movement"] = movement
        return object
    }

    private func makeMotion(id: String) -> PetMotion {
        PetMotion(
            id: id,
            loops: true,
            frames: [
                MotionFrame(
                    atlasID: "main",
                    sourceRect: PixelRect(
                        x: 0,
                        y: 0,
                        width: 32,
                        height: 32
                    ),
                    duration: .milliseconds(100)
                )
            ]
        )
    }
}
