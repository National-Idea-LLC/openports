import Foundation
import Testing
@testable import Squatter

struct LsofParserTests {
    private static func users(_ uid: uid_t) -> String {
        switch uid {
        case 501: "elyas"
        case 0: "root"
        default: "uid\(uid)"
        }
    }

    private func parse(_ text: String, currentUID: uid_t = 501) -> [Listener] {
        LsofParser.parse(text, currentUID: currentUID, userName: Self.users)
    }

    @Test func singleListener() {
        let out = """
        p42
        cnode
        u501
        f23
        PTCP
        n*:3000
        TST=LISTEN
        TQR=0
        TQS=0
        """
        let result = parse(out)
        #expect(result.count == 1)
        #expect(result.first == Listener(
            port: 3000, pid: 42, processName: "node", user: "elyas",
            addresses: ["*"], isOwnedByCurrentUser: true
        ))
    }

    @Test func ipv4AndIpv6OnSamePortMerge() {
        let out = """
        p42
        cnode
        u501
        f23
        PTCP
        n127.0.0.1:3000
        TST=LISTEN
        f24
        PTCP
        n[::1]:3000
        TST=LISTEN
        """
        let result = parse(out)
        #expect(result.count == 1)
        #expect(result[0].addresses == ["127.0.0.1", "::1"])
    }

    @Test func samePortDifferentProcessesStaySeparate() {
        let out = "p1\ncalpha\nu501\nf1\nPTCP\nn*:8080\nTST=LISTEN\np2\ncbeta\nu501\nf1\nPTCP\nn*:8080\nTST=LISTEN\n"
        let result = parse(out)
        #expect(result.map(\.processName) == ["alpha", "beta"])
    }

    @Test func sortedByPortThenName() {
        let out = "p9\nczeta\nu501\nf1\nPTCP\nn*:9000\nTST=LISTEN\np3\ncalpha\nu501\nf1\nPTCP\nn*:80\nTST=LISTEN\nf2\nPTCP\nn*:9000\nTST=LISTEN\n"
        #expect(parse(out).map { "\($0.processName):\($0.port)" } == ["alpha:80", "alpha:9000", "zeta:9000"])
    }

    @Test func ownershipAndUserResolution() {
        let out = "p1\nclaunchd\nu0\nf1\nPTCP\nn*:22\nTST=LISTEN\np2\ncnode\nu501\nf1\nPTCP\nn*:3000\nTST=LISTEN\n"
        let result = parse(out)
        #expect(result[0].user == "root")
        #expect(result[0].isOwnedByCurrentUser == false)
        #expect(result[1].user == "elyas")
        #expect(result[1].isOwnedByCurrentUser == true)
    }

    @Test func skipsNonListenAndMalformedRecords() {
        let out = """
        p1
        cweird
        u501
        f1
        PTCP
        n*:1000
        TST=ESTABLISHED
        f2
        PTCP
        nnot-an-endpoint
        TST=LISTEN
        f3
        PTCP
        n*:99999
        TST=LISTEN
        f4
        PTCP
        n*:1001
        TST=LISTEN
        """
        #expect(parse(out).map(\.port) == [1001])
    }

    @Test func toleratesMissingStateAndUnknownFields() {
        let out = "p1\ncx\nu501\nZfuture-field\nf1\nPTCP\nn*:5\n"
        #expect(parse(out).map(\.port) == [5])
    }

    @Test func emptyAndGarbageInputYieldNothing() {
        #expect(parse("").isEmpty)
        #expect(parse("\n\n").isEmpty)
        #expect(parse("n*:3000\nTST=LISTEN\n").isEmpty) // socket with no process context
        #expect(parse("pabc\ncx\nu501\nf1\nn*:3000\n").isEmpty) // unparsable pid
    }

    @Test func endpointParsing() {
        #expect(LsofParser.Endpoint(parsing: "*:3000") == .init(address: "*", port: 3000))
        #expect(LsofParser.Endpoint(parsing: "[::1]:8080") == .init(address: "::1", port: 8080))
        #expect(LsofParser.Endpoint(parsing: "[fe80::1%en0]:443") == .init(address: "fe80::1%en0", port: 443))
        #expect(LsofParser.Endpoint(parsing: ":3000") == nil)
        #expect(LsofParser.Endpoint(parsing: "3000") == nil)
        #expect(LsofParser.Endpoint(parsing: "*:") == nil)
    }

    @Test func realFixtureParsesAndCollapsesDuplicates() throws {
        let url = try #require(Bundle(for: Anchor.self).url(forResource: "lsof-sample", withExtension: "txt"))
        let text = try String(contentsOf: url, encoding: .utf8)
        let result = parse(text)

        let rawRows = text.split(separator: "\n").filter { $0.hasPrefix("n") }.count
        #expect(!result.isEmpty)
        #expect(result.count < rawRows, "duplicate (pid, port) rows must collapse")
        #expect(Set(result.map(\.id)).count == result.count, "ids are unique")
        #expect(result == result.sorted { ($0.port, $0.processName, $0.pid) < ($1.port, $1.processName, $1.pid) })
        #expect(result.contains { $0.addresses.contains("::1") }, "fixture has an [::1] listener")
        #expect(result.contains { $0.addresses.contains("*") })
    }
}

private final class Anchor {}
