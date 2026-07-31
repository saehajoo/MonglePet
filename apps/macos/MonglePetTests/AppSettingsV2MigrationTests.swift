import Foundation
import XCTest
@testable import MonglePet

final class AppSettingsV2MigrationTests: XCTestCase {
    func testV2MapperRoundTripsMultiplePetProfilesWithoutChangingOrder() throws {
        let installedID = UUID(
            uuidString: "40000000-0000-0000-0000-000000000001"
        )!
        let builtInProfile = BehaviorProfile(
            petKey: .builtIn,
            mode: .manual,
            manualSequenceID: "built-in-custom",
            sequences: [
                BehaviorSequence(
                    id: "built-in-custom",
                    steps: [BehaviorStep(motionID: "wave", repeatCount: 3)],
                    repeats: true
                )
            ],
            automaticRules: []
        )
        let installedProfile = BehaviorProfile(
            petKey: .installed(installedID),
            mode: .automatic,
            manualSequenceID: "installed-custom",
            sequences: [
                BehaviorSequence(
                    id: "installed-custom",
                    steps: [BehaviorStep(motionID: "coding", repeatCount: 7)],
                    repeats: false
                )
            ],
            automaticRules: []
        )
        let settings = AppSettings(
            selectedPetInstallationID: installedID,
            lastUserPresentation: .awake,
            overlay: .default,
            behaviorProfiles: [builtInProfile, installedProfile]
        )

        let stored = try AppSettingsV2Mapper.storedSettings(from: settings)
        let mapped = AppSettingsV2Mapper.domainSettings(from: stored)

        XCTAssertEqual(stored.schemaVersion, 2)
        XCTAssertEqual(mapped.settings, settings)
        XCTAssertTrue(mapped.issues.isEmpty)
        XCTAssertEqual(mapped.settings.behaviorProfiles.map(\.petKey), [
            .builtIn,
            .installed(installedID)
        ])
    }

    func testV2MapperDropsInvalidAndDuplicateProfileKeysIndependently() {
        let installedID = UUID(
            uuidString: "40000000-0000-0000-0000-000000000002"
        )!
        let sequence = StoredBehaviorSequenceV2(
            id: "default",
            steps: [StoredBehaviorStepV2(motionID: "idle", repeatCount: 1)],
            repeats: true
        )
        let profile = { (key: StoredPetBehaviorKeyV2) in
            StoredBehaviorProfileV2(
                petKey: key,
                mode: "automatic",
                manualSequenceID: "default",
                sequences: [sequence],
                automaticRules: []
            )
        }
        let stored = StoredAppSettingsV2(
            schemaVersion: 2,
            selectedPetInstallationID: installedID.uuidString,
            lastUserPresentation: "awake",
            overlay: StoredOverlaySettings(
                screenIdentifier: nil,
                originX: 0,
                originY: 0,
                width: 192,
                clickThrough: false
            ),
            behaviorProfiles: [
                profile(.installed(installationID: "invalid")),
                profile(.builtIn),
                profile(.builtIn),
                profile(.installed(installationID: installedID.uuidString))
            ]
        )

        let mapped = AppSettingsV2Mapper.domainSettings(from: stored)

        XCTAssertEqual(mapped.settings.behaviorProfiles.map(\.petKey), [
            .builtIn,
            .installed(installedID)
        ])
        XCTAssertEqual(
            mapped.issues.filter { $0 == .invalidField("behaviorProfiles.0.petKey") }.count,
            1
        )
        XCTAssertEqual(
            mapped.issues.filter { $0 == .invalidField("behaviorProfiles.2.petKey") }.count,
            1
        )
    }

    func testMigratesV1FixtureIntoSelectedInstalledProfileUsingMotionCycles() throws {
        let decoder = JSONDecoder()
        let source = try decoder.decode(
            StoredAppSettings.self,
            from: fixtureData(named: "settings-v1-migration")
        )
        let expected = try decoder.decode(
            StoredAppSettingsV2.self,
            from: fixtureData(named: "settings-v2-migrated")
        )

        let migrated = try AppSettingsV1ToV2Migrator.migrate(
            source,
            selectedPetDefinition: petDefinition
        )

        XCTAssertEqual(migrated.settings, expected)
        XCTAssertEqual(
            migrated.issues,
            [.invalidField("behaviorProfiles.0.sequences.0.steps.2.motionID")]
        )
    }

