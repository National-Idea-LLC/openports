import AppKit
import Foundation
import SwiftUI
import Testing
@testable import Squatter

/// Renders the popover in a real (offscreen) window and writes PNGs for eyeballing.
/// Not an assertion on pixels — a build-time sanity check that the views lay out.
@MainActor
struct SnapshotTests {
    private static let outputDirectory = URL(filePath: NSTemporaryDirectory()).appending(path: "squatter-snapshots")

    private func snapshot<V: View>(_ view: V, name: String, size: CGSize = CGSize(width: 360, height: 460), dark: Bool = false) throws -> URL {
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
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
        let listURL = try snapshot(PortListView(model: list, settings: SettingsModel(loginItem: FakeLoginItem(), preferences: Preferences(defaults: freshDefaults()))), name: "list")
        let darkURL = try snapshot(PortListView(model: list, settings: SettingsModel(loginItem: FakeLoginItem(), preferences: Preferences(defaults: freshDefaults()))), name: "list-dark", dark: true)

        let stubborn = await loadedModel(many)
        await stubborn.kill(sampleListener) // names never change → .stillRunning after the grace period
        let stubbornURL = try snapshot(PortListView(model: stubborn, settings: SettingsModel(loginItem: FakeLoginItem(), preferences: Preferences(defaults: freshDefaults()))), name: "list-force-kill")

        let empty = await loadedModel("")
        let emptyURL = try snapshot(PortListView(model: empty, settings: SettingsModel(loginItem: FakeLoginItem(), preferences: Preferences(defaults: freshDefaults()))), name: "empty")

        let failing = PortListModel(
            scanner: PortScanner(runner: FakeRunner(.failure(.lsofNotFound(path: "/usr/sbin/lsof"))), currentUID: 501),
            killer: KillRecorder(names: [:]).killer,
            actions: RecordingActions(),
            preferences: Preferences(defaults: freshDefaults())
        )
        await failing.refresh()
        let errorURL = try snapshot(PortListView(model: failing, settings: SettingsModel(loginItem: FakeLoginItem(), preferences: Preferences(defaults: freshDefaults()))), name: "error")

        let ignoring = await loadedModel(many)
        ignoring.ignorePort(of: sampleListener)
        ignoring.ignoreProcess(of: Listener(port: 22, pid: 1, processName: "launchd", user: "root", addresses: ["*"], isOwnedByCurrentUser: false))
        ignoring.showIgnored = true
        let ignoredURL = try snapshot(PortListView(model: ignoring, settings: SettingsModel(loginItem: FakeLoginItem(), preferences: Preferences(defaults: freshDefaults()))), name: "list-ignored")

        let approval = FakeLoginItem(status: .requiresApproval)
        let settings = SettingsModel(loginItem: approval, preferences: Preferences(defaults: freshDefaults()))
        let settingsURL = try snapshot(SettingsView(settings: settings, model: ignoring).frame(width: 320), name: "settings", size: CGSize(width: 320, height: 560))

        for url in [listURL, darkURL, stubbornURL, emptyURL, errorURL, ignoredURL, settingsURL] {
            let size = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int ?? 0
            #expect(size > 1_000, "\(url.lastPathComponent) looks blank")
        }
        print("SNAPSHOTS: \(Self.outputDirectory.path)")
    }
}
