import SwiftUI

@main
struct SquatterApp: App {
    @State private var model = PortListModel()
    @State private var settings: SettingsModel

    init() {
        Preferences.registerToolTipDelay()
        // Never start the updater under XCTest: the test host shares the app's defaults,
        // so a started updater would schedule real checks and could show the permission
        // prompt in the middle of a test run.
        let isTesting = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        _settings = State(initialValue: SettingsModel(updater: SparkleUpdater(startingUpdater: !isTesting)))
    }

    var body: some Scene {
        MenuBarExtra {
            PortListView(model: model, settings: settings)
        } label: {
            if let count = model.menuBarCount {
                Label(String(count), systemImage: "network")
                    .labelStyle(.titleAndIcon)
                    .accessibilityLabel(Text("Squatter, \(count) listening"))
            } else {
                Image(systemName: "network")
                    .accessibilityLabel(Text("Squatter"))
            }
        }
        .menuBarExtraStyle(.window)
    }
}
