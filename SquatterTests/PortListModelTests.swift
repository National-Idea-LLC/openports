import Foundation
import Testing
@testable import Squatter

@MainActor
struct PortListModelTests {
    private func makeModel(
        runner: FakeRunner = FakeRunner(.success(lsofResult(sampleLsof))),
        kills: KillRecorder = KillRecorder(names: [42: "node"]),
        actions: RecordingActions = RecordingActions(),
        defaults: UserDefaults = freshDefaults(),
        badgeInterval: Duration = .milliseconds(100)
    ) -> PortListModel {
        PortListModel(
            scanner: PortScanner(runner: runner, currentUID: 501, userName: testUserName),
            killer: kills.killer,
            actions: actions,
            preferences: Preferences(defaults: defaults),
            forceKillGrace: .milliseconds(60),
            forceKillWait: .milliseconds(60),
            badgeInterval: badgeInterval
        )
    }

    @Test func refreshLoadsListeners() async {
        let model = makeModel()
        #expect(!model.hasLoaded)
        await model.refresh()
        #expect(model.hasLoaded)
        #expect(model.listeners == [sampleListener])
        #expect(model.lastError == nil)
    }

    @Test func failedRefreshKeepsLastListAndReportsError() async {
        let runner = FakeRunner(.success(lsofResult(sampleLsof)))
        let model = makeModel(runner: runner)
        await model.refresh()
        await runner.set(.failure(.launchFailed("boom")))
        await model.refresh()
        #expect(model.listeners == [sampleListener])
        #expect(model.lastError?.contains("boom") == true)
        await runner.set(.success(lsofResult("")))
        await model.refresh()
        #expect(model.listeners.isEmpty)
        #expect(model.lastError == nil)
    }

    @Test func filterMatchesPortNameAndPid() async {
        let two = sampleLsof + "p7\ncpostgres\nu501\nf1\nPTCP\nn127.0.0.1:5432\nTST=LISTEN\n"
        let model = makeModel(runner: FakeRunner(.success(lsofResult(two))))
        await model.refresh()
        #expect(model.filtered.count == 2)
        model.filterText = "NODE"
        #expect(model.filtered.map(\.processName) == ["node"])
        model.filterText = "543"
        #expect(model.filtered.map(\.port) == [5432])
        model.filterText = "7"
        #expect(model.filtered.map(\.pid) == [7])
        model.filterText = "nothing"
        #expect(model.filtered.isEmpty)
    }

    @Test func killThatExitsRemovesRowAndState() async {
        let runner = FakeRunner(.success(lsofResult(sampleLsof)))
        let kills = KillRecorder(names: [42: "node"])
        kills.onSignal { pid, _ in kills.setName(nil, for: pid) }
        let model = makeModel(runner: runner, kills: kills)
        await model.refresh()
        await runner.set(.success(lsofResult("")))

        await model.kill(sampleListener)

        #expect(kills.signals.map(\.1) == [SIGTERM])
        #expect(model.listeners.isEmpty)
        #expect(model.killStates.isEmpty)
    }

    @Test func stubbornProcessOffersForceKillThenDies() async {
        let runner = FakeRunner(.success(lsofResult(sampleLsof)))
        let kills = KillRecorder(names: [42: "node"])
        kills.onSignal { pid, sig in if sig == SIGKILL { kills.setName(nil, for: pid) } }
        let model = makeModel(runner: runner, kills: kills)
        await model.refresh()

        await model.kill(sampleListener)
        #expect(model.killState(for: sampleListener) == .stillRunning)
        #expect(model.listeners == [sampleListener])

        await runner.set(.success(lsofResult("")))
        await model.forceKill(sampleListener)
        #expect(kills.signals.map(\.1) == [SIGTERM, SIGKILL])
        #expect(model.killStates.isEmpty)
        #expect(model.listeners.isEmpty)
    }

    @Test func killErrorIsSurfacedAndDismissable() async {
        let kills = KillRecorder(names: [42: "node"], signalResult: EPERM)
        let model = makeModel(kills: kills)
        await model.refresh()
        await model.kill(sampleListener)
        guard case .failed(let message)? = model.killState(for: sampleListener) else {
            Issue.record("expected .failed, got \(String(describing: model.killState(for: sampleListener)))")
            return
        }
        #expect(message.contains("another user"))
        model.dismissKillError(for: sampleListener)
        #expect(model.killState(for: sampleListener) == nil)
    }

