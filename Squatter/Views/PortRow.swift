import SwiftUI

/// One listener. Click selects (the `List` handles that); opening and killing are explicit.
struct PortRow: View {
    let model: PortListModel
    let listener: Listener

    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isSelected: Bool { model.selection == listener.id }
    private var killState: KillState? { model.killState(for: listener) }
    private var canKill: Bool { listener.isOwnedByCurrentUser }
    private var isIgnored: Bool { model.isIgnored(listener) }
    /// A row Squatter mapped to a Docker container: Stop Container replaces Kill/Force Kill.
    private var isContainer: Bool { listener.container != nil }

    /// The question this row is asking, or `nil` when it is not awaiting confirmation.
    private var confirmationPrompt: Text? {
        switch killState {
        case .confirming: Text("Kill this process?")
        case .confirmingForce: Text("Force kill this process?")
        case .confirmingStop: Text("Stop this container?")
        default: nil
        }
    }

    /// Where the text column starts: LED (7) + spacing (10) + port column (62) + spacing (10).
    /// The URL sits below the action chips rather than beside them, so it needs the inset spelled
    /// out to line up with the process name.
    private static let textColumnInset: CGFloat = 89

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .center, spacing: 10) {
                LED(color: ledColor)

                Text(String(listener.port))
                    .font(.system(.title3, design: .monospaced).weight(.semibold))
                    .monospacedDigit()
                    .frame(width: 62, alignment: .leading)
                    .foregroundStyle(isIgnored ? .secondary : .primary)

                details

                Spacer(minLength: 6)

                trailing
                    .layoutPriority(1)
            }

            // Full row width, below the chips rather than beside them: sharing the line with the
            // hover actions truncated it to "http://lo…host:3000" on exactly the row being read.
            if confirmationPrompt == nil {
                URLLine(url: listener.localURLString, isIgnored: isIgnored) {
                    model.open(listener)
                }
                .padding(.leading, Self.textColumnInset)
            }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 6)
        .background {
            // Selection already draws its own highlight; this is only the hover cue.
            if isHovering && !isSelected {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(.quaternary.opacity(0.55))
            }
        }
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovering)
        .contextMenu { menuItems }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityText))
        .accessibilityAction(named: Text("Open in Browser")) { model.open(listener) }
        .accessibilityAction(named: Text("Copy URL")) { model.copyURL(listener) }
        .accessibilityAction(named: isContainer ? Text("Stop Container") : Text("Kill Process")) {
            if isContainer {
                model.requestStopContainer(listener)
            } else {
                model.requestKill(listener)
            }
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 1) {
            titleLine
            if let confirmationPrompt {
                // The name above already says which process; this line asks, so the buttons
                // never have to compete with a long name for width.
                confirmationPrompt
                    .font(.caption2)
                    .foregroundStyle(.red)
            } else {
                HStack(spacing: 6) {
                    if let container = listener.container {
                        // The PID of com.docker.backend is the same for every container row
                        // and tells the user nothing; the image tells them what it is.
                        Text(verbatim: container.image)
                    } else {
                        Text(verbatim: "PID \(listener.pid)")
                            .monospacedDigit()
                    }
                    ForEach(listener.addresses.sorted(), id: \.self) { address in
                        AddressChip(address: address)
                    }
                    Spacer(minLength: 0)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private var titleLine: some View {
        if let container = listener.container {
            HStack(spacing: 4) {
                Image(systemName: "shippingbox.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help(Text("Published by Docker container \(container.name) → port \(String(container.containerPort))"))
                Text(listener.displayName)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                    .foregroundStyle(isIgnored ? .secondary : .primary)
            }
        } else {
            Text(listener.processName)
                .font(.callout.weight(.medium))
                .lineLimit(1)
                .foregroundStyle(isIgnored ? .secondary : .primary)
        }
    }

    // MARK: LED

    private var ledColor: Color {
        switch killState {
        case .confirming, .confirmingForce, .confirmingStop: .red
        case .terminating, .forcing, .stopping: .orange
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
        case .confirming:
            // The row already names the process, so the prompt stays short — long names
            // would otherwise squeeze the buttons into ellipses.
            HStack(spacing: 8) {
                Button("Cancel") { model.cancelKill(listener) }
                    .glassButtonStyle()
                    .controlSize(.small)
                    .keyboardShortcut(.cancelAction)
                Button("Kill", role: .destructive) {
                    Task { await model.kill(listener) }
                }
                .prominentButtonStyle(tint: .red)
                .controlSize(.small)
                .accessibilityLabel(Text("Confirm killing \(listener.processName) on port \(String(listener.port))"))
            }
            .fixedSize()
        case .confirmingForce:
            HStack(spacing: 8) {
                Button("Cancel") { model.cancelKill(listener) }
                    .glassButtonStyle()
                    .controlSize(.small)
                    .keyboardShortcut(.cancelAction)
                Button("Force Kill", role: .destructive) {
                    Task { await model.forceKill(listener) }
                }
                .prominentButtonStyle(tint: .red)
                .controlSize(.small)
                .accessibilityLabel(Text("Confirm force killing \(listener.processName) on port \(String(listener.port))"))
            }
            .fixedSize()
        case .confirmingStop:
            // Matches the `.confirming` case's layout exactly: `.fixedSize()` and layout
            // priority exist because long names once squeezed these buttons into ellipses.
            // The button says "Stop", not "Stop Container" — same idiom as the Kill pair
            // above, where the prompt line already names the object and the button is the
            // bare verb. Accessibility keeps the full container name regardless.
            HStack(spacing: 8) {
                Button("Cancel") { model.cancelKill(listener) }
                    .glassButtonStyle()
                    .controlSize(.small)
                    .keyboardShortcut(.cancelAction)
                Button("Stop", role: .destructive) {
                    Task { await model.stopContainer(listener) }
                }
                .prominentButtonStyle(tint: .red)
                .controlSize(.small)
                .accessibilityLabel(Text("Confirm stopping \(listener.displayName) on port \(String(listener.port))"))
            }
            .fixedSize()
        case .terminating:
            progress(Text("Killing…"))
        case .forcing:
            progress(Text("Force killing…"))
        case .stopping:
            progress(Text("Stopping…"))
        case .stillRunning:
            HStack(spacing: 8) {
                Text("Still running")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Force Kill", role: .destructive) {
                    Task { await model.forceKill(listener) }
                }
                .prominentButtonStyle(tint: .red)
                .controlSize(.small)
                .accessibilityLabel(Text("Force kill \(listener.processName) on port \(String(listener.port))"))
            }
            .fixedSize()
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
        GlassGroup(spacing: 6) {
            hoverActionChips
        }
    }

    private var hoverActionChips: some View {
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
            .glassSurface(in: LiquidGlass.chipShape, interactive: true, fallback: AnyShapeStyle(.thickMaterial))
            .accessibilityLabel(Text("More actions for \(listener.processName) on port \(String(listener.port))"))
            .help(Text("More actions"))

            RowAction(systemImage: "arrow.up.right", tint: .accentColor) {
                model.open(listener)
            }
            .accessibilityLabel(Text("Open \(listener.processName) on port \(String(listener.port)) in browser"))
            .help(Text("Open \(listener.localURLString)"))

            if isContainer {
                RowAction(systemImage: "stop.fill", tint: .red) {
                    model.requestStopContainer(listener)
                }
                .accessibilityLabel(Text("Stop container \(listener.displayName) on port \(String(listener.port))"))
                .help(Text("Stop the Docker container \(listener.displayName)"))
            } else {
                RowAction(systemImage: "xmark", tint: canKill ? .red : .secondary) {
                    model.requestKill(listener)
                }
                .disabled(!canKill)
                .accessibilityLabel(Text("Kill \(listener.processName) on port \(String(listener.port))"))
                .help(canKill
                    ? Text("Kill \(listener.processName) (SIGTERM)")
                    : Text("Owned by \(listener.user). Kill it from that account or with sudo in Terminal."))
            }
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
        if isContainer {
            Button("Stop Container", systemImage: "stop.circle", role: .destructive) {
                model.requestStopContainer(listener)
            }
        } else {
            Button("Kill Process", systemImage: "xmark.circle", role: .destructive) {
                model.requestKill(listener)
            }
            .disabled(!canKill)
            Button("Force Kill", systemImage: "bolt.fill", role: .destructive) {
                model.requestForceKill(listener)
            }
            .disabled(!canKill)
        }
        Divider()
        switch model.ignoreReason(listener) {
        case .port, .processName:
            Button("Unignore", systemImage: "eye") { model.unignore(listener) }
        case .highPort:
            // Unignore would be a dead button here: this row is hidden by a rule, and no
            // list removal reveals it. Offer the rule's own undo instead.
            Button(String(localized: "Show Ports Above \(String(model.highPortThreshold))"), systemImage: "eye") {
                model.stopHidingHighPorts()
            }
        case nil:
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
        var text = if let container = listener.container {
            String(localized: "\(container.name), Docker container from \(container.image), on port \(String(listener.port))")
        } else {
            String(localized: "\(listener.processName) on port \(String(listener.port)), PID \(String(listener.pid))")
        }
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

/// The listener's URL, spelled out on its own line so it can be read and clicked without
/// hovering the row for the ↗ button's tooltip.
///
/// Always `http://localhost:<port>` — see `Listener.localURLString`. On a dev machine localhost
/// reaches every locally-bound port whatever the row advertises, so this stays right even for a
/// row bound to `0.0.0.0`; the address chip above is what reports the actual binding.
private struct URLLine: View {
    let url: String
    let isIgnored: Bool
    let open: () -> Void

    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: open) {
            Text(verbatim: url)
                .font(.caption2.monospaced())
                .lineLimit(1)
                .truncationMode(.middle)
                // The underline, not the colour, is what marks this as a link. `.tint` was tried
                // and reverted: on Liquid Glass the panel's luminance comes from whatever is
                // behind the window, so an accent blue that reads fine on white washes out over
                // a dark wallpaper. `.primary` is the colour the process name above already
                // uses, so it is legible in both appearances over any backdrop.
                .underline()
                .foregroundStyle(isIgnored ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                // Hover still gives feedback, just without carrying the affordance alone.
                .opacity(isHovering ? 1 : 0.75)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
            // The row's own cursor is the arrow; a link should say it is one.
            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovering)
        // The row carries one combined label and an "Open in Browser" action already, so this
        // must not surface as a second, near-duplicate target.
        .accessibilityHidden(true)
    }
}

/// Square icon button that only shows on hover/selection.
///
/// The chip is drawn in glass, or in a material below macOS 26, rather than a tinted wash: the row
/// underneath can be the window background, the hover fill, or the accent-coloured selection, and
/// only a surface of its own keeps the glyph legible on all three.
private struct RowAction: View {
    let systemImage: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.caption.weight(.bold))
                .frame(width: 24, height: 24)
                .glassSurface(in: LiquidGlass.chipShape, interactive: true, fallback: AnyShapeStyle(.thickMaterial))
                .foregroundStyle(tint)
        }
        .buttonStyle(.plain)
    }
}
