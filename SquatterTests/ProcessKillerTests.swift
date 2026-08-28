import Darwin
import Foundation
import Testing
@testable import Squatter

struct ProcessKillerTests {
    @Test func sendsSigtermByDefaultAndSigkillWhenForced() throws {
        let rec = KillRecorder(names: [42: "node"])
        try rec.killer.terminate(sampleListener)
        try rec.killer.terminate(sampleListener, force: true)
        #expect(rec.signals.map(\.0) == [42, 42])
        #expect(rec.signals.map(\.1) == [SIGTERM, SIGKILL])
    }

    @Test func refusesWhenPidNowBelongsToAnotherProcess() {
        let rec = KillRecorder(names: [42: "Safari"])
        #expect(throws: KillError.processChanged(pid: 42, expected: "node", actual: "Safari")) {
            try rec.killer.terminate(sampleListener)
        }
        #expect(rec.signals.isEmpty, "must not signal a mismatched PID")
    }

    @Test func refusesWhenProcessAlreadyExited() {
        let rec = KillRecorder(names: [:])
        #expect(throws: KillError.processChanged(pid: 42, expected: "node", actual: nil)) {
            try rec.killer.terminate(sampleListener)
        }
        #expect(rec.signals.isEmpty)
    }

    @Test func mapsErrnoToTypedErrors() {
        #expect(throws: KillError.notPermitted(pid: 42, processName: "node")) {
            try KillRecorder(names: [42: "node"], signalResult: EPERM).killer.terminate(sampleListener)
        }
        #expect(throws: KillError.noSuchProcess(pid: 42, processName: "node")) {
            try KillRecorder(names: [42: "node"], signalResult: ESRCH).killer.terminate(sampleListener)
        }
        #expect(throws: KillError.failed(pid: 42, processName: "node", errno: EINVAL)) {
            try KillRecorder(names: [42: "node"], signalResult: EINVAL).killer.terminate(sampleListener)
        }
    }

    @Test func isRunningRequiresMatchingName() {
        let rec = KillRecorder(names: [42: "node"])
        #expect(rec.killer.isRunning(sampleListener))
        rec.setName("Safari", for: 42)
        #expect(!rec.killer.isRunning(sampleListener))
        rec.setName(nil, for: 42)
        #expect(!rec.killer.isRunning(sampleListener))
    }

    @Test func waitForExitReturnsTrueOnceGone() async {
        let rec = KillRecorder(names: [42: "node"])
        let waiter = Task { await rec.killer.waitForExit(of: sampleListener, timeout: .seconds(2), pollEvery: .milliseconds(10)) }
        try? await Task.sleep(for: .milliseconds(30))
        rec.setName(nil, for: 42)
        #expect(await waiter.value == true)
    }

    @Test func waitForExitTimesOutWhileStillRunning() async {
        let rec = KillRecorder(names: [42: "node"])
        let exited = await rec.killer.waitForExit(of: sampleListener, timeout: .milliseconds(50), pollEvery: .milliseconds(10))
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
