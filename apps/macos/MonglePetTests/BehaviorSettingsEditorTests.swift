import Foundation
import XCTest
@testable import MonglePet

final class BehaviorSettingsEditorTests: XCTestCase {
    func testBehaviorSelectionLabelShowsAnimationOrStepCount() {
        XCTAssertEqual(
            BehaviorSelectionLabel.text(
                for: BehaviorSequence(
                    id: "wave",
                    displayName: "인사 복사본",
                    steps: [BehaviorStep(motionID: "인사", repeatCount: 1)],
                    repeats: true
                )
            ),
            "인사"
        )
        XCTAssertEqual(
            BehaviorSelectionLabel.text(
                for: BehaviorSequence(
                    id: "default",
                    displayName: "기본",
                    steps: [
                        BehaviorStep(
                            motionID: PetMotionReference.currentPetDefault,
                            repeatCount: 1
                        )
                    ],
                    repeats: true
                )
            ),
            "기본 애니메이션"
        )
        XCTAssertEqual(
            BehaviorSelectionLabel.text(
                for: BehaviorSequence(
                    id: "routine",
                    displayName: "아침 루틴",
                    steps: [
                        BehaviorStep(motionID: "wake", repeatCount: 1),
                        BehaviorStep(motionID: "stretch", repeatCount: 1)
                    ],
                    repeats: true
                )
            ),
            "wake 외 1개"
        )
    }

    func testGeneratedSingleStepBehaviorNamesSynchronizeToCurrentAnimations() throws {
        var settings = try BehaviorSettingsEditor.addingSequence(
            named: "인사 복사본",
            initialMotionID: "인사",
            to: makeSettings()
        )
        settings = try BehaviorSettingsEditor.addingSequence(
            named: "사용자가 정한 이름",
            initialMotionID: "행복",
            to: settings
        )
        settings = try BehaviorSettingsEditor.addingSequence(
            named: "산책 복사본 2",
            initialMotionID: "산책",
            to: settings
        )

        settings = try BehaviorSettingsEditor
            .synchronizingGeneratedSingleStepBehaviorNames(in: settings)

        XCTAssertNotNil(settings.sequences.first { $0.displayName == "인사" })
        XCTAssertNotNil(settings.sequences.first { $0.displayName == "산책" })
        XCTAssertNotNil(
            settings.sequences.first { $0.displayName == "사용자가 정한 이름" }
        )
    }

    func testMotionCatalogUsesCurrentPetAnimationsAndPreservesMissingSavedValue() {
        let frame = MotionFrame(
            atlasID: "main",
            sourceRect: PixelRect(x: 0, y: 0, width: 10, height: 10),
            duration: .milliseconds(100)
        )
        let pet = PetDefinition(
            id: "test.pet",
            displayName: "Test Pet",
            defaultMotionID: "idle",
            motions: [
                PetMotion(id: "idle", loops: true, frames: [frame]),
                PetMotion(id: "waving", loops: true, frames: [frame])
            ]
        )

        XCTAssertEqual(
            BehaviorMotionCatalog.identifiers(for: pet, including: "waving"),
            [PetMotionReference.currentPetDefault, "waving"]
        )
        XCTAssertEqual(
            BehaviorMotionCatalog.identifiers(for: pet, including: "legacy"),
            [PetMotionReference.currentPetDefault, "waving", "legacy"]
        )
    }

    func testSequenceNamesAreTrimmedAndComparedCaseInsensitively() throws {
        let added = try BehaviorSettingsEditor.addingSequence(
            named: "  Coding Time  ",
            to: makeSettings()
        )

        XCTAssertEqual(added.sequences.last?.displayName, "Coding Time")
        XCTAssertNotEqual(added.sequences.last?.id, "Coding Time")
        XCTAssertThrowsError(
            try BehaviorSettingsEditor.addingSequence(
                named: "coding time",
                to: added
            )
        ) { error in
            XCTAssertEqual(error as? BehaviorSettingsEditError, .duplicateSequenceName)
        }
        XCTAssertThrowsError(
            try BehaviorSettingsEditor.addingSequence(named: " \n ", to: added)
        ) { error in
            XCTAssertEqual(error as? BehaviorSettingsEditError, .invalidSequenceName)
        }
    }

