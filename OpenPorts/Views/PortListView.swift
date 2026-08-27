import SwiftUI

/// Popover root. Scaffold only — the live list arrives in M1.
struct PortListView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "network")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(String(localized: "Nothing is listening."))
                .foregroundStyle(.secondary)
        }
        .frame(width: 360, height: 440)
    }
}

#Preview {
    PortListView()
}
