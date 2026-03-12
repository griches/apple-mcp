import SwiftUI

struct CockpitView: View {
    @EnvironmentObject private var appState: AppState
    @State private var scanResult = "Tap Scan to load Daily Intel"
    @State private var isScanning = false

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 12) {
                Label("Inbox Intelligence", systemImage: "envelope.badge.shield.half.filled")
                    .font(.headline)
                Divider()
                ScrollView {
                    Text(scanResult)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Button(isScanning ? "Scanning..." : "Scan Inboxes") {
                    Task {
                        await scanInboxes()
                    }
                }
                .disabled(isScanning)
            }
            .padding()
            .frame(minWidth: 360)

            VStack(alignment: .leading, spacing: 12) {
                Label("Active Servers", systemImage: "server.rack")
                    .font(.headline)
                Divider()

                if appState.daemons.runningServers.isEmpty {
                    Text("No MCP daemons are currently running.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(appState.daemons.runningServers.keys.sorted()), id: \.self) { name in
                        HStack {
                            Circle()
                                .fill(.green)
                                .frame(width: 8, height: 8)
                            Text(name)
                                .font(.system(.body, design: .monospaced))
                        }
                    }
                }

                Spacer()
            }
            .padding()
            .frame(minWidth: 260)
        }
        .navigationTitle("Cockpit")
    }

    private func scanInboxes() async {
        isScanning = true
        scanResult = "Scanning..."

        let result = await appState.scanInboxes()
        switch result {
        case .success(let output):
            scanResult = output.text
        case .failure(let error):
            scanResult = "Error: \(error.localizedDescription)"
        }

        isScanning = false
    }
}