    @Test func pollingRefreshesOnIntervalAndStops() async throws {
        let runner = FakeRunner(.success(lsofResult(sampleLsof)))
        let defaults = freshDefaults()
        Preferences(defaults: defaults).refreshInterval = 0.5 // clamp floor; fast enough for a test
        let model = makeModel(runner: runner, defaults: defaults)

        model.startPolling()
        model.startPolling() // idempotent
        #expect(model.isPolling)
        try await Task.sleep(for: .milliseconds(1200))
        model.stopPolling()
        #expect(!model.isPolling)
        let launches = await runner.launches
        #expect(launches >= 2 && launches <= 4, "got \(launches)")

        try await Task.sleep(for: .milliseconds(700))
        #expect(await runner.launches == launches, "must not scan after stopPolling")
    }

    @Test func selectionClearsWhenRowDisappears() async {
        let runner = FakeRunner(.success(lsofResult(sampleLsof)))
        let model = makeModel(runner: runner)
        await model.refresh()
        model.selection = sampleListener.id
        await runner.set(.success(lsofResult("")))
        await model.refresh()
        #expect(model.selection == nil)
    }

    // MARK: ignore list

    private static let twoLsof = sampleLsof + "p7\ncpostgres\nu501\nf1\nPTCP\nn127.0.0.1:5432\nTST=LISTEN\n"

    @Test func ignoringAPortHidesItAndCountsIt() async {
        let model = makeModel(runner: FakeRunner(.success(lsofResult(Self.twoLsof))))
        await model.refresh()
        model.selection = sampleListener.id
        model.ignorePort(of: sampleListener)
        #expect(model.filtered.map(\.port) == [5432])
        #expect(model.hiddenCount == 1)
        #expect(model.isIgnored(sampleListener))
        #expect(model.selection == nil, "hidden row can't stay selected")
        model.showIgnored = true
        #expect(model.filtered.map(\.port) == [3000, 5432])
        #expect(model.hiddenCount == 1, "count is independent of reveal")
    }

    @Test func ignoringAProcessHidesEveryPortItOwns() async {
        let sameProcess = sampleLsof + "p42\ncnode\nu501\nf2\nPTCP\nn*:3001\nTST=LISTEN\n"
        let model = makeModel(runner: FakeRunner(.success(lsofResult(sameProcess))))
        await model.refresh()
        #expect(model.listeners.count == 2)
        model.ignoreProcess(of: sampleListener)
        #expect(model.filtered.isEmpty)
        #expect(model.hiddenCount == 2)
        model.unignore(sampleListener)
        #expect(model.filtered.count == 2)
        #expect(model.hiddenCount == 0)
    }

    @Test func ignoreListPersistsAcrossModels() async {
        let defaults = freshDefaults()
        let first = makeModel(defaults: defaults)
        await first.refresh()
        first.ignorePort(of: sampleListener)
        first.ignoreProcess(of: sampleListener)

        let second = makeModel(defaults: defaults)
        await second.refresh()
        #expect(second.ignoredPorts == [3000])
        #expect(second.ignoredProcessNames == ["node"])
        #expect(second.filtered.isEmpty)

        second.removeIgnoredPort(3000)
        #expect(second.filtered.isEmpty, "process rule still hides it")
        second.removeIgnoredProcessName("node")
        #expect(second.filtered == [sampleListener])
        #expect(Preferences(defaults: defaults).ignoredPorts.isEmpty)
        #expect(Preferences(defaults: defaults).ignoredProcessNames.isEmpty)
    }

    @Test func textFilterAndIgnoreCompose() async {
        let model = makeModel(runner: FakeRunner(.success(lsofResult(Self.twoLsof))))
        await model.refresh()
        model.ignorePort(of: sampleListener)
        model.filterText = "node"
        #expect(model.filtered.isEmpty)
        model.showIgnored = true
        #expect(model.filtered.map(\.processName) == ["node"])
    }

    // MARK: sort

