import Foundation
import XCTest
@testable import MonglePet

final class AppSettingsV11MigrationTests: XCTestCase {
    func testV10MigrationCreatesOneIndependentSelectedInstance() throws {
        let installationID = UUID(
            uuidString: "11111111-1111-1111-1111-111111111111"
        )!
        let instanceID = UUID(
            uuidString: "22222222-2222-2222-2222-222222222222"
        )!
        let selectedProfileID = UUID(
            uuidString: "33333333-3333-3333-3333-333333333333"
        )!
        let retainedProfileID = UUID(
            uuidString: "44444444-4444-4444-4444-444444444444"
        )!
        var generatedIDs = [
            instanceID,
            retainedProfileID,
            selectedProfileID
        ].makeIterator()
        let storedV10 = try makeStoredV10(
            selectedPetInstallationID: installationID,
            includeSelectedProfile: true
        )

        let migrated = try AppSettingsV10ToV11Migrator.migrate(
            storedV10,
            idGenerator: { generatedIDs.next()! }
        )
        let instance = try XCTUnwrap(
            migrated.settings.activePetInstances.first
        )

        XCTAssertEqual(migrated.settings.schemaVersion, 11)
        XCTAssertEqual(
            migrated.settings.selectedPetInstanceID,
            instanceID.uuidString
        )
        XCTAssertEqual(instance.instanceID, instanceID.uuidString)
        XCTAssertEqual(
            instance.petKey,
            .installed(installationID: installationID.uuidString)
        )
        XCTAssertNil(instance.nickname)
        XCTAssertEqual(instance.presentation, "tuckedAway")
        XCTAssertEqual(instance.overlay, storedV10.overlay)
        XCTAssertEqual(instance.behaviorProfileID, selectedProfileID.uuidString)
        XCTAssertEqual(instance.displayOrder, 0)
        XCTAssertEqual(migrated.settings.behaviorProfiles.count, 2)
        XCTAssertEqual(
            migrated.settings.behaviorProfiles.map(\.profileID),
            [retainedProfileID.uuidString, selectedProfileID.uuidString]
        )
        XCTAssertTrue(migrated.issues.isEmpty)
    }

    func testV10MigrationRetainsUnselectedProfilesAndCreatesMissingDefault()
        throws
    {
        let installationID = UUID(
            uuidString: "11111111-1111-1111-1111-111111111111"
        )!
        let instanceID = UUID(
            uuidString: "22222222-2222-2222-2222-222222222222"
        )!
        let retainedProfileID = UUID(
            uuidString: "33333333-3333-3333-3333-333333333333"
        )!
        let newProfileID = UUID(
            uuidString: "44444444-4444-4444-4444-444444444444"
        )!
        var generatedIDs = [
            instanceID,
            retainedProfileID,
            newProfileID
        ].makeIterator()
        let storedV10 = try makeStoredV10(
            selectedPetInstallationID: installationID,
            includeSelectedProfile: false
        )

        let migrated = try AppSettingsV10ToV11Migrator.migrate(
            storedV10,
            idGenerator: { generatedIDs.next()! }
        )
        let instance = try XCTUnwrap(
            migrated.settings.activePetInstances.first
        )
        let defaultProfile = try XCTUnwrap(
            migrated.settings.behaviorProfiles.last
        )

        XCTAssertEqual(migrated.settings.behaviorProfiles.count, 2)
        XCTAssertEqual(instance.behaviorProfileID, newProfileID.uuidString)
        XCTAssertEqual(defaultProfile.profileID, newProfileID.uuidString)
        XCTAssertEqual(
            defaultProfile.petKey,
            .installed(installationID: installationID.uuidString)
        )
        XCTAssertEqual(
            defaultProfile.manualSequenceID,
            BuiltInBehaviorPresets.defaultSequenceID
        )
        XCTAssertEqual(defaultProfile.sequences.count, 1)
    }

    func testV11DocumentRoundTripsStableInstanceAndProfileIDs() throws {
        let storedV10 = try makeStoredV10(
            selectedPetInstallationID: nil,
            includeSelectedProfile: true
        )
        let identifiers = [
            UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
        ]
        var generatedIDs = identifiers.makeIterator()
        let migrated = try AppSettingsV10ToV11Migrator.migrate(
            storedV10,
            idGenerator: { generatedIDs.next()! }
        )

        let data = try JSONEncoder().encode(migrated.settings)
        let decoded = try JSONDecoder().decode(
            StoredAppSettingsV11.self,
            from: data
        )

        XCTAssertEqual(decoded, migrated.settings)
        XCTAssertEqual(
            decoded.activePetInstances.first?.behaviorProfileID,
            decoded.behaviorProfiles.first(where: {
                $0.petKey == .builtIn
            })?.profileID
        )
    }

    func testRejectsNonV10Source() throws {
        let stored = try makeStoredV10(
            selectedPetInstallationID: nil,
            includeSelectedProfile: true
        )
        let invalid = StoredAppSettingsV10(
            schemaVersion: 9,
            selectedPetInstallationID: stored.selectedPetInstallationID,
            lastUserPresentation: stored.lastUserPresentation,
            overlay: stored.overlay,
            behaviorProfiles: stored.behaviorProfiles
        )

        XCTAssertThrowsError(
            try AppSettingsV10ToV11Migrator.migrate(invalid)
        ) { error in
            XCTAssertEqual(
                error as? AppSettingsV10ToV11MigrationError,
                .unsupportedSourceSchema(9)
            )
        }
    }

    private func makeStoredV10(
        selectedPetInstallationID: UUID?,
        includeSelectedProfile: Bool
    ) throws -> StoredAppSettingsV10 {
        let selectedKey = PetBehaviorKey(
            installationID: selectedPetInstallationID
        )
        let otherInstallationID = UUID(
            uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"
        )!
        let sequence = BehaviorSequence(
            id: "default",
            steps: [BehaviorStep(motionID: "idle", repeatCount: 1)],
            repeats: true
        )
        var profiles = [
            BehaviorProfile(
                petKey: .installed(otherInstallationID),
                mode: .automatic,
                manualSequenceID: sequence.id,
                sequences: [sequence],
                automaticRules: []
            )
        ]
        if includeSelectedProfile {
            profiles.append(
                BehaviorProfile(
                    petKey: selectedKey,
                    mode: .manual,
                    manualSequenceID: sequence.id,
                    sequences: [sequence],
                    automaticRules: []
                )
            )
        }
        return try AppSettingsV10Mapper.storedSettings(
            from: AppSettings(
                selectedPetInstallationID: selectedPetInstallationID,
                lastUserPresentation: .tuckedAway,
                overlay: OverlaySettings(
                    screenIdentifier: "display-1",
                    originX: 120,
                    originY: 80,
                    width: 240,
                    clickThrough: true
                ),
                behaviorProfiles: profiles
            )
        )
    }
}
