import AppKit
import Foundation
import SwiftUI
import Testing
@testable import OpenPorts

/// Renders the popover in a real (offscreen) window and writes PNGs for eyeballing.
/// Not an assertion on pixels — a build-time sanity check that the views lay out.
@MainActor
struct SnapshotTests {
    private static let outputDirectory = URL(filePath: NSTemporaryDirectory()).appending(path: "openports-snapshots")

    private func snapshot<V: View>(_ view: V, name: String) throws -> URL {
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 360, height: 440)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        window.appearance = NSAppearance(named: .aqua)
        host.layoutSubtreeIfNeeded()
        let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        let png = try #require(rep.representation(using: .png, properties: [:]))
        try FileManager.default.createDirectory(at: Self.outputDirectory, withIntermediateDirectories: true)
        let url = Self.outputDirectory.appending(path: "\(name).png")
        try png.write(to: url)
        return url
    }

    private func loadedModel(_ lsof: String, kills: KillRecorder = KillRecorder(names: [42: "node", 7: "postgres", 1: "launchd"])) async -> PortListModel {
        let model = PortListModel(
            scanner: PortScanner(runner: FakeRunner(.success(lsofResult(lsof))), currentUID: 501, userName: testUserName),
            killer: kills.killer,
            actions: RecordingActions(),
            preferences: Preferences(defaults: freshDefaults())
        )
        await model.refresh()
        return model
    }

    @Test func rendersListEmptyAndErrorStates() async throws {
        let many = sampleLsof
            + "p7\ncpostgres\nu501\nf1\nPTCP\nn127.0.0.1:5432\nTST=LISTEN\nf2\nPTCP\nn[::1]:5432\nTST=LISTEN\n"
            + "p1\nclaunchd\nu0\nf1\nPTCP\nn*:22\nTST=LISTEN\n"
            + "p9\ncT3 Code (Alpha)\nu501\nf1\nPTCP\nn127.0.0.1:61921\nTST=LISTEN\n"
        let list = await loadedModel(many)
        list.selection = sampleListener.id
        let listURL = try snapshot(PortListView(model: list), name: "list")

        let stubborn = await loadedModel(many)
        await stubborn.kill(sampleListener) // names never change → .stillRunning after the grace period
        let stubbornURL = try snapshot(PortListView(model: stubborn), name: "list-force-kill")

        let empty = await loadedModel("")
        let emptyURL = try snapshot(PortListView(model: empty), name: "empty")

        let failing = PortListModel(
            scanner: PortScanner(runner: FakeRunner(.failure(.lsofNotFound(path: "/usr/sbin/lsof"))), currentUID: 501),
            killer: KillRecorder(names: [:]).killer,
            actions: RecordingActions(),
            preferences: Preferences(defaults: freshDefaults())
        )
        await failing.refresh()
        let errorURL = try snapshot(PortListView(model: failing), name: "error")

        for url in [listURL, stubbornURL, emptyURL, errorURL] {
            let size = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int ?? 0
            #expect(size > 1_000, "\(url.lastPathComponent) looks blank")
        }
        print("SNAPSHOTS: \(Self.outputDirectory.path)")
    }
}
