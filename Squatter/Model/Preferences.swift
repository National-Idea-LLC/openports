import Foundation

/// Every persisted key, defined once. Never rename a shipped key without a migration.
enum DefaultsKeys {
    static let refreshInterval = "squatter.refreshInterval"
    static let showCountInMenuBar = "squatter.showCountInMenuBar"
    static let ignoredPorts = "squatter.ignoredPorts"
    static let ignoredProcessNames = "squatter.ignoredProcessNames"
    static let sortOrder = "squatter.sortOrder"
    static let dockerIntegration = "squatter.dockerIntegration"
    static let hideHighPorts = "squatter.hideHighPorts"
    static let highPortThreshold = "squatter.highPortThreshold"

    /// AppKit's own key, so it carries no `squatter.` prefix and must not be renamed.
    /// Milliseconds a control must be hovered before its `.help()` tooltip appears.
    static let initialToolTipDelay = "NSInitialToolTipDelay"
}

/// How the list is ordered. Raw values are persisted — don't rename.
enum SortOrder: String, CaseIterable, Sendable {
    case port
    case processName
    /// Ascending PID, which is roughly launch order — the newest dev server is at the bottom.
    case pid
}

/// Typed access to the app's `UserDefaults`. Inject a private suite in tests.
/// Main-actor bound: only the model and settings UI read it.
@MainActor
struct Preferences {
    static let defaultRefreshInterval: TimeInterval = 2
    static let defaultHighPortThreshold: UInt16 = 10_000

    /// The row's ⋯ / ↗ / ✕ chips only exist while the row is hovered, so AppKit's stock delay
    /// (about two seconds) outlasts the time the pointer is actually over them — the tooltip
    /// arrives after you have already moved on, or not at all. This is short enough to land
    /// while the chip is still under the cursor, long enough not to fire on a pointer just
    /// crossing the row.
    static let toolTipDelayMilliseconds = 400

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Shortens the tooltip delay for the whole app. Registered rather than set, so it stays out
    /// of the user's plist and any explicit `defaults write` of the same key still wins.
    /// Call once before the first view is built.
    static func registerToolTipDelay(in defaults: UserDefaults = .standard) {
        defaults.register(defaults: [DefaultsKeys.initialToolTipDelay: toolTipDelayMilliseconds])
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

    /// On by default: with no Docker CLI installed nothing is ever spawned, so the cost of
    /// leaving it on is zero. Off is the escape hatch for anyone who wants no second process.
    var dockerIntegration: Bool {
        get {
            guard defaults.object(forKey: DefaultsKeys.dockerIntegration) != nil else { return true }
            return defaults.bool(forKey: DefaultsKeys.dockerIntegration)
        }
        nonmutating set { defaults.set(newValue, forKey: DefaultsKeys.dockerIntegration) }
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
