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
    func testBuiltInBehaviorPresetsInstallInMemoryAndManualSelectionPersists() {
        let session = AppSettingsSession(
            store: AppSettingsStore(settingsURL: settingsURL)
        )
        _ = session.load()

        session.installBuiltInBehaviorPresetsIfNeeded()

        XCTAssertEqual(
            session.settings.sequences.map(\.id),
            ["idle", "focus", "rest", "sleep"]
        )
        XCTAssertEqual(session.settings.manualSequenceID, "idle")
        XCTAssertEqual(session.settings.automaticRules.count, 2)
        XCTAssertEqual(
            AppSettingsStore(settingsURL: settingsURL).load().source,
            .defaults
        )

        session.setManualSequenceID("focus")
        let reloaded = AppSettingsStore(settingsURL: settingsURL).load()
        XCTAssertEqual(reloaded.settings.manualSequenceID, "focus")
        XCTAssertEqual(reloaded.settings.sequences, BuiltInBehaviorPresets.sequences)
        XCTAssertEqual(
            reloaded.settings.automaticRules,
            BuiltInBehaviorPresets.automaticRules
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
