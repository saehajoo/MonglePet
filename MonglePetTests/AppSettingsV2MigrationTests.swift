import Foundation
import XCTest
@testable import MonglePet

final class AppSettingsV2MigrationTests: XCTestCase {
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
