import Foundation

/// Serialises `lsof` runs: at most one in flight, and every `scan()` call made while one is
/// running joins it and receives the same result instead of spawning another process.
actor PortScanner {
    typealias UserNameResolver = @Sendable (uid_t) -> String

    private let runner: any CommandRunning
    private let currentUID: uid_t
    private let userName: UserNameResolver
    private let docker: DockerProbe?
    private var inFlight: Task<[Listener], any Error>?

    init(
        runner: any CommandRunning = LsofRunner(),
        currentUID: uid_t = getuid(),
        userName: @escaping UserNameResolver = LsofParser.defaultUserName,
        docker: DockerProbe? = DockerProbe()
    ) {
        self.runner = runner
        self.currentUID = currentUID
        self.userName = userName
        self.docker = docker
    }

    /// Forwarded from the Docker Integration setting.
    func setDockerEnabled(_ enabled: Bool) async { await docker?.setEnabled(enabled) }

    func scan() async throws -> [Listener] {
        if let inFlight {
            return try await inFlight.value
        }
        let task = Task { [runner, currentUID, userName, docker] in
            let listeners = try Self.listeners(from: try await runner.run(), currentUID: currentUID, userName: userName)
            guard let docker else { return listeners }
            let containers = await docker.snapshot()
            guard !containers.isEmpty else { return listeners }
            return listeners.map { $0.withContainer(containers[$0.port]) }
        }
        inFlight = task
        defer { inFlight = nil }
        return try await task.value
    }

    /// Exit-code contract: any stdout is parsed regardless of status (lsof exits 1 on partial
    /// results and 0/1 with warnings); empty stdout with status 0 or 1 means "nothing is
    /// listening"; anything else is a real failure.
    static func listeners(
        from result: CommandResult,
        currentUID: uid_t,
        userName: UserNameResolver = LsofParser.defaultUserName
    ) throws -> [Listener] {
        guard let stdout = String(data: result.stdout, encoding: .utf8) else {
            throw ScanError.outputNotUTF8
        }
        if stdout.isEmpty {
            switch result.exitCode {
            case 0, 1:
                return []
            default:
                let stderr = String(data: result.stderr, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                throw ScanError.nonZeroExit(code: result.exitCode, stderr: stderr)
            }
        }
        return LsofParser.parse(stdout, currentUID: currentUID, userName: userName)
    }
}