    func testSequenceCanStartWithDuplicatedAnimation() throws {
        let added = try BehaviorSettingsEditor.addingSequence(
            named: "wave 복사본",
            initialMotionID: "wave 복사본",
            to: makeSettings()
        )

        let sequence = try XCTUnwrap(added.sequences.last)
        XCTAssertEqual(sequence.displayName, "wave 복사본")
        XCTAssertEqual(
            sequence.steps,
            [BehaviorStep(motionID: "wave 복사본", repeatCount: 1)]
        )
        XCTAssertFalse(sequence.repeats)
    }

    func testStepsCanBeAddedEditedMovedAndRemovedWhileKeepingOne() throws {
        var settings = try BehaviorSettingsEditor.addingSequence(
            named: "custom",
            to: makeSettings()
        )
        let customID = try XCTUnwrap(settings.sequences.last?.id)
        settings = try BehaviorSettingsEditor.addingStep(to: customID, in: settings)
        settings = try BehaviorSettingsEditor.replacingStep(
            in: customID,
            at: 1,
            with: BehaviorStep(
                motionID: "focus",
                repeatCount: 9
            ),
            settings: settings
        )
        settings = try BehaviorSettingsEditor.movingStep(
            in: customID,
            from: 1,
            to: 0,
            settings: settings
        )

        var custom = try XCTUnwrap(settings.sequences.first { $0.id == customID })
        XCTAssertEqual(
            custom.steps.map(\.motionID),
            ["focus", PetMotionReference.currentPetDefault]
        )
        XCTAssertEqual(custom.steps[0].repeatCount, 9)

        settings = try BehaviorSettingsEditor.removingStep(
            from: customID,
            at: 1,
            settings: settings
        )
        custom = try XCTUnwrap(settings.sequences.first { $0.id == customID })
        XCTAssertEqual(custom.steps.count, 1)
        XCTAssertThrowsError(
            try BehaviorSettingsEditor.removingStep(
                from: customID,
                at: 0,
                settings: settings
            )
        ) { error in
            XCTAssertEqual(error as? BehaviorSettingsEditError, .cannotRemoveLastStep)
        }
    }

    func testSpecificAnimationCanBeAppendedAsBehaviorStep() throws {
        var settings = try BehaviorSettingsEditor.addingSequence(
            named: "custom",
            to: makeSettings()
        )
        let customID = try XCTUnwrap(settings.sequences.last?.id)

        settings = try BehaviorSettingsEditor.addingStep(
            to: customID,
            motionID: "wave",
            in: settings
        )

        let custom = try XCTUnwrap(
            settings.sequences.first { $0.id == customID }
        )
        XCTAssertEqual(
            custom.steps.last,
            BehaviorStep(motionID: "wave", repeatCount: 1)
        )
    }

