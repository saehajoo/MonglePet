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
                sequences: profile.sequences,
                automaticRules: profile.automaticRules,
                movement: profile.movement,
                pettingMotionID: profile.pettingMotionID,
                speech: profile.speech
            )
        )

        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        XCTAssertEqual(object["schemaVersion"] as? Int, 7)
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
        XCTAssertNil(object["clickThrough"])
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        for forbiddenKey in [
            "installationID",
            "petKey",
            "originX",
            "originY",
            "screenIdentifier",
            "lastUserPresentation",
            "clickThrough",
            "opacity",
            "movementBoundary",
            "pixelArtRendering"
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

    func testCodecRejectsManualModeWithoutSelection() {
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

        XCTAssertThrowsError(
            try RecommendedPetProfileCodec.encode(profile, for: petDefinition)
        ) { error in
            XCTAssertEqual(
                error as? RecommendedPetProfileError,
                .invalidField("behavior.manualSequenceID")
            )
        }
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
                .invalidField("pettingMotionID")
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
        XCTAssertThrowsError(
            try RecommendedPetProfileCodec.encode(
                reservedMovementReference,
                for: petDefinition
            )
        ) { error in
            XCTAssertEqual(
                error as? RecommendedPetProfileError,
                .invalidField("movement.cursorFollowingMotionID")
            )
        }
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
        object["schemaVersion"] = 8
        let futureData = try JSONSerialization.data(withJSONObject: object)

        XCTAssertThrowsError(
            try RecommendedPetProfileCodec.decode(
                futureData,
                for: petDefinition
            )
        ) { error in
            XCTAssertEqual(
                error as? RecommendedPetProfileError,
                .unsupportedSchemaVersion(8)
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
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encodedV2)
                as? [String: Any]
        )
        object["schemaVersion"] = 1
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
    }

    func testCodecDecodesSchemaV2WithSafeAvoidingDefaults() throws {
        let encodedV3 = try RecommendedPetProfileCodec.encode(
            makeProfile(),
            for: petDefinition
        )
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encodedV3)
                as? [String: Any]
        )
        object["schemaVersion"] = 2
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
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encodedV5)
                as? [String: Any]
        )
        object["schemaVersion"] = 4
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
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encodedV6)
                as? [String: Any]
        )
        object["schemaVersion"] = 5
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
        XCTAssertEqual(summary.sequences, profile.sequences)
        XCTAssertEqual(summary.automaticRules, profile.automaticRules)
        XCTAssertEqual(summary.movement, profile.movement)
        XCTAssertEqual(
            summary.pettingMotionID,
            profile.pettingMotionID
        )
        XCTAssertEqual(summary.speech, profile.speech)
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
        speech: PetSpeechSettings? = nil
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
            )
        )
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
