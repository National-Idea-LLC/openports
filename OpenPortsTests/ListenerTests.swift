import Foundation
import Testing
@testable import OpenPorts

struct ListenerTests {
    @Test func idCombinesPidAndPort() {
        let listener = Listener(
            port: 3000, pid: 42, processName: "node", user: "elyas",
            addresses: ["*"], isOwnedByCurrentUser: true
        )
        #expect(listener.id == "42:3000")
        #expect(listener.localURLString == "http://localhost:3000")
    }

    @Test func fixtureIsPresentAndInLsofFieldFormat() throws {
        let url = try #require(Bundle(for: FixtureAnchor.self).url(forResource: "lsof-sample", withExtension: "txt"))
        let text = try String(contentsOf: url, encoding: .utf8)
        let lines = text.split(separator: "\n")
        #expect(lines.first?.hasPrefix("p") == true)
        #expect(lines.contains("TST=LISTEN"))
    }
}

/// Class anchor so `Bundle(for:)` resolves the test bundle.
private final class FixtureAnchor {}
