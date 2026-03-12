import SwiftUI

private struct PersonaCardData: Identifiable {
    let id: String
    let persona: String
    let account: String
    let role: String
    let lane: String
    let isPrimaryReply: Bool
    let isCatchAll: Bool
}

private struct PersonaCardView: View {
    let data: PersonaCardData

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(data.persona)
                    .font(.system(.caption, design: .rounded).bold())
                if data.isPrimaryReply {
                    badge("primary", color: .blue)
                }
                if data.isCatchAll {
                    badge("catch-all", color: .purple)
                }
            }
            Text(data.account)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
            Text(data.role)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(.separator, lineWidth: 1)
        )
    }

    private func badge(_ label: String, color: Color) -> some View {
        Text(label)
            .font(.caption2)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }
}

private func parsePersonas(from json: String) -> [PersonaCardData] {
    guard
        let data = json.data(using: .utf8),
        let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
        let accounts = root["accounts"] as? [[String: Any]]
    else { return [] }

    return accounts.compactMap { dict in
        guard
            let id = dict["persona_id"] as? String,
            let persona = dict["persona"] as? String,
            let account = dict["account"] as? String
        else { return nil }
        return PersonaCardData(
            id: id,
            persona: persona,
            account: account,
            role: dict["role"] as? String ?? "",
            lane: dict["default_lane"] as? String ?? "",
            isPrimaryReply: dict["primary_reply_from"] as? Bool ?? false,
            isCatchAll: dict["catch_all"] as? Bool ?? false
        )
    }
}

struct CockpitView: View {
    @EnvironmentObject private var appState: AppState
    @State private var scanResult = "Tap Scan to load Daily Intel"
    @State private var personaMapResult = ""
    @State private var parsedPersonas: [PersonaCardData] = []
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
                    VStack(alignment: .leading, spacing: 6) {
                        if parsedPersonas.isEmpty {
                            Text(personaMapResult.isEmpty ? "Loading..." : personaMapResult)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            ForEach(parsedPersonas) { persona in
                                PersonaCardView(data: persona)
                            }
                        }
                        Button(isLoadingPersonaMap ? "Refreshing..." : "Refresh") {
                            Task { await loadPersonaMap() }
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
        .onAppear {
            Task { await loadPersonaMap() }
        }
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
            parsedPersonas = parsePersonas(from: output.text)
        case .failure(let error):
            personaMapResult = "Error: \(error.localizedDescription)"
            parsedPersonas = []
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
