import SwiftUI

/// One listener. Click selects (the `List` handles that); opening and killing are explicit.
struct PortRow: View {
    let model: PortListModel
    let listener: Listener

    @State private var isHovering = false

    private var isSelected: Bool { model.selection == listener.id }
    private var killState: KillState? { model.killState(for: listener) }
    private var canKill: Bool { listener.isOwnedByCurrentUser }
    private var isIgnored: Bool { model.isIgnored(listener) }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            LED(color: ledColor)

            Text(String(listener.port))
                .font(.system(.title3, design: .monospaced).weight(.semibold))
                .monospacedDigit()
                .frame(width: 62, alignment: .leading)
                .foregroundStyle(isIgnored ? .secondary : .primary)

            VStack(alignment: .leading, spacing: 1) {
                Text(listener.processName)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                    .foregroundStyle(isIgnored ? .secondary : .primary)
                HStack(spacing: 6) {
                    Text(verbatim: "PID \(listener.pid)")
                        .monospacedDigit()
                    ForEach(listener.addresses.sorted(), id: \.self) { address in
                        AddressChip(address: address)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer(minLength: 6)

            trailing
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 6)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .contextMenu { menuItems }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityText))
        .accessibilityAction(named: Text("Open in Browser")) { model.open(listener) }
        .accessibilityAction(named: Text("Copy URL")) { model.copyURL(listener) }
        .accessibilityAction(named: Text("Kill Process")) { Task { await model.kill(listener) } }
    }

    // MARK: LED

    private var ledColor: Color {
        switch killState {
        case .terminating, .forcing: .orange
        case .stillRunning, .failed: .red
        case nil:
            if isIgnored { .primary.opacity(0.15) }
            else if canKill { .green }
            else { .secondary.opacity(0.5) }
        }
    }

    // MARK: Trailing area

    @ViewBuilder
    private var trailing: some View {
        switch killState {
        case nil:
            if isHovering || isSelected {
                hoverActions
            }
        case .terminating:
            progress(Text("Killing…"))
        case .forcing:
            progress(Text("Force killing…"))
        case .stillRunning:
            HStack(spacing: 8) {
                Text("Still running")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Force Kill", role: .destructive) {
                    Task { await model.forceKill(listener) }
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.small)
                .accessibilityLabel(Text("Force kill \(listener.processName) on port \(String(listener.port))"))
            }
        case .failed(let message):
            HStack(spacing: 6) {
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 150, alignment: .trailing)
                Button {
                    model.dismissKillError(for: listener)
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption2.weight(.bold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel(Text("Dismiss error"))
            }
        }
    }

    private var hoverActions: some View {
        HStack(spacing: 4) {
            Menu {
                menuItems
            } label: {
                Image(systemName: "ellipsis")
                    .font(.caption.weight(.bold))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .frame(width: 24, height: 24)
            .foregroundStyle(.secondary)
            // The borderless menu style drops the label's background, so the chip lives here.
            .background(.quaternary.opacity(0.8), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .accessibilityLabel(Text("More actions for \(listener.processName) on port \(String(listener.port))"))
            .help(Text("More actions"))

            RowAction(systemImage: "arrow.up.right", tint: .accentColor) {
                model.open(listener)
            }
            .accessibilityLabel(Text("Open \(listener.processName) on port \(String(listener.port)) in browser"))
            .help(Text("Open \(listener.localURLString)"))

            RowAction(systemImage: "xmark", tint: canKill ? .red : .secondary) {
                Task { await model.kill(listener) }
            }
            .disabled(!canKill)
            .accessibilityLabel(Text("Kill \(listener.processName) on port \(String(listener.port))"))
            .help(canKill
                ? Text("Kill \(listener.processName) (SIGTERM)")
                : Text("Owned by \(listener.user). Kill it from that account or with sudo in Terminal."))
        }
    }

    private func progress(_ label: Text) -> some View {
        HStack(spacing: 6) {
            ProgressView()
                .controlSize(.mini)
            label
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Menu (shared by the ⋯ button and the right-click menu)

    @ViewBuilder
    private var menuItems: some View {
        Button("Open in Browser", systemImage: "arrow.up.right.square") { model.open(listener) }
        Divider()
        Button("Copy URL", systemImage: "doc.on.doc") { model.copyURL(listener) }
        Button("Copy Port", systemImage: "number") { model.copyPort(listener) }
        Button("Copy PID", systemImage: "tag") { model.copyPID(listener) }
        Divider()
        Button("Kill Process", systemImage: "xmark.circle", role: .destructive) {
            Task { await model.kill(listener) }
        }
        .disabled(!canKill)
        Button("Force Kill", systemImage: "bolt.fill", role: .destructive) {
            Task { await model.forceKill(listener) }
        }
        .disabled(!canKill)
        Divider()
        if isIgnored {
            Button("Unignore", systemImage: "eye") { model.unignore(listener) }
        } else {
            Button(String(localized: "Ignore Port \(String(listener.port))"), systemImage: "eye.slash") {
                model.ignorePort(of: listener)
            }
            Button(String(localized: "Ignore \(listener.processName)"), systemImage: "eye.slash") {
                model.ignoreProcess(of: listener)
            }
        }
    }

    // MARK: Text

    private var accessibilityText: String {
        var text = String(localized: "\(listener.processName) on port \(String(listener.port)), PID \(String(listener.pid))")
        if !canKill { text += String(localized: ", owned by \(listener.user)") }
        if isIgnored { text += String(localized: ", ignored") }
        return text
    }
}

/// Bind address as a small monospaced chip. `*` means every interface — reachable from the network.
private struct AddressChip: View {
    let address: String

    private var isWildcard: Bool { address == "*" || address == "0.0.0.0" || address == "::" }

    var body: some View {
        Text(address)
            .font(.caption2.monospaced())
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(.quaternary.opacity(0.7), in: RoundedRectangle(cornerRadius: 3, style: .continuous))
            .help(isWildcard
                ? Text("Bound to all interfaces — reachable from other devices on your network")
                : Text("Bound to \(address)"))
    }
}

/// Square icon button that only shows on hover/selection.
private struct RowAction: View {
    let systemImage: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.caption.weight(.bold))
                .frame(width: 24, height: 24)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .foregroundStyle(tint)
        }
        .buttonStyle(.plain)
    }
}
