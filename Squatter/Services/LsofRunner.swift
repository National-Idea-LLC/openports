import Foundation

/// Captured result of a finished child process.
struct CommandResult: Sendable, Equatable {
    let stdout: Data
    let stderr: Data
    let exitCode: Int32
}

/// Anything that can produce `lsof` output. `LsofRunner` is the real one; tests inject fakes.
protocol CommandRunning: Sendable {
    func run() async throws -> CommandResult
}

/// Why a scan could not produce a listener list. Messages follow the "what / why / next" rule.
enum ScanError: Error, Equatable, Sendable, LocalizedError {
    case lsofNotFound(path: String)
    case launchFailed(String)
    case nonZeroExit(code: Int32, stderr: String)
    case outputNotUTF8

    var errorDescription: String? {
        switch self {
        case .lsofNotFound(let path):
            String(localized: "Couldn't find lsof at \(path). Squatter needs the system lsof tool to list ports.")
        case .launchFailed(let reason):
            String(localized: "Couldn't start lsof: \(reason). Try refreshing.")
        case .nonZeroExit(let code, let stderr):
            String(localized: "lsof exited with code \(code). \(stderr.isEmpty ? "" : stderr) Try refreshing.")
        case .outputNotUTF8:
            String(localized: "lsof returned output Squatter couldn't read. Try refreshing.")
        }
    }
}

/// Runs one child process to completion and captures both output streams.
///
/// The executable path and arguments are fixed at construction and are never derived from
/// user input: in production the only caller is `LsofRunner`, which supplies its own
/// constants. Nothing here parses a command line or spawns a shell.
struct ProcessRunner: Sendable {
    let executablePath: String
    let arguments: [String]

    func run() async throws -> CommandResult {
        // Reused from the one-subprocess world: the app only ever runs `lsof`, so a missing
        // executable is always "lsof not found" even though this type is now generic.
        guard FileManager.default.isExecutableFile(atPath: executablePath) else {
            throw ScanError.lsofNotFound(path: executablePath)
        }

        let process = Process()
        process.executableURL = URL(filePath: executablePath)
        process.arguments = arguments
        process.environment = [:]
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.standardInput = FileHandle.nullDevice

        // Register for termination before launching so a fast exit can't be missed.
        let exited = Task<Void, Never> {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                process.terminationHandler = { _ in continuation.resume() }
            }
        }

        do {
            try process.run()
        } catch {
            exited.cancel()
            throw ScanError.launchFailed(error.localizedDescription)
        }

        // Drain both pipes on separate threads so a large listing can't fill a pipe and
        // stall the child. See readToEnd — doing this with FileHandle.bytes deadlocks.
        async let stdout = Self.readToEnd(stdoutPipe.fileHandleForReading)
        async let stderr = Self.readToEnd(stderrPipe.fileHandleForReading)
        let (out, err) = try await (stdout, stderr)
        await exited.value

        return CommandResult(stdout: out, stderr: err, exitCode: process.terminationStatus)
    }

    /// Each pipe is drained by a blocking read on its own thread. The obvious
    /// `for try await byte in handle.bytes` version deadlocks: `FileHandle.bytes`
    /// serialises reads across handles, so the stderr drain waits for output the child
    /// won't write until it exits, while the child blocks writing to a full 64 KB stdout
    /// pipe. Measured: 128 KB of stdout hung forever; this moves 4 MB in ~6 ms.
    private static func readToEnd(_ handle: FileHandle) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global().async {
                do { continuation.resume(returning: try handle.readToEnd() ?? Data()) }
                catch { continuation.resume(throwing: error) }
            }
        }
    }
}

/// Runs the one fixed `lsof` command. Absolute path, fixed arguments, no shell, no user input.
struct LsofRunner: CommandRunning {
    static let executablePath = "/usr/sbin/lsof"
    static let arguments = ["-nP", "-iTCP", "-sTCP:LISTEN", "+c0", "-F", "pcunPT"]

    private let process = ProcessRunner(
        executablePath: LsofRunner.executablePath,
        arguments: LsofRunner.arguments
    )

    func run() async throws -> CommandResult { try await process.run() }
}