    @Test func sortByProcessNameIsCaseInsensitiveThenPort() async {
        let lsof = "p1\ncZeta\nu501\nf1\nPTCP\nn*:80\nTST=LISTEN\n"
            + "p2\ncalpha\nu501\nf1\nPTCP\nn*:9000\nTST=LISTEN\n"
            + "p3\ncBeta\nu501\nf1\nPTCP\nn*:443\nTST=LISTEN\n"
            + "p4\ncalpha\nu501\nf1\nPTCP\nn*:8000\nTST=LISTEN\n"
        let defaults = freshDefaults()
        let model = makeModel(runner: FakeRunner(.success(lsofResult(lsof))), defaults: defaults)
        await model.refresh()
        #expect(model.sortOrder == .port)
        #expect(model.filtered.map(\.port) == [80, 443, 8000, 9000])

        model.sortOrder = .processName
        #expect(model.filtered.map { "\($0.processName):\($0.port)" } == ["alpha:8000", "alpha:9000", "Beta:443", "Zeta:80"])
        #expect(Preferences(defaults: defaults).sortOrder == .processName, "persisted")
        #expect(makeModel(defaults: defaults).sortOrder == .processName, "restored on next launch")
    }

    @Test func groupsSplitYoursOthersAndIgnored() async {
        let lsof = "p1\nclaunchd\nu0\nf1\nPTCP\nn*:22\nTST=LISTEN\n" + sampleLsof
            + "p7\ncpostgres\nu501\nf1\nPTCP\nn127.0.0.1:5432\nTST=LISTEN\n"
        let model = makeModel(runner: FakeRunner(.success(lsofResult(lsof))))
        await model.refresh()
        #expect(model.groups.map(\.kind) == [.yours, .otherUsers])
        #expect(model.groups[0].listeners.map(\.port) == [3000, 5432])
        #expect(model.groups[1].listeners.map(\.port) == [22])

        model.ignorePort(of: sampleListener)
        #expect(model.groups.map(\.kind) == [.yours, .otherUsers])
        model.showIgnored = true
        #expect(model.groups.map(\.kind) == [.yours, .otherUsers, .ignored])
        #expect(model.groups[2].listeners.map(\.port) == [3000])
        model.filterText = "launchd"
        #expect(model.groups.map(\.kind) == [.otherUsers], "empty groups drop out")
    }

    // MARK: keyboard intents

    @Test func keyboardIntentsActOnTheVisibleSelection() async throws {
        let actions = RecordingActions()
        let kills = KillRecorder(names: [42: "node"])
        kills.onSignal { pid, _ in kills.setName(nil, for: pid) }
        let model = makeModel(kills: kills, actions: actions)
        await model.refresh()

        #expect(!model.openSelected())
        #expect(!model.copySelectedURL())
        #expect(!model.killSelected())

        model.selection = sampleListener.id
        #expect(model.openSelected())
        #expect(model.copySelectedURL())
        #expect(actions.opened.count == 1 && actions.copied == ["http://localhost:3000"])

        model.filterText = "zzz" // selection no longer visible
        #expect(model.selectedListener == nil)
        #expect(!model.openSelected())
        model.filterText = ""

        #expect(model.killSelected(), "arms the confirmation")
        #expect(model.killState(for: sampleListener) == .confirming)
        #expect(kills.signals.isEmpty, "nothing is signalled until confirmed")
        await model.kill(sampleListener)
        #expect(kills.signals.map(\.1) == [SIGTERM])
    }

    // MARK: kill confirmation

    @Test func killPathsArmAConfirmationInsteadOfSignalling() async {
        let kills = KillRecorder(names: [42: "node"])
        let model = makeModel(kills: kills)
        await model.refresh()

        model.requestKill(sampleListener)
        #expect(model.killState(for: sampleListener) == .confirming)
        #expect(model.isAwaitingKillConfirmation)
        #expect(kills.signals.isEmpty)

        model.requestKill(sampleListener) // idempotent while armed
        #expect(model.killState(for: sampleListener) == .confirming)

        model.cancelKill(sampleListener)
        #expect(model.killState(for: sampleListener) == nil)
        #expect(!model.isAwaitingKillConfirmation)
        #expect(kills.signals.isEmpty)
    }

