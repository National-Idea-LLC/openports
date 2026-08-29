import Foundation

/// The Docker container that published a host port, when Squatter could identify one.
struct ContainerRef: Hashable, Sendable {
    /// Full container ID from `docker ps --no-trunc`. Used by plan 008 to stop it.
    let id: String
    /// Container name, e.g. `api-db-1`. What the row shows instead of `com.docker.backend`.
    let name: String
    /// Image reference, e.g. `postgres:16`.
    let image: String
    /// The port *inside* the container, which is often different from the host port.
    let containerPort: UInt16

    /// First 12 characters — how `docker ps` prints an ID and how a user would recognise it.
    var shortID: String { String(id.prefix(12)) }
}

/// One listening TCP socket, collapsed across address families.
/// Identity is `(pid, port)`; IPv4/IPv6 rows for the same pair merge into one `Listener`.
struct Listener: Identifiable, Hashable, Sendable {
    let port: UInt16
    let pid: pid_t
    let processName: String
    let user: String
    let addresses: Set<String>
    let isOwnedByCurrentUser: Bool
    let container: ContainerRef?

    init(
        port: UInt16,
        pid: pid_t,
        processName: String,
        user: String,
        addresses: Set<String>,
        isOwnedByCurrentUser: Bool,
        container: ContainerRef? = nil
    ) {
        self.port = port
        self.pid = pid
        self.processName = processName
        self.user = user
        self.addresses = addresses
        self.isOwnedByCurrentUser = isOwnedByCurrentUser
        self.container = container
    }

    var id: String { "\(pid):\(port)" }

    /// `http://localhost:<port>` — what "Open" and "Copy URL" act on.
    var localURLString: String { "http://localhost:\(port)" }

    /// What the row calls this listener: the container name when there is one, otherwise
    /// the process name. `com.docker.backend` tells the user nothing.
    var displayName: String { container?.name ?? processName }

    /// Copy of this listener carrying `container`. Annotation happens in `PortScanner`
    /// after parsing, so `LsofParser` stays a pure function that knows nothing about Docker.
    func withContainer(_ container: ContainerRef?) -> Listener {
        Listener(
            port: port, pid: pid, processName: processName, user: user,
            addresses: addresses, isOwnedByCurrentUser: isOwnedByCurrentUser,
            container: container
        )
    }
}