    func testDeletingCustomSequenceCleansReferencesAndProtectsBuiltIns() throws {
        var settings = try BehaviorSettingsEditor.addingSequence(
            named: "custom",
            to: makeSettings()
        )
        let customID = try XCTUnwrap(settings.sequences.last?.id)
        settings = settingsReplacingManualSequenceID(customID, in: settings)
        settings = try BehaviorSettingsEditor.addingApplicationRule(
            bundleIdentifier: "com.example.Editor",
            sequenceID: customID,
            to: settings
        )
        settings = settings.replacingActiveBehaviorProfile(
            BehaviorProfile(
                petKey: settings.selectedPetKey,
                mode: settings.behaviorMode,
                manualSequenceID: settings.manualSequenceID,
                sequences: settings.sequences,
                automaticRules: settings.automaticRules,
                movement: settings.movementSettings,
                pettingMotionID: settings.pettingMotionID,
                speech: PetSpeechSettings(
                    isEnabled: true,
                    periodicIsEnabled: true,
                    periodicIntervalMilliseconds: 25_000,
                    periodicOrder: .sequential,
                    behaviorChangePolicy: .keep,
                    phrases: [
                        PetSpeechPhrase(
                            text: "남는 대사",
                            trigger: .periodic,
                            displayMode: .untilNextPhrase
                        ),
                        PetSpeechPhrase(
                            text: "삭제될 대사",
                            trigger: .sequence(customID)
                        )
                    ]
                )
            )
        )

        settings = try BehaviorSettingsEditor.removingSequence(
            id: customID,
            from: settings
        )

        XCTAssertNil(settings.manualSequenceID)
        XCTAssertFalse(settings.sequences.contains { $0.id == customID })
        XCTAssertFalse(settings.automaticRules.contains { $0.sequenceID == customID })
        XCTAssertEqual(
            settings.speechSettings.phrases.map(\.text),
            ["남는 대사"]
        )
        XCTAssertTrue(settings.speechSettings.periodicIsEnabled)
        XCTAssertEqual(
            settings.speechSettings.periodicIntervalMilliseconds,
            25_000
        )
        XCTAssertEqual(settings.speechSettings.periodicOrder, .sequential)
        XCTAssertEqual(
            settings.speechSettings.behaviorChangePolicy,
            .keep
        )
        XCTAssertEqual(
            settings.speechSettings.phrases.first?.displayMode,
            .untilNextPhrase
        )
        XCTAssertThrowsError(
            try BehaviorSettingsEditor.removingSequence(
                id: BuiltInBehaviorPresets.defaultSequenceID,
                from: settings
            )
        ) { error in
            XCTAssertEqual(error as? BehaviorSettingsEditError, .protectedSequence)
        }
    }

    func testApplicationAndIdleRulesCanBeAddedUpdatedAndRemoved() throws {
        let applicationRuleID = UUID()
        let idleRuleID = UUID()
        let disabledIdleSettings = try BehaviorSettingsEditor.settingIdleRule(
            seconds: 2,
            sequenceID: BuiltInBehaviorPresets.defaultSequenceID,
            isEnabled: false,
            in: makeSettings(rules: [])
        )
        XCTAssertEqual(disabledIdleSettings.automaticRules.count, 1)
        XCTAssertFalse(try XCTUnwrap(disabledIdleSettings.automaticRules.first).isEnabled)
        XCTAssertEqual(
            disabledIdleSettings.automaticRules.first?.condition,
            .idleAtLeast(milliseconds: 2_000)
        )

        var settings = try BehaviorSettingsEditor.addingApplicationRule(
            bundleIdentifier: "com.apple.dt.Xcode",
            sequenceID: BuiltInBehaviorPresets.defaultSequenceID,
            id: applicationRuleID,
            to: makeSettings(rules: [])
        )
        settings = try BehaviorSettingsEditor.addingIdleRule(
            seconds: 3,
            sequenceID: BuiltInBehaviorPresets.defaultSequenceID,
            id: idleRuleID,
            to: settings
        )

        let updatedIdleSettings = try BehaviorSettingsEditor.addingIdleRule(
            seconds: 5,
            sequenceID: BuiltInBehaviorPresets.defaultSequenceID,
            to: settings
        )
        XCTAssertEqual(updatedIdleSettings.automaticRules.count, 2)
        XCTAssertEqual(
            updatedIdleSettings.automaticRules[1].condition,
            .idleAtLeast(milliseconds: 5_000)
        )
        XCTAssertThrowsError(
            try BehaviorSettingsEditor.addingApplicationRule(
                bundleIdentifier: "COM.APPLE.DT.XCODE",
                sequenceID: BuiltInBehaviorPresets.defaultSequenceID,
                to: settings
            )
        ) { error in
            XCTAssertEqual(error as? BehaviorSettingsEditError, .invalidRule)
        }

        XCTAssertEqual(settings.automaticRules.map(\.priority), [0, 1])
        XCTAssertEqual(
            settings.automaticRules[1].condition,
            .idleAtLeast(milliseconds: 3_000)
        )

        settings = try BehaviorSettingsEditor.settingAutomaticRulePriorityOrder(
            [.application, .movement, .idle],
            in: settings
        )
        XCTAssertEqual(
            settings.automaticRulePriorityOrder,
            [.application, .movement, .idle]
        )
        XCTAssertThrowsError(
            try BehaviorSettingsEditor.settingAutomaticRulePriorityOrder(
                [.idle, .application],
                in: settings
            )
        )

        let edited = AutomaticRule(
            id: applicationRuleID,
            isEnabled: false,
            priority: 8,
            condition: .application(bundleIdentifier: "com.apple.Safari"),
            sequenceID: BuiltInBehaviorPresets.defaultSequenceID
        )
        settings = try BehaviorSettingsEditor.replacingRule(edited, in: settings)
        XCTAssertEqual(settings.automaticRules[0], edited)

        settings = try BehaviorSettingsEditor.removingRule(id: idleRuleID, from: settings)
        XCTAssertEqual(settings.automaticRules.map(\.id), [applicationRuleID])

        XCTAssertThrowsError(
            try BehaviorSettingsEditor.addingApplicationRule(
                bundleIdentifier: "com.example bad",
                sequenceID: BuiltInBehaviorPresets.defaultSequenceID,
                to: settings
            )
        ) { error in
            XCTAssertEqual(error as? BehaviorSettingsEditError, .invalidRule)
        }
        XCTAssertThrowsError(
            try BehaviorSettingsEditor.addingIdleRule(
                seconds: 0,
                sequenceID: BuiltInBehaviorPresets.defaultSequenceID,
                to: settings
            )
        ) { error in
            XCTAssertEqual(error as? BehaviorSettingsEditError, .invalidRule)
        }
        XCTAssertThrowsError(
            try BehaviorSettingsEditor.addingIdleRule(
                seconds: 86_401,
                sequenceID: BuiltInBehaviorPresets.defaultSequenceID,
                to: settings
            )
        ) { error in
            XCTAssertEqual(error as? BehaviorSettingsEditError, .invalidRule)
        }
    }

