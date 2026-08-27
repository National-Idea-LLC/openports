import Foundation
import Testing
@testable import OpenPorts

/// Scripted stand-in for `lsof` that counts launches and can hold each run open.
private actor FakeRunner: CommandRunning {
    private let result: Result<CommandResult, ScanError>
    private let delay: Duration
    private(set) var launches = 0

    init(_ result: Result<CommandResult, ScanError>, delay: Duration = .zero) {
        self.result = result
        self.delay = delay
    }

    func run() async throws -> CommandResult {
        launches += 1
        if delay > .zero { try await Task.sleep(for: delay) }
        return try result.get()
    }
}

private let sample = "p42\ncnode\nu501\nf1\nPTCP\nn*:3000\nTST=LISTEN\n"

private func ok(_ stdout: String, code: Int32 = 0, stderr: String = "") -> CommandResult {
    CommandResult(stdout: Data(stdout.utf8), stderr: Data(stderr.utf8), exitCode: code)
}

struct PortScannerTests {
    @Test func parsesRunnerOutput() async throws {
        let scanner = PortScanner(runner: FakeRunner(.success(ok(sample))), currentUID: 501)
        let listeners = try await scanner.scan()
        #expect(listeners.map(\.port) == [3000])
        #expect(listeners[0].isOwnedByCurrentUser)
    }

    @Test func concurrentScansCoalesceIntoOneLaunch() async throws {
        let runner = FakeRunner(.success(ok(sample)), delay: .milliseconds(150))
        let scanner = PortScanner(runner: runner, currentUID: 501)

        let results = try await withThrowingTaskGroup(of: [Listener].self) { group in
            for _ in 0..<5 { group.addTask { try await scanner.scan() } }
            return try await group.reduce(into: [[Listener]]()) { $0.append($1) }
        }

        #expect(results.count == 5)
        #expect(results.allSatisfy { $0.map(\.port) == [3000] })
        #expect(await runner.launches == 1)
    }

    @Test func sequentialScansLaunchAgain() async throws {
        let runner = FakeRunner(.success(ok(sample)))
        let scanner = PortScanner(runner: runner, currentUID: 501)
        _ = try await scanner.scan()
        _ = try await scanner.scan()
        #expect(await runner.launches == 2)
    }

    @Test func runnerErrorsPropagateAndDoNotStickTheActor() async throws {
        let runner = FakeRunner(.failure(.launchFailed("boom")))
        let scanner = PortScanner(runner: runner, currentUID: 501)
        await #expect(throws: ScanError.launchFailed("boom")) { try await scanner.scan() }
        await #expect(throws: ScanError.launchFailed("boom")) { try await scanner.scan() }
        #expect(await runner.launches == 2)
    }

    // MARK: exit-code contract

    @Test func emptyOutputWithExit0Or1MeansNoListeners() throws {
        #expect(try PortScanner.listeners(from: ok("", code: 0), currentUID: 501).isEmpty)
        #expect(try PortScanner.listeners(from: ok("", code: 1), currentUID: 501).isEmpty)
    }

    @Test func outputIsParsedEvenWhenExitCodeIs1() throws {
        let result = ok(sample, code: 1, stderr: "lsof: WARNING: can't stat() fuse file system\n")
        #expect(try PortScanner.listeners(from: result, currentUID: 501).map(\.port) == [3000])
    }

    @Test func emptyOutputWithOtherExitCodeThrows() {
        let result = ok("", code: 2, stderr: "lsof: unsupported option\n")
        #expect(throws: ScanError.nonZeroExit(code: 2, stderr: "lsof: unsupported option")) {
            try PortScanner.listeners(from: result, currentUID: 501)
        }
    }

    @Test func invalidUTF8Throws() {
        let result = CommandResult(stdout: Data([0xFF, 0xFE, 0x00]), stderr: Data(), exitCode: 0)
        #expect(throws: ScanError.outputNotUTF8) {
            try PortScanner.listeners(from: result, currentUID: 501)
        }
    }

    // MARK: integration — the real binary

    @Test func realLsofRunsAndProducesFieldOutput() async throws {
        let result = try await LsofRunner().run()
        #expect([0, 1].contains(result.exitCode), "unexpected lsof exit \(result.exitCode)")
        let text = try #require(String(data: result.stdout, encoding: .utf8))
        if !text.isEmpty {
            #expect(text.hasPrefix("p"))
            #expect(try !PortScanner.listeners(from: result, currentUID: getuid()).isEmpty)
        }
    }
}
