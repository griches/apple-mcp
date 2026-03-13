import SwiftUI

private struct PaletteAction: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let keywords: [String]
    let perform: @MainActor () async -> Void
}

struct CommandPaletteView: View {
    @Binding var isPresented: Bool
    @Binding var selectedView: ShellView?

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var audit: AuditController
    @EnvironmentObject private var brain: BrainManager
    @EnvironmentObject private var production: ProductionController
    @EnvironmentObject private var session: ShellSessionController

    @State private var query = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Search commands", text: $query)
                .textFieldStyle(.roundedBorder)

            List(filteredActions) { action in
                Button {
                    Task {
                        audit.record(category: .commandPalette, title: "Palette action", detail: action.title)
                        await action.perform()
                        isPresented = false
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(action.title)
                        Text(action.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
        }
        .padding()
        .frame(minWidth: 640, minHeight: 420)
    }

    private var filteredActions: [PaletteAction] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else {
            return actions
        }

        return actions.filter { action in
            action.title.lowercased().contains(normalized)
                || action.subtitle.lowercased().contains(normalized)
                || action.keywords.contains(where: { $0.lowercased().contains(normalized) })
        }
    }

    private var actions: [PaletteAction] {
        var items: [PaletteAction] = [
            PaletteAction(
                id: "nav-cockpit",
                title: "Open Cockpit",
                subtitle: "Switch to the shell cockpit.",
                keywords: ["cockpit", "home", "dashboard"]
            ) {
                selectedView = .cockpit
                audit.record(category: .navigation, title: "Open view", detail: ShellView.cockpit.rawValue)
            },
            PaletteAction(
                id: "nav-terminal",
                title: "Open Agent Terminal",
                subtitle: "Switch to the terminal.",
                keywords: ["terminal", "agent", "command"]
            ) {
                selectedView = .terminal
                audit.record(category: .navigation, title: "Open view", detail: ShellView.terminal.rawValue)
            },
            PaletteAction(
                id: "clear-terminal-history",
                title: "Clear Terminal History",
                subtitle: "Reset the persisted Agent Terminal transcript.",
                keywords: ["terminal", "history", "clear", "reset"]
            ) {
                session.clearTerminalHistory()
                selectedView = .terminal
            },
            PaletteAction(
                id: "nav-production",
                title: "Open Production",
                subtitle: "Switch to the production runtime.",
                keywords: ["production", "fcp", "motion"]
            ) {
                selectedView = .production
                audit.record(category: .navigation, title: "Open view", detail: ShellView.production.rawValue)
            },
            PaletteAction(
                id: "nav-audit",
                title: "Open Audit",
                subtitle: "Switch to the audit timeline.",
                keywords: ["audit", "log", "history"]
            ) {
                selectedView = .audit
                audit.record(category: .navigation, title: "Open view", detail: ShellView.audit.rawValue)
            },
            PaletteAction(
                id: "restart-all-daemons",
                title: "Restart All Daemons",
                subtitle: "Restart every MCP child process.",
                keywords: ["daemon", "restart", "mcp", "all"]
            ) {
                appState.daemons.restartAll()
            },
            PaletteAction(
                id: "build-all-daemons",
                title: "Build All Daemons",
                subtitle: "Run npm build for every MCP server package.",
                keywords: ["daemon", "build", "mcp", "all"]
            ) {
                await appState.daemons.buildAll()
            },
            PaletteAction(
                id: "run-next-workflow",
                title: "Run Next Workflow",
                subtitle: "Start the next queued production job.",
                keywords: ["workflow", "run", "queue", "production"]
            ) {
                selectedView = .production
                await production.runNextWorkflow()
            },
            PaletteAction(
                id: "queue-fcp-export",
                title: "Queue FCP Export",
                subtitle: "Queue the current timeline export preset.",
                keywords: ["fcp", "export", "timeline"]
            ) {
                selectedView = .production
                production.queueWorkflowJob(
                    client: "Palette",
                    preset: .fcpExportCurrentTimeline,
                    exportTargetID: production.defaultExportTarget?.id
                )
            },
            PaletteAction(
                id: "queue-fcp-monitor",
                title: "Queue FCP Monitor",
                subtitle: "Queue the background task monitor preset.",
                keywords: ["fcp", "monitor", "background", "tasks"]
            ) {
                selectedView = .production
                production.queueWorkflowJob(client: "Palette", preset: .fcpMonitorBackgroundTasks)
            },
            PaletteAction(
                id: "queue-motion-review",
                title: "Queue Motion Review Placeholder",
                subtitle: "Queue the Motion placeholder review preset.",
                keywords: ["motion", "placeholder", "review"]
            ) {
                selectedView = .production
                production.queueWorkflowJob(client: "Palette", preset: .motionPlaceholderReview)
            },
            PaletteAction(
                id: "queue-motion-export",
                title: "Queue Motion Export Placeholder",
                subtitle: "Queue the Motion placeholder export preset.",
                keywords: ["motion", "placeholder", "export"]
            ) {
                selectedView = .production
                production.queueWorkflowJob(
                    client: "Palette",
                    preset: .motionPlaceholderExport,
                    exportTargetID: production.defaultExportTarget?.id
                )
            },
            PaletteAction(
                id: "clear-finished-jobs",
                title: "Clear Finished Jobs",
                subtitle: "Remove completed, failed, and canceled jobs from the active queue.",
                keywords: ["jobs", "queue", "clear", "finished"]
            ) {
                selectedView = .production
                production.clearFinishedJobs()
            },
            PaletteAction(
                id: "open-downloads",
                title: "Open Downloads in Finder",
                subtitle: "Open the Downloads folder.",
                keywords: ["finder", "downloads"]
            ) {
                _ = await appState.openDownloadsFolder()
            },
            PaletteAction(
                id: "open-repo",
                title: "Open Repo in Finder",
                subtitle: "Open the repo root.",
                keywords: ["finder", "repo"]
            ) {
                _ = await appState.openRepoFolder()
            },
            PaletteAction(
                id: "reveal-active-brain",
                title: "Reveal Active Brain",
                subtitle: "Show the current operating brain file in Finder.",
                keywords: ["brain", "finder", "reveal"]
            ) {
                _ = await appState.revealBrainFile()
            },
            PaletteAction(
                id: "use-repo-brain",
                title: "Use Repo Brain",
                subtitle: "Switch back to the repo-bundled brain file.",
                keywords: ["brain", "repo", "default"]
            ) {
                brain.useRepoDefault()
                appState.daemons.restart(serverName: "knowledge-corpus")
            },
            PaletteAction(
                id: "use-local-brain",
                title: "Use Local Brain",
                subtitle: "Seed and switch to the user-local brain copy.",
                keywords: ["brain", "local", "seed"]
            ) {
                do {
                    try brain.useLocalBrain()
                    appState.daemons.restart(serverName: "knowledge-corpus")
                } catch {
                    audit.record(category: .system, title: "Local brain switch failed", detail: error.localizedDescription)
                }
            },
            PaletteAction(
                id: "open-repo-terminal",
                title: "Open Repo in Terminal",
                subtitle: "Launch Terminal at the repo root.",
                keywords: ["terminal", "repo", "shell"]
            ) {
                _ = await appState.openRepoInTerminal()
            },
            PaletteAction(
                id: "open-repo-iterm",
                title: "Open Repo in iTerm",
                subtitle: "Launch iTerm at the repo root.",
                keywords: ["iterm", "repo", "shell"]
            ) {
                _ = await appState.openRepoInITerm()
            },
            PaletteAction(
                id: "preview-finder-selection",
                title: "Open Finder Selection in Preview",
                subtitle: "Preview the first selected Finder item.",
                keywords: ["preview", "finder", "selection", "artifact"]
            ) {
                _ = await appState.openFinderSelectionInPreview()
            },
            PaletteAction(
                id: "photos-finder-selection",
                title: "Open Finder Selection in Photos",
                subtitle: "Open the first selected Finder item in Photos.",
                keywords: ["photos", "finder", "selection", "artifact"]
            ) {
                _ = await appState.openFinderSelectionInPhotos()
            },
            PaletteAction(
                id: "open-accessibility",
                title: "Open Accessibility Settings",
                subtitle: "Jump directly to the Accessibility privacy pane.",
                keywords: ["settings", "accessibility", "tcc"]
            ) {
                _ = await appState.openAccessibilitySettings()
            },
            PaletteAction(
                id: "open-screen-recording",
                title: "Open Screen Recording Settings",
                subtitle: "Jump directly to the Screen Recording privacy pane.",
                keywords: ["settings", "screen recording", "tcc"]
            ) {
                _ = await appState.openScreenRecordingSettings()
            },
            PaletteAction(
                id: "open-automation-settings",
                title: "Open Automation Settings",
                subtitle: "Jump directly to the Automation privacy pane.",
                keywords: ["settings", "automation", "tcc"]
            ) {
                _ = await appState.openAutomationSettings()
            },
            PaletteAction(
                id: "open-full-disk-settings",
                title: "Open Full Disk Access Settings",
                subtitle: "Jump directly to the Full Disk Access pane.",
                keywords: ["settings", "full disk access", "tcc"]
            ) {
                _ = await appState.openFullDiskAccessSettings()
            },
            PaletteAction(
                id: "list-shortcuts",
                title: "List Shortcuts",
                subtitle: "Run the native shortcuts list action.",
                keywords: ["shortcuts", "list"]
            ) {
                _ = await appState.listShortcuts()
            },
            PaletteAction(
                id: "reveal-audit-log",
                title: "Reveal Audit Log",
                subtitle: "Open the persisted audit log location in Finder.",
                keywords: ["audit", "log", "finder"]
            ) {
                _ = await appState.revealFinderPath(audit.filePath)
            },
        ]

        if let target = production.defaultExportTarget {
            items.append(
                PaletteAction(
                    id: "open-default-export-target",
                    title: "Open Default Export Target",
                    subtitle: target.path,
                    keywords: ["export", "target", "finder"]
                ) {
                    _ = await appState.openFinderPath(target.path)
                }
            )
        }

        items.append(contentsOf: appState.daemons.allRuntimeStates.map { state in
            PaletteAction(
                id: "restart-\(state.serverName)",
                title: "Restart \(state.serverName)",
                subtitle: "Current state: \(state.status.rawValue)",
                keywords: ["daemon", "restart", state.serverName]
            ) {
                appState.daemons.restart(serverName: state.serverName)
            }
        })

        return items
    }
}
