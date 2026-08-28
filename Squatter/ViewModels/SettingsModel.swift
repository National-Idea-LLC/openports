import Foundation
import Observation

/// Backs the settings popover: Launch at Login and the refresh interval.
@MainActor
@Observable
final class SettingsModel {
    static let refreshIntervalChoices: [TimeInterval] = [1, 2, 5]
    static let releasesURL = URL(string: "https://github.com/National-Idea-LLC/squatter/releases")
    static let sourceURL = URL(string: "https://github.com/National-Idea-LLC/squatter")

    /// "0.1.0 (1)" from the bundle, or "—" when running outside a bundle (tests).
    static var bundleVersion: String {
        let info = Bundle.main.infoDictionary ?? [:]
        guard let short = info["CFBundleShortVersionString"] as? String else { return "—" }
        let build = info["CFBundleVersion"] as? String
        return build.map { "\(short) (\($0))" } ?? short
    }

    let appVersion: String

    private(set) var loginItemStatus: LoginItemStatus
    /// What went wrong the last time Launch at Login was toggled; `nil` after a success.
    private(set) var loginItemError: String?

    @ObservationIgnored private let loginItem: any LoginItemManaging
    @ObservationIgnored private let preferences: Preferences
    @ObservationIgnored private let actions: any SystemActions

    init(
        loginItem: any LoginItemManaging = SystemLoginItem(),
        preferences: Preferences = Preferences(),
        actions: any SystemActions = AppKitSystemActions(),
        appVersion: String = SettingsModel.bundleVersion
    ) {
        self.loginItem = loginItem
        self.preferences = preferences
        self.actions = actions
        self.appVersion = appVersion
        self.loginItemStatus = loginItem.status
    }

    /// No auto-updater: open the GitHub Releases page in the browser.
    func checkForUpdates() {
        guard let url = Self.releasesURL else { return }
        actions.open(url)
    }

    func openSource() {
        guard let url = Self.sourceURL else { return }
        actions.open(url)
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
                ? String(localized: "Couldn't turn on Launch at Login: \(error.localizedDescription) Try again, or add Squatter under System Settings › General › Login Items.")
                : String(localized: "Couldn't turn off Launch at Login: \(error.localizedDescription) Try again, or remove Squatter under System Settings › General › Login Items.")
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
