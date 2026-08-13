import XCTest
@testable import MonglePet

final class MultiPetQALaunchConfigurationTests: XCTestCase {
    func testRequiresUITestingAndValidCount() {
        XCTAssertNil(
            MultiPetQALaunchConfiguration(
                arguments: ["MonglePet", "--qa-active-pet-count", "4"]
            )
        )
        XCTAssertNil(
            MultiPetQALaunchConfiguration(
                arguments: [
                    "MonglePet", "--ui-testing",
                    "--qa-active-pet-count", "0"
                ]
            )
        )
        XCTAssertNil(
            MultiPetQALaunchConfiguration(
                arguments: [
                    "MonglePet", "--ui-testing",
                    "--qa-active-pet-count", "65"
                ]
            )
        )
    }

    func testParsesWorkloadOptions() throws {
        let configuration = try XCTUnwrap(
            MultiPetQALaunchConfiguration(
                arguments: [
                    "MonglePet", "--ui-testing",
                    "--qa-active-pet-count", "8",
                    "--qa-movement-mode", "free-roaming",
                    "--qa-duration-seconds", "60"
                ]
            )
        )

        XCTAssertEqual(configuration.activePetCount, 8)
        XCTAssertEqual(configuration.movementMode, .freeRoaming)
        XCTAssertEqual(configuration.duration, 60)
    }

    func testCreatesIndependentAwakeInstancesForSelectedMovementMode() throws {
        let configuration = try XCTUnwrap(
            MultiPetQALaunchConfiguration(
                arguments: [
                    "MonglePet", "--ui-testing",
                    "--qa-active-pet-count", "4",
                    "--qa-movement-mode", "cursor-following"
                ]
            )
        )

        let settings = configuration.makeSettings()

        XCTAssertEqual(settings.activePetInstances.count, 4)
        XCTAssertEqual(settings.petBehaviorProfiles.count, 4)
        XCTAssertEqual(
            Set(settings.activePetInstances.map(\.instanceID)).count,
            4
        )
        XCTAssertEqual(
            Set(settings.activePetInstances.map(\.behaviorProfileID)).count,
            4
        )
        XCTAssertTrue(
            settings.activePetInstances.allSatisfy {
                $0.presentation == .awake
            }
        )
        for instance in settings.activePetInstances {
            XCTAssertEqual(
                settings.runtimeSettings(for: instance.instanceID)?
                    .movementSettings.mode,
                .cursorFollowing
            )
        }
    }
}
