import SwiftUI

/// Popover root: filter bar, grouped list (or a state view), status bar. Binds to `PortListModel`; no logic here.
struct PortListView: View {
    @Bindable var model: PortListModel
    let settings: SettingsModel

    @State private var isShowingSettings = false
    @FocusState private var isListFocused: Bool

    var body: some View {
        layout
            .frame(width: 360, height: 460)
            // On macOS 26 the menu bar panel is already Liquid Glass; painting a material over it
            // would flatten it back into an opaque sheet.
            .background(LiquidGlass.isAvailable ? AnyShapeStyle(.clear) : AnyShapeStyle(.regularMaterial))
            .onAppear { model.startPolling() }
            .onDisappear { model.stopPolling() }
    }

    /// Glass bars float over the list, so on macOS 26 the filter bar and status bar are safe-area
    /// insets: the list keeps its full height, scrolls under them, and fades at both edges. Without
    /// glass they are opaque, so they stack instead and the list stops where they begin.
    @ViewBuilder
    private var layout: some View {
        if LiquidGlass.isAvailable {
            content
                .safeAreaInset(edge: .top, spacing: 0) { filterBar }
                .safeAreaInset(edge: .bottom, spacing: 0) { statusBar }
        } else {
            VStack(spacing: 0) {
                filterBar
                content
                statusBar
            }
        }
    }

    // MARK: Filter bar

