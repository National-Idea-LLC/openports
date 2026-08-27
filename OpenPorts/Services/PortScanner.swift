import Foundation

/// Serialises `lsof` runs: at most one in flight, and every `scan()` call made while one is
/// running joins it and receives the same result instead of spawning another process.
actor PortScanner {
    private let runner: any CommandRunning
    private let currentUID: uid_t
    private var inFlight: Task<[Listener], any Error>?

    init(runner: any CommandRunning = LsofRunner(), currentUID: uid_t = getuid()) {
        self.runner = runner
        self.currentUID = currentUID
    }

    func scan() async throws -> [Listener] {
        if let inFlight {
            return try await inFlight.value
        }
        let task = Task { [runner, currentUID] in
            let result = try await runner.run()
            return try Self.listeners(from: result, currentUID: currentUID)
        }
        inFlight = task
        defer { inFlight = nil }
        return try await task.value
    }

    /// Exit-code contract: any stdout is parsed regardless of status (lsof exits 1 on partial
    /// results and 0/1 with warnings); empty stdout with status 0 or 1 means "nothing is
    /// listening"; anything else is a real failure.
    static func listeners(from result: CommandResult, currentUID: uid_t) throws -> [Listener] {
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
        return LsofParser.parse(stdout, currentUID: currentUID)
    }
}
