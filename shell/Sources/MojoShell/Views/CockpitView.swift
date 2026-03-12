import SwiftUI

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

private struct BrainOverviewCardView: View {
    let data: BrainOverviewCardData

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(data.title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(data.value)
                .font(.system(.title3, design: .rounded).bold())
            Text(data.detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(.separator, lineWidth: 1)
        )
    }
}

private struct StatusDotView: View {
    let status: NowPlayingStatus

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
    }

    private var color: Color {
        switch status {
        case .live:
            return .green
        case .stopped:
            return .orange
        case .error:
            return .red
        }
    }
}

struct CockpitView: View {
    @EnvironmentObject private var appState: AppState
    @State private var scanResult = "Tap Scan to load Daily Intel"
    @State private var personaMapResult = ""
    @State private var parsedPersonas: [PersonaCardData] = []
    @State private var brainOverviewResult = "Tap Brain Overview"
    @State private var parsedBrainOverview: BrainOverviewPanelData?
    @State private var nowPlayingResult = "Tap Now Playing"
    @State private var parsedNowPlaying = parseNowPlaying(from: "")
    @State private var isScanning = false
    @State private var isLoadingPersonaMap = false
    @State private var isLoadingBrainOverview = false
    @State private var isLoadingNowPlaying = false
    @State private var lastNowPlayingRefresh: Date?
    @State private var hasLoadedInitialPanels = false

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
                        if let parsedBrainOverview {
                            Text(parsedBrainOverview.headline)
                                .font(.system(.body, design: .rounded).bold())
                            Text(parsedBrainOverview.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            HStack(alignment: .top, spacing: 8) {
                                ForEach(parsedBrainOverview.cards) { card in
                                    BrainOverviewCardView(data: card)
                                }
                            }

                            if !parsedBrainOverview.sections.isEmpty {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Sections")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(parsedBrainOverview.sections.joined(separator: " • "))
                                        .font(.caption2)
                                }
                            }

                            if !parsedBrainOverview.machineEntities.isEmpty {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Machine Entities")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(parsedBrainOverview.machineEntities.joined(separator: " • "))
                                        .font(.caption2)
                                }
                            }
                        } else {
                            Text(brainOverviewResult)
                                .font(.system(.caption, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
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
                        HStack(spacing: 6) {
                            StatusDotView(status: parsedNowPlaying.status)
                            Text(parsedNowPlaying.title)
                                .font(.system(.body, design: .rounded).bold())
                        }
                        Text(parsedNowPlaying.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(parsedNowPlaying.detail)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        if let lastNowPlayingRefresh {
                            Text("Updated \(lastNowPlayingRefresh.formatted(date: .omitted, time: .shortened)) • Auto-refresh every 30s")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Auto-refresh every 30s")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Button(isLoadingNowPlaying ? "Loading..." : "Now Playing") {
                            Task {
                                await loadNowPlaying(triggeredByPoll: false)
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
        .task {
            guard !hasLoadedInitialPanels else { return }
            hasLoadedInitialPanels = true
            await loadPersonaMap()
            await loadBrainOverview()
            await loadNowPlaying(triggeredByPoll: false)
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                if Task.isCancelled {
                    break
                }
                await loadNowPlaying(triggeredByPoll: true)
            }
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
            parsedBrainOverview = parseBrainOverview(from: output.text)
        case .failure(let error):
            brainOverviewResult = "Error: \(error.localizedDescription)"
            parsedBrainOverview = nil
        }
        isLoadingBrainOverview = false
    }

    private func loadNowPlaying(triggeredByPoll: Bool) async {
        guard !isLoadingNowPlaying else { return }
        isLoadingNowPlaying = true
        let result = await appState.fetchNowPlaying()
        switch result {
        case .success(let output):
            nowPlayingResult = output.text
            parsedNowPlaying = parseNowPlaying(from: output.text)
            lastNowPlayingRefresh = Date()
        case .failure(let error):
            nowPlayingResult = "Error: \(error.localizedDescription)"
            parsedNowPlaying = parseNowPlaying(from: nowPlayingResult)
            if !triggeredByPoll {
                lastNowPlayingRefresh = Date()
            }
        }
        isLoadingNowPlaying = false
    }
}
