import Foundation

/// One listening TCP socket, collapsed across address families.
/// Identity is `(pid, port)`; IPv4/IPv6 rows for the same pair merge into one `Listener`.
struct Listener: Identifiable, Hashable, Sendable {
    let port: UInt16
    let pid: pid_t
    let processName: String
    let user: String
    let addresses: Set<String>
    let isOwnedByCurrentUser: Bool

    var id: String { "\(pid):\(port)" }

    /// `http://localhost:<port>` — what "Open" and "Copy URL" act on.
    var localURLString: String { "http://localhost:\(port)" }
}
