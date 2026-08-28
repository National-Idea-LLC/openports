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
        HStack(spacing: 12) {
            Text(String(listener.port))
                .font(.system(.body, design: .monospaced).weight(.semibold))
                .frame(minWidth: 52, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(listener.processName)
                        .lineLimit(1)
                    if isIgnored {
                        Image(systemName: "eye.slash")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel(Text("Ignored"))
                    }
                }
                Text(detailText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            trailing
        }
        .padding(.vertical, 4)
        .opacity(canKill && !isIgnored ? 1 : 0.6)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .contextMenu { contextMenu }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityText))
        .accessibilityAction(named: Text("Open in Browser")) { model.open(listener) }
        .accessibilityAction(named: Text("Copy URL")) { model.copyURL(listener) }
        .accessibilityAction(named: Text("Kill Process")) { Task { await model.kill(listener) } }
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
            HStack(spacing: 6) {
                Text("Still running")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Force Kill", role: .destructive) {
                    Task { await model.forceKill(listener) }
                }
                .controlSize(.small)
                .accessibilityLabel(Text("Force kill \(listener.processName) on port \(String(listener.port))"))
            }
        case .failed(let message):
            HStack(spacing: 6) {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    .frame(maxWidth: 160, alignment: .trailing)
                Button {
                    model.dismissKillError(for: listener)
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel(Text("Dismiss error"))
            }
        }
    }

    private var hoverActions: some View {
        HStack(spacing: 8) {
            Button {
                model.open(listener)
            } label: {
                Image(systemName: "arrow.up.right.square")
            }
            .foregroundStyle(Color.accentColor)
            .accessibilityLabel(Text("Open \(listener.processName) on port \(String(listener.port)) in browser"))
            .help(Text("Open \(listener.localURLString)"))

            Button(role: .destructive) {
                Task { await model.kill(listener) }
            } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .foregroundStyle(canKill ? Color.red : Color.secondary)
            .disabled(!canKill)
            .accessibilityLabel(Text("Kill \(listener.processName) on port \(String(listener.port))"))
            .help(canKill
                ? Text("Kill \(listener.processName) (SIGTERM)")
                : Text("Owned by \(listener.user). Kill it from that account or with sudo in Terminal."))
        }
        .buttonStyle(.plain)
        .font(.title3)
    }

    private func progress(_ label: Text) -> some View {
        HStack(spacing: 6) {
            ProgressView()
                .controlSize(.small)
            label
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Context menu

    @ViewBuilder
    private var contextMenu: some View {
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

    private var detailText: String {
        let addresses = listener.addresses.sorted().joined(separator: ", ")
        return String(localized: "PID \(String(listener.pid)) · \(addresses)")
    }

    private var accessibilityText: String {
        var text = String(localized: "\(listener.processName) on port \(String(listener.port)), PID \(String(listener.pid))")
        if !canKill { text += String(localized: ", owned by \(listener.user)") }
        return text
    }
}
