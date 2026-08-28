import Darwin
import Foundation
import Synchronization
@testable import OpenPorts

/// Scripted stand-in for `lsof` that counts launches, can hold each run open, and can be re-scripted.
actor FakeRunner: CommandRunning {
    private var result: Result<CommandResult, ScanError>
    private let delay: Duration
    private(set) var launches = 0

    init(_ result: Result<CommandResult, ScanError>, delay: Duration = .zero) {
        self.result = result
        self.delay = delay
    }

    func set(_ result: Result<CommandResult, ScanError>) { self.result = result }

    func run() async throws -> CommandResult {
        launches += 1
        if delay > .zero { try await Task.sleep(for: delay) }
        return try result.get()
    }
}

let sampleLsof = "p42\ncnode\nu501\nf1\nPTCP\nn*:3000\nTST=LISTEN\n"
let sampleListener = Listener(port: 3000, pid: 42, processName: "node", user: "elyas", addresses: ["*"], isOwnedByCurrentUser: true)

func lsofResult(_ stdout: String, code: Int32 = 0, stderr: String = "") -> CommandResult {
    CommandResult(stdout: Data(stdout.utf8), stderr: Data(stderr.utf8), exitCode: code)
}

/// Records signals and serves scripted process names, so no real process is touched.
final class KillRecorder: Sendable {
    private struct State {
        var signals: [(pid_t, Int32)] = []
        var names: [pid_t: String] = [:]
        var signalResult: Int32 = 0
        var onSignal: (@Sendable (pid_t, Int32) -> Void)?
    }
    private let state = Mutex<State>(State())

    init(names: [pid_t: String], signalResult: Int32 = 0) {
        state.withLock { $0.names = names; $0.signalResult = signalResult }
    }

    var signals: [(pid_t, Int32)] { state.withLock { $0.signals } }
    func setName(_ name: String?, for pid: pid_t) { state.withLock { $0.names[pid] = name } }
    /// Runs after each recorded signal — e.g. to make the process "exit" on SIGKILL.
    func onSignal(_ handler: @escaping @Sendable (pid_t, Int32) -> Void) { state.withLock { $0.onSignal = handler } }

    var killer: ProcessKiller {
        ProcessKiller(
            signal: { pid, sig in
                let (result, hook) = self.state.withLock { $0.signals.append((pid, sig)); return ($0.signalResult, $0.onSignal) }
                hook?(pid, sig)
                return result
            },
            processName: { pid in self.state.withLock { $0.names[pid] } }
        )
    }
}

/// Captures what the model asked the OS to do.
@MainActor
final class RecordingActions: SystemActions {
    private(set) var opened: [URL] = []
    private(set) var copied: [String] = []
    func open(_ url: URL) { opened.append(url) }
    func copy(_ text: String) { copied.append(text) }
}

/// A throwaway `UserDefaults` suite, wiped on creation.
func freshDefaults(_ name: String = #function) -> UserDefaults {
    let suite = "sa.ni.openports.tests.\(name)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return defaults
}
