import AppKit
import Foundation
import SwiftUI
import Testing
@testable import Squatter

/// Renders the popover in a real (offscreen) window and writes PNGs for eyeballing.
/// Asserts each render fills exactly the frame it was asked for (a view that escapes its
/// frame fails by name) and is not blank; pixel *content* is still eyeball-only.
@MainActor
struct SnapshotTests {
    private static let outputDirectory = URL(filePath: NSTemporaryDirectory()).appending(path: "squatter-snapshots")

    private func snapshot<V: View>(_ view: V, name: String, size: CGSize = CGSize(width: 360, height: 460), dark: Bool = false) throws -> URL {
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        // Key the window: inactive windows render selection and prominent buttons in grey,
        // which hides exactly the contrast problems these snapshots exist to catch.
        window.makeKeyAndOrderFront(nil)
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        host.layoutSubtreeIfNeeded()
        // A view that escapes its frame must fail here, by name. The 2026-08-29 settings
        // regression rendered 320x3294 instead of 320x480 and sailed past the byte check.
        #expect(
            host.bounds.size == size,
            "\(name) escaped its frame: laid out \(host.bounds.width)x\(host.bounds.height) pt, asked for \(size.width)x\(size.height) pt"
        )
        let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        let scale = window.backingScaleFactor
        let expectedWidth = Int((size.width * scale).rounded())
        let expectedHeight = Int((size.height * scale).rounded())
        #expect(
            rep.pixelsWide == expectedWidth && rep.pixelsHigh == expectedHeight,
            "\(name) rendered \(rep.pixelsWide)x\(rep.pixelsHigh) px, expected \(expectedWidth)x\(expectedHeight) px at \(scale)x"
        )
        let png = try #require(rep.representation(using: .png, properties: [:]))
        try FileManager.default.createDirectory(at: Self.outputDirectory, withIntermediateDirectories: true)
        let url = Self.outputDirectory.appending(path: "\(name).png")
        try png.write(to: url)
        return url
    }

    private func loadedModel(
        _ lsof: String,
        kills: KillRecorder = KillRecorder(names: [42: "node", 7: "postgres", 1: "launchd"]),
        docker: DockerProbe? = nil
    ) async -> PortListModel {
        let runner = FakeRunner(.success(lsofResult(lsof)))
        let scanner = PortScanner(runner: runner, currentUID: 501, userName: testUserName, docker: docker)
        let model = PortListModel(
            scanner: scanner,
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
        let listURL = try snapshot(PortListView(model: list, settings: SettingsModel(loginItem: FakeLoginItem(), updater: FakeUpdater(), preferences: Preferences(defaults: freshDefaults()))), name: "list")
        let darkURL = try snapshot(PortListView(model: list, settings: SettingsModel(loginItem: FakeLoginItem(), updater: FakeUpdater(), preferences: Preferences(defaults: freshDefaults()))), name: "list-dark", dark: true)

        let stubborn = await loadedModel(many)
        await stubborn.kill(sampleListener) // names never change → .stillRunning after the grace period
        let stubbornURL = try snapshot(PortListView(model: stubborn, settings: SettingsModel(loginItem: FakeLoginItem(), updater: FakeUpdater(), preferences: Preferences(defaults: freshDefaults()))), name: "list-force-kill")

        let empty = await loadedModel("")
        let emptyURL = try snapshot(PortListView(model: empty, settings: SettingsModel(loginItem: FakeLoginItem(), updater: FakeUpdater(), preferences: Preferences(defaults: freshDefaults()))), name: "empty")

        let failing = PortListModel(
            scanner: PortScanner(runner: FakeRunner(.failure(.lsofNotFound(path: "/usr/sbin/lsof"))), currentUID: 501, docker: nil),
            killer: KillRecorder(names: [:]).killer,
            actions: RecordingActions(),
            preferences: Preferences(defaults: freshDefaults())
        )
        await failing.refresh()
        let errorURL = try snapshot(PortListView(model: failing, settings: SettingsModel(loginItem: FakeLoginItem(), updater: FakeUpdater(), preferences: Preferences(defaults: freshDefaults()))), name: "error")

        // Arm the longest name in the fixture — the confirmation must not truncate its buttons.
        let longName = many + "p11\ncAdobe Desktop Service\nu501\nf1\nPTCP\nn127.0.0.1:15292\nTST=LISTEN\n"
        let confirming = await loadedModel(longName, kills: KillRecorder(names: [11: "Adobe Desktop Service"]))
        let victim = try #require(confirming.listeners.first { $0.processName == "Adobe Desktop Service" })
        confirming.requestKill(victim)
        let confirmURL = try snapshot(PortListView(model: confirming, settings: SettingsModel(loginItem: FakeLoginItem(), updater: FakeUpdater(), preferences: Preferences(defaults: freshDefaults()))), name: "list-confirm-kill")

        let forcing = await loadedModel(longName, kills: KillRecorder(names: [11: "Adobe Desktop Service"]))
        let forceVictim = try #require(forcing.listeners.first { $0.processName == "Adobe Desktop Service" })
        forcing.requestForceKill(forceVictim)
        let forceConfirmURL = try snapshot(PortListView(model: forcing, settings: SettingsModel(loginItem: FakeLoginItem(), updater: FakeUpdater(), preferences: Preferences(defaults: freshDefaults()))), name: "list-confirm-force-kill")

        let ignoring = await loadedModel(many)
        ignoring.ignorePort(of: sampleListener)
        ignoring.ignoreProcess(of: Listener(port: 22, pid: 1, processName: "launchd", user: "root", addresses: ["*"], isOwnedByCurrentUser: false))
        ignoring.showIgnored = true
        let ignoredURL = try snapshot(PortListView(model: ignoring, settings: SettingsModel(loginItem: FakeLoginItem(), updater: FakeUpdater(), preferences: Preferences(defaults: freshDefaults()))), name: "list-ignored")

        let highPorts = many + "p20\ncmDNSResponder\nu501\nf1\nPTCP\nn*:52398\nTST=LISTEN\n"
        let highPortModel = await loadedModel(highPorts)
        highPortModel.hideHighPorts = true
        highPortModel.showIgnored = true
        let highPortsURL = try snapshot(PortListView(model: highPortModel, settings: SettingsModel(loginItem: FakeLoginItem(), updater: FakeUpdater(), preferences: Preferences(defaults: freshDefaults()))), name: "list-high-ports")

        // hideHighPorts on so the new settings section renders with its number field enabled.
        ignoring.hideHighPorts = true
        let approval = FakeLoginItem(status: .requiresApproval)
        let settings = SettingsModel(loginItem: approval, updater: FakeUpdater(pendingUpdateVersion: "9.9.9"), preferences: Preferences(defaults: freshDefaults()))
        let settingsURL = try snapshot(SettingsView(settings: settings, model: ignoring).frame(width: 320), name: "settings", size: CGSize(width: 320, height: 480))

        // A container-published port should show the container's name and image, not the
        // Docker Desktop proxy process that actually owns the socket.
        let dockerFixtureURL = try #require(Bundle(for: Anchor.self).url(forResource: "docker-ps-sample", withExtension: "txt"))
        let dockerFixtureText = try String(contentsOf: dockerFixtureURL, encoding: .utf8)
        let dockerProbe = DockerProbe(runner: FakeRunner(.success(lsofResult(dockerFixtureText))), executablePath: "/test/docker")
        await dockerProbe.refreshNow()
        let dockerModel = await loadedModel("p600\nccom.docker.backend\nu501\nf1\nPTCP\nn*:5432\nTST=LISTEN\n", docker: dockerProbe)
        let dockerURL = try snapshot(PortListView(model: dockerModel, settings: SettingsModel(loginItem: FakeLoginItem(), updater: FakeUpdater(), preferences: Preferences(defaults: freshDefaults()))), name: "list-docker")

        // Stop Container's confirmation must not truncate its buttons any more than Kill's does.
        let containerRow = try #require(dockerModel.listeners.first { $0.container != nil })
        dockerModel.requestStopContainer(containerRow)
        let confirmStopURL = try snapshot(PortListView(model: dockerModel, settings: SettingsModel(loginItem: FakeLoginItem(), updater: FakeUpdater(), preferences: Preferences(defaults: freshDefaults()))), name: "list-confirm-stop")

        for url in [listURL, darkURL, stubbornURL, confirmURL, forceConfirmURL, emptyURL, errorURL, ignoredURL, highPortsURL, settingsURL, dockerURL, confirmStopURL] {
            let size = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int ?? 0
            #expect(size > 1_000, "\(url.lastPathComponent) looks blank")
        }
        print("SNAPSHOTS: \(Self.outputDirectory.path)")
    }
}

private final class Anchor {}
