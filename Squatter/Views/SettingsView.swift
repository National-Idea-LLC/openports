import SwiftUI

/// Shown from the gear in the popover footer. Binds to `SettingsModel`; no logic here.
struct SettingsView: View {
    @Bindable var settings: SettingsModel
    @Bindable var model: PortListModel
    @State private var portsToAdd = ""
    /// Tokens the last submission could not read as ports, echoed back so nothing is
    /// silently dropped.
    @State private var skippedPorts: [String] = []

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $settings.launchAtLogin) {
                    Text("Launch at login")
                }
                if settings.needsLoginItemApproval {
                    LabeledContent {
                        Button("Open Login Items") { settings.openLoginItemsSettings() }
                            .controlSize(.small)
                    } label: {
                        Text("Waiting for approval in System Settings")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if let error = settings.loginItemError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            Section {
                Toggle(isOn: $model.showCountInMenuBar) {
                    Text("Show count in menu bar")
                }
                Picker(selection: $model.sortOrder) {
                    Text("Port").tag(SortOrder.port)
                    Text("Process name").tag(SortOrder.processName)
                    Text("PID").tag(SortOrder.pid)
                } label: {
                    Text("Sort by")
                }
                Picker(selection: $settings.refreshInterval) {
                    ForEach(SettingsModel.refreshIntervalChoices, id: \.self) { seconds in
                        Text(intervalLabel(seconds)).tag(seconds)
                    }
                } label: {
                    Text("Refresh every")
                }
                Toggle(isOn: $model.dockerIntegration) {
                    Text("Docker integration")
                }
            } footer: {
                // Each sentence names its own subject: these sit two rows below the control they
                // describe, with another row in between, so "Only while the list is open." had
                // nothing on screen to attach to.
                VStack(alignment: .leading, spacing: 6) {
                    Text(model.showCountInMenuBar
                        ? "The list refreshes only while it's open. The menu bar count keeps updating every 10 seconds after you close it."
                        : "The list refreshes only while it's open.")
                    Text("Docker integration names the container behind a published port. Squatter only runs the docker command when Docker is installed.")
                }
                .settingsFooter()
            }
            Section {
                Toggle(isOn: $model.hideHighPorts) {
                    Text("Hide high ports")
                }
                LabeledContent {
                    TextField(
                        "",
                        value: $model.highPortThreshold,
                        format: .number.grouping(.never)
                    )
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .frame(width: 64)
                    .disabled(!model.hideHighPorts)
                } label: {
                    Text("Hide ports above")
                }
            } footer: {
                Text("Most ports above 10,000 belong to macOS background services, not to your dev servers. Hidden rows are counted next to the eye in the list.")
                    .settingsFooter()
            }
            Section {
                LabeledContent {
                    HStack(spacing: 6) {
                        TextField(String(localized: "3000, 5173"), text: $portsToAdd)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 120)
                            .onSubmit(addPorts)
                        Button("Add Ports", systemImage: "plus") { addPorts() }
                            .labelStyle(.iconOnly)
                            .controlSize(.small)
                            .disabled(portsToAdd.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } label: {
                    Text("Ignore these ports")
                }
                if !skippedPorts.isEmpty {
                    Text("Skipped \(skippedPorts.joined(separator: ", ")) — a port is a number from 1 to 65535.")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                ForEach(model.ignoredPorts.sorted(), id: \.self) { port in
                    ignoredRow(Text("Port \(String(port))")) { model.removeIgnoredPort(port) }
                }
                ForEach(model.ignoredProcessNames.sorted(), id: \.self) { name in
                    ignoredRow(Text(name)) { model.removeIgnoredProcessName(name) }
                }
            } header: {
                Text("Ignored")
            } footer: {
                Text("Separate ports with a comma, a space, or a new line. Right-click any row in the list to ignore it by process name.")
                    .settingsFooter()
            }
            Section {
                LabeledContent {
                    Text(settings.appVersion)
                } label: {
                    Text("Version")
                }
                LabeledContent {
                    Button("Check for Updates") { settings.checkForUpdates() }
                        .controlSize(.small)
                } label: {
                    Text("Updates")
                }
                LabeledContent {
                    Button("Report a Bug") { settings.reportBug() }
                        .controlSize(.small)
                } label: {
                    Text("Something broken?")
                }
                LabeledContent {
                    Button("View Source") { settings.openSource() }
                        .controlSize(.small)
                } label: {
                    Text("Open source, MIT")
                }
            } header: {
                Text("About")
            } footer: {
                Text("Squatter never connects to the internet on its own. Checking for updates or reporting a bug opens GitHub in your browser.")
                    .settingsFooter()
            }
        }
        .formStyle(.grouped)
        .frame(width: 320, height: 480) // fixed; the form scrolls when the ignore list grows
        .onAppear { settings.refreshLoginItemStatus() }
    }

    private func ignoredRow(_ label: Text, remove: @escaping () -> Void) -> some View {
        LabeledContent {
            Button(action: remove) {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel(Text("Stop ignoring"))
        } label: {
            label
        }
    }

    private func addPorts() {
        let result = model.addIgnoredPorts(from: portsToAdd)
        skippedPorts = result.skipped
        // Keep only what could not be read, so the user can fix it in place.
        portsToAdd = result.skipped.joined(separator: ", ")
    }

    private func intervalLabel(_ seconds: TimeInterval) -> String {
        seconds == 1 ? String(localized: "1 second") : String(localized: "\(Int(seconds)) seconds")
    }
}

// The grouped `Form` resets the font and colour environment for its own rows and footers, so
// neither `.font()` on the Form nor `.dynamicTypeSize` reaches them — both were measured as
// exact no-ops against the offscreen snapshot, as was `.foregroundStyle` on a footer's content
// view. Only a modifier on the label's own `Text` takes, which is why this exists rather than
// one styling pass at the top. Labels themselves are left at the Form's own size: 15 pt was
// tried on 2026-08-29 and read as too large.
private extension View {
    /// Explanatory text under a section. The Form draws footers in the system's secondary grey,
    /// about 3.9:1 against the panel — thin for a multi-line paragraph. Lift the contrast to
    /// roughly 6.4:1 without promoting the text to a label.
    func settingsFooter() -> some View {
        foregroundStyle(Color.primary.opacity(0.75))
    }
}

#Preview {
    SettingsView(settings: SettingsModel(), model: PortListModel())
}
