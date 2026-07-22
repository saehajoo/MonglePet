import Foundation
import XCTest
@testable import MonglePet

final class BehaviorSettingsEditorTests: XCTestCase {
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
            ["idle", "waving"]
        )
        XCTAssertEqual(
            BehaviorMotionCatalog.identifiers(for: pet, including: "legacy"),
            ["idle", "waving", "legacy"]
        )
    }

    func testSequenceNamesAreTrimmedAndComparedCaseInsensitively() throws {
        let added = try BehaviorSettingsEditor.addingSequence(
            named: "  Coding Time  ",
            to: makeSettings()
        )

        XCTAssertEqual(added.sequences.last?.id, "Coding Time")
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

    func testStepsCanBeAddedEditedMovedAndRemovedWhileKeepingOne() throws {
        var settings = try BehaviorSettingsEditor.addingSequence(
            named: "custom",
            to: makeSettings()
        )
        settings = try BehaviorSettingsEditor.addingStep(to: "custom", in: settings)
        settings = try BehaviorSettingsEditor.replacingStep(
            in: "custom",
            at: 1,
            with: BehaviorStep(
                motionID: "focus",
                duration: .seconds(9),
                playbackSpeed: 1.5
            ),
            settings: settings
        )
        settings = try BehaviorSettingsEditor.movingStep(
            in: "custom",
            from: 1,
            to: 0,
            settings: settings
        )

        var custom = try XCTUnwrap(settings.sequences.first { $0.id == "custom" })
        XCTAssertEqual(custom.steps.map(\.motionID), ["focus", "idle"])
        XCTAssertEqual(custom.steps[0].duration, .seconds(9))

        settings = try BehaviorSettingsEditor.removingStep(
            from: "custom",
            at: 1,
            settings: settings
        )
        custom = try XCTUnwrap(settings.sequences.first { $0.id == "custom" })
        XCTAssertEqual(custom.steps.count, 1)
        XCTAssertThrowsError(
            try BehaviorSettingsEditor.removingStep(
                from: "custom",
                at: 0,
                settings: settings
            )
        ) { error in
            XCTAssertEqual(error as? BehaviorSettingsEditError, .cannotRemoveLastStep)
        }
    }

    func testDeletingCustomSequenceCleansReferencesAndProtectsBuiltIns() throws {
        var settings = try BehaviorSettingsEditor.addingSequence(
            named: "custom",
            to: makeSettings(manualSequenceID: "idle")
        )
        settings = settingsReplacingManualSequenceID("custom", in: settings)
        settings = try BehaviorSettingsEditor.addingApplicationRule(
            bundleIdentifier: "com.example.Editor",
            sequenceID: "custom",
            to: settings
        )

        settings = try BehaviorSettingsEditor.removingSequence(
            id: "custom",
            from: settings
        )

        XCTAssertEqual(settings.manualSequenceID, "idle")
        XCTAssertFalse(settings.sequences.contains { $0.id == "custom" })
        XCTAssertFalse(settings.automaticRules.contains { $0.sequenceID == "custom" })
        XCTAssertThrowsError(
            try BehaviorSettingsEditor.removingSequence(id: "idle", from: settings)
        ) { error in
            XCTAssertEqual(error as? BehaviorSettingsEditError, .protectedSequence)
        }
    }

    func testApplicationAndIdleRulesCanBeAddedUpdatedAndRemoved() throws {
        let applicationRuleID = UUID()
        let idleRuleID = UUID()
        var settings = try BehaviorSettingsEditor.addingApplicationRule(
            bundleIdentifier: "com.apple.dt.Xcode",
            sequenceID: "focus",
            id: applicationRuleID,
            to: makeSettings(rules: [])
        )
        settings = try BehaviorSettingsEditor.addingIdleRule(
            minutes: 3,
            sequenceID: "rest",
            id: idleRuleID,
            to: settings
        )

        XCTAssertEqual(settings.automaticRules.map(\.priority), [0, 1])
        XCTAssertEqual(
            settings.automaticRules[1].condition,
            .idleAtLeast(milliseconds: 180_000)
        )

        let edited = AutomaticRule(
            id: applicationRuleID,
            isEnabled: false,
            priority: 8,
            condition: .application(bundleIdentifier: "com.apple.Safari"),
            sequenceID: "idle"
        )
        settings = try BehaviorSettingsEditor.replacingRule(edited, in: settings)
        XCTAssertEqual(settings.automaticRules[0], edited)

        settings = try BehaviorSettingsEditor.removingRule(id: idleRuleID, from: settings)
        XCTAssertEqual(settings.automaticRules.map(\.id), [applicationRuleID])

        XCTAssertThrowsError(
            try BehaviorSettingsEditor.addingApplicationRule(
                bundleIdentifier: "com.example bad",
                sequenceID: "idle",
                to: settings
            )
        ) { error in
            XCTAssertEqual(error as? BehaviorSettingsEditError, .invalidRule)
        }
        XCTAssertThrowsError(
            try BehaviorSettingsEditor.addingIdleRule(
                minutes: 0,
                sequenceID: "idle",
                to: settings
            )
        ) { error in
            XCTAssertEqual(error as? BehaviorSettingsEditError, .invalidRule)
        }
    }

    private func makeSettings(
        manualSequenceID: String? = "idle",
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

    private func settingsReplacingManualSequenceID(
        _ manualSequenceID: String,
        in settings: AppSettings
    ) -> AppSettings {
        AppSettings(
            selectedPetInstallationID: settings.selectedPetInstallationID,
            lastUserPresentation: settings.lastUserPresentation,
            behaviorMode: settings.behaviorMode,
            overlay: settings.overlay,
            manualSequenceID: manualSequenceID,
            sequences: settings.sequences,
            automaticRules: settings.automaticRules
        )
    }
}
