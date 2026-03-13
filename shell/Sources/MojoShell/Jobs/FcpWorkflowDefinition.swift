import AppKit
import Foundation

/// A single step in a computer-use workflow.
struct WorkflowStep: Identifiable, Sendable {
    let id = UUID()
    let description: String

    /// Preferred: find an AX element by role + title fragment and click its center.
    let axQuery: AXQuery?

    /// Fallback: fixed coordinates as "x,y" string (used when AX lookup fails or isn't applicable).
    let fallbackCoordinates: String?

    /// Keystroke to fire (e.g. "cmd+e") — used instead of a click when set.
    let keypress: String?

    /// Text to type into the focused element.
    let typeText: String?

    /// App to bring to the foreground via NSWorkspace (deterministic; ignores the app-switcher order).
    /// When set, all other action fields are ignored.
    let appActivationName: String?

    /// Optional operator checkpoint before executing this step.
    let approvalPrompt: String?

    /// Delay in seconds AFTER this step executes.
    let delayAfter: TimeInterval

    struct AXQuery: Sendable {
        let appName: String
        let role: String        // e.g. "AXButton"
        let titleContaining: String
    }

    // Convenience initialisers

    /// Activates a running app by its localised name using NSWorkspace.
    /// Does NOT use cmd+tab — directly addresses the target process.
    static func activateApp(
        _ appName: String,
        approvalPrompt: String? = nil,
        delay: TimeInterval = 0.5
    ) -> WorkflowStep {
        WorkflowStep(
            description: "Activate \(appName)",
            axQuery: nil,
            fallbackCoordinates: nil,
            keypress: nil,
            typeText: nil,
            appActivationName: appName,
            approvalPrompt: approvalPrompt,
            delayAfter: delay
        )
    }

    static func click(
        _ description: String,
        app: String,
        buttonTitled title: String,
        fallback: String? = nil,
        approvalPrompt: String? = nil,
        delay: TimeInterval = 0.3
    ) -> WorkflowStep {
        WorkflowStep(
            description: description,
            axQuery: AXQuery(appName: app, role: "AXButton", titleContaining: title),
            fallbackCoordinates: fallback,
            keypress: nil,
            typeText: nil,
            appActivationName: nil,
            approvalPrompt: approvalPrompt,
            delayAfter: delay
        )
    }

    static func keypress(
        _ description: String,
        key: String,
        approvalPrompt: String? = nil,
        delay: TimeInterval = 0.3
    ) -> WorkflowStep {
        WorkflowStep(
            description: description,
            axQuery: nil,
            fallbackCoordinates: nil,
            keypress: key,
            typeText: nil,
            appActivationName: nil,
            approvalPrompt: approvalPrompt,
            delayAfter: delay
        )
    }

    static func type(
        _ description: String,
        text: String,
        approvalPrompt: String? = nil,
        delay: TimeInterval = 0.2
    ) -> WorkflowStep {
        WorkflowStep(
            description: description,
            axQuery: nil,
            fallbackCoordinates: nil,
            keypress: nil,
            typeText: text,
            appActivationName: nil,
            approvalPrompt: approvalPrompt,
            delayAfter: delay
        )
    }

    static func coordinate(
        _ description: String,
        at xy: String,
        approvalPrompt: String? = nil,
        delay: TimeInterval = 0.3
    ) -> WorkflowStep {
        WorkflowStep(
            description: description,
            axQuery: nil,
            fallbackCoordinates: xy,
            keypress: nil,
            typeText: nil,
            appActivationName: nil,
            approvalPrompt: approvalPrompt,
            delayAfter: delay
        )
    }
}

/// Predefined computer-use workflow sequences for Final Cut Pro.
enum FcpWorkflowDefinition {