    @Test func confirmingSendsSigtermAndEscapeCancelsEverything() async {
        let two = sampleLsof + "p7\ncpostgres\nu501\nf1\nPTCP\nn127.0.0.1:5432\nTST=LISTEN\n"
        let kills = KillRecorder(names: [42: "node", 7: "postgres"])
        kills.onSignal { pid, _ in kills.setName(nil, for: pid) }
        let model = makeModel(runner: FakeRunner(.success(lsofResult(two))), kills: kills)
        await model.refresh()

        model.requestKill(sampleListener)
        model.requestKill(model.listeners[1])
        #expect(model.isAwaitingKillConfirmation)
        model.cancelAllKillConfirmations()
        #expect(!model.isAwaitingKillConfirmation)
        #expect(kills.signals.isEmpty)

        model.requestKill(sampleListener)
        await model.kill(sampleListener)
        #expect(kills.signals.map(\.1) == [SIGTERM])
        #expect(model.killState(for: sampleListener) == nil)
    }

    @Test func armingASecondRowCancelsTheFirst() async {
        let two = sampleLsof + "p7\ncpostgres\nu501\nf1\nPTCP\nn127.0.0.1:5432\nTST=LISTEN\n"
        let kills = KillRecorder(names: [42: "node", 7: "postgres"])
        let model = makeModel(runner: FakeRunner(.success(lsofResult(two))), kills: kills)
        await model.refresh()
        let postgres = model.listeners[1]

        model.requestKill(sampleListener)
        model.requestKill(postgres)
        #expect(model.killState(for: sampleListener) == nil, "the first row disarms")
        #expect(model.killState(for: postgres) == .confirming)
        #expect(model.killStates.values.count(where: { $0 == .confirming }) == 1)
        #expect(kills.signals.isEmpty)
    }

    @Test func armingDoesNotDisturbAKillAlreadyInFlight() async {
        let two = sampleLsof + "p7\ncpostgres\nu501\nf1\nPTCP\nn127.0.0.1:5432\nTST=LISTEN\n"
        let kills = KillRecorder(names: [42: "node", 7: "postgres"])
        let model = makeModel(runner: FakeRunner(.success(lsofResult(two))), kills: kills)
        await model.refresh()
        let postgres = model.listeners[1]

        await model.kill(sampleListener) // node never exits → .stillRunning
        #expect(model.killState(for: sampleListener) == .stillRunning)
        model.requestKill(postgres)
        #expect(model.killState(for: sampleListener) == .stillRunning, "in-flight kills survive")
        #expect(model.killState(for: postgres) == .confirming)
    }

    @Test func confirmationIsRefusedForOtherUsersRows() async {
        let root = "p1\nclaunchd\nu0\nf1\nPTCP\nn*:22\nTST=LISTEN\n"
        let model = makeModel(runner: FakeRunner(.success(lsofResult(root))), kills: KillRecorder(names: [1: "launchd"]))
        await model.refresh()
        let launchd = model.listeners[0]
        model.requestKill(launchd)
        #expect(model.killState(for: launchd) == nil)
        #expect(!model.isAwaitingKillConfirmation)
    }

    @Test func forceKillFromTheMenuArmsAConfirmationInsteadOfSignalling() async {
        let kills = KillRecorder(names: [42: "node"])
        let model = makeModel(kills: kills)
        await model.refresh()

        model.requestForceKill(sampleListener)
        #expect(model.killState(for: sampleListener) == .confirmingForce)
        #expect(model.isAwaitingKillConfirmation)
        #expect(kills.signals.isEmpty)

        model.cancelKill(sampleListener)
        #expect(model.killState(for: sampleListener) == nil)
        #expect(kills.signals.isEmpty)
    }

    @Test func confirmedForceKillSendsSigkillAndNothingElse() async {
        let kills = KillRecorder(names: [42: "node"])
        kills.onSignal { pid, _ in kills.setName(nil, for: pid) }
        let model = makeModel(kills: kills)
        await model.refresh()

        model.requestForceKill(sampleListener)
        await model.forceKill(sampleListener)
        #expect(kills.signals.map(\.1) == [SIGKILL])
        #expect(model.killState(for: sampleListener) == nil)
    }

    @Test func forceKillConfirmationIsRefusedForOtherUsersRows() async {
        let root = "p1\nclaunchd\nu0\nf1\nPTCP\nn*:22\nTST=LISTEN\n"
        let model = makeModel(runner: FakeRunner(.success(lsofResult(root))), kills: KillRecorder(names: [1: "launchd"]))
        await model.refresh()
        let launchd = model.listeners[0]
        model.requestForceKill(launchd)
        #expect(model.killState(for: launchd) == nil)
        #expect(!model.isAwaitingKillConfirmation)
    }

