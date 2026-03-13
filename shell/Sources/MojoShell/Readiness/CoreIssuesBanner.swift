import SwiftUI

struct CoreIssuesBanner: View {
    @EnvironmentObject private var readiness: ReadinessState
    @State private var dismissed = false

    private var blockingIssues: [ReadinessIssue] {
        readiness.coreIssues.filter { $0.severity == .blocking }
    }

    private var warningCount: Int {
        readiness.coreIssues.filter { $0.severity != .blocking }.count
    }

    var body: some View {
        if dismissed || readiness.coreIssues.isEmpty {
            EmptyView()
        } else if !blockingIssues.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text("Environment issues")
                        .font(.headline)
                    Spacer()
                    Button("Dismiss") {
                        dismissed = true
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                }

                ForEach(blockingIssues) { issue in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(issue.title)
                            .font(.caption.bold())
                        Text(issue.fixInstruction)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let url = issue.actionURL {
                            Link("Open Settings", destination: url)
                                .font(.caption)
                        }
                    }
                }
            }
            .padding(12)
            .background(.red.opacity(0.08))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.red.opacity(0.3), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal)
            .padding(.top, 8)
        } else {
            HStack(spacing: 8) {
                Circle()
                    .fill(.orange)
                    .frame(width: 8, height: 8)
                Text("\(warningCount) environment warning\(warningCount == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Dismiss") {
                    dismissed = true
                }
                .buttonStyle(.plain)
                .font(.caption)
            }
            .padding(.horizontal)
            .padding(.top, 8)
        }
    }
}