    func testDeletingUnreferencedBehaviorPreservesEveryIndependentMovementMode() throws {
        let modes: [PetMovementMode] = [
            .fixed, .cursorFollowing, .freeRoaming, .cursorAvoiding
        ]
        for mode in modes {
            for roamingDwellMode in [FreeRoamingDwellMode.behaviorCompletion, .random] {
                let base = try BehaviorSettingsEditor.addingSequence(
                    named: "사용하지 않는 행동",
                    to: makeSettings()
                )
                let removedID = try XCTUnwrap(base.sequences.last?.id)
                let movement = independentMovement(
                    mode: mode,
                    removableID: "keep-me",
                    roamingDwellMode: roamingDwellMode
                )
                let settings = base.replacingActiveBehaviorProfile(
                    BehaviorProfile(
                        petKey: base.selectedPetKey,
                        stationaryBehaviorMode: .fixed,
                        stationarySequenceID: nil,
                        sequences: base.sequences + [
                            BehaviorSequence(
                                id: "keep-me",
                                displayName: "계속 사용할 행동",
                                steps: [BehaviorStep(motionID: "wave", repeatCount: 1)],
                                repeats: false
                            )
                        ],
                        automaticRules: base.automaticRules,
                        movement: movement
                    )
                )

                let result = try BehaviorSettingsEditor.removingSequence(
                    id: removedID,
                    from: settings
                )

                XCTAssertEqual(result.movementSettings, movement)
                XCTAssertEqual(result.stationaryBehaviorMode, .fixed)
                XCTAssertNil(result.stationarySequenceID)
                XCTAssertEqual(result.activePetInstances, settings.activePetInstances)
                XCTAssertEqual(result.speechSettings, settings.speechSettings)
                XCTAssertEqual(result.sequences, settings.sequences.filter { $0.id != removedID })
            }
        }
    }

