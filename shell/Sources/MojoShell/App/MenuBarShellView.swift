import SwiftUI

struct MenuBarShellView: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var brain: BrainManager
    @EnvironmentObject private var production: ProductionController
    @EnvironmentObject private var readiness: ReadinessState
    @EnvironmentObject private var session: ShellSessionController

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(statusTitle, systemImage: statusIcon)
                .font(.headline)

            Text(statusSubtitle)
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            Button("Open Cockpit") {
                openMainWindow(.cockpit)
            }
            Button("Open Agent Terminal") {
                openMainWindow(.terminal)
            }
            Button("Open Production") {
                openMainWindow(.production)
            }
            Button("Open Audit") {
                openMainWindow(.audit)
            }

            Divider()

            Button("Run Next Workflow") {
                openMainWindow(.production)
                Task { await production.runNextWorkflow() }
            }
            .disabled(production.isRunningWorkflow || !readiness.isReady(for: .computerUse))

            Button("Restart All Daemons") {
                appState.daemons.restartAll()
            }

            Button("Build All Daemons") {
                Task { await appState.daemons.buildAll() }
            }

            Divider()

            Button("Use Repo Brain") {
                brain.useRepoDefault()
                appState.daemons.restart(serverName: "knowledge-corpus")
            }

            Button("Use Local Brain") {
                do {
                    try brain.useLocalBrain()
                    appState.daemons.restart(serverName: "knowledge-corpus")
                } catch {
                    // Ignore here; readiness surface will show issues.
                }
            }

            Button("Reveal Active Brain") {
                Task { _ = await appState.revealBrainFile() }
            }

            if let target = production.defaultExportTarget {
                Button("Open Default Export Target") {
                    Task { _ = await appState.openFinderPath(target.path) }
                }
            }

            Divider()

            if production.jobs.isEmpty {
                Text("No queued jobs.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("\(queuedJobCount) queued job(s)")
                    .font(.caption)
                Text("\(failedJobCount) failed or canceled")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(width: 280)
        .task {
            await readiness.refresh()
        }
    }

    private var queuedJobCount: Int {
        production.jobs.filter { $0.status == .queued }.count
    }

    private var failedJobCount: Int {
        production.jobs.filter { $0.status == .failed || $0.status == .canceled }.count
    }

    private var statusIcon: String {
        if hasBlockingIssue {
            return "exclamationmark.triangle.fill"
        }
        if hasAnyIssue {
            return "exclamationmark.circle"
        }
        return "checkmark.circle.fill"
    }

    private var statusTitle: String {
        if hasBlockingIssue {
            return "MojoShell needs attention"
        }
        if hasAnyIssue {
            return "MojoShell partially ready"
        }
        return "MojoShell ready"
    }

    private var statusSubtitle: String {
        if let issue = readiness.coreIssues.first ?? readiness.featureIssues.values.flatMap({ $0 }).first {
            return issue.fixInstruction
        }
        return "Queued jobs: \(queuedJobCount) • Provider: \(appState.computerUseProviderName)"
    }

    private var hasBlockingIssue: Bool {
        readiness.coreIssues.contains(where: { $0.severity == .blocking })
            || readiness.featureIssues.values.flatMap({ $0 }).contains(where: { $0.severity == .blocking })
    }

    private var hasAnyIssue: Bool {
        !readiness.coreIssues.isEmpty || readiness.featureIssues.values.contains(where: { !$0.isEmpty })
    }

    private func openMainWindow(_ view: ShellView) {
        session.selectedView = view
        openWindow(id: "main")
    }
}
