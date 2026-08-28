import Foundation
import Observation

/// Backs the settings popover: Launch at Login and the refresh interval.
@MainActor
@Observable
final class SettingsModel {
    static let refreshIntervalChoices: [TimeInterval] = [1, 2, 5]

    private(set) var loginItemStatus: LoginItemStatus
    /// What went wrong the last time Launch at Login was toggled; `nil` after a success.
    private(set) var loginItemError: String?

    @ObservationIgnored private let loginItem: any LoginItemManaging
    @ObservationIgnored private let preferences: Preferences

    init(loginItem: any LoginItemManaging = SystemLoginItem(), preferences: Preferences = Preferences()) {
        self.loginItem = loginItem
        self.preferences = preferences
        self.loginItemStatus = loginItem.status
    }

    /// Bindable: `.enabled` and `.requiresApproval` both read as on — the user asked for it.
    var launchAtLogin: Bool {
        get { loginItemStatus == .enabled || loginItemStatus == .requiresApproval }
        set { setLaunchAtLogin(newValue) }
    }

    var needsLoginItemApproval: Bool { loginItemStatus == .requiresApproval }

    var refreshInterval: TimeInterval {
        get { preferences.refreshInterval }
        set { preferences.refreshInterval = newValue }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try loginItem.register() } else { try loginItem.unregister() }
            loginItemError = nil
        } catch {
            loginItemError = enabled
                ? String(localized: "Couldn't turn on Launch at Login: \(error.localizedDescription) Try again, or add OpenPorts under System Settings › General › Login Items.")
                : String(localized: "Couldn't turn off Launch at Login: \(error.localizedDescription) Try again, or remove OpenPorts under System Settings › General › Login Items.")
        }
        refreshLoginItemStatus()
    }

    func refreshLoginItemStatus() {
        loginItemStatus = loginItem.status
    }

    func openLoginItemsSettings() {
        loginItem.openSystemSettings()
    }
}