    /// Tahoe search fields are capsules; the older rounded rectangle matches the rest of a
    /// pre-glass window, where a capsule would look out of place.
    private var searchFieldShape: AnyShape {
        LiquidGlass.isAvailable
            ? AnyShape(Capsule(style: .continuous))
            : AnyShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var filterBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.callout)
            TextField(String(localized: "Port, process, or PID"), text: $model.filterText)
                .textFieldStyle(.plain)
                .font(.callout)
            if !model.filterText.isEmpty {
                Button {
                    model.filterText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Clear filter"))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .glassSurface(in: searchFieldShape, fallback: AnyShapeStyle(.quaternary.opacity(0.6)))
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if !model.hasLoaded {
            StateView(led: .secondary, title: Text("Scanning…"))
        } else if let error = model.lastError, model.listeners.isEmpty {
            StateView(led: .red, title: Text("Couldn't list ports"), detail: Text(error)) {
                Button("Retry") { Task { await model.refresh() } }
                    .keyboardShortcut(.defaultAction)
            }
        } else if model.listeners.isEmpty {
            StateView(led: .clear, title: Text("Nothing is listening."), detail: Text("Start a dev server and it shows up here."))
        } else if model.filtered.isEmpty, model.filterText.isEmpty {
            StateView(led: .secondary, title: Text("Everything is ignored."), detail: Text("\(model.hiddenCount) ignored")) {
                Button("Show Ignored") { model.showIgnored = true }
            }
        } else if model.filtered.isEmpty {
            StateView(led: .secondary, title: Text("No match for “\(model.filterText)”"))
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
            ForEach(model.groups) { group in
                // Headers are ordinary rows (not `Section` headers) so they scroll away instead of
                // pinning with a hairline, and never take selection.
                GroupHeader(kind: group.kind, count: group.listeners.count)
                    .selectionDisabled()
                    .listRowInsets(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8))
                    .listRowSeparator(.hidden)
                ForEach(group.listeners) { listener in
                    PortRow(model: model, listener: listener)
                        .tag(listener.id)
                        .listRowInsets(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8))
                        .listRowSeparator(.hidden)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .softScrollEdges()
        .environment(\.defaultMinListRowHeight, 24)
        .focused($isListFocused)
        .onAppear { isListFocused = true }
        .onKeyPress(.escape) {
            guard model.isAwaitingKillConfirmation else { return .ignored }
            model.cancelAllKillConfirmations()
            return .handled
        }
        .onKeyPress(.return) { model.openSelected() ? .handled : .ignored }
        .onKeyPress(.delete) { model.killSelected() ? .handled : .ignored }
        .onKeyPress(characters: CharacterSet(charactersIn: "c"), phases: .down) { press in
            guard press.modifiers == .command else { return .ignored }
            return model.copySelectedURL() ? .handled : .ignored
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            LED(color: .red)
            Text(message)
                .font(.caption)
                .lineLimit(2)
            Spacer()
            Button("Retry") { Task { await model.refresh() } }
                .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.red.opacity(0.08))
    }

    // MARK: Status bar

    private var statusBar: some View {
        GlassGroup(spacing: 8) {
            statusBarControls
        }
    }

    private var statusBarControls: some View {
        HStack(spacing: 8) {
            Button {
                Task { await model.refresh() }
            } label: {
                HStack(spacing: 6) {
                    if model.isRefreshing {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                    Text(countText)
                        .monospacedDigit()
                }
            }
            .keyboardShortcut("r")
            .accessibilityLabel(Text("Refresh list"))
            .help(Text("Refresh (⌘R)"))

            if model.hiddenCount > 0 {
                Button {
                    model.showIgnored.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: model.showIgnored ? "eye" : "eye.slash")
                        Text(hiddenText).monospacedDigit()
                    }
                }
                .accessibilityLabel(Text(model.showIgnored ? "Hide ignored ports" : "Show ignored ports"))
            }

            Spacer()

            Button {
                isShowingSettings.toggle()
            } label: {
                Image(systemName: "gearshape")
            }
            .keyboardShortcut(",")
            .accessibilityLabel(Text("Settings"))
            .help(Text("Settings (⌘,)"))
            .popover(isPresented: $isShowingSettings, arrowEdge: .bottom) {
                SettingsView(settings: settings, model: model)
            }

            Button {
                // AppKit: SwiftUI has no cross-platform quit API.
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .keyboardShortcut("q")
            .accessibilityLabel(Text("Quit Squatter"))
            .help(Text("Quit Squatter (⌘Q)"))
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        // Glass buttons float straight on the window's own glass, so the bar behind them and the
        // hairline that separated it would only add weight. Pre-glass, both still earn their keep.
        .chromeButtonStyle()
        .padding(.horizontal, LiquidGlass.isAvailable ? 10 : 14)
        .padding(.vertical, LiquidGlass.isAvailable ? 6 : 9)
        .background(LiquidGlass.isAvailable ? AnyShapeStyle(.clear) : AnyShapeStyle(.bar))
        .overlay(alignment: .top) {
            if !LiquidGlass.isAvailable { Divider() }
        }
    }

    // MARK: Text

    private var hiddenText: String {
        String(localized: "\(model.hiddenCount) ignored")
    }

    private var countText: String {
        let total = model.listeners.count
        let shown = model.filtered.count
        if shown == total {
            return String(localized: "\(total) listening")
        }
        return String(localized: "\(shown) of \(total)")
    }
}

// MARK: - Pieces

/// The status light. One per row; also anchors the state views.
struct LED: View {
    var color: Color

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 7, height: 7)
            .overlay(Circle().strokeBorder(.primary.opacity(0.12), lineWidth: 0.5))
            .accessibilityHidden(true)
    }
}

private struct GroupHeader: View {
    let kind: ListenerGroup.Kind
    let count: Int

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
            Text(String(count))
                .monospacedDigit()
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .font(.caption2.weight(.semibold))
        .textCase(.uppercase)
        .kerning(0.6)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 6)
        .padding(.top, 8)
        .padding(.bottom, 2)
    }

    private var title: String {
        switch kind {
        case .yours: String(localized: "Yours")
        case .otherUsers: String(localized: "Other users")
        case .ignored: String(localized: "Ignored")
        }
    }
}

/// Centered LED + title + optional detail and action, for loading, empty, and error states.
private struct StateView<Content: View>: View {
    let led: Color
    var title: Text
    var detail: Text?
    @ViewBuilder var content: () -> Content

    init(led: Color, title: Text, detail: Text? = nil, @ViewBuilder content: @escaping () -> Content = { EmptyView() }) {
        self.led = led
        self.title = title
        self.detail = detail
        self.content = content
    }

    var body: some View {
        VStack(spacing: 12) {
            // An unlit panel: eight dark sockets, the one that matters lit in the state's color.
            HStack(spacing: 8) {
                ForEach(0..<8, id: \.self) { index in
                    LED(color: index == 3 && led != .clear ? led : Color.primary.opacity(0.08))
                }
            }
            .padding(.bottom, 6)
            title
                .font(.body.weight(.medium))
            if let detail {
                detail
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 260)
            }
            content()
                .padding(.top, 4)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview("Empty") {
    PortListView(model: PortListModel(), settings: SettingsModel())
}
