import Foundation
import ServiceManagement

enum LaunchAtLoginStatus: Equatable {
    case notRegistered
    case enabled
    case requiresApproval
    case unavailable
}

enum LaunchAtLoginStatusMapper {
    static func map(_ systemStatus: SMAppService.Status) -> LaunchAtLoginStatus {
        switch systemStatus {
        case .notRegistered, .notFound:
            return .notRegistered
        case .enabled:
            return .enabled
        case .requiresApproval:
            return .requiresApproval
        @unknown default:
            return .unavailable
        }
    }
}

@MainActor
protocol LaunchAtLoginServicing: AnyObject {
    var status: LaunchAtLoginStatus { get }
    func register() throws
    func unregister() throws
}

@MainActor
final class SystemLaunchAtLoginService: LaunchAtLoginServicing {
    private let service = SMAppService.mainApp

    var status: LaunchAtLoginStatus {
        LaunchAtLoginStatusMapper.map(service.status)
    }

    func register() throws {
        try service.register()
    }

    func unregister() throws {
        try service.unregister()
    }
}

@MainActor
final class LaunchAtLoginController: ObservableObject {
    static let shared = LaunchAtLoginController(service: SystemLaunchAtLoginService())

    @Published private(set) var status: LaunchAtLoginStatus
    @Published private(set) var errorMessage: String?

    private let service: LaunchAtLoginServicing

    var isRegistered: Bool {
        status == .enabled || status == .requiresApproval
    }

    var canChangeRegistration: Bool {
        status != .unavailable
    }

    var statusText: String {
        switch status {
        case .notRegistered:
            return "Lancement automatique désactivé"
        case .enabled:
            return "Lancement automatique activé"
        case .requiresApproval:
            return "Enregistré, mais une autorisation est requise dans Réglages Système"
        case .unavailable:
            return "État du lancement automatique indisponible"
        }
    }

    init(service: LaunchAtLoginServicing) {
        self.service = service
        status = service.status
    }

    func refresh() {
        status = service.status
        errorMessage = nil
    }

    func setRegistered(_ shouldRegister: Bool) {
        errorMessage = nil

        do {
            if shouldRegister {
                try service.register()
            } else {
                try service.unregister()
            }

            refresh()
        } catch {
            status = service.status
            errorMessage = shouldRegister
                ? "Impossible d’activer le lancement automatique : \(error.localizedDescription)"
                : "Impossible de désactiver le lancement automatique : \(error.localizedDescription)"
        }
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
