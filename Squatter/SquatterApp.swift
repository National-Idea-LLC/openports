import SwiftUI

@main
struct SquatterApp: App {
    @State private var model = PortListModel()
    @State private var settings = SettingsModel()

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
