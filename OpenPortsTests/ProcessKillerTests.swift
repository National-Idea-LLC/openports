import Darwin
import Foundation
import Synchronization
import Testing
@testable import OpenPorts

/// Records signals and serves scripted process names, so no real process is touched.
private final class Recorder: Sendable {
    private let state = Mutex<State>(State())
    private struct State { var signals: [(pid_t, Int32)] = []; var names: [pid_t: String] = [:]; var signalResult: Int32 = 0 }

    init(names: [pid_t: String], signalResult: Int32 = 0) {
        state.withLock { $0.names = names; $0.signalResult = signalResult }
    }
    var signals: [(pid_t, Int32)] { state.withLock { $0.signals } }
    func setName(_ name: String?, for pid: pid_t) { state.withLock { $0.names[pid] = name } }

    var killer: ProcessKiller {
        ProcessKiller(
            signal: { pid, sig in self.state.withLock { $0.signals.append((pid, sig)); return $0.signalResult } },
            processName: { pid in self.state.withLock { $0.names[pid] } }
        )
    }
}

private let node = Listener(port: 3000, pid: 42, processName: "node", user: "elyas", addresses: ["*"], isOwnedByCurrentUser: true)

struct ProcessKillerTests {
    @Test func sendsSigtermByDefaultAndSigkillWhenForced() throws {
        let rec = Recorder(names: [42: "node"])
        try rec.killer.terminate(node)
        try rec.killer.terminate(node, force: true)
        #expect(rec.signals.map(\.0) == [42, 42])
        #expect(rec.signals.map(\.1) == [SIGTERM, SIGKILL])
    }

    @Test func refusesWhenPidNowBelongsToAnotherProcess() {
        let rec = Recorder(names: [42: "Safari"])
        #expect(throws: KillError.processChanged(pid: 42, expected: "node", actual: "Safari")) {
            try rec.killer.terminate(node)
        }
        #expect(rec.signals.isEmpty, "must not signal a mismatched PID")
    }

    @Test func refusesWhenProcessAlreadyExited() {
        let rec = Recorder(names: [:])
        #expect(throws: KillError.processChanged(pid: 42, expected: "node", actual: nil)) {
            try rec.killer.terminate(node)
        }
        #expect(rec.signals.isEmpty)
    }

    @Test func mapsErrnoToTypedErrors() {
        #expect(throws: KillError.notPermitted(pid: 42, processName: "node")) {
            try Recorder(names: [42: "node"], signalResult: EPERM).killer.terminate(node)
        }
        #expect(throws: KillError.noSuchProcess(pid: 42, processName: "node")) {
            try Recorder(names: [42: "node"], signalResult: ESRCH).killer.terminate(node)
        }
        #expect(throws: KillError.failed(pid: 42, processName: "node", errno: EINVAL)) {
            try Recorder(names: [42: "node"], signalResult: EINVAL).killer.terminate(node)
        }
    }

    @Test func isRunningRequiresMatchingName() {
        let rec = Recorder(names: [42: "node"])
        #expect(rec.killer.isRunning(node))
        rec.setName("Safari", for: 42)
        #expect(!rec.killer.isRunning(node))
        rec.setName(nil, for: 42)
        #expect(!rec.killer.isRunning(node))
    }

    @Test func waitForExitReturnsTrueOnceGone() async {
        let rec = Recorder(names: [42: "node"])
        let waiter = Task { await rec.killer.waitForExit(of: node, timeout: .seconds(2), pollEvery: .milliseconds(10)) }
        try? await Task.sleep(for: .milliseconds(30))
        rec.setName(nil, for: 42)
        #expect(await waiter.value == true)
    }

    @Test func waitForExitTimesOutWhileStillRunning() async {
        let rec = Recorder(names: [42: "node"])
        let exited = await rec.killer.waitForExit(of: node, timeout: .milliseconds(50), pollEvery: .milliseconds(10))
        #expect(exited == false)
    }

    @Test func errorMessagesSayWhatWhyAndNext() {
        let changed = KillError.processChanged(pid: 42, expected: "node", actual: "Safari").errorDescription ?? ""
        #expect(changed.contains("node") && changed.contains("Safari") && changed.contains("Refresh"))
        let denied = KillError.notPermitted(pid: 42, processName: "launchd").errorDescription ?? ""
        #expect(denied.contains("another user"))
    }

    // MARK: integration — real kill(2) against a child we own

    @Test func reallyTerminatesAChildProcess() async throws {
        let child = Process()
        child.executableURL = URL(filePath: "/bin/sleep")
        child.arguments = ["30"]
        try child.run()
        let listener = Listener(port: 1, pid: child.processIdentifier, processName: "sleep", user: "me", addresses: ["*"], isOwnedByCurrentUser: true)

        let killer = ProcessKiller()
        #expect(killer.isRunning(listener))
        try killer.terminate(listener)
        child.waitUntilExit()
        #expect(child.terminationReason == .uncaughtSignal)
        #expect(!killer.isRunning(listener))
    }
}
