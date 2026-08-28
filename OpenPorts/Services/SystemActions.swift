import AppKit

/// The two things the model asks the OS to do on the user's behalf. AppKit lives behind
/// this protocol so the model can be tested without touching the pasteboard or a browser.
@MainActor
protocol SystemActions {
    func open(_ url: URL)
    func copy(_ text: String)
}

struct AppKitSystemActions: SystemActions {
    func open(_ url: URL) {
        // AppKit: SwiftUI's `openURL` needs an environment; the model has none.
        NSWorkspace.shared.open(url)
    }

    func copy(_ text: String) {
        // AppKit: SwiftUI has no pasteboard API.
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
