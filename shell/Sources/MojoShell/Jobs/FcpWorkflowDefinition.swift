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
        delay: TimeInterval = 0.5
    ) -> WorkflowStep {
        WorkflowStep(
            description: "Activate \(appName)",
            axQuery: nil,
            fallbackCoordinates: nil,
            keypress: nil,
            typeText: nil,
            appActivationName: appName,
            delayAfter: delay
        )
    }

    static func click(
        _ description: String,
        app: String,
        buttonTitled title: String,
        fallback: String? = nil,
        delay: TimeInterval = 0.3
    ) -> WorkflowStep {
        WorkflowStep(
            description: description,
            axQuery: AXQuery(appName: app, role: "AXButton", titleContaining: title),
            fallbackCoordinates: fallback,
            keypress: nil,
            typeText: nil,
            appActivationName: nil,
            delayAfter: delay
        )
    }

    static func keypress(
        _ description: String,
        key: String,
        delay: TimeInterval = 0.3
    ) -> WorkflowStep {
        WorkflowStep(
            description: description,
            axQuery: nil,
            fallbackCoordinates: nil,
            keypress: key,
            typeText: nil,
            appActivationName: nil,
            delayAfter: delay
        )
    }

    static func type(
        _ description: String,
        text: String,
        delay: TimeInterval = 0.2
    ) -> WorkflowStep {
        WorkflowStep(
            description: description,
            axQuery: nil,
            fallbackCoordinates: nil,
            keypress: nil,
            typeText: text,
            appActivationName: nil,
            delayAfter: delay
        )
    }

    static func coordinate(
        _ description: String,
        at xy: String,
        delay: TimeInterval = 0.3
    ) -> WorkflowStep {
        WorkflowStep(
            description: description,
            axQuery: nil,
            fallbackCoordinates: xy,
            keypress: nil,
            typeText: nil,
            appActivationName: nil,
            delayAfter: delay
        )
    }
}

/// Predefined computer-use workflow sequences for Final Cut Pro.
enum FcpWorkflowDefinition {

    /// Assembly workflow: bring FCP to front, open the Share sheet, select the target format.
    ///
    /// Phase 1 scope: gets FCP focused and opens the export dialog.
    /// The specific share destination (Master File, YouTube, etc.) is wired per client template.
    static func assemblyWorkflow(shareDestination: String = "Master File…") -> [WorkflowStep] {
        [
            // 1. Bring FCP to front deterministically via NSWorkspace (not cmd+tab)
            .activateApp("Final Cut Pro"),

            // 2. Click the verified AX toolbar share button title from the live FCP discovery pass.
            .click(
                "Open Share menu",
                app: "Final Cut Pro",
                buttonTitled: "Share the project, event clip, or Timeline range",
                delay: 1.0
            ),

            // 3. If a sheet is now open, click the share destination button
            .click(
                "Select share destination '\(shareDestination)'",
                app: "Final Cut Pro",
                buttonTitled: shareDestination,
                fallback: nil,
                delay: 0.5
            ),

            // 4. Click "Next…" in the sheet
            .click(
                "Click Next",
                app: "Final Cut Pro",
                buttonTitled: "Next",
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

    func run(
        steps: [WorkflowStep],
        sessionId: String,
        onProgress: @escaping @Sendable (String) -> Void
    ) async throws {
        for (index, step) in steps.enumerated() {
            onProgress("[\(index + 1)/\(steps.count)] \(step.description)…")

            if let appName = step.appActivationName {
                let activated = await MainActor.run {
                    NSWorkspace.shared.runningApplications
                        .first { $0.localizedName == appName }?
                        .activate(options: .activateIgnoringOtherApps)
                        ?? false
                }
                if !activated {
                    throw WorkflowError.appNotRunning(appName)
                }
            } else if let keypress = step.keypress {
                _ = try await provider.execute(
                    sessionId: sessionId,
                    action: ComputerUseAction(type: .keypress, target: keypress)
                )
            } else if let text = step.typeText {
                _ = try await provider.execute(
                    sessionId: sessionId,
                    action: ComputerUseAction(type: .type, target: text)
                )
            } else if let query = step.axQuery {
                let target = try resolveAXTarget(query: query, fallback: step.fallbackCoordinates)
                _ = try await provider.execute(
                    sessionId: sessionId,
                    action: ComputerUseAction(type: .click, target: target)
                )
            } else if let coords = step.fallbackCoordinates {
                _ = try await provider.execute(
                    sessionId: sessionId,
                    action: ComputerUseAction(type: .click, target: coords)
                )
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

    var errorDescription: String? {
        switch self {
        case .elementNotFound(let app, let role, let title):
            return "Could not find '\(title)' (\(role)) in \(app). Is the app open?"
        case .appNotRunning(let name):
            return "\(name) is not running. Open it before starting the workflow."
        }
    }
}
