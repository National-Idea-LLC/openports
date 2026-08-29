import Foundation

/// One container reported by `docker ps --no-trunc --format '{{json .}}'`. Property names
/// match Docker's own JSON keys verbatim (not Swift naming convention) so `Decodable` needs
/// no `CodingKeys`, and unknown keys are skipped automatically.
private struct DockerPSLine: Decodable {
    let ID: String
    let Image: String
    let Names: String
    let Ports: String
    let State: String
}

/// Thin `CommandRunning` wrapper around `ProcessRunner`, mirroring `LsofRunner`.
private struct DockerRunner: CommandRunning {
    let process: ProcessRunner
    func run() async throws -> CommandResult { try await process.run() }
}

/// Maps host ports to the Docker containers that published them.
///
/// Never blocks a scan: `snapshot()` returns the last known mapping immediately and kicks
/// off a refresh in the background when the cache is stale, so the first list after launch
/// is unannotated and the next one (a few seconds later) is annotated. `docker ps` talks to
/// the local daemon over a unix socket — nothing leaves the machine, so golden rule #6's ban
/// on network calls is unaffected.
actor DockerProbe {
    static let arguments = ["ps", "--no-trunc", "--format", "{{json .}}"]
    /// Shorter than lsof's 10 s: this is optional decoration, not the list itself.
    static let timeout: Duration = .seconds(3)
    static let freshFor: Duration = .seconds(5)
    /// After a failure (daemon not running is the common one) back off hard — otherwise a
    /// 2 s poll spawns a failing `docker ps` every two seconds forever.
    static let backoffAfterFailure: Duration = .seconds(30)

    /// Absolute paths only, in a fixed list — resolved by checking each candidate directly,
    /// never by asking the shell to resolve a bare command name. Covers Docker Desktop,
    /// Homebrew, Rancher Desktop and OrbStack.
    static let searchPaths: [String] = [
        "/usr/local/bin/docker",
        "/opt/homebrew/bin/docker",
        NSHomeDirectory() + "/.docker/bin/docker",
        NSHomeDirectory() + "/.rd/bin/docker",
        NSHomeDirectory() + "/.orbstack/bin/docker",
        "/Applications/Docker.app/Contents/Resources/bin/docker",
    ]

    /// First existing, executable candidate wins. The injected `isExecutable` closure is
    /// what makes this testable on a machine with no Docker.
    static func findExecutable(
        in paths: [String] = searchPaths,
        isExecutable: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) -> String? {
        paths.first(where: isExecutable)
    }

    private let commandRunner: (any CommandRunning)?
    private let clock: ContinuousClock
    private var isEnabled = true
    private var cache: [UInt16: ContainerRef] = [:]
    private var lastRefresh: ContinuousClock.Instant?
    private var failureUntil: ContinuousClock.Instant?
    private var refreshTask: Task<Void, Never>?

    /// `executablePath` defaults to a real filesystem check (`findExecutable()`), so a
    /// machine without Docker pays only that one-time check and never spawns anything —
    /// `commandRunner` stays `nil` and `runner` (even if a caller passed one) is ignored.
    /// Tests pass `executablePath: nil` explicitly to simulate "Docker not installed"
    /// deterministically, regardless of the injected `runner`.
    init(
        runner: (any CommandRunning)? = nil,
        executablePath: String? = DockerProbe.findExecutable(),
        clock: ContinuousClock = ContinuousClock()
    ) {
        self.clock = clock
        guard let executablePath else {
            self.commandRunner = nil
            return
        }
        self.commandRunner = runner ?? DockerRunner(process: ProcessRunner(
            executablePath: executablePath,
            arguments: Self.arguments,
            timeout: Self.timeout,
            environment: ["HOME": NSHomeDirectory()]
        ))
    }

    /// `setEnabled(false)` clears the cache and stops all refreshes.
    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        if !enabled {
            cache = [:]
            lastRefresh = nil
            failureUntil = nil
            refreshTask?.cancel()
            refreshTask = nil
        }
    }

    /// Cached mapping. Triggers a background refresh when stale; never awaits the subprocess.
    func snapshot() -> [UInt16: ContainerRef] {
        guard isEnabled, commandRunner != nil else { return [:] }
        if isStale {
            Task { await self.runRefresh() }
        }
        return cache
    }

    /// Runs `docker ps` now and updates the cache. Tests call this to be deterministic.
    func refreshNow() async {
        guard isEnabled, commandRunner != nil else { return }
        await runRefresh()
    }

    private var isStale: Bool {
        guard let lastRefresh else { return true }
        return clock.now - lastRefresh >= Self.freshFor
    }

    /// Only one refresh in flight at a time (same reasoning as `PortScanner.inFlight`).
    private func runRefresh() async {
        if let refreshTask {
            await refreshTask.value
            return
        }
        if let failureUntil, clock.now < failureUntil { return }
        let task = Task { await self.performRefresh() }
        refreshTask = task
        await task.value
        refreshTask = nil
    }

    /// Ignores errors entirely: any thrown error, non-zero exit, or non-UTF-8 output sets
    /// `failureUntil` and leaves the previous cache in place. Docker being absent or stopped
    /// is normal, not an error the user should see.
    private func performRefresh() async {
        guard let commandRunner else { return }
        do {
            let result = try await commandRunner.run()
            guard result.exitCode == 0 else {
                throw ScanError.nonZeroExit(code: result.exitCode, stderr: "")
            }
            guard let text = String(data: result.stdout, encoding: .utf8) else {
                throw ScanError.outputNotUTF8
            }
            cache = Self.parse(text)
            lastRefresh = clock.now
            failureUntil = nil
        } catch {
            failureUntil = clock.now + Self.backoffAfterFailure
        }
    }

    /// Parses `docker ps --no-trunc --format '{{json .}}'` NDJSON into host-port → container.
    /// Pure: no I/O, so it is fixture-tested exactly like `LsofParser`.
    ///
    /// A line that fails to decode is skipped, never thrown — same forward-compatibility
    /// posture as `LsofParser`, whose doc comment says malformed records are skipped.
    static func parse(_ output: String) -> [UInt16: ContainerRef] {
        var result: [UInt16: ContainerRef] = [:]
        let decoder = JSONDecoder()

        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let data = line.data(using: .utf8),
                  let entry = try? decoder.decode(DockerPSLine.self, from: data),
                  entry.State == "running"
            else { continue }

            let name = entry.Names.split(separator: ",", maxSplits: 1).first.map(String.init) ?? entry.Names

            for portMapping in entry.Ports.components(separatedBy: ", ") where !portMapping.isEmpty {
                // JSONDecoder already unescaped `>` back into `>` for us — parse the
                // decoded string, never the raw NDJSON bytes.
                guard let arrow = portMapping.range(of: "->") else { continue } // exposed, not published
                let left = portMapping[portMapping.startIndex..<arrow.lowerBound]
                let right = portMapping[arrow.upperBound...]
                guard right.hasSuffix("/tcp") else { continue } // UDP or other — Squatter lists TCP only
                let containerPortText = right.dropLast("/tcp".count)
                guard let lastColon = left.lastIndex(of: ":") else { continue }
                let hostPortText = left[left.index(after: lastColon)...]

                guard let hostRange = Self.portRange(hostPortText),
                      let containerRange = Self.portRange(containerPortText),
                      hostRange.count <= 1024 // refuse huge ranges rather than allocate from hostile input
                else { continue }

                if hostRange.count == containerRange.count {
                    for (hostPort, containerPort) in zip(hostRange, containerRange) where result[hostPort] == nil {
                        result[hostPort] = ContainerRef(id: entry.ID, name: name, image: entry.Image, containerPort: containerPort)
                    }
                } else {
                    for hostPort in hostRange where result[hostPort] == nil {
                        result[hostPort] = ContainerRef(id: entry.ID, name: name, image: entry.Image, containerPort: containerRange.lowerBound)
                    }
                }
            }
        }
        return result
    }

    /// Parses `"5432"` or `"9000-9002"` into an inclusive port range.
    private static func portRange(_ text: Substring) -> ClosedRange<UInt16>? {
        if let dash = text.firstIndex(of: "-") {
            guard let start = UInt16(text[text.startIndex..<dash]),
                  let end = UInt16(text[text.index(after: dash)...]),
                  start <= end
            else { return nil }
            return start...end
        }
        guard let value = UInt16(text) else { return nil }
        return value...value
    }
}
