import SwiftUI

/// Popover root: search, list (or state view), footer. Binds to `PortListModel`; no logic here.
struct PortListView: View {
    @Bindable var model: PortListModel

    var body: some View {
        VStack(spacing: 0) {
            searchField
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 360, height: 440)
        .onAppear { model.startPolling() }
        .onDisappear { model.stopPolling() }
    }

    // MARK: Sections

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(String(localized: "Filter by port, process, or PID"), text: $model.filterText)
                .textFieldStyle(.plain)
            if !model.filterText.isEmpty {
                Button {
                    model.filterText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel(Text("Clear filter"))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var content: some View {
        if !model.hasLoaded {
            StateView(systemImage: "network") {
                ProgressView()
                    .controlSize(.small)
            }
        } else if let error = model.lastError, model.listeners.isEmpty {
            StateView(systemImage: "exclamationmark.triangle", title: Text("Couldn't list ports")) {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Retry") { Task { await model.refresh() } }
                    .keyboardShortcut(.defaultAction)
            }
        } else if model.listeners.isEmpty {
            StateView(systemImage: "network.slash", title: Text("Nothing is listening."))
        } else if model.filtered.isEmpty {
            StateView(systemImage: "magnifyingglass", title: Text("No ports match “\(model.filterText)”"))
        } else {
            VStack(spacing: 0) {
                if let error = model.lastError {
                    errorBanner(error)
                }
                list
            }
        }
    }

    private var list: some View {
        List(selection: $model.selection) {
            ForEach(model.filtered) { listener in
                PortRow(model: model, listener: listener)
                    .tag(listener.id)
            }
        }
        .listStyle(.plain)
        .onKeyPress(.return) {
            guard let listener = selectedListener else { return .ignored }
            model.open(listener)
            return .handled
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text(message)
                .font(.caption)
                .lineLimit(2)
            Spacer()
            Button("Retry") { Task { await model.refresh() } }
                .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.quaternary)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button {
                Task { await model.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .keyboardShortcut("r")
            .disabled(model.isRefreshing)
            .accessibilityLabel(Text("Refresh list"))
            .help(Text("Refresh (⌘R)"))

            Text(countText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()

            Spacer()

            Button {
                // AppKit: SwiftUI has no cross-platform quit API.
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .keyboardShortcut("q")
            .accessibilityLabel(Text("Quit OpenPorts"))
            .help(Text("Quit OpenPorts (⌘Q)"))
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: Helpers

    private var selectedListener: Listener? {
        model.filtered.first { $0.id == model.selection }
    }

    private var countText: String {
        let total = model.listeners.count
        let shown = model.filtered.count
        if shown == total {
            return String(localized: "\(total) listening")
        }
        return String(localized: "\(shown) of \(total) listening")
    }
}

/// Centered symbol + title + optional extra content, used for loading, empty, and error states.
private struct StateView<Content: View>: View {
    let systemImage: String
    var title: Text?
    @ViewBuilder var content: () -> Content

    init(systemImage: String, title: Text? = nil, @ViewBuilder content: @escaping () -> Content = { EmptyView() }) {
        self.systemImage = systemImage
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 34))
                .foregroundStyle(.secondary)
            if let title {
                title.foregroundStyle(.secondary)
            }
            content()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview("Empty") {
    PortListView(model: PortListModel())
}
