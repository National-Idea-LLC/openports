import Foundation

/// Pure parser for `lsof -nP -iTCP -sTCP:LISTEN +c0 -F pcunPT` field-mode output.
///
/// No I/O. User-name resolution and the current UID are injected so the parser
/// is deterministic under test; production callers use the defaults.
enum LsofParser {
    /// Parses raw `lsof -F` output into listeners sorted by port, then process name, then PID.
    /// Rows sharing `(pid, port)` (IPv4 + IPv6 sockets) merge into one listener whose
    /// `addresses` is the union. Malformed or non-LISTEN records are skipped, never thrown.
    static func parse(
        _ output: String,
        currentUID: uid_t = getuid(),
        userName: (uid_t) -> String = defaultUserName
    ) -> [Listener] {
        var listeners: [ListenerKey: Listener] = [:]
        var process: ProcessContext?
        var socket = SocketRecord()

        func flushSocket() {
            defer { socket = SocketRecord() }
            guard let process, socket.isListening, let endpoint = socket.endpoint else { return }
            let key = ListenerKey(pid: process.pid, port: endpoint.port)
            if let existing = listeners[key] {
                listeners[key] = existing.adding(address: endpoint.address)
            } else {
                listeners[key] = Listener(
                    port: endpoint.port,
                    pid: process.pid,
                    processName: process.command,
                    user: userName(process.uid),
                    addresses: [endpoint.address],
                    isOwnedByCurrentUser: process.uid == currentUID
                )
            }
        }

        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let prefix = line.first else { continue }
            let value = String(line.dropFirst())
            switch prefix {
            case "p":
                flushSocket()
                process = pid_t(value).map { ProcessContext(pid: $0) }
            case "c":
                process?.command = value
            case "u":
                if let uid = uid_t(value) { process?.uid = uid }
            case "f":
                flushSocket()
            case "n":
                socket.endpoint = Endpoint(parsing: value)
            case "T":
                if value.hasPrefix("ST=") { socket.state = String(value.dropFirst(3)) }
            default:
                continue // Unknown field: ignore for forward compatibility.
            }
        }
        flushSocket()

        return listeners.values.sorted {
            ($0.port, $0.processName, $0.pid) < ($1.port, $1.processName, $1.pid)
        }
    }

    /// Resolves a UID to a login name via `getpwuid`, falling back to the numeric UID.
    static func defaultUserName(_ uid: uid_t) -> String {
        guard let entry = getpwuid(uid), let name = entry.pointee.pw_name else { return String(uid) }
        return String(cString: name)
    }

    // MARK: - Internals

    private struct ListenerKey: Hashable {
        let pid: pid_t
        let port: UInt16
    }

    private struct ProcessContext {
        let pid: pid_t
        var command = ""
        var uid: uid_t = uid_t.max
    }

    private struct SocketRecord {
        var endpoint: Endpoint?
        var state: String?
        /// `lsof` was asked for LISTEN only; a missing `TST` field is tolerated, a different one is not.
        var isListening: Bool { state == nil || state == "LISTEN" }
    }

    struct Endpoint: Equatable {
        let address: String
        let port: UInt16

        init(address: String, port: UInt16) {
            self.address = address
            self.port = port
        }

        /// Accepts `*:3000`, `127.0.0.1:3000`, `[::1]:8080`; brackets are stripped from the address.
        init?(parsing text: String) {
            guard let colon = text.lastIndex(of: ":"), let port = UInt16(text[text.index(after: colon)...]) else {
                return nil
            }
            var host = String(text[..<colon])
            if host.hasPrefix("["), host.hasSuffix("]") { host = String(host.dropFirst().dropLast()) }
            guard !host.isEmpty else { return nil }
            self.address = host
            self.port = port
        }
    }
}

private extension Listener {
    func adding(address: String) -> Listener {
        Listener(
            port: port, pid: pid, processName: processName, user: user,
            addresses: addresses.union([address]), isOwnedByCurrentUser: isOwnedByCurrentUser
        )
    }
}
