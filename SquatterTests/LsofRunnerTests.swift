import Foundation
import Testing
@testable import Squatter

struct LsofRunnerTests {
    @Test func capturesStdoutAndExitCodeOfASuccessfulCommand() async throws {
        let runner = ProcessRunner(executablePath: "/bin/echo", arguments: ["hello", "ports"])
        let result = try await runner.run()
        #expect(result.exitCode == 0)
        #expect(String(data: result.stdout, encoding: .utf8) == "hello ports\n")
        #expect(result.stderr.isEmpty)
    }

    @Test func capturesNonZeroExitAndStderr() async throws {
        let runner = ProcessRunner(executablePath: "/bin/ls", arguments: ["/nonexistent-path-for-test"])
        let result = try await runner.run()
        #expect(result.exitCode == 1)
        #expect(result.stdout.isEmpty)
        let stderr = try #require(String(data: result.stderr, encoding: .utf8))
        // The exact wording is the OS's, not ours — assert containment, not equality.
        #expect(stderr.contains("No such file or directory"))
    }

    @Test func missingExecutableThrowsLsofNotFound() async throws {
        let runner = ProcessRunner(executablePath: "/usr/sbin/definitely-not-lsof", arguments: [])
        await #expect(throws: ScanError.lsofNotFound(path: "/usr/sbin/definitely-not-lsof")) {
            try await runner.run()
        }
    }

    @Test func nonExecutableFileThrowsLsofNotFound() async throws {
        // /etc/hosts exists but isn't executable — distinct from a path that doesn't exist at all.
        let runner = ProcessRunner(executablePath: "/etc/hosts", arguments: [])
        await #expect(throws: ScanError.lsofNotFound(path: "/etc/hosts")) {
            try await runner.run()
        }
    }

    @Test func largeOutputDoesNotDeadlockTheDrain() async throws {
        // Regression test for the concurrent-drain design: 256 KB is well past the 64 KB pipe
        // buffer that would stall a sequential reader waiting on the other stream to finish.
        let runner = ProcessRunner(executablePath: "/bin/dd", arguments: ["if=/dev/zero", "bs=1024", "count=256"])
        let result = try await runner.run()
        #expect(result.stdout.count == 262_144)
        #expect(result.exitCode == 0)
        // dd also writes its summary to stderr; a non-empty value proves both pipes drained.
        #expect(!result.stderr.isEmpty)
    }

    @Test func emptyOutputIsNotAnError() async throws {
        let runner = ProcessRunner(executablePath: "/usr/bin/true", arguments: [])
        let result = try await runner.run()
        #expect(result.exitCode == 0)
        #expect(result.stdout.isEmpty)
        #expect(result.stderr.isEmpty)
    }

    @Test func lsofRunnerUsesTheFixedCommand() {
        // Guard against loosening the invariant later: LsofParser is written against exactly
        // these arguments, so changing them requires updating the parser and its fixtures too.
        #expect(LsofRunner.executablePath == "/usr/sbin/lsof")
        #expect(LsofRunner.arguments == ["-nP", "-iTCP", "-sTCP:LISTEN", "+c0", "-F", "pcunPT"])
    }
}
