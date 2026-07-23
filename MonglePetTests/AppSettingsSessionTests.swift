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
    func testBehaviorProfilesStayIndependentAcrossPetSwitchesAndRelaunch() throws {
        let installedID = UUID(
            uuidString: "11111111-1111-1111-1111-111111111112"
        )!
        let session = AppSettingsSession(
            store: AppSettingsStore(settingsURL: settingsURL)
        )
        _ = session.load()
        session.ensureSystemDefaultBehavior()

        XCTAssertTrue(session.addBehaviorSequence(named: "built-in-custom"))
        session.setManualSequenceID("built-in-custom")
        session.setBehaviorMode(.manual)
        XCTAssertTrue(
            session.addApplicationRule(
                bundleIdentifier: "com.example.BuiltIn",
                sequenceID: "built-in-custom"
            )
        )

        session.setSelectedPetInstallationID(installedID)
        XCTAssertEqual(
            session.settings.sequences.map(\.id),
            [BuiltInBehaviorPresets.defaultSequenceID]
        )
        XCTAssertEqual(session.settings.behaviorMode, .automatic)
        XCTAssertTrue(session.settings.automaticRules.isEmpty)
        XCTAssertTrue(session.addBehaviorSequence(named: "installed-custom"))
        XCTAssertTrue(
            session.updateBehaviorStep(
                sequenceID: "installed-custom",
                index: 0,
                motionID: "coding",
                repeatCount: 5
            )
        )
        XCTAssertTrue(
            session.addIdleRule(
                minutes: 5,
                sequenceID: "installed-custom"
            )
        )

        session.setSelectedPetInstallationID(nil)
        XCTAssertEqual(session.settings.behaviorMode, .manual)
        XCTAssertEqual(session.settings.manualSequenceID, "built-in-custom")
        XCTAssertTrue(session.settings.sequences.contains { $0.id == "built-in-custom" })
        XCTAssertFalse(session.settings.sequences.contains { $0.id == "installed-custom" })
        XCTAssertEqual(session.settings.automaticRules.count, 1)
        XCTAssertEqual(
            session.settings.automaticRules.first?.condition,
            .application(bundleIdentifier: "com.example.BuiltIn")
        )

        let reloaded = AppSettingsSession(
            store: AppSettingsStore(settingsURL: settingsURL)
        )
        XCTAssertEqual(reloaded.load().source, .file)
        XCTAssertEqual(reloaded.settings.behaviorProfiles.count, 2)
        reloaded.setSelectedPetInstallationID(installedID)

        XCTAssertEqual(reloaded.settings.behaviorMode, .automatic)
        XCTAssertFalse(reloaded.settings.sequences.contains { $0.id == "built-in-custom" })
        let installedStep = try XCTUnwrap(
            reloaded.settings.sequences.first { $0.id == "installed-custom" }?.steps.first
        )
        XCTAssertEqual(installedStep.motionID, "coding")
        XCTAssertEqual(installedStep.repeatCount, 5)
        XCTAssertEqual(reloaded.settings.automaticRules.count, 1)
        XCTAssertEqual(
            reloaded.settings.automaticRules.first?.condition,
            .idleAtLeast(milliseconds: 300_000)
        )
    }

    @MainActor
    func testMovementSettingsStayIndependentAcrossPetSwitchesAndRelaunch() {
        let installationID = UUID(
            uuidString: "11111111-1111-1111-1111-111111111117"
        )!
        let builtInMovement = PetMovementSettings(
            mode: .cursorFollowing,
            speed: 220,
            cursorDistance: 100,
            stopRadius: 18,
            freeRoamingDwellMilliseconds: 7_000,
            prefersFrontmostWindow: false
        )
        let installedMovement = PetMovementSettings(
            mode: .freeRoaming,
            speed: 300,
            cursorDistance: 140,
            stopRadius: 24,
            freeRoamingDwellMilliseconds: 10_000,
            prefersFrontmostWindow: true
        )
        let session = AppSettingsSession(
            store: AppSettingsStore(settingsURL: settingsURL)
        )
        _ = session.load()
        session.ensureSystemDefaultBehavior()
        session.setMovementSettings(builtInMovement)
        session.setBehaviorMode(.manual)
        XCTAssertTrue(session.addBehaviorSequence(named: "movement-preserved"))
        XCTAssertEqual(session.settings.movementSettings, builtInMovement)

        session.setSelectedPetInstallationID(installationID)
        XCTAssertEqual(session.settings.movementSettings, .default)
        session.setMovementSettings(installedMovement)

        session.setSelectedPetInstallationID(nil)
        XCTAssertEqual(session.settings.movementSettings, builtInMovement)

        let reloaded = AppSettingsSession(
            store: AppSettingsStore(settingsURL: settingsURL)
        )
        XCTAssertEqual(reloaded.load().source, .file)
        XCTAssertEqual(reloaded.settings.movementSettings, builtInMovement)
        reloaded.setSelectedPetInstallationID(installationID)
        XCTAssertEqual(reloaded.settings.movementSettings, installedMovement)
    }

    @MainActor
    func testSeparateInstalledPetsReceiveIndependentDefaultProfiles() {
        let firstInstallationID = UUID(
            uuidString: "11111111-1111-1111-1111-111111111113"
        )!
        let secondInstallationID = UUID(
            uuidString: "11111111-1111-1111-1111-111111111114"
        )!
        let session = AppSettingsSession(
            store: AppSettingsStore(settingsURL: settingsURL)
        )
        _ = session.load()

        session.setSelectedPetInstallationID(firstInstallationID)
        XCTAssertTrue(session.addBehaviorSequence(named: "first-custom"))

        session.setSelectedPetInstallationID(secondInstallationID)
        XCTAssertEqual(
            session.settings.sequences.map(\.id),
            [BuiltInBehaviorPresets.defaultSequenceID]
        )
        XCTAssertFalse(
            session.settings.sequences.contains { $0.id == "first-custom" }
        )

        session.setSelectedPetInstallationID(firstInstallationID)
        XCTAssertTrue(
            session.settings.sequences.contains { $0.id == "first-custom" }
        )
        XCTAssertEqual(session.settings.behaviorProfiles.count, 2)
    }

    @MainActor
    func testReselectingSameInstallationRetainsCustomizedProfile() throws {
        let installationID = UUID(
            uuidString: "11111111-1111-1111-1111-111111111115"
        )!
        let session = AppSettingsSession(
            store: AppSettingsStore(settingsURL: settingsURL)
        )
        _ = session.load()
        session.setSelectedPetInstallationID(installationID)
        XCTAssertTrue(session.addBehaviorSequence(named: "kept-after-edit"))
        let profileBeforeReselection = try XCTUnwrap(
            session.settings.behaviorProfile(for: .installed(installationID))
        )

        session.setSelectedPetInstallationID(installationID)

        XCTAssertEqual(
            session.settings.behaviorProfile(for: .installed(installationID)),
            profileBeforeReselection
        )
    }

    @MainActor
    func testRemovingSelectedInstallationProfileSelectsBuiltInAndPersists() {
        let installationID = UUID(
            uuidString: "11111111-1111-1111-1111-111111111116"
        )!
        let session = AppSettingsSession(
            store: AppSettingsStore(settingsURL: settingsURL)
        )
        _ = session.load()
        session.setSelectedPetInstallationID(installationID)
        XCTAssertTrue(session.addBehaviorSequence(named: "removed-with-pet"))

        XCTAssertTrue(
            session.removeBehaviorProfile(forInstallationID: installationID)
        )

        XCTAssertNil(session.settings.selectedPetInstallationID)
        XCTAssertNil(
            session.settings.behaviorProfile(for: .installed(installationID))
        )
        XCTAssertNotNil(session.settings.behaviorProfile(for: .builtIn))
        let persistedSettings = AppSettingsStore(settingsURL: settingsURL)
            .load().settings
        XCTAssertNil(persistedSettings.selectedPetInstallationID)
        XCTAssertNil(
            persistedSettings.behaviorProfile(for: .installed(installationID))
        )
        XCTAssertNotNil(persistedSettings.behaviorProfile(for: .builtIn))
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
    func testMovementPreviewWaitsForExplicitPersistence() {
        let session = AppSettingsSession(
            store: AppSettingsStore(settingsURL: settingsURL)
        )
        _ = session.load()
        let movement = PetMovementSettings(
            mode: .cursorFollowing,
            speed: 280,
            cursorDistance: 144,
            stopRadius: 24,
            freeRoamingDwellMilliseconds: 8_000,
            prefersFrontmostWindow: false,
            cursorFollowingMotionID: "run"
        )

        session.setMovementSettings(movement, persist: false)

        XCTAssertEqual(session.settings.movementSettings, movement)
        XCTAssertEqual(
            AppSettingsStore(settingsURL: settingsURL).load().source,
            .defaults
        )

        session.persistCurrentSettings()
        XCTAssertEqual(
            AppSettingsStore(settingsURL: settingsURL).load()
                .settings.movementSettings,
            movement
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
                repeatCount: 12
            )
        )
        XCTAssertFalse(session.addBehaviorSequence(named: "coding"))
        XCTAssertNotNil(session.behaviorEditErrorMessage)

        let reloaded = AppSettingsStore(settingsURL: settingsURL).load().settings
        let coding = reloaded.sequences.first { $0.id == "coding" }
        XCTAssertEqual(coding?.steps.count, 2)
        XCTAssertEqual(coding?.steps[1].motionID, "focus")
        XCTAssertEqual(coding?.steps[1].repeatCount, 12)
    }

    @MainActor
    func testBehaviorStepEditingRejectsInvalidRepeatCountWithoutChangingSettings() {
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
                repeatCount: 0
            )
        )
        XCTAssertEqual(session.settings, originalSettings)
        XCTAssertNotNil(session.behaviorEditErrorMessage)
    }

    @MainActor
    func testRenamingAndRemovingMotionReferencesUpdatesBehaviorAndMovement() throws {
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
                repeatCount: 4
            )
        )
        session.setMovementSettings(
            PetMovementSettings(
                mode: .cursorFollowing,
                speed: AppSettingsLimits.defaultMovementSpeed,
                cursorDistance: AppSettingsLimits.defaultCursorDistance,
                stopRadius: AppSettingsLimits.defaultMovementStopRadius,
                freeRoamingDwellMilliseconds:
                    AppSettingsLimits.defaultFreeRoamingDwellMilliseconds,
                prefersFrontmostWindow: true,
                cursorFollowingMotionID: "wave",
                freeRoamingMotionID: "wave"
            )
        )
        var changes: [AppSettings] = []
        session.onChange = { changes.append($0) }

        XCTAssertTrue(
            session.renameMotionReferences(
                from: "wave",
                to: "hello"
            )
        )

        let currentStep = try XCTUnwrap(
            session.settings.sequences.first { $0.id == "custom" }?.steps.first
        )
        XCTAssertEqual(currentStep.motionID, "hello")
        XCTAssertEqual(session.settings.movementSettings.cursorFollowingMotionID, "hello")
        XCTAssertEqual(session.settings.movementSettings.freeRoamingMotionID, "hello")

        XCTAssertTrue(session.removeMotionReferences("hello"))
        let removedStep = try XCTUnwrap(
            session.settings.sequences.first { $0.id == "custom" }?.steps.first
        )
        XCTAssertEqual(removedStep.motionID, PetMotionReference.currentPetDefault)
        XCTAssertNil(session.settings.movementSettings.cursorFollowingMotionID)
        XCTAssertNil(session.settings.movementSettings.freeRoamingMotionID)
        XCTAssertEqual(changes.last, session.settings)
        let reloaded = AppSettingsStore(settingsURL: settingsURL).load().settings
        XCTAssertEqual(
            reloaded.sequences.first { $0.id == "custom" }?.steps.first?.motionID,
            PetMotionReference.currentPetDefault
        )
        XCTAssertNil(reloaded.movementSettings.cursorFollowingMotionID)
        XCTAssertNil(reloaded.movementSettings.freeRoamingMotionID)
    }

    @MainActor
    func testUnmodifiedLegacyDefaultsMigrateToSingleSystemDefault() throws {
        let legacySettings = StoredAppSettings(
            schemaVersion: 1,
            selectedPetInstallationID: nil,
            lastUserPresentation: "awake",
            behaviorMode: "automatic",
            overlay: StoredOverlaySettings(
                screenIdentifier: nil,
                originX: 0,
                originY: 0,
                width: 192,
                clickThrough: false
            ),
            manualSequenceID: "idle",
            sequences: BuiltInBehaviorPresets.legacySequences.map { sequence in
                StoredBehaviorSequence(
                    id: sequence.id,
                    steps: sequence.steps.map { step in
                        StoredBehaviorStep(
                            motionID: step.motionID,
                            durationMilliseconds: 3_000,
                            playbackSpeed: 1
                        )
                    },
                    repeats: sequence.repeats
                )
            },
            automaticRules: BuiltInBehaviorPresets.legacyAutomaticRules.map { rule in
                StoredAutomaticRule(
                    id: rule.id.uuidString,
                    isEnabled: rule.isEnabled,
                    priority: rule.priority,
                    condition: {
                        switch rule.condition {
                        case let .idleAtLeast(milliseconds):
                            return .idleAtLeast(milliseconds: milliseconds)
                        case let .application(bundleIdentifier):
                            return .application(bundleIdentifier: bundleIdentifier)
                        case let .unsupported(type):
                            return .unsupported(type: type)
                        }
                    }(),
                    sequenceID: rule.sequenceID
                )
            }
        )
        try JSONEncoder().encode(legacySettings).write(to: settingsURL)
        let session = AppSettingsSession(
            store: AppSettingsStore(settingsURL: settingsURL)
        )

        _ = session.load { _ in self.migrationPetDefinition }
        session.ensureSystemDefaultBehavior()

        XCTAssertEqual(session.settings.sequences, BuiltInBehaviorPresets.sequences)
        XCTAssertEqual(
            session.settings.manualSequenceID,
            BuiltInBehaviorPresets.defaultSequenceID
        )
        XCTAssertTrue(session.settings.automaticRules.isEmpty)
    }

    private var migrationPetDefinition: PetDefinition {
        let frame = MotionFrame(
            atlasID: "main",
            sourceRect: PixelRect(x: 0, y: 0, width: 10, height: 10),
            duration: .seconds(1)
        )
        return PetDefinition(
            id: "migration.pet",
            displayName: "Migration Pet",
            defaultMotionID: "idle",
            motions: ["idle", "focus", "rest", "sleep"].map {
                PetMotion(id: $0, loops: true, frames: [frame])
            }
        )
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
