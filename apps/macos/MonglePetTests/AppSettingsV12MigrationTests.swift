import XCTest
@testable import MonglePet

final class AppSettingsV12MigrationTests: XCTestCase {
    func testV11PromotesMovementAndPettingMotionsToReusableBehaviors() throws {
        let legacy = try XCTUnwrap(
            JSONDecoder().decode(
                StoredAppSettingsV11.self,
                from: Data(legacyJSON.utf8)
            )
        )
        let migrated = try AppSettingsV11ToV12Migrator.migrate(legacy)
        let profile = try XCTUnwrap(migrated.settings.behaviorProfiles.first)

        let walkID = try XCTUnwrap(
            profile.movement.cursorFollowingBehavior.fallbackBehaviorID
        )
        XCTAssertEqual(
            profile.sequences.first(where: { $0.id == walkID })?.steps.first?.motionID,
            "walk"
        )
        XCTAssertEqual(profile.pettingBehaviorID, walkID)
        XCTAssertEqual(profile.sequences.first?.displayName, "기본")
        XCTAssertEqual(profile.automaticRules.count, 2)
        XCTAssertEqual(
            profile.automaticRulePriorityOrder,
            ["movement", "idle", "application"]
        )
    }

    func testEarlyV12PriorityListRestoresMovementAsHighestDefault() throws {
        let legacy = try JSONDecoder().decode(
            StoredAppSettingsV11.self,
            from: Data(legacyJSON.utf8)
        )
        let migrated = try AppSettingsV11ToV12Migrator.migrate(legacy).settings
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: JSONEncoder().encode(migrated)
            ) as? [String: Any]
        )
        var profiles = try XCTUnwrap(
            object["behaviorProfiles"] as? [[String: Any]]
        )
        profiles[0]["automaticRulePriorityOrder"] = ["application", "idle"]
        object["behaviorProfiles"] = profiles
        let stored = try JSONDecoder().decode(
            StoredAppSettingsV12.self,
            from: JSONSerialization.data(withJSONObject: object)
        )

        let mapped = AppSettingsV12Mapper.domainSettings(from: stored)

        XCTAssertEqual(
            mapped.settings.automaticRulePriorityOrder,
            [.movement, .application, .idle]
        )
    }

    func testV12MigrationAddsSafeRandomDefaultsAndV13RoundTripsThem() throws {
        let legacy = try JSONDecoder().decode(
            StoredAppSettingsV11.self,
            from: Data(legacyJSON.utf8)
        )
        let v12 = try AppSettingsV11ToV12Migrator.migrate(legacy).settings
        let v13 = try AppSettingsV12ToV13Migrator.migrate(v12)
        let storedProfile = try XCTUnwrap(v13.behaviorProfiles.first)

        XCTAssertEqual(v13.schemaVersion, 13)
        XCTAssertEqual(storedProfile.randomSequenceIDs, [])
        XCTAssertFalse(storedProfile.movement.randomizesFreeRoamingDwell)
        XCTAssertEqual(
            storedProfile.movement.freeRoamingDwellMinimumMilliseconds,
            1_500
        )

        let mapped = AppSettingsV13Mapper.domainSettings(from: v13).settings
        let sequenceID = try XCTUnwrap(mapped.sequences.first?.id)
        let movement = mapped.movementSettings
        let customized = mapped.replacingActiveBehaviorProfile(
            BehaviorProfile(
                petKey: mapped.selectedPetKey,
                mode: .random,
                manualSequenceID: mapped.manualSequenceID,
                randomSequenceIDs: [sequenceID],
                sequences: mapped.sequences,
                automaticRules: mapped.automaticRules,
                automaticRulePriorityOrder:
                    mapped.automaticRulePriorityOrder,
                movement: PetMovementSettings(
                    mode: movement.mode,
                    speed: movement.speed,
                    cursorDistance: movement.cursorDistance,
                    stopRadius: movement.stopRadius,
                    freeRoamingDwellMilliseconds: 3_000,
                    prefersFrontmostWindow:
                        movement.prefersFrontmostWindow,
                    cursorFollowingAnimation:
                        movement.cursorFollowingAnimation,
                    freeRoamingAnimation:
                        movement.freeRoamingAnimation,
                    cursorAvoidingIdleBehavior:
                        movement.cursorAvoidingIdleBehavior,
                    cursorAvoidingDetectionDistance:
                        movement.cursorAvoidingDetectionDistance,
                    cursorAvoidingSpeed: movement.cursorAvoidingSpeed,
                    cursorAvoidingAnimation:
                        movement.cursorAvoidingAnimation,
                    randomizesFreeRoamingDwell: true,
                    freeRoamingDwellMinimumMilliseconds: 1_000
                ),
                pettingMotionID: mapped.pettingMotionID,
                speech: mapped.speechSettings
            )
        )
        let roundTrip = AppSettingsV13Mapper.domainSettings(
            from: try AppSettingsV13Mapper.storedSettings(from: customized)
        ).settings

        XCTAssertEqual(roundTrip.behaviorMode, .random)
        XCTAssertEqual(roundTrip.randomSequenceIDs, [sequenceID])
        XCTAssertTrue(
            roundTrip.movementSettings.randomizesFreeRoamingDwell
        )
        XCTAssertEqual(
            roundTrip.movementSettings.freeRoamingDwellMinimumMilliseconds,
            1_000
        )
    }

    func testSharedV13RandomFixtureRoundTrips() throws {
        let stored = try JSONDecoder().decode(
            StoredAppSettingsV13.self,
            from: Data(contentsOf: fixtureURL("schema-v13-random-behaviors.json"))
        )
        let mapped = AppSettingsV13Mapper.domainSettings(from: stored)

        XCTAssertTrue(mapped.issues.isEmpty)
        XCTAssertEqual(mapped.settings.behaviorMode, .random)
        XCTAssertEqual(
            mapped.settings.randomSequenceIDs,
            [BuiltInBehaviorPresets.defaultSequenceID, "walk"]
        )
        XCTAssertTrue(
            mapped.settings.movementSettings.randomizesFreeRoamingDwell
        )
        XCTAssertEqual(
            mapped.settings.movementSettings
                .freeRoamingDwellMinimumMilliseconds,
            2_000
        )

        let encoded = try AppSettingsV13Mapper.storedSettings(
            from: mapped.settings
        )
        XCTAssertEqual(encoded.behaviorProfiles.first?.mode, "random")
        XCTAssertEqual(
            encoded.behaviorProfiles.first?.randomSequenceIDs,
            [BuiltInBehaviorPresets.defaultSequenceID, "walk"]
        )
    }

    private func fixtureURL(_ fileName: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("shared/Fixtures/Settings")
            .appendingPathComponent(fileName)
    }

    private var legacyJSON: String {
        """
        {
          "schemaVersion": 11,
          "selectedPetInstanceID": "10000000-0000-0000-0000-000000000001",
          "activePetInstances": [{
            "instanceID": "10000000-0000-0000-0000-000000000001",
            "petKey": { "type": "builtIn" },
            "behaviorProfileID": "20000000-0000-0000-0000-000000000001",
            "displayOrder": 0,
            "nickname": null,
            "presentation": "awake",
            "overlay": { "screenIdentifier": null, "originX": 0, "originY": 0, "width": 160, "clickThrough": false, "opacity": 1, "pointerOverlapFadeEnabled": false, "pointerOverlapOpacity": 0.25, "pixelArtRendering": null, "movementBoundary": { "mode": "allDisplays", "screenIdentifier": null, "normalizedRect": null } }
          }],
          "behaviorProfiles": [{
            "profileID": "20000000-0000-0000-0000-000000000001",
            "petKey": { "type": "builtIn" },
            "mode": "automatic",
            "manualSequenceID": "__monglepet_default_behavior__",
            "sequences": [{ "id": "__monglepet_default_behavior__", "steps": [{ "motionID": "idle", "repeatCount": 1 }], "repeats": true }],
            "automaticRules": [
              { "id": "30000000-0000-0000-0000-000000000001", "isEnabled": true, "priority": 20, "condition": { "type": "idleAtLeast", "milliseconds": 60000 }, "sequenceID": "__monglepet_default_behavior__" },
              { "id": "30000000-0000-0000-0000-000000000002", "isEnabled": true, "priority": 10, "condition": { "type": "application", "bundleIdentifier": "com.example.app" }, "sequenceID": "__monglepet_default_behavior__" }
            ],
            "movement": {
              "mode": "cursorFollowing", "speed": 120, "cursorDistance": 64, "stopRadius": 12, "freeRoamingDwellMilliseconds": 3000, "prefersFrontmostWindow": true,
              "cursorFollowingAnimation": { "fallbackMotionID": "walk", "usesDirectionalMotions": false, "usesDiagonalMotions": false, "directionMotionIDs": {} },
              "freeRoamingAnimation": { "fallbackMotionID": null, "usesDirectionalMotions": false, "usesDiagonalMotions": false, "directionMotionIDs": {} },
              "cursorAvoidingIdleBehavior": "stationary", "cursorAvoidingDetectionDistance": 160, "cursorAvoidingSpeed": 320,
              "cursorAvoidingAnimation": { "fallbackMotionID": null, "usesDirectionalMotions": false, "usesDiagonalMotions": false, "directionMotionIDs": {} }
            },
            "pettingMotionID": "walk",
            "speech": { "isEnabled": false, "periodicIsEnabled": false, "periodicIntervalMilliseconds": 30000, "periodicOrder": "random", "behaviorChangePolicy": "dismiss", "phrases": [], "theme": { "colorStyle": "system", "customBackgroundColor": { "red": 1, "green": 1, "blue": 1 }, "customTextColor": { "red": 0, "green": 0, "blue": 0 }, "backgroundOpacity": 0.94, "fontSize": 13, "contentPadding": 10, "cornerRadius": 12, "showsTail": true, "tailAlignment": "center" }, "placement": { "preferredPosition": "automatic", "horizontalOffset": 0, "gap": 8 } }
          }]
        }
        """
    }
}
