import ServiceManagement

enum LoginItemStatus: Equatable, Sendable {
    case enabled
    case disabled
    /// Registered, but the user must approve it in System Settings › General › Login Items.
    case requiresApproval
    case notFound
}

/// `SMAppService` behind a protocol so the settings model can be tested without touching launchd.
@MainActor
protocol LoginItemManaging {
    var status: LoginItemStatus { get }
    func register() throws
    func unregister() throws
    func openSystemSettings()
}

struct SystemLoginItem: LoginItemManaging {
    private var service: SMAppService { .mainApp }

    var status: LoginItemStatus {
        switch service.status {
        case .enabled: .enabled
        case .notRegistered: .disabled
        case .requiresApproval: .requiresApproval
        case .notFound: .notFound
        @unknown default: .disabled
        }
    }

    func register() throws { try service.register() }
    func unregister() throws { try service.unregister() }
    func openSystemSettings() { SMAppService.openSystemSettingsLoginItems() }
}
