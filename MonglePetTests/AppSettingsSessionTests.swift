import Foundation
import XCTest
@testable import MonglePet

final class AppSettingsSessionTests: XCTestCase {
    private var temporaryDirectoryURL: URL!
    private var settingsURL: URL!

    override func setUpWithError() throws {
        temporaryDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: temporaryDirectoryURL,
            withIntermediateDirectories: true
        )
        settingsURL = temporaryDirectoryURL.appendingPathComponent("settings.json")
    }

    override func tearDownWithError() throws {
        if let temporaryDirectoryURL,
           FileManager.default.fileExists(atPath: temporaryDirectoryURL.path) {
            try FileManager.default.removeItem(at: temporaryDirectoryURL)
        }
        temporaryDirectoryURL = nil
        settingsURL = nil
    }

    @MainActor
    func testChangesApplyImmediatelyAndPersistAcrossSessions() throws {
        let session = AppSettingsSession(
            store: AppSettingsStore(settingsURL: settingsURL)
        )
        var changedSettings: [AppSettings] = []
        session.onChange = { changedSettings.append($0) }
        XCTAssertEqual(session.load().source, .defaults)

        session.setUserPresentation(.tuckedAway)
        session.setBehaviorMode(.manual)
        session.setOverlayWidth(280)
        session.setClickThrough(true)
        session.setOverlayGeometry(
            OverlaySettings(
                screenIdentifier: "display-42",
                originX: 123,
                originY: 456,
                width: 280,
                clickThrough: true
            )
        )

        XCTAssertEqual(changedSettings.count, 5)
        XCTAssertEqual(session.settings.lastUserPresentation, .tuckedAway)
        XCTAssertEqual(session.settings.behaviorMode, .manual)
        XCTAssertNil(session.saveErrorMessage)

        let reloaded = AppSettingsSession(
            store: AppSettingsStore(settingsURL: settingsURL)
        )
        XCTAssertEqual(reloaded.load().source, .file)
        XCTAssertEqual(reloaded.settings, session.settings)
    }

    @MainActor
    func testSelectedPetInstallationPersistsAndCanReturnToBuiltInPet() {
        let session = AppSettingsSession(
            store: AppSettingsStore(settingsURL: settingsURL)
        )
        _ = session.load()
        let installationID = UUID(
            uuidString: "11111111-1111-1111-1111-111111111111"
        )!

        session.setSelectedPetInstallationID(installationID)
        XCTAssertEqual(
            AppSettingsStore(settingsURL: settingsURL).load()
                .settings.selectedPetInstallationID,
            installationID
        )

        session.setSelectedPetInstallationID(nil)
        XCTAssertNil(
            AppSettingsStore(settingsURL: settingsURL).load()
                .settings.selectedPetInstallationID
        )
    }

    @MainActor
    func testOverlayWidthPreviewWaitsForExplicitPersistence() {
        let session = AppSettingsSession(
            store: AppSettingsStore(settingsURL: settingsURL)
        )
        _ = session.load()

        session.setOverlayWidth(320, persist: false)

        XCTAssertEqual(session.settings.overlay.width, 320)
        XCTAssertEqual(
            AppSettingsStore(settingsURL: settingsURL).load().source,
            .defaults
        )

        session.persistCurrentSettings()
        XCTAssertEqual(
            AppSettingsStore(settingsURL: settingsURL).load().settings.overlay.width,
            320
        )
    }

    @MainActor
    func testSynchronizedRuntimeGeometryIsIncludedInNextSavedChange() {
        let session = AppSettingsSession(
            store: AppSettingsStore(settingsURL: settingsURL)
        )
        _ = session.load()
        let runtimeOverlay = OverlaySettings(
            screenIdentifier: "display-7",
            originX: 700,
            originY: 80,
            width: 192,
            clickThrough: false
        )

        session.synchronizeOverlayGeometry(runtimeOverlay)
        XCTAssertEqual(
            AppSettingsStore(settingsURL: settingsURL).load().source,
            .defaults
        )

        session.setBehaviorMode(.manual)
        let reloaded = AppSettingsStore(settingsURL: settingsURL).load()
        XCTAssertEqual(reloaded.settings.overlay, runtimeOverlay)
        XCTAssertEqual(reloaded.settings.behaviorMode, .manual)
    }

    @MainActor
    func testSystemDefaultBehaviorInstallsInMemoryAndCustomSelectionPersists() {
        let session = AppSettingsSession(
            store: AppSettingsStore(settingsURL: settingsURL)
        )
        _ = session.load()

        session.ensureSystemDefaultBehavior()

        XCTAssertEqual(
            session.settings.sequences.map(\.id),
            [BuiltInBehaviorPresets.defaultSequenceID]
        )
        XCTAssertEqual(
            session.settings.manualSequenceID,
            BuiltInBehaviorPresets.defaultSequenceID
        )
        XCTAssertTrue(session.settings.automaticRules.isEmpty)
        XCTAssertEqual(
            AppSettingsStore(settingsURL: settingsURL).load().source,
            .defaults
        )

        XCTAssertTrue(session.addBehaviorSequence(named: "coding"))
        session.setManualSequenceID("coding")
        let reloaded = AppSettingsStore(settingsURL: settingsURL).load()
        XCTAssertEqual(reloaded.settings.manualSequenceID, "coding")
        XCTAssertEqual(
            reloaded.settings.sequences.map(\.id),
            [BuiltInBehaviorPresets.defaultSequenceID, "coding"]
        )
        XCTAssertTrue(reloaded.settings.automaticRules.isEmpty)
    }

    @MainActor
    func testBehaviorEditingReportsErrorsAndPersistsValidChanges() {
        let session = AppSettingsSession(
            store: AppSettingsStore(settingsURL: settingsURL)
        )
        _ = session.load()
        session.ensureSystemDefaultBehavior()

        XCTAssertTrue(session.addBehaviorSequence(named: "coding"))
        XCTAssertNil(session.behaviorEditErrorMessage)
        XCTAssertTrue(session.addBehaviorStep(to: "coding"))
        XCTAssertTrue(
            session.updateBehaviorStep(
                sequenceID: "coding",
                index: 1,
                motionID: "focus",
                durationSeconds: 12,
                playbackSpeed: 1.5
            )
        )
        XCTAssertFalse(session.addBehaviorSequence(named: "coding"))
        XCTAssertNotNil(session.behaviorEditErrorMessage)

        let reloaded = AppSettingsStore(settingsURL: settingsURL).load().settings
        let coding = reloaded.sequences.first { $0.id == "coding" }
        XCTAssertEqual(coding?.steps.count, 2)
        XCTAssertEqual(coding?.steps[1].motionID, "focus")
        XCTAssertEqual(coding?.steps[1].duration, .seconds(12))
        XCTAssertEqual(coding?.steps[1].playbackSpeed, 1.5)
    }

    @MainActor
    func testBehaviorStepEditingRejectsNonFiniteDurationWithoutChangingSettings() {
        let session = AppSettingsSession(
            store: AppSettingsStore(settingsURL: settingsURL)
        )
        _ = session.load()
        session.ensureSystemDefaultBehavior()
        let originalSettings = session.settings

        XCTAssertFalse(
            session.updateBehaviorStep(
                sequenceID: BuiltInBehaviorPresets.defaultSequenceID,
                index: 0,
                motionID: PetMotionReference.currentPetDefault,
                durationSeconds: .infinity,
                playbackSpeed: 1
            )
        )
        XCTAssertEqual(session.settings, originalSettings)
        XCTAssertNotNil(session.behaviorEditErrorMessage)
    }

    @MainActor
    func testReplacingMotionReferencesAppliesImmediatelyAndPersists() throws {
        let session = AppSettingsSession(
            store: AppSettingsStore(settingsURL: settingsURL)
        )
        _ = session.load()
        session.ensureSystemDefaultBehavior()
        XCTAssertTrue(session.addBehaviorSequence(named: "custom"))
        XCTAssertTrue(
            session.updateBehaviorStep(
                sequenceID: "custom",
                index: 0,
                motionID: "wave",
                durationSeconds: 4,
                playbackSpeed: 1.25
            )
        )
        var changes: [AppSettings] = []
        session.onChange = { changes.append($0) }

        XCTAssertTrue(
            session.replaceBehaviorMotionReferences(
                from: "wave",
                with: PetMotionReference.currentPetDefault
            )
        )

        let currentStep = try XCTUnwrap(
            session.settings.sequences.first { $0.id == "custom" }?.steps.first
        )
        XCTAssertEqual(currentStep.motionID, PetMotionReference.currentPetDefault)
        XCTAssertEqual(changes.last, session.settings)
        let reloaded = AppSettingsStore(settingsURL: settingsURL).load().settings
        XCTAssertEqual(
            reloaded.sequences.first { $0.id == "custom" }?.steps.first?.motionID,
            PetMotionReference.currentPetDefault
        )
    }

    @MainActor
    func testUnmodifiedLegacyDefaultsMigrateToSingleSystemDefault() throws {
        let legacySettings = AppSettings(
            selectedPetInstallationID: nil,
            lastUserPresentation: .awake,
            behaviorMode: .automatic,
            overlay: .default,
            manualSequenceID: "idle",
            sequences: BuiltInBehaviorPresets.legacySequences,
            automaticRules: BuiltInBehaviorPresets.legacyAutomaticRules
        )
        try AppSettingsStore(settingsURL: settingsURL).save(legacySettings)
        let session = AppSettingsSession(
            store: AppSettingsStore(settingsURL: settingsURL)
        )

        _ = session.load()
        session.ensureSystemDefaultBehavior()

        XCTAssertEqual(session.settings.sequences, BuiltInBehaviorPresets.sequences)
        XCTAssertEqual(
            session.settings.manualSequenceID,
            BuiltInBehaviorPresets.defaultSequenceID
        )
        XCTAssertTrue(session.settings.automaticRules.isEmpty)
    }

    func testModifiedLegacyBehaviorIsPreservedWhileSystemDefaultIsAdded() throws {
        var modifiedSequences = BuiltInBehaviorPresets.legacySequences
        let idle = try XCTUnwrap(modifiedSequences.first)
        modifiedSequences[0] = BehaviorSequence(
            id: idle.id,
            steps: [
                BehaviorStep(
                    motionID: "idle",
                    duration: .seconds(4),
                    playbackSpeed: 1
                )
            ],
            repeats: true
        )
        let settings = AppSettings(
            selectedPetInstallationID: nil,
            lastUserPresentation: .awake,
            behaviorMode: .automatic,
            overlay: .default,
            manualSequenceID: "idle",
            sequences: modifiedSequences,
            automaticRules: BuiltInBehaviorPresets.legacyAutomaticRules
        )

        let normalized = BuiltInBehaviorPresets.normalizedDefaults(in: settings)

        XCTAssertEqual(normalized.sequences.first, BuiltInBehaviorPresets.sequences[0])
        XCTAssertEqual(Array(normalized.sequences.dropFirst()), modifiedSequences)
        XCTAssertEqual(normalized.manualSequenceID, "idle")
        XCTAssertEqual(
            normalized.automaticRules,
            BuiltInBehaviorPresets.legacyAutomaticRules
        )
    }

    @MainActor
    func testNewerSchemaPreservesFileWhileAllowingRuntimePresentationChange() throws {
        let originalData = Data(#"{"schemaVersion":9,"future":true}"#.utf8)
        try originalData.write(to: settingsURL)
        let session = AppSettingsSession(
            store: AppSettingsStore(settingsURL: settingsURL)
        )

        let result = session.load()
        session.setUserPresentation(.tuckedAway)

        XCTAssertEqual(result.source, .newerSchema(9))
        XCTAssertFalse(session.isWritingEnabled)
        XCTAssertNotNil(session.loadNotice)
        XCTAssertEqual(session.settings.lastUserPresentation, .tuckedAway)
        XCTAssertEqual(try Data(contentsOf: settingsURL), originalData)
    }

    @MainActor
    func testRestorePositionPolicyDistinguishesDefaultsCorruptAndPartialRecovery() {
        let defaults = AppSettingsLoadResult(
            settings: .default,
            issues: [],
            source: .defaults,
            isWritingEnabled: true
        )
        let corrupt = AppSettingsLoadResult(
            settings: .default,
            issues: [.corruptFileQuarantined("settings.corrupt-test.json")],
            source: .recovered,
            isWritingEnabled: true
        )
        let partial = AppSettingsLoadResult(
            settings: .default,
            issues: [.invalidField("behaviorMode")],
            source: .recovered,
            isWritingEnabled: true
        )

        XCTAssertFalse(defaults.shouldRestoreOverlayPosition)
        XCTAssertFalse(corrupt.shouldRestoreOverlayPosition)
        XCTAssertTrue(partial.shouldRestoreOverlayPosition)
    }
}
