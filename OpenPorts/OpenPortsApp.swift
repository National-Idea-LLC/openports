import SwiftUI

@main
struct OpenPortsApp: App {
    @State private var model = PortListModel()
    @State private var settings = SettingsModel()

    var body: some Scene {
        MenuBarExtra {
            PortListView(model: model, settings: settings)
        } label: {
            Image(systemName: "network")
                .accessibilityLabel(Text("OpenPorts"))
        }
        .menuBarExtraStyle(.window)
    }
}