    /// Assembly workflow: bring FCP to front, open the Export File sheet, confirm.
    ///
    /// AX discovery status (2026-03-12):
    ///   ✅ Step 1 — toolbar Share button: "Share the project, event clip, or Timeline range"
    ///   ⚠️  Step 2 — shareDestination: "Export File (default)…" is context-sensitive.
    ///              It does NOT appear in the AX tree unless FCP has an exportable project/clip
    ///              selected. Without that state, only "Export XML…" and "Export Captions…"
    ///              are visible. File > Share > "Export File (default)…" is the target entry.
    ///   ✅ Step 3-4 — export sheet buttons confirmed live (2026-03-12):
    ///              Advance: "Next…" (AXButton, ellipsis included) at approx 994,715
    ///              Cancel:  "Cancel" (AXButton) at approx 916,715
    ///              Note: "Save Effects Preset" is a separate inspector button, not the sheet advance.
    ///
    /// - Parameter shareDestination: The share-sheet destination button title to select.
    ///   Defaults to `"Export File (default)…"` — the File > Share item name (context-sensitive).
    ///   Other destinations: `"Apple Devices 1080p…"`, `"Social Platforms…"`, etc.
    static func assemblyWorkflow(
        shareDestination: String = "Export File (default)…",
        exportTargetPath: String? = nil
    ) -> [WorkflowStep] {
        let destinationPrompt = exportTargetPath.map {
            "Confirm the export destination in Final Cut Pro before MojoShell clicks it. Target folder: \($0)"
        } ?? "Confirm the export destination in Final Cut Pro before MojoShell clicks it."

        let nextPrompt = exportTargetPath.map {
            "Confirm the export sheet is configured correctly before advancing. Save into: \($0)"
        } ?? "Confirm the export sheet is configured correctly before advancing."

        return [
            // 1. Bring FCP to front deterministically (NSWorkspace, not cmd+tab)
            .activateApp("Final Cut Pro"),

            // 2. Click the toolbar Share button.
            //    Verified AX title: "Share the project, event clip, or Timeline range"
            //    Requires a clip/project selected; button is enabled when something is in the timeline.
            .click(
                "Open Share sheet via toolbar",
                app: "Final Cut Pro",
                buttonTitled: "Share the project, event clip, or Timeline range",
                delay: 1.0
            ),

            // 3. Select the export destination.
            //    "Export File (default)…" is the target AX title — only exposed when FCP
            //    has an exportable project/clip selected in the timeline.
            //    TBD: verify exact title with:
            //      scripts/discover_ax_elements.py --app "Final Cut Pro" --title export --max-depth 10
            .click(
                "Select '\(shareDestination)'",
                app: "Final Cut Pro",
                buttonTitled: shareDestination,
                approvalPrompt: destinationPrompt,
                delay: 0.5
            ),

            // 4. Advance through the export sheet.
            //    Verified AX title: "Next…" (with ellipsis) — confirmed live 2026-03-12.
            //    "Save Effects Preset" is a separate inspector button; the sheet advance is "Next…".
            .click(
                "Click Next…",
                app: "Final Cut Pro",
                buttonTitled: "Next…",
                fallback: nil,
                approvalPrompt: nextPrompt,
                delay: 0.5
            ),
        ]
    }

    /// Monitoring check: read the current background task list via Cmd+9 (Background Tasks window).
    static func monitoringCheck() -> [WorkflowStep] {
        [
            .activateApp("Final Cut Pro"),
            .keypress("Open Background Tasks window (Cmd+9)", key: "cmd+9", delay: 0.8),
        ]
    }
}

/// Executes a list of `WorkflowStep` values against a `ComputerUseProvider`, logging progress.
struct WorkflowExecutor {
    let provider: any ComputerUseProvider

    @MainActor
    func run(
        steps: [WorkflowStep],
        sessionId: String,
        onProgress: @escaping (String) -> Void,
        onStepResult: ((Int, WorkflowStep, ComputerUseResult) -> Void)? = nil,
        onApprovalRequested: ((Int, WorkflowStep) async -> Bool)? = nil
    ) async throws {
        for (index, step) in steps.enumerated() {
            onProgress("[\(index + 1)/\(steps.count)] \(step.description)…")

            if step.approvalPrompt != nil {
                let approved = await onApprovalRequested?(index, step) ?? false
                if !approved {
                    throw WorkflowError.approvalRejected(step.description)
                }
            }

            var stepResult: ComputerUseResult?

            if let appName = step.appActivationName {
                let activated = await MainActor.run {
                    NSWorkspace.shared.runningApplications
                        .first { $0.localizedName == appName }?
                        .activate()
                        ?? false
                }
                if !activated {
                    throw WorkflowError.appNotRunning(appName)
                }
            } else if let keypress = step.keypress {
                stepResult = try await provider.execute(
                    sessionId: sessionId,
                    action: ComputerUseAction(type: .keypress, target: keypress)
                )
            } else if let text = step.typeText {
                stepResult = try await provider.execute(
                    sessionId: sessionId,
                    action: ComputerUseAction(type: .type, target: text)
                )
            } else if let query = step.axQuery {
                let target = try resolveAXTarget(query: query, fallback: step.fallbackCoordinates)
                stepResult = try await provider.execute(
                    sessionId: sessionId,
                    action: ComputerUseAction(type: .click, target: target)
                )
            } else if let coords = step.fallbackCoordinates {
                stepResult = try await provider.execute(
                    sessionId: sessionId,
                    action: ComputerUseAction(type: .click, target: coords)
                )
            }

            if let stepResult {
                onStepResult?(index, step, stepResult)
            }

            if step.delayAfter > 0 {
                try await Task.sleep(nanoseconds: UInt64(step.delayAfter * 1_000_000_000))
            }
        }

        onProgress("Workflow complete.")
    }

    private func resolveAXTarget(query: WorkflowStep.AXQuery, fallback: String?) throws -> String {
        if let elements = try? AccessibilityElementFinder.findElements(
            inApp: query.appName,
            roles: [query.role],
            titleContaining: query.titleContaining
        ), let first = elements.first {
            return "\(Int(first.screenPoint.x)),\(Int(first.screenPoint.y))"
        }

        if let fallback {
            return fallback
        }

        throw WorkflowError.elementNotFound(query.appName, query.role, query.titleContaining)
    }
}

enum WorkflowError: LocalizedError {
    case elementNotFound(String, String, String)
    case appNotRunning(String)
    case approvalRejected(String)

    var errorDescription: String? {
        switch self {
        case .elementNotFound(let app, let role, let title):
            return "Could not find '\(title)' (\(role)) in \(app). Is the app open?"
        case .appNotRunning(let name):
            return "\(name) is not running. Open it before starting the workflow."
        case .approvalRejected(let description):
            return "Approval rejected for step: \(description)"
        }
    }
}