    @Test func theModelRefusesToSignalOtherUsersProcesses() async {
        let root = "p1\nclaunchd\nu0\nf1\nPTCP\nn*:22\nTST=LISTEN\n"
        let kills = KillRecorder(names: [1: "launchd"])
        let model = makeModel(runner: FakeRunner(.success(lsofResult(root))), kills: kills)
        await model.refresh()
        let launchd = model.listeners[0]

        await model.kill(launchd)
        await model.forceKill(launchd)
        #expect(kills.signals.isEmpty)
        #expect(model.killStates.isEmpty)
    }

    @Test func closingThePopoverClearsArmedPromptsButNotKillsInFlight() async {
        let two = sampleLsof + "p7\ncpostgres\nu501\nf1\nPTCP\nn127.0.0.1:5432\nTST=LISTEN\n"
        let kills = KillRecorder(names: [42: "node", 7: "postgres"])
        let model = makeModel(runner: FakeRunner(.success(lsofResult(two))), kills: kills)
        await model.refresh()
        let postgres = model.listeners[1]

        await model.kill(sampleListener) // node never exits → .stillRunning
        #expect(model.killState(for: sampleListener) == .stillRunning)
        model.requestForceKill(postgres)

        model.stopPolling()
        #expect(model.killState(for: sampleListener) == .stillRunning)
        #expect(model.killState(for: postgres) == nil)
        #expect(!model.isAwaitingKillConfirmation)
    }

    @Test func armedConfirmationClearsWhenTheRowDisappears() async {
        let runner = FakeRunner(.success(lsofResult(sampleLsof)))
        let model = makeModel(runner: runner)
        await model.refresh()
        model.requestKill(sampleListener)
        #expect(model.isAwaitingKillConfirmation)
        await runner.set(.success(lsofResult("")))
        await model.refresh()
        #expect(model.killStates.isEmpty)
        #expect(!model.isAwaitingKillConfirmation)
    }

    @Test func killSelectedRefusesOtherUsersRowsAndDoubleKills() async {
        let root = "p1\nclaunchd\nu0\nf1\nPTCP\nn*:22\nTST=LISTEN\n" + sampleLsof
        let kills = KillRecorder(names: [1: "launchd", 42: "node"])
        let model = makeModel(runner: FakeRunner(.success(lsofResult(root))), kills: kills)
        await model.refresh()

        model.selection = "1:22"
        #expect(!model.killSelected(), "not our process")

        model.selection = sampleListener.id
        model.requestKill(sampleListener)
        await model.kill(sampleListener) // stays .stillRunning (name never changes)
        #expect(model.killState(for: sampleListener) == .stillRunning)
        #expect(!model.killSelected(), "kill already in flight")
        #expect(kills.signals.count == 1)
    }

    // MARK: menu bar count badge

    @Test func badgeOffMeansNoCountAndNoBackgroundPolling() async throws {
        let runner = FakeRunner(.success(lsofResult(sampleLsof)))
        let model = makeModel(runner: runner)
        #expect(model.menuBarCount == nil)
        #expect(!model.isPolling)
        try await Task.sleep(for: .milliseconds(250))
        #expect(await runner.launches == 0)
        await model.refresh()
        #expect(model.menuBarCount == nil, "still nil while the badge is off")
    }

    @Test func badgeOnPollsInBackgroundAndCountsVisibleRows() async throws {
        let two = sampleLsof + "p7\ncpostgres\nu501\nf1\nPTCP\nn127.0.0.1:5432\nTST=LISTEN\n"
        let runner = FakeRunner(.success(lsofResult(two)))
        let defaults = freshDefaults()
        let model = makeModel(runner: runner, defaults: defaults)

        model.showCountInMenuBar = true
        #expect(model.isPolling)
        try await Task.sleep(for: .milliseconds(350))
        let launches = await runner.launches
        #expect(launches >= 2 && launches <= 5, "background cadence, got \(launches)")
        #expect(model.menuBarCount == 2)
        #expect(Preferences(defaults: defaults).showCountInMenuBar)

        model.ignorePort(of: sampleListener)
        #expect(model.menuBarCount == 1, "ignored rows don't count")

        model.showCountInMenuBar = false
        #expect(!model.isPolling)
        #expect(model.menuBarCount == nil)
        let after = await runner.launches
        try await Task.sleep(for: .milliseconds(250))
        #expect(await runner.launches == after, "no polling once the badge is off")
    }

