import SwiftUI

@main
struct OpenPortsApp: App {
    var body: some Scene {
        MenuBarExtra(String(localized: "OpenPorts"), systemImage: "network") {
            PortListView()
        }
        .menuBarExtraStyle(.window)
    }
}
