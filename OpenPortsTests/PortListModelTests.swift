import Foundation
import Testing
@testable import OpenPorts

@MainActor
struct PortListModelTests {
    private func makeModel(
        runner: FakeRunner = FakeRunner(.success(lsofResult(sampleLsof))),
        kills: KillRecorder = KillRecorder(names: [42: "node"]),
        actions: RecordingActions = RecordingActions(),
        defaults: UserDefaults = freshDefaults()
    ) -> PortListModel {
        PortListModel(
            scanner: PortScanner(runner: runner, currentUID: 501),
            killer: kills.killer,
            actions: actions,
            preferences: Preferences(defaults: defaults),
            forceKillGrace: .milliseconds(60),
            forceKillWait: .milliseconds(60)
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

    @Test func keysCarryThePrefix() {
        for key in [DefaultsKeys.refreshInterval, DefaultsKeys.showCountInMenuBar, DefaultsKeys.ignoredPorts, DefaultsKeys.ignoredProcessNames] {
            #expect(key.hasPrefix("openports."))
        }
    }
}
