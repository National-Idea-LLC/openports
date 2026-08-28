import Foundation
import Observation

/// Per-row progress of a kill request.
enum KillState: Equatable, Sendable {
    /// Kill was requested; waiting for the user to confirm before any signal is sent.
    case confirming
    /// SIGTERM sent; waiting up to the grace period for the process to exit.
    case terminating
    /// Still alive after the grace period — the UI offers Force Kill.
    case stillRunning
    /// SIGKILL sent; waiting for exit.
    case forcing
    case failed(String)
}

struct ListenerGroup: Identifiable, Equatable {
    enum Kind: Equatable { case yours, otherUsers, ignored }
    let kind: Kind
    let listeners: [Listener]
    var id: Kind { kind }
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
    /// Show the visible-listener count next to the menu bar icon. Turning it on polls in the
    /// background at `badgeInterval` while the popover is closed; off means popover-only polling.
    var showCountInMenuBar: Bool {
        didSet {
            preferences.showCountInMenuBar = showCountInMenuBar
            restartPollingLoop()
        }
    }

    @ObservationIgnored private let scanner: PortScanner
    @ObservationIgnored private let killer: ProcessKiller
    @ObservationIgnored private let actions: any SystemActions
    @ObservationIgnored private let preferences: Preferences
    @ObservationIgnored private let forceKillGrace: Duration
    @ObservationIgnored private let forceKillWait: Duration
    @ObservationIgnored private let badgeInterval: Duration
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var isPopoverVisible = false

    init(
        scanner: PortScanner = PortScanner(),
        killer: ProcessKiller = ProcessKiller(),
        actions: any SystemActions = AppKitSystemActions(),
        preferences: Preferences = Preferences(),
        forceKillGrace: Duration = .seconds(2),
        forceKillWait: Duration = .seconds(1),
        badgeInterval: Duration = .seconds(10)
    ) {
        self.scanner = scanner
        self.killer = killer
        self.actions = actions
        self.preferences = preferences
        self.forceKillGrace = forceKillGrace
        self.forceKillWait = forceKillWait
        self.badgeInterval = badgeInterval
        self.ignoredPorts = preferences.ignoredPorts
        self.ignoredProcessNames = preferences.ignoredProcessNames
        self.sortOrder = preferences.sortOrder
        self.showCountInMenuBar = preferences.showCountInMenuBar
        restartPollingLoop()
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

    /// `filtered`, split into the groups the list renders. Order encodes what you can act on:
    /// your own processes first, other users' (not killable) next, ignored rows last when revealed.
    var groups: [ListenerGroup] {
        var yours: [Listener] = [], others: [Listener] = [], ignored: [Listener] = []
        for listener in filtered {
            if isIgnored(listener) { ignored.append(listener) }
            else if listener.isOwnedByCurrentUser { yours.append(listener) }
            else { others.append(listener) }
        }
        return [
            ListenerGroup(kind: .yours, listeners: yours),
            ListenerGroup(kind: .otherUsers, listeners: others),
            ListenerGroup(kind: .ignored, listeners: ignored),
        ].filter { !$0.listeners.isEmpty }
    }

    /// How many current listeners the ignore list hides (independent of the text filter).
    var hiddenCount: Int { listeners.count(where: isIgnored) }

    func isIgnored(_ listener: Listener) -> Bool {
        ignoredPorts.contains(listener.port) || ignoredProcessNames.contains(listener.processName)
    }

    var isPolling: Bool { pollTask != nil }

    /// Number to show in the menu bar, or `nil` when the badge is off or nothing has loaded yet.
    /// Counts what the list would show with the ignore list applied.
    var menuBarCount: Int? {
        guard showCountInMenuBar, hasLoaded else { return nil }
        return listeners.count - hiddenCount
    }

    /// The selected row, if it is currently visible.
    var selectedListener: Listener? {
        filtered.first { $0.id == selection }
    }

    func killState(for listener: Listener) -> KillState? { killStates[listener.id] }

    // MARK: Refresh

    /// Popover appeared: scan now and every `refreshInterval` seconds until `stopPolling()`.
    func startPolling() {
        guard !isPopoverVisible else { return }
        isPopoverVisible = true
        restartPollingLoop()
    }

    /// Popover closed: back to background cadence if the badge is on, otherwise stop entirely.
    func stopPolling() {
        isPopoverVisible = false
        restartPollingLoop()
    }

    /// One loop serves both cadences; the interval is re-read each tick so a settings change
    /// applies without restarting.
    private func restartPollingLoop() {
        pollTask?.cancel()
        pollTask = nil
        guard isPopoverVisible || showCountInMenuBar else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await refresh()
                let interval = isPopoverVisible ? Duration.seconds(preferences.refreshInterval) : badgeInterval
                do { try await Task.sleep(for: interval) } catch { return }
            }
        }
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

    /// Arms the confirmation. Nothing is signalled until `confirmKill(_:)`.
    func requestKill(_ listener: Listener) {
        guard listener.isOwnedByCurrentUser, killStates[listener.id] == nil else { return }
        killStates[listener.id] = .confirming
    }

    func cancelKill(_ listener: Listener) {
        guard killStates[listener.id] == .confirming else { return }
        killStates[listener.id] = nil
    }

    /// True while any row is waiting for confirmation — lets Escape cancel from the list.
    var isAwaitingKillConfirmation: Bool { killStates.values.contains(.confirming) }

    func cancelAllKillConfirmations() {
        killStates = killStates.filter { $0.value != .confirming }
    }

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

    /// Arms the kill confirmation for the selected row. Refuses rows the user can't kill
    /// or that already have a kill in flight.
    @discardableResult
    func killSelected() -> Bool {
        guard let listener = selectedListener, listener.isOwnedByCurrentUser, killStates[listener.id] == nil else {
            return false
        }
        requestKill(listener)
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
