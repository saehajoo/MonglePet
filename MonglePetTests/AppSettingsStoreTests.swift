import Foundation
import XCTest
@testable import MonglePet

final class AppSettingsStoreTests: XCTestCase {
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

    func testMissingFileUsesDefaultsThenRoundTripsExplicitSchema() throws {
        let store = AppSettingsStore(settingsURL: settingsURL)
        let initial = store.load()

        XCTAssertEqual(initial.settings, .default)
        XCTAssertEqual(initial.source, .defaults)
        XCTAssertTrue(initial.isWritingEnabled)

        let settings = makeSettings()
        try store.save(settings)
        let loaded = store.load()

        XCTAssertEqual(loaded.settings, settings)
        XCTAssertEqual(loaded.source, .file)
        XCTAssertTrue(loaded.issues.isEmpty)

        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: settingsURL))
                as? [String: Any]
        )
        XCTAssertEqual(json["schemaVersion"] as? Int, 1)
        XCTAssertEqual(json["lastUserPresentation"] as? String, "tuckedAway")
        XCTAssertEqual(json["behaviorMode"] as? String, "manual")

        let sequences = try XCTUnwrap(json["sequences"] as? [[String: Any]])
        let steps = try XCTUnwrap(sequences.first?["steps"] as? [[String: Any]])
        XCTAssertEqual(steps.first?["durationMilliseconds"] as? Int, 2_000)

        let rules = try XCTUnwrap(json["automaticRules"] as? [[String: Any]])
        let applicationCondition = try XCTUnwrap(rules.first?["condition"] as? [String: Any])
        XCTAssertEqual(applicationCondition["type"] as? String, "application")
        XCTAssertEqual(
            applicationCondition["bundleIdentifier"] as? String,
            "com.example.Editor"
        )
        let idleCondition = try XCTUnwrap(rules.dropFirst().first?["condition"] as? [String: Any])
        XCTAssertEqual(idleCondition["type"] as? String, "idleAtLeast")
        XCTAssertEqual(idleCondition["milliseconds"] as? Int, 120_000)
    }

    func testInvalidItemsRecoverIndependentlyAndUnknownConditionIsDisabled() throws {
        let validSequence = StoredBehaviorSequence(
            id: "focus-sequence",
            steps: [
                StoredBehaviorStep(
                    motionID: "",
                    durationMilliseconds: 0,
                    playbackSpeed: 100
                ),
                StoredBehaviorStep(
                    motionID: "focus",
                    durationMilliseconds: 5_000,
                    playbackSpeed: 1
                )
            ],
            repeats: true
        )
        let unknownRuleID = UUID()
        let missingSequenceRuleID = UUID()
        let stored = StoredAppSettings(
            schemaVersion: 1,
            selectedPetInstallationID: "not-a-uuid",
            lastUserPresentation: "suspended",
            behaviorMode: "future-mode",
            overlay: StoredOverlaySettings(
                screenIdentifier: "   ",
                originX: 10,
                originY: 20,
                width: 1_000,
                clickThrough: true
            ),
            manualSequenceID: "missing-sequence",
            sequences: [
                validSequence,
                validSequence,
                StoredBehaviorSequence(id: "empty", steps: [], repeats: true)
            ],
            automaticRules: [
                StoredAutomaticRule(
                    id: unknownRuleID.uuidString,
                    isEnabled: true,
                    priority: 10,
                    condition: .unsupported(type: "futureCondition"),
                    sequenceID: "focus-sequence"
                ),
                StoredAutomaticRule(
                    id: missingSequenceRuleID.uuidString,
                    isEnabled: true,
                    priority: 1,
                    condition: .application(bundleIdentifier: "com.example.Editor"),
                    sequenceID: "missing-sequence"
                ),
                StoredAutomaticRule(
                    id: "invalid-rule-id",
                    isEnabled: true,
                    priority: 0,
                    condition: .idleAtLeast(milliseconds: 120_000),
                    sequenceID: "focus-sequence"
                )
            ]
        )
        try JSONEncoder().encode(stored).write(to: settingsURL)
        let store = AppSettingsStore(settingsURL: settingsURL)

        let loaded = store.load()

        XCTAssertEqual(loaded.source, .recovered)
        XCTAssertNil(loaded.settings.selectedPetInstallationID)
        XCTAssertEqual(loaded.settings.lastUserPresentation, .awake)
        XCTAssertEqual(loaded.settings.behaviorMode, .automatic)
        XCTAssertEqual(loaded.settings.overlay.screenIdentifier, nil)
        XCTAssertEqual(loaded.settings.overlay.width, 384)
        XCTAssertTrue(loaded.settings.overlay.clickThrough)
        XCTAssertNil(loaded.settings.manualSequenceID)
        XCTAssertEqual(loaded.settings.sequences.count, 1)
        XCTAssertEqual(loaded.settings.sequences[0].steps.count, 1)
        XCTAssertEqual(loaded.settings.automaticRules.count, 2)
        XCTAssertTrue(loaded.settings.automaticRules.allSatisfy { !$0.isEnabled })
        XCTAssertEqual(
            loaded.settings.automaticRules.first?.condition,
            .unsupported(type: "futureCondition")
        )
        XCTAssertTrue(loaded.issues.contains(.disabledRule(unknownRuleID.uuidString)))
        XCTAssertTrue(
            loaded.issues.contains(.disabledRule(missingSequenceRuleID.uuidString))
        )

        try store.save(loaded.settings)
        let savedAgain = store.load()
        XCTAssertEqual(savedAgain.settings, loaded.settings)
    }

    func testCorruptFileIsQuarantinedBeforeDefaultsCanBeSaved() throws {
        let quarantineID = UUID(uuidString: "20000000-0000-0000-0000-000000000001")!
        try Data("{not-json".utf8).write(to: settingsURL)
        let store = AppSettingsStore(
            settingsURL: settingsURL,
            quarantineIDGenerator: { quarantineID }
        )

        let loaded = store.load()

        let quarantineName = "settings.corrupt-\(quarantineID.uuidString).json"
        let quarantineURL = temporaryDirectoryURL.appendingPathComponent(quarantineName)
        XCTAssertEqual(loaded.settings, .default)
        XCTAssertEqual(loaded.source, .recovered)
        XCTAssertEqual(loaded.issues, [.corruptFileQuarantined(quarantineName)])
        XCTAssertFalse(FileManager.default.fileExists(atPath: settingsURL.path))
        XCTAssertEqual(try Data(contentsOf: quarantineURL), Data("{not-json".utf8))

        try store.save(.default)
        XCTAssertTrue(FileManager.default.fileExists(atPath: settingsURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: quarantineURL.path))
    }

    func testNewerSchemaIsPreservedAndDisablesWriting() throws {
        let originalData = Data(#"{"schemaVersion":2,"futureValue":true}"#.utf8)
        try originalData.write(to: settingsURL)
        let store = AppSettingsStore(settingsURL: settingsURL)

        let loaded = store.load()

        XCTAssertEqual(loaded.source, .newerSchema(2))
        XCTAssertEqual(loaded.issues, [.newerSchemaVersion(2)])
        XCTAssertFalse(loaded.isWritingEnabled)
        XCTAssertEqual(try Data(contentsOf: settingsURL), originalData)
        XCTAssertThrowsError(try store.save(.default)) { error in
            XCTAssertEqual(
                error as? AppSettingsStoreError,
                .writingDisabledForNewerSchema
            )
        }
        XCTAssertEqual(try Data(contentsOf: settingsURL), originalData)
    }

    func testOversizedFileIsQuarantinedWithoutDecoding() throws {
        let quarantineID = UUID(uuidString: "20000000-0000-0000-0000-000000000002")!
        let oversizedData = Data(
            repeating: 0x20,
            count: AppSettingsLimits.maximumFileSize + 1
        )
        try oversizedData.write(to: settingsURL)
        let store = AppSettingsStore(
            settingsURL: settingsURL,
            quarantineIDGenerator: { quarantineID }
        )

        let loaded = store.load()

        let quarantineURL = temporaryDirectoryURL.appendingPathComponent(
            "settings.corrupt-\(quarantineID.uuidString).json"
        )
        XCTAssertEqual(loaded.source, .recovered)
        XCTAssertFalse(FileManager.default.fileExists(atPath: settingsURL.path))
        XCTAssertEqual(
            try Data(contentsOf: quarantineURL).count,
            AppSettingsLimits.maximumFileSize + 1
        )
    }

    func testInvalidDomainSettingsAreRejectedWithoutLeavingTemporaryFiles() throws {
        let invalidSettings = AppSettings(
            selectedPetInstallationID: nil,
            lastUserPresentation: .suspended,
            behaviorMode: .automatic,
            overlay: .default,
            manualSequenceID: nil,
            sequences: [],
            automaticRules: []
        )
        let store = AppSettingsStore(settingsURL: settingsURL)

        XCTAssertThrowsError(try store.save(invalidSettings)) { error in
            XCTAssertEqual(
                error as? AppSettingsStoreError,
                .invalidSettings("lastUserPresentation")
            )
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: settingsURL.path))
        let children = try FileManager.default.contentsOfDirectory(
            at: temporaryDirectoryURL,
            includingPropertiesForKeys: nil
        )
        XCTAssertTrue(children.isEmpty)
    }

    func testReplacingExistingSettingsIsAtomicAndCleansTemporaryFile() throws {
        let temporaryID = UUID(uuidString: "20000000-0000-0000-0000-000000000003")!
        let store = AppSettingsStore(
            settingsURL: settingsURL,
            temporaryIDGenerator: { temporaryID }
        )
        try store.save(makeSettings())
        try store.save(.default)

        XCTAssertEqual(store.load().settings, .default)
        let children = try FileManager.default.contentsOfDirectory(
            at: temporaryDirectoryURL,
            includingPropertiesForKeys: nil
        )
        XCTAssertEqual(children.map(\.lastPathComponent), ["settings.json"])
    }

    private func makeSettings() -> AppSettings {
        let selectedPetID = UUID(
            uuidString: "30000000-0000-0000-0000-000000000001"
        )!
        let applicationRuleID = UUID(
            uuidString: "30000000-0000-0000-0000-000000000002"
        )!
        let idleRuleID = UUID(
            uuidString: "30000000-0000-0000-0000-000000000003"
        )!
        let idleSequence = BehaviorSequence(
            id: "idle-sequence",
            steps: [
                BehaviorStep(
                    motionID: "idle",
                    duration: .seconds(2),
                    playbackSpeed: 1
                )
            ],
            repeats: true
        )
        let focusSequence = BehaviorSequence(
            id: "focus-sequence",
            steps: [
                BehaviorStep(
                    motionID: "focus",
                    duration: .seconds(30),
                    playbackSpeed: 1.5
                )
            ],
            repeats: true
        )

        return AppSettings(
            selectedPetInstallationID: selectedPetID,
            lastUserPresentation: .tuckedAway,
            behaviorMode: .manual,
            overlay: OverlaySettings(
                screenIdentifier: "display-1",
                originX: 100,
                originY: 200,
                width: 240,
                clickThrough: true
            ),
            manualSequenceID: focusSequence.id,
            sequences: [idleSequence, focusSequence],
            automaticRules: [
                AutomaticRule(
                    id: applicationRuleID,
                    isEnabled: true,
                    priority: 10,
                    condition: .application(bundleIdentifier: "com.example.Editor"),
                    sequenceID: focusSequence.id
                ),
                AutomaticRule(
                    id: idleRuleID,
                    isEnabled: true,
                    priority: 5,
                    condition: .idleAtLeast(milliseconds: 120_000),
                    sequenceID: idleSequence.id
                )
            ]
        )
    }
}
