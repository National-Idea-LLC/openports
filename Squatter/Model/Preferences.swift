import Foundation

/// Every persisted key, defined once. Never rename a shipped key without a migration.
enum DefaultsKeys {
    static let refreshInterval = "squatter.refreshInterval"
    static let showCountInMenuBar = "squatter.showCountInMenuBar"
    static let ignoredPorts = "squatter.ignoredPorts"
    static let ignoredProcessNames = "squatter.ignoredProcessNames"
    static let sortOrder = "squatter.sortOrder"
    static let hideHighPorts = "squatter.hideHighPorts"
    static let highPortThreshold = "squatter.highPortThreshold"
}

/// How the list is ordered. Raw values are persisted — don't rename.
enum SortOrder: String, CaseIterable, Sendable {
    case port
    case processName
}

/// Typed access to the app's `UserDefaults`. Inject a private suite in tests.
/// Main-actor bound: only the model and settings UI read it.
@MainActor
struct Preferences {
    static let defaultRefreshInterval: TimeInterval = 2
    static let defaultHighPortThreshold: UInt16 = 10_000

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

    var ignoredPorts: Set<UInt16> {
        get {
            let stored = defaults.array(forKey: DefaultsKeys.ignoredPorts) as? [Int] ?? []
            return Set(stored.compactMap { UInt16(exactly: $0) })
        }
        nonmutating set { defaults.set(newValue.sorted().map(Int.init), forKey: DefaultsKeys.ignoredPorts) }
    }

    var ignoredProcessNames: Set<String> {
        get { Set(defaults.stringArray(forKey: DefaultsKeys.ignoredProcessNames) ?? []) }
        nonmutating set { defaults.set(newValue.sorted(), forKey: DefaultsKeys.ignoredProcessNames) }
    }

    var sortOrder: SortOrder {
        get { defaults.string(forKey: DefaultsKeys.sortOrder).flatMap(SortOrder.init(rawValue:)) ?? .port }
        nonmutating set { defaults.set(newValue.rawValue, forKey: DefaultsKeys.sortOrder) }
    }

    var showCountInMenuBar: Bool {
        get { defaults.bool(forKey: DefaultsKeys.showCountInMenuBar) }
        nonmutating set { defaults.set(newValue, forKey: DefaultsKeys.showCountInMenuBar) }
    }

    /// Off by default: an update must never make rows vanish from someone's list without
    /// them asking.
    var hideHighPorts: Bool {
        get { defaults.bool(forKey: DefaultsKeys.hideHighPorts) }
        nonmutating set { defaults.set(newValue, forKey: DefaultsKeys.hideHighPorts) }
    }

    /// Ports strictly above this are hidden while `hideHighPorts` is on. Clamped on read,
    /// like `refreshInterval`, so a hand-edited plist can't hide everything.
    var highPortThreshold: UInt16 {
        get {
            let stored = defaults.integer(forKey: DefaultsKeys.highPortThreshold)
            guard stored > 0 else { return Self.defaultHighPortThreshold }
            return UInt16(min(max(stored, 1), 65_535))
        }
        nonmutating set { defaults.set(Int(newValue), forKey: DefaultsKeys.highPortThreshold) }
    }
}
