import SwiftUI

struct ProductionDashboardView: View {
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
                Spacer()
                Button("Run Assembly Workflow (Stub)") {
                    runAssemblyWorkflow()
                }
            }
            .padding()
            .frame(minWidth: 280)
        }
        .navigationTitle("Production")
    }

    private func runAssemblyWorkflow() {
        print("[ProductionDashboard] Assembly workflow triggered — stub provider active")
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
