import Foundation
import Testing
@testable import Squatter

struct ContainerStopperTests {
    private let sampleContainer = ContainerRef(id: "aa11bb22cc33", name: "api-db-1", image: "postgres:16", containerPort: 5432)

    @Test func validIDsAreAcceptedAndInvalidOnesRejected() {
        #expect(ContainerStopper.isValidID("aa11bb22cc33")) // 12 chars
        #expect(ContainerStopper.isValidID(String(repeating: "a", count: 64))) // 64 chars
        #expect(!ContainerStopper.isValidID(""))
        #expect(!ContainerStopper.isValidID("ABCDEF123456"))
        #expect(!ContainerStopper.isValidID("abc"))
        #expect(!ContainerStopper.isValidID("--rm; rm -rf /"))
        #expect(!ContainerStopper.isValidID("a b"))
        #expect(!ContainerStopper.isValidID(String(repeating: "a", count: 65)))
    }

    @Test func stopBuildsTheExactArgv() {
        #expect(ContainerStopper.arguments(id: "aa11bb22cc33") == ["stop", "-t", "5", "aa11bb22cc33"])
    }

    @Test func invalidIDNeverRunsAnything() async {
        let recorder = StopRecorder()
        let stopper = recorder.stopper
        let badContainer = ContainerRef(id: "; rm -rf ~", name: "x", image: "y", containerPort: 1)
        await #expect(throws: ContainerStopError.invalidID) {
            try await stopper.stop(badContainer)
        }
        #expect(recorder.launches.isEmpty)
    }

    @Test func nonZeroExitSurfacesStderr() async {
        let recorder = StopRecorder(result: .success(CommandResult(
            stdout: Data(),
            stderr: Data("Error response from daemon: No such container".utf8),
            exitCode: 1
        )))
        let stopper = recorder.stopper
        do {
            try await stopper.stop(sampleContainer)
            Issue.record("expected .failed to be thrown")
        } catch let error as ContainerStopError {
            guard case .failed(let message) = error else {
                Issue.record("expected .failed, got \(error)")
                return
            }
            #expect(message.contains("No such container"))
            #expect(error.errorDescription?.contains("Try `docker stop`") == true)
        } catch {
            Issue.record("unexpected error type \(error)")
        }
    }

    @Test func missingDockerThrowsNotFound() async {
        let recorder = StopRecorder(dockerAvailable: false)
        let stopper = recorder.stopper
        await #expect(throws: ContainerStopError.dockerNotFound) {
            try await stopper.stop(sampleContainer)
        }
        #expect(recorder.launches.isEmpty)
    }
}
