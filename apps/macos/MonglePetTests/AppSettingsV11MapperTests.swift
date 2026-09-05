import Foundation
import XCTest
@testable import MonglePet

final class AppSettingsV11MapperTests: XCTestCase {
    func testValidSharedFixtureRoundTripsWithoutChangingIdentifiers() throws {
        let stored = try expectedFixture()

        let mapped = AppSettingsV11Mapper.domainSettings(from: stored)
        let encoded = try AppSettingsV11Mapper.storedSettings(
            from: mapped.settings
        )

        XCTAssertTrue(mapped.issues.isEmpty)
        XCTAssertEqual(encoded, stored)
    }

    func testTwoInstancesKeepIndependentProfileAndOverlayChanges() throws {
        let original = try AppSettingsV11Mapper.domainSettings(
            from: expectedFixture()
        ).settings
        let firstInstance = try XCTUnwrap(original.selectedPetInstance)
        let firstRecord = try XCTUnwrap(
            original.petBehaviorProfiles.first {
                $0.profileID == firstInstance.behaviorProfileID
            }
        )
        let secondInstanceID = UUID(
            uuidString: "44444444-4444-4444-4444-444444444444"
        )!
        let secondProfileID = UUID(
            uuidString: "55555555-5555-5555-5555-555555555555"
        )!
        let secondOverlay = OverlaySettings(
            screenIdentifier: "secondary-display",
            originX: -600,
            originY: 80,
            width: 256,
            clickThrough: true,
            opacity: 0.65,
            pointerOverlapFadeEnabled: true,
            pointerOverlapOpacity: 0.15,
            pixelArtRendering: true,
            movementBoundary: .default
        )
        let settings = AppSettings(
            selectedPetInstanceID: firstInstance.instanceID,
            activePetInstances: [
                firstInstance,
                PetInstanceSettings(
                    instanceID: secondInstanceID,
                    petKey: firstInstance.petKey,
                    nickname: "두 번째",
                    presentation: .tuckedAway,
                    overlay: secondOverlay,
                    behaviorProfileID: secondProfileID,
                    displayOrder: 1
                )
            ],
            petBehaviorProfiles: [
                firstRecord,
                PetBehaviorProfileSettings(
                    profileID: secondProfileID,
                    profile: firstRecord.profile
                )
            ]
        )

        let selectedOverlay = OverlaySettings(
            screenIdentifier: "primary-display",
            originX: 120,
            originY: 90,
            width: 300,
            clickThrough: false,
            opacity: 0.9,
            pointerOverlapFadeEnabled: false,
            pointerOverlapOpacity: 0.2,
            pixelArtRendering: false,
            movementBoundary: .default
        )
        let selectedProfile = BehaviorProfile(
            petKey: firstRecord.profile.petKey,
            mode: .manual,
            manualSequenceID: "selected",
            sequences: firstRecord.profile.sequences + [
                BehaviorSequence(
                    id: "selected",
                    steps: [
                        BehaviorStep(
                            motionID: "selected",
                            repeatCount: 1
                        )
                    ],
                    repeats: true
                )
            ],
            automaticRules: firstRecord.profile.automaticRules,
            movement: firstRecord.profile.movement,
            pettingMotionID: firstRecord.profile.pettingMotionID,
            speech: firstRecord.profile.speech
        )
        let edited = settings
            .replacingSelectedOverlay(selectedOverlay)
            .replacingActiveBehaviorProfile(selectedProfile)

        let stored = try AppSettingsV11Mapper.storedSettings(from: edited)
        let reloaded = AppSettingsV11Mapper.domainSettings(from: stored)

        XCTAssertTrue(reloaded.issues.isEmpty)
        XCTAssertEqual(reloaded.settings, edited)
        XCTAssertEqual(
            reloaded.settings.activePetInstances[0].overlay,
            selectedOverlay
        )
        XCTAssertEqual(
            reloaded.settings.activePetInstances[1].overlay,
            secondOverlay
        )
        XCTAssertNotEqual(
            reloaded.settings.activePetInstances[0].behaviorProfileID,
            reloaded.settings.activePetInstances[1].behaviorProfileID
        )
        XCTAssertEqual(
            reloaded.settings.activeBehaviorProfile?.mode,
            .manual
        )
        XCTAssertEqual(
            reloaded.settings.petBehaviorProfiles.first {
                $0.profileID == secondProfileID
            }?.profile.mode,
            firstRecord.profile.mode
        )
    }

