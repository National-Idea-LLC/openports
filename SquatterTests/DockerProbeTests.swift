import Foundation
import Testing
@testable import Squatter

struct DockerProbeTests {
    @Test func fixtureMapsHostPortsToContainers() throws {
        let url = try #require(Bundle(for: Anchor.self).url(forResource: "docker-ps-sample", withExtension: "txt"))
        let text = try String(contentsOf: url, encoding: .utf8)
        let containers = DockerProbe.parse(text)

        let db = try #require(containers[5432])
        #expect(db.name == "api-db-1")
        #expect(db.image == "postgres:16")
        #expect(db.containerPort == 5432)

        let cache = try #require(containers[6380])
        #expect(cache.name == "api-cache-1")
        #expect(cache.image == "redis:7-alpine")
        #expect(cache.containerPort == 6379)

        let edge = try #require(containers[8080])
        #expect(edge.name == "edge")
        #expect(edge.image == "nginx:alpine")
        #expect(edge.containerPort == 80)
    }

    @Test func portRangesExpand() throws {
        let url = try #require(Bundle(for: Anchor.self).url(forResource: "docker-ps-sample", withExtension: "txt"))
        let text = try String(contentsOf: url, encoding: .utf8)
        let containers = DockerProbe.parse(text)

        for (hostPort, containerPort) in [(9000, 9000), (9001, 9001), (9002, 9002)] {
            let ref = try #require(containers[UInt16(hostPort)])
            #expect(ref.name == "edge")
            #expect(ref.containerPort == UInt16(containerPort))
        }
    }

    @Test func unpublishedAndUdpPortsAreSkipped() throws {
        let url = try #require(Bundle(for: Anchor.self).url(forResource: "docker-ps-sample", withExtension: "txt"))
        let text = try String(contentsOf: url, encoding: .utf8)
        let containers = DockerProbe.parse(text)
        #expect(containers[443] == nil, "exposed but not published")

        let udpLine = """
        {"ID":"deadbeef0000111122223333444455556666777788889999aaaabbbbccccdddd","Image":"dnsmasq","Names":"dns-1","Ports":"0.0.0.0:5300->53/udp","State":"running"}
        """
        #expect(DockerProbe.parse(udpLine).isEmpty)
    }

    @Test func nonRunningContainersAreSkipped() {
        let exitedLine = """
        {"ID":"1111222233334444555566667777888899990000aaaabbbbccccddddeeeeffff","Image":"redis:7","Names":"old-cache","Ports":"0.0.0.0:7000->6379/tcp","State":"exited"}
        """
        #expect(DockerProbe.parse(exitedLine).isEmpty)
    }

    @Test func garbageLinesAreSkippedNotThrown() throws {
        let url = try #require(Bundle(for: Anchor.self).url(forResource: "docker-ps-sample", withExtension: "txt"))
        let goodLine = try String(contentsOf: url, encoding: .utf8)
            .split(separator: "\n")
            .first { $0.contains("api-db-1") }
        let goodLineText = try #require(goodLine)
        let containers = DockerProbe.parse("not json\n" + goodLineText)
        #expect(containers[5432]?.name == "api-db-1")
    }

    @Test func absentDockerNeverSpawnsAProcess() async {
        #expect(DockerProbe.findExecutable(in: ["/nope"], isExecutable: { _ in false }) == nil)

        let fake = FakeRunner(.success(lsofResult("")))
        let probe = DockerProbe(runner: fake, executablePath: nil)
        #expect(await probe.snapshot().isEmpty)
        await probe.refreshNow()
        #expect(await fake.launches == 0)
    }

    @Test func failureBacksOffAndKeepsTheLastGoodMapping() async throws {
        let url = try #require(Bundle(for: Anchor.self).url(forResource: "docker-ps-sample", withExtension: "txt"))
        let text = try String(contentsOf: url, encoding: .utf8)

        let fake = FakeRunner(.success(lsofResult(text)))
        let probe = DockerProbe(runner: fake, executablePath: "/test/docker")
        await probe.refreshNow()
        #expect(await probe.snapshot()[5432]?.name == "api-db-1")

        await fake.set(.failure(.launchFailed("daemon")))
        await probe.refreshNow()
        let snapshotAfterFailure = await probe.snapshot()
        #expect(snapshotAfterFailure[5432]?.name == "api-db-1", "previous cache survives a failed refresh")
    }
}

private final class Anchor {}
