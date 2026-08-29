import Foundation

/// Why a container could not be stopped. Messages follow the "what / why / next" rule.
enum ContainerStopError: Error, Equatable, Sendable, LocalizedError {
    case dockerNotFound
    case invalidID
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .dockerNotFound:
            String(localized: "Couldn't find the docker command. Start Docker Desktop, or stop this container from your terminal.")
        case .invalidID:
            String(localized: "Couldn't stop this container: Squatter didn't recognise its ID. Refresh and try again.")
        case .failed(let reason):
            String(localized: "Couldn't stop this container. \(reason) Try `docker stop` in your terminal.")
        }
    }
}

/// Thin `CommandRunning` wrapper around `ProcessRunner`, mirroring `LsofRunner`/`DockerProbe`.
private struct StopRunner: CommandRunning {
    let process: ProcessRunner
    func run() async throws -> CommandResult { try await process.run() }
}

/// Runs `docker stop` for one container. Separate from `ProcessKiller` on purpose: that type
/// only ever calls `kill(2)`, and this one only ever runs one fixed subprocess. **Stop only**
/// — never removes, force-kills, or restarts a container, and never discards its state.
struct ContainerStopper: Sendable {
    /// `--time 5`: SIGTERM, then SIGKILL after five seconds. Docker's default is ten, which
    /// is a long time to watch a spinner.
    static func arguments(id: String) -> [String] { ["stop", "--time", "5", id] }
    /// Long enough to cover `--time 5` plus Docker's own overhead, well short of forever.
    static let timeout: Duration = .seconds(20)

    /// Only lowercase hex, 12-64 characters — the exact shape of a Docker container ID.
    /// The ID is the one argument in this app that comes from parsed output rather than a
    /// constant, so it is validated before it can reach `Process`. `allSatisfy` over a fixed
    /// character set, not `NSRegularExpression` — simpler to audit for what it rejects.
    static func isValidID(_ id: String) -> Bool {
        (12...64).contains(id.count) && id.allSatisfy { "0123456789abcdef".contains($0) }
    }

    /// Builds the real runner from the discovered CLI path; injectable for tests so they
    /// spawn nothing.
    var makeRunner: @Sendable (String) -> (any CommandRunning)? = { id in
        guard let path = DockerProbe.findExecutable() else { return nil }
        return StopRunner(process: ProcessRunner(
            executablePath: path,
            arguments: ContainerStopper.arguments(id: id),
            timeout: ContainerStopper.timeout,
            environment: ["HOME": NSHomeDirectory()]
        ))
    }

    /// Validates the ID, finds the CLI, runs it, and throws on a non-zero exit. Exit 0
    /// returns normally. The ID is checked *before* `makeRunner` is ever called — no runner
    /// is constructed for a string that doesn't look like a container ID.
    func stop(_ container: ContainerRef) async throws {
        guard Self.isValidID(container.id) else { throw ContainerStopError.invalidID }
        guard let runner = makeRunner(container.id) else { throw ContainerStopError.dockerNotFound }

        let result: CommandResult
        do {
            result = try await runner.run()
        } catch {
            throw ContainerStopError.failed(error.localizedDescription)
        }

        guard result.exitCode == 0 else {
            let stderr = String(data: result.stderr, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw ContainerStopError.failed(stderr.isEmpty ? "docker exited with code \(result.exitCode)." : stderr)
        }
    }
}