    func testInvalidInstanceFieldsRecoverWithoutDroppingOtherInstance() throws {
        let fixture = try expectedFixture()
        let first = try XCTUnwrap(fixture.activePetInstances.first)
        let recoveredInstanceID = UUID(
            uuidString: "66666666-6666-6666-6666-666666666666"
        )!
        let recoveredProfileID = UUID(
            uuidString: "77777777-7777-7777-7777-777777777777"
        )!
        var generated = [recoveredInstanceID, recoveredProfileID]
            .makeIterator()
        let invalidOverlay = StoredOverlaySettingsV4(
            screenIdentifier: first.overlay.screenIdentifier,
            originX: first.overlay.originX,
            originY: first.overlay.originY,
            width: 9_999,
            clickThrough: first.overlay.clickThrough,
            opacity: first.overlay.opacity,
            pointerOverlapFadeEnabled:
                first.overlay.pointerOverlapFadeEnabled,
            pointerOverlapOpacity: first.overlay.pointerOverlapOpacity,
            pixelArtRendering: first.overlay.pixelArtRendering,
            movementBoundary: first.overlay.movementBoundary
        )
        let invalidSecond = StoredPetInstanceV11(
            instanceID: first.instanceID,
            petKey: first.petKey,
            nickname: "  두 번째  ",
            presentation: "suspended",
            overlay: invalidOverlay,
            behaviorProfileID: first.behaviorProfileID,
            displayOrder: first.displayOrder
        )
        let stored = StoredAppSettingsV11(
            schemaVersion: 11,
            selectedPetInstanceID: first.instanceID,
            activePetInstances: [first, invalidSecond],
            behaviorProfiles: fixture.behaviorProfiles
        )

        let mapped = AppSettingsV11Mapper.domainSettings(
            from: stored,
            idGenerator: { generated.next()! }
        )

        XCTAssertEqual(mapped.settings.activePetInstances.count, 2)
        XCTAssertEqual(
            mapped.settings.activePetInstances.map(\.displayOrder),
            [0, 1]
        )
        XCTAssertEqual(
            mapped.settings.activePetInstances[1].instanceID,
            recoveredInstanceID
        )
        XCTAssertEqual(mapped.settings.activePetInstances[1].nickname, "두 번째")
        XCTAssertEqual(mapped.settings.activePetInstances[1].presentation, .awake)
        XCTAssertEqual(
            mapped.settings.activePetInstances[1].overlay.width,
            AppSettingsLimits.maximumOverlayWidth
        )
        XCTAssertEqual(
            mapped.settings.activePetInstances[1].behaviorProfileID,
            recoveredProfileID
        )
        XCTAssertNotEqual(
            mapped.settings.activePetInstances[0].behaviorProfileID,
            mapped.settings.activePetInstances[1].behaviorProfileID
        )
        XCTAssertTrue(mapped.issues.contains(
            .invalidField("activePetInstances.1.instanceID")
        ))
        XCTAssertTrue(mapped.issues.contains(
            .invalidField("activePetInstances.1.behaviorProfileID")
        ))
        XCTAssertTrue(mapped.issues.contains(
            .invalidField("activePetInstances.1.presentation")
        ))
        XCTAssertTrue(mapped.issues.contains(
            .invalidField("activePetInstances.1.overlay.width")
        ))
    }

    func testStoreMigratesV10OnceAndKeepsGeneratedIDsStable() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let settingsURL = directory.appendingPathComponent("settings.json")
        let v10 = try JSONDecoder().decode(
            StoredAppSettingsV10.self,
            from: Data(contentsOf: fixtureURL("schema-v10-single-pet.json"))
        )
        try JSONEncoder().encode(v10).write(to: settingsURL)
        let store = AppSettingsStore(settingsURL: settingsURL)

        let migrated = store.load()
        let reloaded = store.load()
        let envelope = try JSONDecoder().decode(
            StoredSchemaEnvelope.self,
            from: Data(contentsOf: settingsURL)
        )

        XCTAssertEqual(envelope.schemaVersion, 16)
        XCTAssertEqual(migrated.source, .file)
        XCTAssertEqual(reloaded.source, .file)
        XCTAssertEqual(reloaded.settings, migrated.settings)
        XCTAssertEqual(
            reloaded.settings.selectedPetInstanceID,
            migrated.settings.selectedPetInstanceID
        )
        XCTAssertEqual(
            reloaded.settings.petBehaviorProfiles.map(\.profileID),
            migrated.settings.petBehaviorProfiles.map(\.profileID)
        )
    }

    private func expectedFixture() throws -> StoredAppSettingsV11 {
        try JSONDecoder().decode(
            StoredAppSettingsV11.self,
            from: Data(
                contentsOf: fixtureURL(
                    "schema-v11-single-instance.expected.json"
                )
            )
        )
    }

    private func fixtureURL(_ fileName: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("shared", isDirectory: true)
            .appendingPathComponent("Fixtures", isDirectory: true)
            .appendingPathComponent("Settings", isDirectory: true)
            .appendingPathComponent(fileName, isDirectory: false)
    }
}
