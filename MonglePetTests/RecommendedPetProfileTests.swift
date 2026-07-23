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
                pettingMotionID: profile.pettingMotionID
            )
        )

        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        XCTAssertEqual(object["schemaVersion"] as? Int, 1)
        XCTAssertNotNil(object["behavior"])
        XCTAssertNotNil(object["movement"])
        XCTAssertNotNil(object["automaticRules"])
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
            "clickThrough"
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

    func testCodecDistinguishesFutureSchemaFromUnreadableData() throws {
        let data = try RecommendedPetProfileCodec.encode(
            makeProfile(),
            for: petDefinition
        )
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        object["schemaVersion"] = 2
        let futureData = try JSONSerialization.data(withJSONObject: object)

        XCTAssertThrowsError(
            try RecommendedPetProfileCodec.decode(
                futureData,
                for: petDefinition
            )
        ) { error in
            XCTAssertEqual(
                error as? RecommendedPetProfileError,
                .unsupportedSchemaVersion(2)
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
        pettingMotionID: String? = "petting"
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
                cursorFollowingMotionID: "run",
                freeRoamingMotionID: "idle"
            ),
            pettingMotionID: pettingMotionID
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