    @Test func badgeOnAtLaunchStartsPollingImmediately() async throws {
        let defaults = freshDefaults()
        Preferences(defaults: defaults).showCountInMenuBar = true
        let runner = FakeRunner(.success(lsofResult(sampleLsof)))
        let model = makeModel(runner: runner, defaults: defaults)
        #expect(model.isPolling)
        try await Task.sleep(for: .milliseconds(150))
        #expect(await runner.launches >= 1)
        #expect(model.menuBarCount == 1)
    }

    @Test func popoverCadenceWinsWhileOpenThenFallsBackToBadge() async throws {
        let runner = FakeRunner(.success(lsofResult(sampleLsof)))
        let model = makeModel(runner: runner, badgeInterval: .seconds(30))
        model.showCountInMenuBar = true
        try await Task.sleep(for: .milliseconds(100))
        #expect(await runner.launches == 1, "one background scan, next in 30 s")

        model.startPolling() // popover opened: refreshInterval (clamped 0.5 s) applies
        try await Task.sleep(for: .milliseconds(700))
        #expect(await runner.launches >= 2)

        model.stopPolling()
        #expect(model.isPolling, "badge keeps the loop alive after the popover closes")
    }

    @Test func openAndCopyGoThroughSystemActions() async {
        let actions = RecordingActions()
        let model = makeModel(actions: actions)
        model.open(sampleListener)
        model.copyURL(sampleListener)
        model.copyPort(sampleListener)
        model.copyPID(sampleListener)
        #expect(actions.opened.map(\.absoluteString) == ["http://localhost:3000"])
        #expect(actions.copied == ["http://localhost:3000", "3000", "42"])
    }
}

@MainActor
struct PreferencesTests {
    @Test func defaultsAndRoundTrip() {
        let prefs = Preferences(defaults: freshDefaults())
        #expect(prefs.refreshInterval == 2)
        #expect(prefs.showCountInMenuBar == false)
        prefs.refreshInterval = 5
        prefs.showCountInMenuBar = true
        #expect(prefs.refreshInterval == 5)
        #expect(prefs.showCountInMenuBar)
    }

    @Test func refreshIntervalIsClamped() {
        let prefs = Preferences(defaults: freshDefaults())
        prefs.refreshInterval = 0.01
        #expect(prefs.refreshInterval == 0.5)
        prefs.refreshInterval = 999
        #expect(prefs.refreshInterval == 60)
        prefs.refreshInterval = -1
        #expect(prefs.refreshInterval == 2, "non-positive falls back to the default")
    }

    @Test func ignoreListsRoundTripAndDropInvalidPorts() {
        let defaults = freshDefaults()
        let prefs = Preferences(defaults: defaults)
        #expect(prefs.ignoredPorts.isEmpty && prefs.ignoredProcessNames.isEmpty)
        prefs.ignoredPorts = [8080, 3000]
        prefs.ignoredProcessNames = ["node", "rapportd"]
        #expect(defaults.array(forKey: DefaultsKeys.ignoredPorts) as? [Int] == [3000, 8080])
        #expect(Preferences(defaults: defaults).ignoredPorts == [3000, 8080])
        #expect(Preferences(defaults: defaults).ignoredProcessNames == ["node", "rapportd"])
        defaults.set([70000, -1, 22], forKey: DefaultsKeys.ignoredPorts) // out-of-range junk
        #expect(Preferences(defaults: defaults).ignoredPorts == [22])
    }

    @Test func sortOrderFallsBackToPortOnUnknownValue() {
        let defaults = freshDefaults()
        defaults.set("bogus", forKey: DefaultsKeys.sortOrder)
        #expect(Preferences(defaults: defaults).sortOrder == .port)
    }

    @Test func keysCarryThePrefix() {
        for key in [DefaultsKeys.refreshInterval, DefaultsKeys.showCountInMenuBar, DefaultsKeys.ignoredPorts, DefaultsKeys.ignoredProcessNames, DefaultsKeys.sortOrder] {
            #expect(key.hasPrefix("squatter."))
        }
    }
}
