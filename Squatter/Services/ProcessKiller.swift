import Darwin
import Foundation

/// Why a kill request did not signal the process. Messages follow the "what / why / next" rule.
enum KillError: Error, Equatable, Sendable, LocalizedError {
    /// The PID no longer belongs to the scanned process (exited, or the PID was reused).
    case processChanged(pid: pid_t, expected: String, actual: String?)
    case notPermitted(pid: pid_t, processName: String)
    case noSuchProcess(pid: pid_t, processName: String)
    case failed(pid: pid_t, processName: String, errno: Int32)

    var errorDescription: String? {
        switch self {
        case .processChanged(_, let expected, let actual):
            if let actual {
                String(localized: "Didn't kill \(expected): its PID now belongs to \(actual). Refresh the list and try again.")
            } else {
                String(localized: "\(expected) has already exited. Refresh the list.")
            }
        case .notPermitted(_, let name):
            String(localized: "Can't kill \(name): it's owned by another user. Stop it from that account or with sudo in Terminal.")
        case .noSuchProcess(_, let name):
            String(localized: "\(name) has already exited. Refresh the list.")
        case .failed(_, let name, let errno):
            String(localized: "Couldn't kill \(name) (error \(errno)). Try again or use Force Kill.")
        }
    }
}

/// Sends SIGTERM / SIGKILL with `kill(2)` — never a shell — and only after confirming the PID
/// still maps to the process name captured at scan time.
struct ProcessKiller: Sendable {
    /// Sends `signal` to `pid`; returns 0 on success or the `errno` value on failure.
    typealias Signal = @Sendable (_ pid: pid_t, _ signal: Int32) -> Int32
    /// Current name of the process with this PID, or `nil` if there is none.
    typealias NameLookup = @Sendable (_ pid: pid_t) -> String?

    private let signal: Signal
    private let processName: NameLookup

    init(signal: @escaping Signal = ProcessKiller.systemKill, processName: @escaping NameLookup = ProcessKiller.liveProcessName) {
        self.signal = signal
        self.processName = processName
    }

    /// SIGTERM by default; SIGKILL when `force` is set. Re-validates the PID first.
    func terminate(_ listener: Listener, force: Bool = false) throws(KillError) {
        try validate(listener)
        let result = signal(listener.pid, force ? SIGKILL : SIGTERM)
        switch result {
        case 0: return
        case EPERM: throw .notPermitted(pid: listener.pid, processName: listener.processName)
        case ESRCH: throw .noSuchProcess(pid: listener.pid, processName: listener.processName)
        default: throw .failed(pid: listener.pid, processName: listener.processName, errno: result)
        }
    }

    /// True while a process with this PID *and* this name exists. A reused PID reads as "gone".
    func isRunning(_ listener: Listener) -> Bool {
        processName(listener.pid) == listener.processName
    }

    /// Polls until the process is gone or `timeout` elapses. Returns `true` if it exited.
    func waitForExit(of listener: Listener, timeout: Duration, pollEvery: Duration = .milliseconds(100)) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while isRunning(listener) {
            if clock.now >= deadline { return false }
            do { try await Task.sleep(for: pollEvery, clock: clock) } catch { return !isRunning(listener) }
        }
        return true
    }

    private func validate(_ listener: Listener) throws(KillError) {
        let actual = processName(listener.pid)
        guard actual == listener.processName else {
            throw .processChanged(pid: listener.pid, expected: listener.processName, actual: actual)
        }
    }

    // MARK: - System defaults

    static let systemKill: Signal = { pid, sig in
        Darwin.kill(pid, sig) == 0 ? 0 : errno
    }

    /// `proc_name` returns the same string `lsof +c0` reports (verified against live processes).
    static let liveProcessName: NameLookup = { pid in
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let length = Int(proc_name(pid, &buffer, UInt32(buffer.count)))
        guard length > 0 else { return nil }
        return String(decoding: buffer.prefix(length).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}
