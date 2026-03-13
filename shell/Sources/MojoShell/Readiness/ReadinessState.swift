import ApplicationServices
import Combine
import CoreGraphics
import Foundation

@MainActor
final class ReadinessState: ObservableObject {
    @Published var coreIssues: [ReadinessIssue] = []
    @Published var featureIssues: [ReadinessFeature: [ReadinessIssue]] = [:]
    @Published var showFirstRunSheet = false
    @Published var isRefreshing = false

    private let daemonManager: DaemonManager
    private let defaults: UserDefaults
    private let environment: [String: String]
    private let axCheck: @Sendable () -> Bool
    private let screenRecordingCheck: @Sendable () -> Bool

    init(
        daemonManager: DaemonManager,
        defaults: UserDefaults = .standard,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        axCheck: @escaping @Sendable () -> Bool = { AXIsProcessTrusted() },
        screenRecordingCheck: @escaping @Sendable () -> Bool = { CGPreflightScreenCaptureAccess() }
    ) {
        self.daemonManager = daemonManager
        self.defaults = defaults
        self.environment = environment
        self.axCheck = axCheck
        self.screenRecordingCheck = screenRecordingCheck
    }

    func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }

        coreIssues = sortedIssues(buildCoreIssues())
        featureIssues = [
            .computerUse: sortedIssues(buildComputerUseIssues()),
            .llm: sortedIssues(buildLLMIssues()),
        ]

        let hasAnyIssue = !coreIssues.isEmpty || featureIssues.values.contains(where: { !$0.isEmpty })
        if hasAnyIssue && !defaults.bool(forKey: Self.firstRunShownKey) {
            showFirstRunSheet = true
        }
    }

    func refreshComputerUse() async {
        isRefreshing = true
        defer { isRefreshing = false }
        featureIssues[.computerUse] = sortedIssues(buildComputerUseIssues())
    }

    func isReady(for feature: ReadinessFeature) -> Bool {
        !(featureIssues[feature] ?? []).contains { $0.severity == .blocking }
    }

    func blockingIssue(for feature: ReadinessFeature) -> ReadinessIssue? {
        (featureIssues[feature] ?? []).first { $0.severity == .blocking }
    }

    func axPermissionGranted() -> Bool {
        axCheck()
    }

    func markFirstRunShown() {
        defaults.set(true, forKey: Self.firstRunShownKey)
        showFirstRunSheet = false
    }

    private func buildCoreIssues() -> [ReadinessIssue] {
        var issues: [ReadinessIssue] = []

        var isDirectory = ObjCBool(false)
        let repoRootExists = FileManager.default.fileExists(
            atPath: daemonManager.repoRoot,
            isDirectory: &isDirectory
        ) && isDirectory.boolValue
        if !repoRootExists {
            issues.append(
                ReadinessIssue(
                    id: "repo_root",
                    title: "Repository root not found",
                    fixInstruction: "Ensure the MojoShell repository is present at: \(daemonManager.repoRoot)",
                    actionURL: nil,
                    severity: .blocking
                )
            )
        }

        let brainPath = resolvedBrainPath()
        if !FileManager.default.fileExists(atPath: brainPath) {
            issues.append(
                ReadinessIssue(
                    id: "brain_file",
                    title: "Brain file missing",
                    fixInstruction: "Ensure the brain file exists at: \(brainPath)",
                    actionURL: nil,
                    severity: .blocking
                )
            )
        }

        let missingArtifacts = daemonManager.serverDefinitions.filter { !FileManager.default.fileExists(atPath: $0.scriptPath) }
        if !missingArtifacts.isEmpty {
            let names = missingArtifacts.map(\.name).joined(separator: ", ")
            issues.append(
                ReadinessIssue(
                    id: "daemon_artifacts",
                    title: "MCP server build artifacts missing",
                    fixInstruction: "Run the server builds so each `build/index.js` exists. Missing: \(names)",
                    actionURL: nil,
                    severity: .warning
                )
            )
        }

        return issues
    }

    private func buildComputerUseIssues() -> [ReadinessIssue] {
        var issues: [ReadinessIssue] = []

        if !axCheck() {
            issues.append(
                ReadinessIssue(
                    id: "accessibility",
                    title: "Accessibility permission missing",
                    fixInstruction: "Open System Settings -> Privacy & Security -> Accessibility, then enable MojoShell.",
                    actionURL: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"),
                    severity: .blocking
                )
            )
        }

        if !screenRecordingCheck() {
            issues.append(
                ReadinessIssue(
                    id: "screen_recording",
                    title: "Screen Recording permission missing",
                    fixInstruction: "Open System Settings -> Privacy & Security -> Screen Recording, then enable MojoShell.",
                    actionURL: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"),
                    severity: .warning
                )
            )
        }

        return issues
    }

    private func buildLLMIssues() -> [ReadinessIssue] {
        let hasAnthropic = !(environment["ANTHROPIC_API_KEY"] ?? "").isEmpty
        let hasOpenAI = !(environment["OPENAI_API_KEY"] ?? "").isEmpty

        if !hasAnthropic && !hasOpenAI {
            return [
                ReadinessIssue(
                    id: "llm_no_keys",
                    title: "No LLM API keys configured",
                    fixInstruction: "Set ANTHROPIC_API_KEY or OPENAI_API_KEY in your environment.",
                    actionURL: nil,
                    severity: .blocking
                ),
            ]
        }

        if hasAnthropic != hasOpenAI {
            return [
                ReadinessIssue(
                    id: "llm_single_provider",
                    title: "Only one LLM provider configured",
                    fixInstruction: "Optional: set both ANTHROPIC_API_KEY and OPENAI_API_KEY for fallback redundancy.",
                    actionURL: nil,
                    severity: .info
                ),
            ]
        }

        return []
    }

    private func resolvedBrainPath() -> String {
        if let override = environment["BRAIN_PATH"], !override.isEmpty {
            return override
        }
        return "\(daemonManager.repoRoot)/knowledge-corpus/data/mojosolo_operating_brain.json"
    }

    private func sortedIssues(_ issues: [ReadinessIssue]) -> [ReadinessIssue] {
        issues.sorted { lhs, rhs in
            let leftPriority = severityPriority(lhs.severity)
            let rightPriority = severityPriority(rhs.severity)
            return leftPriority == rightPriority ? lhs.id < rhs.id : leftPriority < rightPriority
        }
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

    private static let firstRunShownKey = "readiness.firstRunShown"
}
