import XCTest
@testable import MonglePet

final class AppSettingsV14MigrationTests: XCTestCase {
    func testV13MigrationSeedsEveryIndependentMovementMode() throws {
        let settings = makeSettings(movement: PetMovementSettings(
            mode: .cursorAvoiding,
            speed: 210,
            cursorDistance: 144,
            stopRadius: 28,
            freeRoamingDwellMilliseconds: 12_000,
            prefersFrontmostWindow: false,
            cursorFollowingAnimation: .single("follow"),
            freeRoamingAnimation: .single("roam"),
            cursorAvoidingIdleBehavior: .freeRoaming,
            cursorAvoidingDetectionDistance: 240,
            cursorAvoidingSpeed: 480,
            cursorAvoidingAnimation: .single("escape"),
            randomizesFreeRoamingDwell: true,
            freeRoamingDwellMinimumMilliseconds: 2_500
        ))
        let v13 = try AppSettingsV13Mapper.storedSettings(from: settings)

        let migrated = try AppSettingsV13ToV14Migrator.migrate(v13)
        let movement = try XCTUnwrap(
            migrated.behaviorProfiles.first?.movement
        )

        XCTAssertEqual(movement.cursorFollowing.speed, 210)
        XCTAssertEqual(movement.cursorFollowing.cursorDistance, 144)
        XCTAssertEqual(movement.freeRoaming.speed, 210)
        XCTAssertEqual(movement.freeRoaming.dwellMilliseconds, 12_000)
        XCTAssertEqual(
            movement.cursorAvoiding.idleFreeRoaming,
            movement.freeRoaming
        )
        XCTAssertEqual(movement.cursorAvoiding.speed, 480)
        XCTAssertEqual(movement.cursorAvoiding.stopRadius, 28)
    }

    func testV14RoundTripPreservesAllIndependentMovementProfiles() throws {
        let follow = CursorFollowingMovementSettings(
            speed: 111,
            cursorDistance: 77,
            stopRadius: 9,
            animation: .single("follow")
        )
        let roam = FreeRoamingMovementSettings(
            speed: 222,
            stopRadius: 18,
            dwellMilliseconds: 9_000,
            randomizesDwell: true,
            dwellMinimumMilliseconds: 1_500,
            prefersFrontmostWindow: true,
            animation: .single("roam")
        )
        let avoidingRoam = FreeRoamingMovementSettings(
            speed: 333,
            stopRadius: 27,
            dwellMilliseconds: 17_000,
            randomizesDwell: false,
            dwellMinimumMilliseconds: 4_000,
            prefersFrontmostWindow: false,
            animation: .single("avoid-idle")
        )
        let movement = PetMovementSettings(
            mode: .cursorAvoiding,
            cursorFollowing: follow,
            freeRoaming: roam,
            cursorAvoiding: CursorAvoidingMovementSettings(
                idleBehavior: .freeRoaming,
                detectionDistance: 275,
                speed: 555,
                stopRadius: 36,
                animation: .single("escape"),
                idleFreeRoaming: avoidingRoam
            )
        )
        let settings = makeSettings(movement: movement)

        let stored = try AppSettingsV14Mapper.storedSettings(from: settings)
        let decoded = AppSettingsV14Mapper.domainSettings(from: stored)

        XCTAssertTrue(decoded.issues.isEmpty)
        XCTAssertEqual(decoded.settings.movementSettings, movement)
        XCTAssertNotEqual(
            decoded.settings.movementSettings.freeRoaming,
            decoded.settings.movementSettings.cursorAvoiding.idleFreeRoaming
        )
    }

    private func makeSettings(
        movement: PetMovementSettings
    ) -> AppSettings {
        AppSettings(
            selectedPetInstallationID: nil,
            lastUserPresentation: .awake,
            behaviorMode: .manual,
            overlay: .default,
            movement: movement,
            manualSequenceID: "default",
            sequences: [
                "default",
                "follow",
                "roam",
                "avoid-idle",
                "escape"
            ].map {
                BehaviorSequence(
                    id: $0,
                    steps: [BehaviorStep(motionID: $0, repeatCount: 1)],
                    repeats: true
                )
            },
            automaticRules: []
        )
    }
}
