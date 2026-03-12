import SwiftUI

struct ProductionDashboardView: View {
    @EnvironmentObject private var appState: AppState
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
    @State private var workflowLog = "Run the stub assembly workflow to exercise the computer-use seam."
    @State private var isRunningWorkflow = false

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
                Text("Computer-use provider: Stub")
                    .foregroundStyle(.secondary)
                Text("Real FCP control is deferred to a future computer-use integration.")
                    .foregroundStyle(.secondary)
                    .font(.callout)
                Divider()
                ScrollView {
                    Text(workflowLog)
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Spacer()
                Button(isRunningWorkflow ? "Running..." : "Run Assembly Workflow (Stub)") {
                    Task {
                        await runAssemblyWorkflow()
                    }
                }
                .disabled(isRunningWorkflow)
            }
            .padding()
            .frame(minWidth: 280)
        }
        .navigationTitle("Production")
    }

    private func runAssemblyWorkflow() async {
        guard let queuedIndex = jobs.firstIndex(where: { $0.status == .queued }) else {
            workflowLog = "No queued media job available."
            return
        }

        isRunningWorkflow = true
        jobs[queuedIndex].status = .running
        jobs[queuedIndex].progress = 0.15

        let jobName = jobs[queuedIndex].name
        let result = await appState.runAssemblyWorkflow(jobName: jobName)

        switch result {
        case .success(let output):
            jobs[queuedIndex].status = .completed
            jobs[queuedIndex].progress = 1.0
            jobs[queuedIndex].completedAt = Date()
            workflowLog = output
        case .failure(let error):
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