    func testDeletingReferencedBehaviorClearsOnlyItsConnectionsAndPreservesOtherPet() throws {
        let settings = removalFixture()
        let result = try BehaviorSettingsEditor.removingSequence(
            id: "remove-me",
            from: settings
        )

        XCTAssertEqual(result.stationaryBehaviorMode, .random)
        XCTAssertEqual(result.stationarySequenceID, BuiltInBehaviorPresets.defaultSequenceID)
        XCTAssertEqual(result.randomSequenceIDs, ["keep-me"])
        XCTAssertEqual(
            result.movementSettings,
            independentMovement(mode: .cursorAvoiding, removableID: nil)
        )
        XCTAssertNil(result.pettingBehaviorID)
        XCTAssertEqual(result.sequences, settings.sequences.filter { $0.id != "remove-me" })
        XCTAssertEqual(
            result.automaticRules,
            settings.automaticRules.filter { $0.sequenceID != "remove-me" }
        )
        XCTAssertEqual(result.automaticRulePriorityOrder, [.application, .idle, .movement])
        XCTAssertEqual(result.speechSettings.phrases.map(\.text), ["남는 주기 대사", "남는 행동 대사"])
        XCTAssertEqual(result.speechSettings.theme, settings.speechSettings.theme)
        XCTAssertEqual(result.speechSettings.placement, settings.speechSettings.placement)
        XCTAssertEqual(result.speechSettings.periodicIntervalMilliseconds, 27_000)
        XCTAssertEqual(result.speechSettings.periodicOrder, .sequential)
        XCTAssertEqual(result.speechSettings.behaviorChangePolicy, .keep)
        XCTAssertTrue(result.speechSettings.isEnabled)
        XCTAssertFalse(result.speechSettings.periodicIsEnabled)
        XCTAssertEqual(result.activePetInstances, settings.activePetInstances)
        let activeProfileID = try XCTUnwrap(settings.selectedPetInstance?.behaviorProfileID)
        XCTAssertEqual(
            result.petBehaviorProfiles.filter { $0.profileID != activeProfileID },
            settings.petBehaviorProfiles.filter { $0.profileID != activeProfileID }
        )
        XCTAssertEqual(result.selectedPetInstanceID, settings.selectedPetInstanceID)
    }

    func testRemovalImpactIncludesInactiveModesDisabledRulesAndAllDirectionsWithoutMutating() {
        let settings = removalFixture()
        let original = settings
        let impact = BehaviorSettingsEditor.removalImpact(for: "remove-me", in: settings)

        XCTAssertEqual(settings, original)
        XCTAssertTrue(impact.replacesStationarySelection)
        XCTAssertTrue(impact.removesRandomSelection)
        XCTAssertTrue(impact.removesPettingSelection)
        XCTAssertEqual(impact.applicationRuleCount, 1)
        XCTAssertEqual(impact.idleRuleCount, 1)
        XCTAssertEqual(impact.otherRuleCount, 1)
        XCTAssertEqual(impact.speechPhraseCount, 2)
        XCTAssertEqual(impact.movementReferences, [
            .init(context: .cursorFollowing, removesFallback: true, directions: [.left, .upRight]),
            .init(context: .freeRoaming, removesFallback: false, directions: [.right]),
            .init(context: .cursorAvoiding, removesFallback: true, directions: [.down, .downLeft]),
            .init(context: .cursorAvoidingIdleFreeRoaming, removesFallback: true, directions: [.up, .downRight])
        ])
    }

    func testUnreferencedBehaviorHasNoRemovalImpact() {
        let impact = BehaviorSettingsEditor.removalImpact(
            for: "not-connected",
            in: removalFixture()
        )
        XCTAssertFalse(impact.replacesStationarySelection)
        XCTAssertFalse(impact.removesRandomSelection)
        XCTAssertFalse(impact.removesPettingSelection)
        XCTAssertEqual(impact.applicationRuleCount + impact.idleRuleCount + impact.otherRuleCount, 0)
        XCTAssertEqual(impact.speechPhraseCount, 0)
        XCTAssertTrue(impact.movementReferences.isEmpty)
    }

