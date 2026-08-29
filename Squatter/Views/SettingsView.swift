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
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
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
                Toggle("Show count in menu bar", isOn: $model.showCountInMenuBar)
                Picker("Sort by", selection: $model.sortOrder) {
                    Text("Port").tag(SortOrder.port)
                    Text("Process name").tag(SortOrder.processName)
                }
                Picker("Refresh every", selection: $settings.refreshInterval) {
                    ForEach(SettingsModel.refreshIntervalChoices, id: \.self) { seconds in
                        Text(intervalLabel(seconds)).tag(seconds)
                    }
                }
            } footer: {
                Text(model.showCountInMenuBar
                    ? "While the list is open. The menu bar count updates every 10 seconds."
                    : "Only while the list is open.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle("Hide high ports", isOn: $model.hideHighPorts)
                LabeledContent("Hide ports above") {
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
                }
            } footer: {
                Text("Most ports above 10,000 belong to macOS background services, not to your dev servers. Hidden rows are counted next to the eye in the list.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                LabeledContent("Version", value: settings.appVersion)
                LabeledContent {
                    Button("Check for Updates") { settings.checkForUpdates() }
                        .controlSize(.small)
                } label: {
                    Text("Updates")
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
                Text("Squatter never connects to the internet on its own. Checking for updates opens GitHub in your browser.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                LabeledContent("Ignore these ports") {
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
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

#Preview {
    SettingsView(settings: SettingsModel(), model: PortListModel())
}
