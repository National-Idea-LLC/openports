import SwiftUI

@main
struct OpenPortsApp: App {
    @State private var model = PortListModel()

    var body: some Scene {
        MenuBarExtra {
            PortListView(model: model)
        } label: {
            Image(systemName: "network")
                .accessibilityLabel(Text("OpenPorts"))
        }
        .menuBarExtraStyle(.window)
    }
}