    func testBehaviorEditsPreserveFixedSelectionStoredDuringRandomMode() throws {
        let original = removalFixture()
        var settings = try BehaviorSettingsEditor.addingSequence(named: "새 행동", to: original)
        let addedID = try XCTUnwrap(settings.sequences.last?.id)
        settings = try BehaviorSettingsEditor.renamingSequence(id: addedID, to: "이름 변경", in: settings)
        settings = try BehaviorSettingsEditor.addingStep(to: addedID, motionID: "wave", in: settings)
        settings = try BehaviorSettingsEditor.settingAutomaticRulePriorityOrder(
            [.idle, .movement, .application], in: settings
        )
        settings = try BehaviorSettingsEditor.removingSequence(id: addedID, from: settings)

        XCTAssertEqual(settings.stationaryBehaviorMode, .random)
        XCTAssertEqual(settings.stationarySequenceID, "remove-me")
        XCTAssertEqual(settings.randomSequenceIDs, original.randomSequenceIDs)
        XCTAssertEqual(settings.movementSettings, original.movementSettings)
        XCTAssertEqual(settings.speechSettings, original.speechSettings)
    }

    func testAddingBehaviorDoesNotReplaceImplicitDefaultSelection() throws {
        let settings = try BehaviorSettingsEditor.addingSequence(named: "새 행동", to: makeSettings())
        XCTAssertEqual(settings.stationaryBehaviorMode, .fixed)
        XCTAssertNil(settings.stationarySequenceID)
    }

    func testMotionReferencesCanBeRenamedOrRecoveredToCurrentPetDefault() throws {
        var settings = try BehaviorSettingsEditor.addingSequence(
            named: "custom",
            to: makeSettings()
        )
        let customID = try XCTUnwrap(settings.sequences.last?.id)
        settings = try BehaviorSettingsEditor.replacingStep(
            in: customID,
            at: 0,
            with: BehaviorStep(
                motionID: "waving",
                repeatCount: 7
            ),
            settings: settings
        )
        settings = try BehaviorSettingsEditor.addingSequence(
            named: "waving",
            initialMotionID: "waving",
            to: settings
        )
        let synchronizedID = try XCTUnwrap(settings.sequences.last?.id)
        settings = settings.replacingActiveBehaviorProfile(
            BehaviorProfile(
                petKey: settings.selectedPetKey,
                mode: settings.behaviorMode,
                manualSequenceID: settings.manualSequenceID,
                sequences: settings.sequences,
                automaticRules: settings.automaticRules,
                movement: PetMovementSettings(
                    mode: .cursorFollowing,
                    speed: AppSettingsLimits.defaultMovementSpeed,
                    cursorDistance: AppSettingsLimits.defaultCursorDistance,
                    stopRadius: AppSettingsLimits.defaultMovementStopRadius,
                    freeRoamingDwellMilliseconds:
                        AppSettingsLimits.defaultFreeRoamingDwellMilliseconds,
                    prefersFrontmostWindow: true,
                    cursorFollowingAnimation: MovementAnimationSettings(
                        fallbackMotionID: customID,
                        usesDirectionalMotions: true,
                        usesDiagonalMotions: true,
                        directionMotionIDs: DirectionalMotionIDs(
                            left: customID,
                            upRight: customID
                        )
                    ),
                    freeRoamingAnimation: MovementAnimationSettings(
                        fallbackMotionID: customID,
                        usesDirectionalMotions: true,
                        directionMotionIDs: DirectionalMotionIDs(
                            right: customID
                        )
                    )
                ),
                pettingMotionID: customID
            )
        )

        settings = try BehaviorSettingsEditor.replacingMotionReferences(
            from: "waving",
            with: "hello",
            movementReplacementMotionID: "hello",
            in: settings
        )
        var step = try XCTUnwrap(
            settings.sequences.first { $0.id == customID }?.steps.first
        )
        XCTAssertEqual(step.motionID, "hello")
        XCTAssertEqual(step.repeatCount, 7)
        XCTAssertEqual(
            settings.sequences.first { $0.id == synchronizedID }?.displayName,
            "hello"
        )
        XCTAssertEqual(
            settings.movementSettings.cursorFollowingMotionID,
            customID
        )
        XCTAssertEqual(settings.movementSettings.freeRoamingMotionID, customID)
        XCTAssertEqual(
            settings.movementSettings.cursorFollowingAnimation
                .directionMotionIDs.left,
            customID
        )
        XCTAssertEqual(
            settings.movementSettings.cursorFollowingAnimation
                .directionMotionIDs.upRight,
            customID
        )
        XCTAssertEqual(
            settings.movementSettings.freeRoamingAnimation
                .directionMotionIDs.right,
            customID
        )
        XCTAssertEqual(settings.pettingMotionID, customID)

        settings = try BehaviorSettingsEditor.replacingMotionReferences(
            from: "hello",
            with: PetMotionReference.currentPetDefault,
            movementReplacementMotionID: nil,
            in: settings
        )
        step = try XCTUnwrap(
            settings.sequences.first { $0.id == customID }?.steps.first
        )
        XCTAssertEqual(step.motionID, PetMotionReference.currentPetDefault)
        XCTAssertEqual(step.repeatCount, 7)
        XCTAssertEqual(settings.movementSettings.cursorFollowingMotionID, customID)
        XCTAssertEqual(settings.movementSettings.freeRoamingMotionID, customID)
        XCTAssertEqual(
            settings.movementSettings.cursorFollowingAnimation
                .directionMotionIDs.left,
            customID
        )
        XCTAssertEqual(
            settings.movementSettings.cursorFollowingAnimation
                .directionMotionIDs.upRight,
            customID
        )
        XCTAssertEqual(
            settings.movementSettings.freeRoamingAnimation
                .directionMotionIDs.right,
            customID
        )
        XCTAssertEqual(settings.pettingMotionID, customID)
    }

