import SwiftUI

struct ProductionDashboardView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var readiness: ReadinessState
    @EnvironmentObject private var production: ProductionController

    @State private var discoveredElements: [FoundAXElement] = []
    @State private var isDiscovering = false

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Label("Job Queue", systemImage: "list.bullet.rectangle")
                        .font(.headline)
                    Spacer()
                    Button("Queue Job") {
                        queueDefaultJob()
                    }
                }
                .padding()

                Divider()

                if production.jobs.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("No jobs yet")
                            .font(.headline)
                        Text("Queue a job, then run assembly.")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding()
                } else {
                    List(production.jobs) { job in
                        JobRow(job: job) {
                            production.retryFailedJob(id: job.id)
                        }
                    }
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
                        Label("Final Cut Pro - \(discoveredElements.count) elements", systemImage: "list.bullet.rectangle.portrait")
                    }
                }

                Divider()

                ScrollView {
                    Text(production.workflowLog)
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox {
                    if production.recentEvents.isEmpty {
                        Text("No events yet")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        ForEach(Array(production.recentEvents.suffix(8).reversed())) { event in
                            EventRow(event: event)
                        }
                    }
                } label: {
                    Label("Recent Events", systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                }

                if let approval = production.pendingApproval {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Step \(approval.stepIndex + 1): \(approval.stepDescription)")
                                .font(.headline)
                            Text(approval.prompt)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            HStack {
                                Button("Approve") {
                                    production.approvePendingStep()
                                }
                                Button("Reject") {
                                    production.rejectPendingStep()
                                }
                            }
                        }
                    } label: {
                        Label("Approval Required", systemImage: "hand.raised")
                    }
                }

                Spacer()

                VStack(alignment: .leading, spacing: 4) {
                    Button(production.isRunningWorkflow ? "Running..." : "Run Assembly Workflow") {
                        Task { await production.runNextAssemblyWorkflow() }
                    }
                    .disabled(production.isRunningWorkflow || !readiness.isReady(for: .computerUse))

                    if !readiness.isReady(for: .computerUse),
                       let issue = readiness.blockingIssue(for: .computerUse) {
                        Text(issue.fixInstruction)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding()
            .frame(minWidth: 320)
        }
        .navigationTitle("Production")
        .task {
            await readiness.refreshComputerUse()
        }
    }

    private func queueDefaultJob() {
        let stamp = Date().formatted(date: .abbreviated, time: .shortened)
        production.queueAssemblyJob(name: "Assembly - \(stamp)", client: "Manual")
    }

    private func discoverFcpElements() async {
        isDiscovering = true
        production.workflowLog = "Scanning Final Cut Pro accessibility tree..."
        do {
            let elements = try AccessibilityElementFinder.findButtons(inApp: "Final Cut Pro")
            discoveredElements = elements
            production.workflowLog = "Found \(elements.count) buttons in Final Cut Pro. Coordinates are in global screen space (origin = top-left of primary display)."
        } catch {
            production.workflowLog = "Discovery error: \(error.localizedDescription)"
            discoveredElements = []
        }
        isDiscovering = false
    }
}

struct JobRow: View {
    let job: MediaJob
    let onRetry: () -> Void

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
            if let error = job.errorMessage, (job.status == .failed || job.status == .canceled) {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(job.status == .canceled ? .orange : .red)
                Button("Retry") {
                    onRetry()
                }
                .buttonStyle(.link)
            }
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
        case .canceled:
            return .orange
        }
    }
}

private struct EventRow: View {
    let event: JobEvent

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(event.timestamp.formatted(date: .omitted, time: .standard))
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.type.rawValue)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(event.message)
                    .font(.caption)
                if let screenshotPath = event.screenshotPath {
                    Text(screenshotPath)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            Spacer()
        }
    }
}
