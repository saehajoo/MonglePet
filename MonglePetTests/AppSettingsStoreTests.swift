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
        XCTAssertEqual(json["schemaVersion"] as? Int, 3)
        XCTAssertEqual(json["lastUserPresentation"] as? String, "tuckedAway")
        XCTAssertNil(json["behaviorMode"])

        let profiles = try XCTUnwrap(json["behaviorProfiles"] as? [[String: Any]])
        XCTAssertEqual(profiles.first?["mode"] as? String, "manual")
        let movement = try XCTUnwrap(profiles.first?["movement"] as? [String: Any])
        XCTAssertEqual(movement["mode"] as? String, "cursorFollowing")
        XCTAssertEqual(movement["speed"] as? Double, 240)
        XCTAssertEqual(movement["cursorDistance"] as? Double, 120)
        XCTAssertEqual(movement["stopRadius"] as? Double, 20)
        XCTAssertEqual(movement["freeRoamingDwellMilliseconds"] as? Int, 9_000)
        XCTAssertEqual(movement["prefersFrontmostWindow"] as? Bool, false)
        XCTAssertEqual(movement["cursorFollowingMotionID"] as? String, "run")
        XCTAssertEqual(movement["freeRoamingMotionID"] as? String, "walk")
        let sequences = try XCTUnwrap(profiles.first?["sequences"] as? [[String: Any]])
        let steps = try XCTUnwrap(sequences.first?["steps"] as? [[String: Any]])
        XCTAssertEqual(steps.first?["repeatCount"] as? Int, 2)
        XCTAssertNil(steps.first?["durationMilliseconds"])

        let rules = try XCTUnwrap(profiles.first?["automaticRules"] as? [[String: Any]])
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
        let validSequence = StoredBehaviorSequenceV2(
            id: "focus-sequence",
            steps: [
                StoredBehaviorStepV2(
                    motionID: "",
                    repeatCount: 0
                ),
                StoredBehaviorStepV2(
                    motionID: "focus",
                    repeatCount: 5
                )
            ],
            repeats: true
        )
        let unknownRuleID = UUID()
        let missingSequenceRuleID = UUID()
        let stored = StoredAppSettingsV2(
            schemaVersion: 2,
            selectedPetInstallationID: "not-a-uuid",
            lastUserPresentation: "suspended",
            overlay: StoredOverlaySettings(
                screenIdentifier: "   ",
                originX: 10,
                originY: 20,
                width: 1_000,
                clickThrough: true
            ),
            behaviorProfiles: [
                StoredBehaviorProfileV2(
                    petKey: .builtIn,
                    mode: "future-mode",
                    manualSequenceID: "missing-sequence",
                    sequences: [
                        validSequence,
                        validSequence,
                        StoredBehaviorSequenceV2(
                            id: "empty",
                            steps: [],
                            repeats: true
                        )
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
        let originalData = Data(#"{"schemaVersion":4,"futureValue":true}"#.utf8)
        try originalData.write(to: settingsURL)
        let store = AppSettingsStore(settingsURL: settingsURL)

        let loaded = store.load()

        XCTAssertEqual(loaded.source, .newerSchema(4))
        XCTAssertEqual(loaded.issues, [.newerSchemaVersion(4)])
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

    func testV1LoadMigratesAndAtomicallyRewritesSettingsAsV3() throws {
        let stored = makeLegacySettings()
        try JSONEncoder().encode(stored).write(to: settingsURL)
        let store = AppSettingsStore(settingsURL: settingsURL)

        let loaded = store.load { _ in self.migrationPetDefinition }

        XCTAssertEqual(loaded.source, .file)
        XCTAssertTrue(loaded.isWritingEnabled)
        XCTAssertEqual(loaded.settings.sequences.first?.steps.first?.repeatCount, 3)
        let migratedData = try Data(contentsOf: settingsURL)
        let envelope = try JSONDecoder().decode(
            StoredSchemaEnvelope.self,
            from: migratedData
        )
        XCTAssertEqual(envelope.schemaVersion, 3)
        XCTAssertNoThrow(
            try JSONDecoder().decode(StoredAppSettingsV3.self, from: migratedData)
        )
        XCTAssertEqual(loaded.settings.movementSettings, .default)
        let children = try FileManager.default.contentsOfDirectory(
            at: temporaryDirectoryURL,
            includingPropertiesForKeys: nil
        )
        XCTAssertEqual(children.map(\.lastPathComponent), ["settings.json"])
    }

    func testV2LoadAddsDefaultMovementAndAtomicallyRewritesAsV3() throws {
        let profile = StoredBehaviorProfileV2(
            petKey: .builtIn,
            mode: "manual",
            manualSequenceID: "default",
            sequences: [
                StoredBehaviorSequenceV2(
                    id: "default",
                    steps: [StoredBehaviorStepV2(motionID: "idle", repeatCount: 1)],
                    repeats: true
                )
            ],
            automaticRules: []
        )
        let stored = StoredAppSettingsV2(
            schemaVersion: 2,
            selectedPetInstallationID: nil,
            lastUserPresentation: "awake",
            overlay: StoredOverlaySettings(
                screenIdentifier: nil,
                originX: 0,
                originY: 0,
                width: 192,
                clickThrough: false
            ),
            behaviorProfiles: [profile]
        )
        try JSONEncoder().encode(stored).write(to: settingsURL)

        let loaded = AppSettingsStore(settingsURL: settingsURL).load()

        XCTAssertEqual(loaded.source, .file)
        XCTAssertEqual(loaded.settings.movementSettings, .default)
        let migrated = try JSONDecoder().decode(
            StoredAppSettingsV3.self,
            from: Data(contentsOf: settingsURL)
        )
        XCTAssertEqual(migrated.schemaVersion, 3)
        XCTAssertEqual(migrated.behaviorProfiles.first?.movement.mode, "fixed")
    }

    func testV1LoadWithoutSelectedPetDefinitionPreservesOriginalFile() throws {
        let originalData = try JSONEncoder().encode(makeLegacySettings())
        try originalData.write(to: settingsURL)
        let store = AppSettingsStore(settingsURL: settingsURL)

        let unavailable = store.load()

        XCTAssertEqual(unavailable.source, .recovered)
        XCTAssertFalse(unavailable.isWritingEnabled)
        XCTAssertEqual(try Data(contentsOf: settingsURL), originalData)

        let migrated = store.load { _ in self.migrationPetDefinition }
        XCTAssertTrue(migrated.isWritingEnabled)
        XCTAssertEqual(migrated.settings.sequences.first?.steps.first?.repeatCount, 3)
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
                    repeatCount: 2
                )
            ],
            repeats: true
        )
        let focusSequence = BehaviorSequence(
            id: "focus-sequence",
            steps: [
                BehaviorStep(
                    motionID: "focus",
                    repeatCount: 30
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
            movement: PetMovementSettings(
                mode: .cursorFollowing,
                speed: 240,
                cursorDistance: 120,
                stopRadius: 20,
                freeRoamingDwellMilliseconds: 9_000,
                prefersFrontmostWindow: false,
                cursorFollowingMotionID: "run",
                freeRoamingMotionID: "walk"
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

    private func makeLegacySettings() -> StoredAppSettings {
        StoredAppSettings(
            schemaVersion: 1,
            selectedPetInstallationID: nil,
            lastUserPresentation: "awake",
            behaviorMode: "manual",
            overlay: StoredOverlaySettings(
                screenIdentifier: nil,
                originX: 0,
                originY: 0,
                width: 192,
                clickThrough: false
            ),
            manualSequenceID: "legacy-custom",
            sequences: [
                StoredBehaviorSequence(
                    id: "legacy-custom",
                    steps: [
                        StoredBehaviorStep(
                            motionID: "idle",
                            durationMilliseconds: 3_000,
                            playbackSpeed: 1
                        )
                    ],
                    repeats: true
                )
            ],
            automaticRules: []
        )
    }

    private var migrationPetDefinition: PetDefinition {
        PetDefinition(
            id: "migration.pet",
            displayName: "Migration Pet",
            defaultMotionID: "idle",
            motions: [
                PetMotion(
                    id: "idle",
                    loops: true,
                    frames: [
                        MotionFrame(
                            atlasID: "main",
                            sourceRect: PixelRect(x: 0, y: 0, width: 10, height: 10),
                            duration: .seconds(1)
                        )
                    ]
                )
            ]
        )
    }
}