    private func makeSettings(
        manualSequenceID: String? = BuiltInBehaviorPresets.defaultSequenceID,
        rules: [AutomaticRule] = BuiltInBehaviorPresets.automaticRules
    ) -> AppSettings {
        AppSettings(
            selectedPetInstallationID: nil,
            lastUserPresentation: .awake,
            behaviorMode: .automatic,
            overlay: .default,
            manualSequenceID: manualSequenceID,
            sequences: BuiltInBehaviorPresets.sequences,
            automaticRules: rules
        )
    }

    private func independentMovement(
        mode: PetMovementMode,
        removableID: String?,
        roamingDwellMode: FreeRoamingDwellMode = .behaviorCompletion
    ) -> PetMovementSettings {
        PetMovementSettings(
            mode: mode,
            cursorFollowing: CursorFollowingMovementSettings(
                speed: 111,
                cursorDistance: 73,
                stopRadius: 7,
                animation: MovementAnimationSettings(
                    fallbackMotionID: removableID,
                    usesDirectionalMotions: true,
                    usesDiagonalMotions: true,
                    directionMotionIDs: DirectionalMotionIDs(
                        left: removableID, right: "keep-me", upRight: removableID
                    )
                )
            ),
            freeRoaming: FreeRoamingMovementSettings(
                speed: 222,
                stopRadius: 12,
                dwellMilliseconds: 19_000,
                dwellMinimumMilliseconds: 1_500,
                prefersFrontmostWindow: false,
                animation: MovementAnimationSettings(
                    fallbackMotionID: "keep-me",
                    usesDirectionalMotions: true,
                    directionMotionIDs: DirectionalMotionIDs(left: "keep-me", right: removableID)
                ),
                dwellMode: roamingDwellMode
            ),
            cursorAvoiding: CursorAvoidingMovementSettings(
                idleBehavior: .freeRoaming,
                detectionDistance: 245,
                speed: 433,
                stopRadius: 23,
                animation: MovementAnimationSettings(
                    fallbackMotionID: removableID,
                    usesDirectionalMotions: true,
                    usesDiagonalMotions: true,
                    directionMotionIDs: DirectionalMotionIDs(
                        up: "keep-me", down: removableID, downLeft: removableID
                    )
                ),
                idleFreeRoaming: FreeRoamingMovementSettings(
                    speed: 344,
                    stopRadius: 34,
                    dwellMilliseconds: 31_000,
                    dwellMinimumMilliseconds: 2_500,
                    prefersFrontmostWindow: true,
                    animation: MovementAnimationSettings(
                        fallbackMotionID: removableID,
                        // Saved direction choices remain independently editable even while disabled.
                        directionMotionIDs: DirectionalMotionIDs(
                            up: removableID, down: "keep-me", downRight: removableID
                        )
                    ),
                    dwellMode: roamingDwellMode == .behaviorCompletion ? .random : .behaviorCompletion
                )
            )
        )
    }