    func testMigrationUsesBuiltInKeyAndAtLeastOneRepeat() throws {
        let stored = StoredAppSettings(
            schemaVersion: 1,
            selectedPetInstallationID: nil,
            lastUserPresentation: "awake",
            behaviorMode: "automatic",
            overlay: .init(
                screenIdentifier: nil,
                originX: 0,
                originY: 0,
                width: 192,
                clickThrough: false
            ),
            manualSequenceID: "short",
            sequences: [
                StoredBehaviorSequence(
                    id: "short",
                    steps: [
                        StoredBehaviorStep(
                            motionID: "focus",
                            durationMilliseconds: 100,
                            playbackSpeed: 2
                        )
                    ],
                    repeats: true
                )
            ],
            automaticRules: []
        )

        let migrated = try AppSettingsV1ToV2Migrator.migrate(
            stored,
            selectedPetDefinition: petDefinition
        )

        XCTAssertEqual(migrated.settings.behaviorProfiles.first?.petKey, .builtIn)
        XCTAssertEqual(
            migrated.settings.behaviorProfiles.first?.sequences.first?.steps.first,
            StoredBehaviorStepV2(motionID: "focus", repeatCount: 1)
        )
        XCTAssertTrue(migrated.issues.isEmpty)
    }

    func testPetBehaviorKeyUsesExplicitDiscriminatorAndRejectsUnknownType() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let decoder = JSONDecoder()

        XCTAssertEqual(
            String(decoding: try encoder.encode(StoredPetBehaviorKeyV2.builtIn), as: UTF8.self),
            #"{"type":"builtIn"}"#
        )
        XCTAssertEqual(
            try decoder.decode(
                StoredPetBehaviorKeyV2.self,
                from: Data(#"{"type":"installed","installationID":"test-id"}"#.utf8)
            ),
            .installed(installationID: "test-id")
        )
        XCTAssertThrowsError(
            try decoder.decode(
                StoredPetBehaviorKeyV2.self,
                from: Data(#"{"type":"future"}"#.utf8)
            )
        )
    }

    func testMigrationRejectsSourceOtherThanSchemaV1() {
        let stored = StoredAppSettings(
            schemaVersion: 2,
            selectedPetInstallationID: nil,
            lastUserPresentation: "awake",
            behaviorMode: "automatic",
            overlay: .init(
                screenIdentifier: nil,
                originX: 0,
                originY: 0,
                width: 192,
                clickThrough: false
            ),
            manualSequenceID: nil,
            sequences: [],
            automaticRules: []
        )

        XCTAssertThrowsError(
            try AppSettingsV1ToV2Migrator.migrate(
                stored,
                selectedPetDefinition: petDefinition
            )
        ) { error in
            XCTAssertEqual(
                error as? AppSettingsV1ToV2MigrationError,
                .unsupportedSourceSchema(2)
            )
        }
    }

    private var petDefinition: PetDefinition {
        let frameRect = PixelRect(x: 0, y: 0, width: 10, height: 10)
        return PetDefinition(
            id: "test.pet",
            displayName: "테스트 펫",
            defaultMotionID: "idle",
            motions: [
                PetMotion(
                    id: "idle",
                    loops: true,
                    frames: [
                        MotionFrame(
                            atlasID: "main",
                            sourceRect: frameRect,
                            duration: .milliseconds(600)
                        )
                    ]
                ),
                PetMotion(
                    id: "focus",
                    loops: true,
                    frames: [
                        MotionFrame(
                            atlasID: "main",
                            sourceRect: frameRect,
                            duration: .milliseconds(400)
                        ),
                        MotionFrame(
                            atlasID: "main",
                            sourceRect: frameRect,
                            duration: .milliseconds(600)
                        )
                    ]
                )
            ]
        )
    }

    private func fixtureData(named name: String) throws -> Data {
        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/Settings/\(name).json")
        return try Data(contentsOf: fixtureURL)
    }
}
