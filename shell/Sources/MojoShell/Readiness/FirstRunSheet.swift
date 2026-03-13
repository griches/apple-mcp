import SwiftUI

struct FirstRunSheet: View {
    @EnvironmentObject private var readiness: ReadinessState

    private var groupedIssues: [(title: String, issues: [ReadinessIssue])] {
        [
            ("Blocking", allIssues.filter { $0.severity == .blocking }),
            ("Warnings", allIssues.filter { $0.severity == .warning }),
            ("Info", allIssues.filter { $0.severity == .info }),
        ].filter { !$0.issues.isEmpty }
    }

    private var allIssues: [ReadinessIssue] {
        let issues = readiness.coreIssues + readiness.featureIssues.values.flatMap { $0 }
        return issues.sorted { lhs, rhs in
            let leftPriority = severityPriority(lhs.severity)
            let rightPriority = severityPriority(rhs.severity)
            return leftPriority == rightPriority ? lhs.id < rhs.id : leftPriority < rightPriority
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("MojoShell Setup", systemImage: "wrench.and.screwdriver")
                .font(.title2.bold())

            Text("Some environment requirements need attention. Fix them now or continue anyway.")
                .foregroundStyle(.secondary)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(groupedIssues, id: \.title) { group in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(group.title)
                                .font(.headline)
                            ForEach(group.issues) { issue in
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: icon(for: issue.severity))
                                        .foregroundStyle(color(for: issue.severity))
                                        .frame(width: 20)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(issue.title)
                                            .font(.callout.bold())
                                        Text(issue.fixInstruction)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        if let url = issue.actionURL {
                                            Link("Open System Settings", destination: url)
                                                .font(.caption)
                                        }
                                    }
                                    Spacer()
                                }
                            }
                        }
                    }
                }
            }

            Divider()

            HStack {
                Button("Retry") {
                    Task { await readiness.refresh() }
                }
                Spacer()
                Button("Continue Anyway") {
                    readiness.markFirstRunShown()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(minWidth: 480, minHeight: 320)
    }

    private func severityPriority(_ severity: ReadinessSeverity) -> Int {
        switch severity {
        case .blocking:
            return 0
        case .warning:
            return 1
        case .info:
            return 2
        }
    }

    private func icon(for severity: ReadinessSeverity) -> String {
        switch severity {
        case .blocking:
            return "xmark.circle.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        case .info:
            return "info.circle"
        }
    }

    private func color(for severity: ReadinessSeverity) -> Color {
        switch severity {
        case .blocking:
            return .red
        case .warning:
            return .orange
        case .info:
            return .blue
        }
    }
}