    private func removalFixture() -> AppSettings {
        let base = makeSettings()
        let profile = BehaviorProfile(
            petKey: base.selectedPetKey,
            stationaryBehaviorMode: .random,
            stationarySequenceID: "remove-me",
            randomSequenceIDs: ["remove-me", "keep-me"],
            sequences: base.sequences + ["remove-me", "keep-me"].map {
                BehaviorSequence(
                    id: $0,
                    displayName: $0 == "remove-me" ? "삭제할 행동" : "남는 행동",
                    steps: [BehaviorStep(motionID: "wave", repeatCount: 3)],
                    repeats: false
                )
            },
            automaticRules: [
                AutomaticRule(
                    id: UUID(), isEnabled: false, priority: 10,
                    condition: .application(bundleIdentifier: "com.example.Editor"),
                    sequenceID: "remove-me"
                ),
                AutomaticRule(
                    id: UUID(), isEnabled: true, priority: 8,
                    condition: .idleAtLeast(milliseconds: 12_000), sequenceID: "remove-me"
                ),
                AutomaticRule(
                    id: UUID(), isEnabled: false, priority: 3,
                    condition: .unsupported(type: "legacy"), sequenceID: "remove-me"
                ),
                AutomaticRule(
                    id: UUID(), isEnabled: true, priority: 1,
                    condition: .application(bundleIdentifier: "com.example.Other"),
                    sequenceID: "keep-me"
                )
            ],
            automaticRulePriorityOrder: [.application, .idle, .movement],
            movement: independentMovement(mode: .cursorAvoiding, removableID: "remove-me"),
            pettingMotionID: "remove-me",
            speech: PetSpeechSettings(
                isEnabled: true,
                periodicIsEnabled: false,
                periodicIntervalMilliseconds: 27_000,
                periodicOrder: .sequential,
                behaviorChangePolicy: .keep,
                phrases: [
                    PetSpeechPhrase(text: "삭제될 대사 1", trigger: .sequence("remove-me")),
                    PetSpeechPhrase(text: "남는 주기 대사", trigger: .periodic, displayMode: .untilNextPhrase),
                    PetSpeechPhrase(text: "삭제될 대사 2", trigger: .sequence("remove-me")),
                    PetSpeechPhrase(text: "남는 행동 대사", trigger: .sequence("keep-me"))
                ],
                theme: PetSpeechBubbleTheme(colorStyle: .mint),
                placement: PetSpeechBubblePlacementSettings(
                    preferredPosition: .below, horizontalOffset: 16, gap: 12
                )
            )
        )
        let settings = base.replacingActiveBehaviorProfile(profile)
        return settings.addingPetInstance(
            for: base.selectedPetKey,
            copyingSettingsFrom: settings.selectedPetInstanceID
        ).selectingPetInstance(settings.selectedPetInstanceID)
    }

    private func settingsReplacingManualSequenceID(
        _ manualSequenceID: String,
        in settings: AppSettings
    ) -> AppSettings {
        settings.replacingActiveBehaviorProfile(
            BehaviorProfile(
                petKey: settings.selectedPetKey,
                mode: settings.behaviorMode,
                manualSequenceID: manualSequenceID,
                sequences: settings.sequences,
                automaticRules: settings.automaticRules
            )
        )
    }
}
