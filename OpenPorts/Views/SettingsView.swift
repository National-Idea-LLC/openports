import SwiftUI

/// Shown from the gear in the popover footer. Binds to `SettingsModel`; no logic here.
struct SettingsView: View {
    @Bindable var settings: SettingsModel

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
                Picker("Refresh every", selection: $settings.refreshInterval) {
                    ForEach(SettingsModel.refreshIntervalChoices, id: \.self) { seconds in
                        Text(intervalLabel(seconds)).tag(seconds)
                    }
                }
            } footer: {
                Text("Only while the list is open.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 320)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { settings.refreshLoginItemStatus() }
    }

    private func intervalLabel(_ seconds: TimeInterval) -> String {
        seconds == 1 ? String(localized: "1 second") : String(localized: "\(Int(seconds)) seconds")
    }
}

#Preview {
    SettingsView(settings: SettingsModel())
}
