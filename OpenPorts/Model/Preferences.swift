import Foundation

/// Every persisted key, defined once. Never rename a shipped key without a migration.
enum DefaultsKeys {
    static let refreshInterval = "openports.refreshInterval"
    static let showCountInMenuBar = "openports.showCountInMenuBar"
    static let ignoredPorts = "openports.ignoredPorts"
    static let ignoredProcessNames = "openports.ignoredProcessNames"
}

/// Typed access to the app's `UserDefaults`. Inject a private suite in tests.
/// Main-actor bound: only the model and settings UI read it.
@MainActor
struct Preferences {
    static let defaultRefreshInterval: TimeInterval = 2

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Seconds between automatic scans while the popover is open. Clamped to a sane range.
    var refreshInterval: TimeInterval {
        get {
            let stored = defaults.double(forKey: DefaultsKeys.refreshInterval)
            return stored > 0 ? min(max(stored, 0.5), 60) : Self.defaultRefreshInterval
        }
        nonmutating set { defaults.set(newValue, forKey: DefaultsKeys.refreshInterval) }
    }

    var showCountInMenuBar: Bool {
        get { defaults.bool(forKey: DefaultsKeys.showCountInMenuBar) }
        nonmutating set { defaults.set(newValue, forKey: DefaultsKeys.showCountInMenuBar) }
    }
}
