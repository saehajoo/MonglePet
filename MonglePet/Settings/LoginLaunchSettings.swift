import Combine
import Foundation
import ServiceManagement

enum LoginLaunchStatus: Equatable, Sendable {
    case notRegistered
    case enabled
    case requiresApproval
    case notFound

    var isRequestedEnabled: Bool {
        self == .enabled || self == .requiresApproval
    }
}

@MainActor
protocol LoginLaunchServicing: AnyObject {
    var status: LoginLaunchStatus { get }

    func register() throws
    func unregister() throws
    func openSystemSettings()
}

@MainActor
final class SystemLoginLaunchService: LoginLaunchServicing {
    private let appService: SMAppService

    init(appService: SMAppService = .mainApp) {
        self.appService = appService
    }

    var status: LoginLaunchStatus {
        switch appService.status {
        case .notRegistered:
            .notRegistered
        case .enabled:
            .enabled
        case .requiresApproval:
            .requiresApproval
        case .notFound:
            .notFound
        @unknown default:
            .notFound
        }
    }

    func register() throws {
        try appService.register()
    }

    func unregister() throws {
        try appService.unregister()
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

@MainActor
final class LoginLaunchSettings: ObservableObject {
    @Published private(set) var status: LoginLaunchStatus
    @Published private(set) var errorMessage: String?

    private let service: any LoginLaunchServicing

    init(service: any LoginLaunchServicing = SystemLoginLaunchService()) {
        self.service = service
        status = service.status
    }

    var isRequestedEnabled: Bool {
        status.isRequestedEnabled
    }

    var requiresApproval: Bool {
        status == .requiresApproval
    }

    func refresh() {
        status = service.status
        if status != .notFound {
            errorMessage = nil
        }
    }

    func setEnabled(_ isEnabled: Bool) {
        errorMessage = nil

        do {
            if isEnabled {
                if status == .requiresApproval {
                    service.openSystemSettings()
                } else if status != .enabled {
                    try service.register()
                }
            } else if status.isRequestedEnabled {
                try service.unregister()
            }
        } catch {
            errorMessage = isEnabled
                ? "로그인 시 자동 실행을 켤 수 없습니다. \(error.localizedDescription)"
                : "로그인 시 자동 실행을 끌 수 없습니다. \(error.localizedDescription)"
        }

        status = service.status
    }

    func openSystemSettings() {
        service.openSystemSettings()
    }
}
