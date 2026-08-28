import Foundation
import Observation

/// Per-row progress of a kill request.
enum KillState: Equatable, Sendable {
    /// SIGTERM sent; waiting up to the grace period for the process to exit.
    case terminating
    /// Still alive after the grace period — the UI offers Force Kill.
    case stillRunning
    /// SIGKILL sent; waiting for exit.
    case forcing
    case failed(String)
}

/// Single source of truth for the popover. Views bind to it and hold no logic.
@MainActor
@Observable
final class PortListModel {
    private(set) var listeners: [Listener] = []
    /// Message from the most recent failed scan; `nil` once a scan succeeds again.
    private(set) var lastError: String?
    private(set) var isRefreshing = false
    /// False until the first scan completes, so the UI can distinguish "loading" from "empty".
    private(set) var hasLoaded = false
    private(set) var killStates: [Listener.ID: KillState] = [:]
    var filterText = ""
    var selection: Listener.ID?
    /// Reveal ignored rows (they render dimmed with an Unignore action).
    var showIgnored = false
    private(set) var ignoredPorts: Set<UInt16>
    private(set) var ignoredProcessNames: Set<String>
    var sortOrder: SortOrder {
        didSet { preferences.sortOrder = sortOrder }
    }

    @ObservationIgnored private let scanner: PortScanner
    @ObservationIgnored private let killer: ProcessKiller
    @ObservationIgnored private let actions: any SystemActions
    @ObservationIgnored private let preferences: Preferences
    @ObservationIgnored private let forceKillGrace: Duration
    @ObservationIgnored private let forceKillWait: Duration
    @ObservationIgnored private var pollTask: Task<Void, Never>?

    init(
        scanner: PortScanner = PortScanner(),
        killer: ProcessKiller = ProcessKiller(),
        actions: any SystemActions = AppKitSystemActions(),
        preferences: Preferences = Preferences(),
        forceKillGrace: Duration = .seconds(2),
        forceKillWait: Duration = .seconds(1)
    ) {
        self.scanner = scanner
        self.killer = killer
        self.actions = actions
        self.preferences = preferences
        self.forceKillGrace = forceKillGrace
        self.forceKillWait = forceKillWait
        self.ignoredPorts = preferences.ignoredPorts
        self.ignoredProcessNames = preferences.ignoredProcessNames
        self.sortOrder = preferences.sortOrder
    }

    // MARK: Derived

    /// Listeners matching `filterText` (port, process name, PID), minus ignored rows unless
    /// `showIgnored`, in `sortOrder`.
    var filtered: [Listener] {
        let query = filterText.trimmingCharacters(in: .whitespaces)
        let visible = listeners.filter { listener in
            guard showIgnored || !isIgnored(listener) else { return false }
            guard !query.isEmpty else { return true }
            return listener.processName.localizedCaseInsensitiveContains(query)
                || String(listener.port).contains(query)
                || String(listener.pid).contains(query)
        }
        switch sortOrder {
        case .port:
            return visible // scanner order: port, then name, then PID
        case .processName:
            return visible.sorted {
                let names = $0.processName.localizedCaseInsensitiveCompare($1.processName)
                guard names == .orderedSame else { return names == .orderedAscending }
                return ($0.port, $0.pid) < ($1.port, $1.pid)
            }
        }
    }

    /// How many current listeners the ignore list hides (independent of the text filter).
    var hiddenCount: Int { listeners.count(where: isIgnored) }

    func isIgnored(_ listener: Listener) -> Bool {
        ignoredPorts.contains(listener.port) || ignoredProcessNames.contains(listener.processName)
    }

    var isPolling: Bool { pollTask != nil }

    /// The selected row, if it is currently visible.
    var selectedListener: Listener? {
        filtered.first { $0.id == selection }
    }

    func killState(for listener: Listener) -> KillState? { killStates[listener.id] }

    // MARK: Refresh

    /// Scans immediately, then every `refreshInterval` seconds until `stopPolling()`.
    /// Call from `onAppear`; polling must not run while the popover is closed.
    /// The interval is re-read each tick so a settings change applies without restarting.
    func startPolling() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await refresh()
                let interval = Duration.seconds(preferences.refreshInterval)
                do { try await Task.sleep(for: interval) } catch { return }
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            listeners = try await scanner.scan()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
        hasLoaded = true
        let present = Set(listeners.map(\.id))
        killStates = killStates.filter { present.contains($0.key) }
        if let selection, !present.contains(selection) { self.selection = nil }
    }

    // MARK: Kill

    func kill(_ listener: Listener) async {
        killStates[listener.id] = .terminating
        do {
            try killer.terminate(listener)
        } catch {
            killStates[listener.id] = .failed(error.localizedDescription)
            return
        }
        if await killer.waitForExit(of: listener, timeout: forceKillGrace) {
            killStates[listener.id] = nil
            await refresh()
        } else {
            killStates[listener.id] = .stillRunning
        }
    }

    func forceKill(_ listener: Listener) async {
        killStates[listener.id] = .forcing
        do {
            try killer.terminate(listener, force: true)
        } catch {
            killStates[listener.id] = .failed(error.localizedDescription)
            return
        }
        _ = await killer.waitForExit(of: listener, timeout: forceKillWait)
        killStates[listener.id] = nil
        await refresh()
    }

    func dismissKillError(for listener: Listener) {
        if case .failed = killStates[listener.id] { killStates[listener.id] = nil }
    }

    // MARK: Keyboard intents (act on the selection; return false when there is nothing to do)

    @discardableResult
    func openSelected() -> Bool {
        guard let listener = selectedListener else { return false }
        open(listener)
        return true
    }

    @discardableResult
    func copySelectedURL() -> Bool {
        guard let listener = selectedListener else { return false }
        copyURL(listener)
        return true
    }

    /// SIGTERM to the selected row. Refuses rows the user can't kill or that already have a kill in flight.
    @discardableResult
    func killSelected() -> Bool {
        guard let listener = selectedListener, listener.isOwnedByCurrentUser, killStates[listener.id] == nil else {
            return false
        }
        Task { await kill(listener) }
        return true
    }

    // MARK: Ignore list

    func ignorePort(of listener: Listener) {
        ignoredPorts.insert(listener.port)
        preferences.ignoredPorts = ignoredPorts
        clearSelectionIfHidden()
    }

    func ignoreProcess(of listener: Listener) {
        ignoredProcessNames.insert(listener.processName)
        preferences.ignoredProcessNames = ignoredProcessNames
        clearSelectionIfHidden()
    }

    /// Removes every rule that hides this listener (its port and its process name).
    func unignore(_ listener: Listener) {
        removeIgnoredPort(listener.port)
        removeIgnoredProcessName(listener.processName)
    }

    func removeIgnoredPort(_ port: UInt16) {
        ignoredPorts.remove(port)
        preferences.ignoredPorts = ignoredPorts
    }

    func removeIgnoredProcessName(_ name: String) {
        ignoredProcessNames.remove(name)
        preferences.ignoredProcessNames = ignoredProcessNames
    }

    private func clearSelectionIfHidden() {
        guard let selection, !filtered.contains(where: { $0.id == selection }) else { return }
        self.selection = nil
    }

    // MARK: Open / copy

    func open(_ listener: Listener) {
        guard let url = URL(string: listener.localURLString) else { return }
        actions.open(url)
    }

    func copyURL(_ listener: Listener) { actions.copy(listener.localURLString) }
    func copyPort(_ listener: Listener) { actions.copy(String(listener.port)) }
    func copyPID(_ listener: Listener) { actions.copy(String(listener.pid)) }
}
