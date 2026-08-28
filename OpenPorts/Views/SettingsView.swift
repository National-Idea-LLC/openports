import SwiftUI

/// Shown from the gear in the popover footer. Binds to `SettingsModel`; no logic here.
struct SettingsView: View {
    @Bindable var settings: SettingsModel
    @Bindable var model: PortListModel

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
            if !model.ignoredPorts.isEmpty || !model.ignoredProcessNames.isEmpty {
                Section("Ignored") {
                    ForEach(model.ignoredPorts.sorted(), id: \.self) { port in
                        ignoredRow(Text("Port \(String(port))")) { model.removeIgnoredPort(port) }
                    }
                    ForEach(model.ignoredProcessNames.sorted(), id: \.self) { name in
                        ignoredRow(Text(name)) { model.removeIgnoredProcessName(name) }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 320)
        .fixedSize(horizontal: false, vertical: true)
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

    private func intervalLabel(_ seconds: TimeInterval) -> String {
        seconds == 1 ? String(localized: "1 second") : String(localized: "\(Int(seconds)) seconds")
    }
}

#Preview {
    SettingsView(settings: SettingsModel(), model: PortListModel())
}
