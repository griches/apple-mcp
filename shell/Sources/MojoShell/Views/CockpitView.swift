import SwiftUI

struct CockpitView: View {
    @EnvironmentObject private var appState: AppState
    @State private var scanResult = "Tap Scan to load Daily Intel"
    @State private var personaMapResult = "Tap Refresh Persona Map"
    @State private var brainOverviewResult = "Tap Brain Overview"
    @State private var nowPlayingResult = "Tap Now Playing"
    @State private var isScanning = false
    @State private var isLoadingPersonaMap = false
    @State private var isLoadingBrainOverview = false
    @State private var isLoadingNowPlaying = false

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
                Label("Live Panels", systemImage: "square.grid.2x2")
                    .font(.headline)
                Divider()

                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(personaMapResult)
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button(isLoadingPersonaMap ? "Loading..." : "Refresh Persona Map") {
                            Task {
                                await loadPersonaMap()
                            }
                        }
                        .disabled(isLoadingPersonaMap)
                    }
                } label: {
                    Label("Persona Map", systemImage: "person.2.badge.gearshape")
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(brainOverviewResult)
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button(isLoadingBrainOverview ? "Loading..." : "Brain Overview") {
                            Task {
                                await loadBrainOverview()
                            }
                        }
                        .disabled(isLoadingBrainOverview)
                    }
                } label: {
                    Label("Brain", systemImage: "brain.head.profile")
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(nowPlayingResult)
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button(isLoadingNowPlaying ? "Loading..." : "Now Playing") {
                            Task {
                                await loadNowPlaying()
                            }
                        }
                        .disabled(isLoadingNowPlaying)
                    }
                } label: {
                    Label("Music", systemImage: "music.note")
                }

                Divider()
                Label("Active Servers", systemImage: "server.rack")
                    .font(.headline)

                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
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
                    }
                }
            }
            .padding()
            .frame(minWidth: 320)
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

    private func loadPersonaMap() async {
        isLoadingPersonaMap = true
        let result = await appState.fetchPersonaMap()
        switch result {
        case .success(let output):
            personaMapResult = output.text
        case .failure(let error):
            personaMapResult = "Error: \(error.localizedDescription)"
        }
        isLoadingPersonaMap = false
    }

    private func loadBrainOverview() async {
        isLoadingBrainOverview = true
        let result = await appState.fetchBrainOverview()
        switch result {
        case .success(let output):
            brainOverviewResult = output.text
        case .failure(let error):
            brainOverviewResult = "Error: \(error.localizedDescription)"
        }
        isLoadingBrainOverview = false
    }

    private func loadNowPlaying() async {
        isLoadingNowPlaying = true
        let result = await appState.fetchNowPlaying()
        switch result {
        case .success(let output):
            nowPlayingResult = output.text
        case .failure(let error):
            nowPlayingResult = "Error: \(error.localizedDescription)"
        }
        isLoadingNowPlaying = false
    }
}
