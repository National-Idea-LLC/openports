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

/// Runs the one fixed `lsof` command. Absolute path, fixed arguments, no shell, no user input.
struct LsofRunner: CommandRunning {
    static let executablePath = "/usr/sbin/lsof"
    static let arguments = ["-nP", "-iTCP", "-sTCP:LISTEN", "+c0", "-F", "pcunPT"]

    func run() async throws -> CommandResult {
        guard FileManager.default.isExecutableFile(atPath: Self.executablePath) else {
            throw ScanError.lsofNotFound(path: Self.executablePath)
        }

        let process = Process()
        process.executableURL = URL(filePath: Self.executablePath)
        process.arguments = Self.arguments
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

        // Drain both pipes concurrently so a large listing can't fill a pipe and stall lsof.
        async let stdout = Self.readToEnd(stdoutPipe.fileHandleForReading)
        async let stderr = Self.readToEnd(stderrPipe.fileHandleForReading)
        let (out, err) = try await (stdout, stderr)
        await exited.value

        return CommandResult(stdout: out, stderr: err, exitCode: process.terminationStatus)
    }

    private static func readToEnd(_ handle: FileHandle) async throws -> Data {
        var data = Data()
        for try await byte in handle.bytes { data.append(byte) }
        return data
    }
}
