import Foundation
import XCTest
@testable import MonglePet

final class LoginLaunchSettingsTests: XCTestCase {
    @MainActor
    func testInitialStatusUsesSystemServiceAsSourceOfTruth() {
        let service = FakeLoginLaunchService(status: .enabled)
        let settings = LoginLaunchSettings(service: service)

        XCTAssertEqual(settings.status, .enabled)
        XCTAssertTrue(settings.isRequestedEnabled)
        XCTAssertFalse(settings.requiresApproval)
    }

    @MainActor
    func testRegisterAndUnregisterRefreshStatusWithoutJSONSettings() {
        let service = FakeLoginLaunchService(status: .notRegistered)
        service.statusAfterRegister = .enabled
        service.statusAfterUnregister = .notRegistered
        let settings = LoginLaunchSettings(service: service)

        settings.setEnabled(true)
        XCTAssertEqual(service.registerCallCount, 1)
        XCTAssertEqual(settings.status, .enabled)
        XCTAssertNil(settings.errorMessage)

        settings.setEnabled(false)
        XCTAssertEqual(service.unregisterCallCount, 1)
        XCTAssertEqual(settings.status, .notRegistered)
        XCTAssertNil(settings.errorMessage)
    }

    @MainActor
    func testApprovalRequiredKeepsRequestedToggleOnAndOpensSystemSettings() {
        let service = FakeLoginLaunchService(status: .notRegistered)
        service.statusAfterRegister = .requiresApproval
        let settings = LoginLaunchSettings(service: service)

        settings.setEnabled(true)

        XCTAssertTrue(settings.isRequestedEnabled)
        XCTAssertTrue(settings.requiresApproval)
        XCTAssertEqual(service.openSystemSettingsCallCount, 0)

        settings.setEnabled(true)
        XCTAssertEqual(service.registerCallCount, 1)
        XCTAssertEqual(service.openSystemSettingsCallCount, 1)
    }

    @MainActor
    func testRegistrationFailureKeepsActualStatusAndShowsError() {
        let service = FakeLoginLaunchService(status: .notRegistered)
        service.registerError = TestError.failed
        let settings = LoginLaunchSettings(service: service)

        settings.setEnabled(true)

        XCTAssertEqual(settings.status, .notRegistered)
        XCTAssertFalse(settings.isRequestedEnabled)
        XCTAssertNotNil(settings.errorMessage)
    }

    @MainActor
    func testUnregistrationFailureKeepsActualEnabledStatusAndShowsError() {
        let service = FakeLoginLaunchService(status: .enabled)
        service.unregisterError = TestError.failed
        let settings = LoginLaunchSettings(service: service)

        settings.setEnabled(false)

        XCTAssertEqual(settings.status, .enabled)
        XCTAssertTrue(settings.isRequestedEnabled)
        XCTAssertNotNil(settings.errorMessage)
    }

    @MainActor
    func testNotFoundStatusAllowsFirstRegistration() {
        let service = FakeLoginLaunchService(status: .notFound)
        service.statusAfterRegister = .enabled
        let settings = LoginLaunchSettings(service: service)

        XCTAssertFalse(settings.isRequestedEnabled)

        settings.setEnabled(true)

        XCTAssertEqual(service.registerCallCount, 1)
        XCTAssertEqual(settings.status, .enabled)
        XCTAssertTrue(settings.isRequestedEnabled)
        XCTAssertNil(settings.errorMessage)
    }
}

private enum TestError: LocalizedError {
    case failed

    var errorDescription: String? {
        "테스트 오류"
    }
}

@MainActor
private final class FakeLoginLaunchService: LoginLaunchServicing {
    var status: LoginLaunchStatus
    var statusAfterRegister: LoginLaunchStatus?
    var statusAfterUnregister: LoginLaunchStatus?
    var registerError: Error?
    var unregisterError: Error?
    private(set) var registerCallCount = 0
    private(set) var unregisterCallCount = 0
    private(set) var openSystemSettingsCallCount = 0

    init(status: LoginLaunchStatus) {
        self.status = status
    }

    func register() throws {
        registerCallCount += 1
        if let registerError {
            throw registerError
        }
        if let statusAfterRegister {
            status = statusAfterRegister
        }
    }

    func unregister() throws {
        unregisterCallCount += 1
        if let unregisterError {
            throw unregisterError
        }
        if let statusAfterUnregister {
            status = statusAfterUnregister
        }
    }

    func openSystemSettings() {
        openSystemSettingsCallCount += 1
    }
}
