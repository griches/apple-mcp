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
    @EnvironmentObject private var brain: BrainManager
    @EnvironmentObject private var readiness: ReadinessState
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
    @State private var operatorResult = "Finder, Safari, Terminal, iTerm, Preview, Photos, Shortcuts, and settings controls are ready."
    @State private var isRunningOperatorAction = false
    @State private var isRunningBrainAction = false
    @State private var isRunningDaemonAction = false

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
                        Text(brain.sourceMode.title)
                            .font(.system(.body, design: .rounded).bold())
                        Text(brain.activeBrainPath)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)

                        HStack {
                            Button("Use Repo") {
                                Task { await switchToRepoBrain() }
                            }
                            Button("Use Local") {
                                Task { await switchToLocalBrain() }
                            }
                            Button("Reveal") {
                                Task { await runOperatorAction(appState.revealBrainFile) }
                            }
                        }
                        .disabled(isRunningBrainAction || isRunningOperatorAction)

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
                        .disabled(isLoadingBrainOverview || isRunningBrainAction)
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

                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(operatorResult)
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)

                        HStack {
                            Button("Downloads") {
                                Task { await runOperatorAction(appState.openDownloadsFolder) }
                            }
                            Button("Repo") {
                                Task { await runOperatorAction(appState.openRepoFolder) }
                            }
                            Button("Brain") {
                                Task { await runOperatorAction(appState.revealBrainFile) }
                            }
                        }
                        .disabled(isRunningOperatorAction)

                        HStack {
                            Button("Finder Selection") {
                                Task { await runOperatorAction(appState.fetchFinderSelection) }
                            }
                            Button("Preview Selection") {
                                Task { await runOperatorAction(appState.openFinderSelectionInPreview) }
                            }
                            Button("Photos Selection") {
                                Task { await runOperatorAction(appState.openFinderSelectionInPhotos) }
                            }
                        }
                        .disabled(isRunningOperatorAction)

                        HStack {
                            Button("Terminal Repo") {
                                Task { await runOperatorAction(appState.openRepoInTerminal) }
                            }
                            Button("iTerm Repo") {
                                Task { await runOperatorAction(appState.openRepoInITerm) }
                            }
                            Button("Safari Tab") {
                                Task { await runOperatorAction(appState.fetchSafariCurrentTab) }
                            }
                        }
                        .disabled(isRunningOperatorAction)

                        HStack {
                            Button("Shortcuts") {
                                Task { await runOperatorAction(appState.listShortcuts) }
                            }
                            Button("Screen Recording") {
                                Task { await runOperatorAction(appState.openScreenRecordingSettings) }
                            }
                            Button("Automation") {
                                Task { await runOperatorAction(appState.openAutomationSettings) }
                            }
                        }
                        .disabled(isRunningOperatorAction)

                        Button("Accessibility Settings") {
                            Task { await runOperatorAction(appState.openAccessibilitySettings) }
                        }
                        .disabled(isRunningOperatorAction)
                    }
                } label: {
                    Label("Operator Controls", systemImage: "switch.2")
                }

                Divider()
                HStack {
                    Label("Daemon Health", systemImage: "server.rack")
                        .font(.headline)
                    Spacer()
                    Button("Build All") {
                        Task { await runDaemonBuildAll() }
                    }
                    .disabled(isRunningDaemonAction)
                    Button("Restart All") {
                        appState.daemons.restartAll()
                    }
                    .disabled(isRunningDaemonAction)
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(appState.daemons.allRuntimeStates) { state in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(daemonStatusColor(state.status))
                                        .frame(width: 8, height: 8)
                                    Text(state.serverName)
                                        .font(.system(.body, design: .monospaced))
                                    Text(state.status.rawValue)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    let buildState = appState.daemons.buildState(for: state.serverName)
                                    Text(buildState?.status.rawValue ?? DaemonBuildStatus.idle.rawValue)
                                        .font(.caption2)
                                        .foregroundStyle(buildStatusColor(buildState?.status ?? .idle))
                                    Spacer()
                                    Button("Build") {
                                        Task { await runDaemonBuild(state.serverName) }
                                    }
                                    .disabled(isRunningDaemonAction)
                                    Button("Restart") {
                                        appState.daemons.restart(serverName: state.serverName)
                                    }
                                    .disabled(isRunningDaemonAction)
                                    Button("Log") {
                                        Task { _ = await appState.revealFinderPath(state.logPath) }
                                    }
                                    Button("Script") {
                                        Task { _ = await appState.revealFinderPath(state.scriptPath) }
                                    }
                                }

                                if let error = state.lastError, !error.isEmpty {
                                    Text(error)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }

                                if let buildState = appState.daemons.buildState(for: state.serverName) {
                                    Text(buildState.lastOutput)
                                        .font(.system(.caption2, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(4)
                                }

                                let runtimeSnippet = appState.daemons.recentRuntimeLog(for: state.serverName)
                                if !runtimeSnippet.isEmpty {
                                    Text(runtimeSnippet)
                                        .font(.system(.caption2, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(4)
                                }
                            }
                            .padding(.vertical, 4)
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
        .onAppear {
            appState.daemons.refreshRuntimeStates()
        }
    }

    private func daemonStatusColor(_ status: DaemonRuntimeStatus) -> Color {
        switch status {
        case .running:
            return .green
        case .starting:
            return .blue
        case .stopped:
            return .gray
        case .notBuilt:
            return .orange
        case .failed:
            return .red
        }
    }

    private func buildStatusColor(_ status: DaemonBuildStatus) -> Color {
        switch status {
        case .idle:
            return .secondary
        case .building:
            return .blue
        case .succeeded:
            return .green
        case .failed:
            return .red
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

    private func runOperatorAction(
        _ action: @escaping () async -> Result<MCPToolExecutionResult, Error>
    ) async {
        guard !isRunningOperatorAction else { return }
        isRunningOperatorAction = true
        defer { isRunningOperatorAction = false }

        let result = await action()
        switch result {
        case .success(let output):
            operatorResult = output.text
        case .failure(let error):
            operatorResult = "Error: \(error.localizedDescription)"
        }
    }

    private func switchToRepoBrain() async {
        guard !isRunningBrainAction else { return }
        isRunningBrainAction = true
        defer { isRunningBrainAction = false }

        brain.useRepoDefault()
        appState.daemons.restart(serverName: "knowledge-corpus")
        await readiness.refresh()
        await loadBrainOverview()
        operatorResult = "Using repo brain: \(brain.activeBrainPath)"
    }

    private func switchToLocalBrain() async {
        guard !isRunningBrainAction else { return }
        isRunningBrainAction = true
        defer { isRunningBrainAction = false }

        do {
            try brain.useLocalBrain()
            appState.daemons.restart(serverName: "knowledge-corpus")
            await readiness.refresh()
            await loadBrainOverview()
            operatorResult = "Using local brain: \(brain.activeBrainPath)"
        } catch {
            operatorResult = "Brain error: \(error.localizedDescription)"
        }
    }

    private func runDaemonBuild(_ serverName: String) async {
        guard !isRunningDaemonAction else { return }
        isRunningDaemonAction = true
        defer { isRunningDaemonAction = false }
        await appState.daemons.build(serverName: serverName)
    }

    private func runDaemonBuildAll() async {
        guard !isRunningDaemonAction else { return }
        isRunningDaemonAction = true
        defer { isRunningDaemonAction = false }
        await appState.daemons.buildAll()
    }
}
