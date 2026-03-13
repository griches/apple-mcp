import SwiftUI

struct ProductionDashboardView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var readiness: ReadinessState
    @State private var jobs: [MediaJob] = [
        MediaJob(
            name: "Appalachian Community FCU — Benefits Overview",
            client: "ElanPresentation",
            status: .completed,
            progress: 1.0,
            createdAt: Date().addingTimeInterval(-3600),
            completedAt: Date(),
            errorMessage: nil
        ),
        MediaJob(
            name: "FedChoice FCU — Enrollment Video",
            client: "ElanPresentation",
            status: .running,
            progress: 0.62,
            createdAt: Date().addingTimeInterval(-600),
            completedAt: nil,
            errorMessage: nil
        ),
        MediaJob(
            name: "Credit Union 1 — Annual Benefits",
            client: "ElanPresentation",
            status: .queued,
            progress: 0.0,
            createdAt: Date(),
            completedAt: nil,
            errorMessage: nil
        ),
    ]
    @State private var workflowLog = "Ready. Use 'Discover FCP Elements' first to verify accessibility access, then 'Run Assembly Workflow' to trigger the share dialog."
    @State private var isRunningWorkflow = false
    @State private var discoveredElements: [FoundAXElement] = []
    @State private var isDiscovering = false

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 0) {
                Label("Job Queue", systemImage: "list.bullet.rectangle")
                    .font(.headline)
                    .padding()
                Divider()
                List(jobs) { job in
                    JobRow(job: job)
                }
            }
            .frame(minWidth: 360)

            VStack(alignment: .leading, spacing: 12) {
                Label("FCP / Motion", systemImage: "film.stack")
                    .font(.headline)
                Divider()
                HStack {
                    Text("Provider: \(appState.computerUseProviderName)")
                    Spacer()
                    Button(isDiscovering ? "Scanning..." : "Discover FCP Elements") {
                        Task { await discoverFcpElements() }
                    }
                    .disabled(isDiscovering || !readiness.axPermissionGranted())
                }
                .foregroundStyle(.secondary)

                if !discoveredElements.isEmpty {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(discoveredElements) { element in
                                HStack(spacing: 8) {
                                    Text("\(Int(element.screenPoint.x)),\(Int(element.screenPoint.y))")
                                        .font(.system(.caption2, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 90, alignment: .leading)
                                    Text(element.title.isEmpty ? "(untitled)" : element.title)
                                        .font(.caption)
                                    Spacer()
                                    Text(element.role)
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                    } label: {
                        Label("Final Cut Pro — \(discoveredElements.count) elements", systemImage: "list.bullet.rectangle.portrait")
                    }
                }

                Divider()
                ScrollView {
                    Text(workflowLog)
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Spacer()
                VStack(alignment: .leading, spacing: 4) {
                    Button(isRunningWorkflow ? "Running..." : "Run Assembly Workflow") {
                        Task { await runAssemblyWorkflow() }
                    }
                    .disabled(isRunningWorkflow || !readiness.isReady(for: .computerUse))

                    if !readiness.isReady(for: .computerUse),
                       let issue = readiness.blockingIssue(for: .computerUse) {
                        Text(issue.fixInstruction)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding()
            .frame(minWidth: 280)
        }
        .navigationTitle("Production")
        .task {
            await readiness.refreshComputerUse()
        }
    }

    private func discoverFcpElements() async {
        isDiscovering = true
        workflowLog = "Scanning Final Cut Pro accessibility tree…"
        do {
            let elements = try AccessibilityElementFinder.findButtons(inApp: "Final Cut Pro")
            discoveredElements = elements
            workflowLog = "Found \(elements.count) buttons in Final Cut Pro. Coordinates are in global screen space (origin = top-left of primary display)."
        } catch {
            workflowLog = "Discovery error: \(error.localizedDescription)"
            discoveredElements = []
        }
        isDiscovering = false
    }

    private func runAssemblyWorkflow() async {
        guard let queuedIndex = jobs.firstIndex(where: { $0.status == .queued }) else {
            workflowLog = "No queued media job available."
            return
        }

        isRunningWorkflow = true

        // Preflight: verify FCP is running and has an exportable selection before starting a session.
        // "Export File (default)…" only appears in the AX tree when a project/clip is selected.
        workflowLog = "Checking Final Cut Pro export state…"
        do {
            let exportItems = try AccessibilityElementFinder.findElements(
                inApp: "Final Cut Pro",
                roles: ["AXMenuItem"],
                titleContaining: "Export File"
            )
            guard !exportItems.isEmpty else {
                workflowLog = "No exportable clip selected in Final Cut Pro. Select a timeline item and try again."
                isRunningWorkflow = false
                return
            }
        } catch AccessibilityElementFinder.FinderError.appNotRunning {
            workflowLog = "Final Cut Pro is not running. Open it and load a project first."
            isRunningWorkflow = false
            return
        } catch AccessibilityElementFinder.FinderError.accessibilityPermissionDenied {
            workflowLog = "Accessibility permission denied. Grant access in System Settings → Privacy & Security → Accessibility."
            isRunningWorkflow = false
            return
        } catch {
            workflowLog = "Preflight error: \(error.localizedDescription)"
            isRunningWorkflow = false
            return
        }

        jobs[queuedIndex].status = .running
        jobs[queuedIndex].progress = 0.15
        workflowLog = "Starting assembly workflow…"

        var sessionId: String?
        do {
            sessionId = try await appState.computerUseProvider.startSession()
            let steps = FcpWorkflowDefinition.assemblyWorkflow()
            let executor = WorkflowExecutor(provider: appState.computerUseProvider)

            try await executor.run(steps: steps, sessionId: sessionId!) { [self] message in
                Task { @MainActor in
                    workflowLog = message
                }
            }

            try await appState.computerUseProvider.stopSession(sessionId: sessionId!)
            sessionId = nil
            jobs[queuedIndex].status = .completed
            jobs[queuedIndex].progress = 1.0
            jobs[queuedIndex].completedAt = Date()
        } catch {
            if let id = sessionId {
                try? await appState.computerUseProvider.stopSession(sessionId: id)
            }
            jobs[queuedIndex].status = .failed
            jobs[queuedIndex].errorMessage = error.localizedDescription
            workflowLog = "Error: \(error.localizedDescription)"
        }

        isRunningWorkflow = false
    }
}

struct JobRow: View {
    let job: MediaJob

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(job.name).bold()
                Spacer()
                Text(job.status.rawValue.capitalized)
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            if job.status == .running {
                ProgressView(value: job.progress)
            }
            Text(job.client)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var statusColor: Color {
        switch job.status {
        case .queued:
            return .gray
        case .running:
            return .blue
        case .completed:
            return .green
        case .failed:
            return .red
        }
    }
}
