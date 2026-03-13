import XCTest
@testable import MojoShell

@MainActor
final class FcpWorkflowTests: XCTestCase {

    // MARK: - WorkflowStep factories

    func testClickStepHasAXQuery() {
        let step = WorkflowStep.click("Test", app: "Final Cut Pro", buttonTitled: "Next")
        XCTAssertNotNil(step.axQuery)
        XCTAssertEqual(step.axQuery?.appName, "Final Cut Pro")
        XCTAssertEqual(step.axQuery?.role, "AXButton")
        XCTAssertEqual(step.axQuery?.titleContaining, "Next")
        XCTAssertNil(step.keypress)
        XCTAssertNil(step.typeText)
    }

    func testKeypressStepHasNoAXQuery() {
        let step = WorkflowStep.keypress("Focus FCP", key: "cmd+tab")
        XCTAssertNil(step.axQuery)
        XCTAssertEqual(step.keypress, "cmd+tab")
    }

    func testTypeStepHasText() {
        let step = WorkflowStep.type("Enter filename", text: "output.mp4")
        XCTAssertEqual(step.typeText, "output.mp4")
        XCTAssertNil(step.keypress)
        XCTAssertNil(step.axQuery)
    }

    func testCoordinateStepHasNoAXQuery() {
        let step = WorkflowStep.coordinate("Click export button", at: "640,400")
        XCTAssertEqual(step.fallbackCoordinates, "640,400")
        XCTAssertNil(step.axQuery)
    }

    // MARK: - FcpWorkflowDefinition

    func testActivateAppStepHasAppActivationName() {
        let step = WorkflowStep.activateApp("Final Cut Pro")
        XCTAssertEqual(step.appActivationName, "Final Cut Pro")
        XCTAssertNil(step.keypress)
        XCTAssertNil(step.axQuery)
        XCTAssertNil(step.typeText)
    }

    func testAssemblyWorkflowHasSteps() {
        let steps = FcpWorkflowDefinition.assemblyWorkflow()
        XCTAssertFalse(steps.isEmpty)
        // First step activates FCP deterministically — not cmd+tab
        XCTAssertEqual(steps.first?.appActivationName, "Final Cut Pro")
        XCTAssertNil(steps.first?.keypress)
        // Second step: toolbar Share button (verified live AX title)
        XCTAssertEqual(
            steps.dropFirst().first?.axQuery?.titleContaining,
            "Share the project, event clip, or Timeline range"
        )
        // Default share destination is the verified File > Share submenu name
        XCTAssertEqual(
            steps.dropFirst(2).first?.axQuery?.titleContaining,
            "Export File (default)…"
        )
        // Step 4: advance button confirmed live — "Next…" (with ellipsis)
        XCTAssertEqual(
            steps.dropFirst(3).first?.axQuery?.titleContaining,
            "Next…"
        )
        XCTAssertEqual(
            steps.dropFirst(2).first?.approvalPrompt,
            "Confirm the export destination in Final Cut Pro before MojoShell clicks it."
        )
        XCTAssertEqual(
            steps.dropFirst(3).first?.approvalPrompt,
            "Confirm the export sheet is configured correctly before advancing."
        )
    }

    func testAssemblyWorkflowIncludesExportTargetInApprovalPrompt() {
        let steps = FcpWorkflowDefinition.assemblyWorkflow(exportTargetPath: "/tmp/exports")

        XCTAssertTrue(steps.dropFirst(2).first?.approvalPrompt?.contains("/tmp/exports") ?? false)
        XCTAssertTrue(steps.dropFirst(3).first?.approvalPrompt?.contains("/tmp/exports") ?? false)
    }

    func testMonitoringCheckFirstStepActivatesFCP() {
        let steps = FcpWorkflowDefinition.monitoringCheck()
        XCTAssertEqual(steps.first?.appActivationName, "Final Cut Pro")
    }

    func testMonitoringCheckHasSteps() {
        let steps = FcpWorkflowDefinition.monitoringCheck()
        XCTAssertEqual(steps.count, 2)
        // Second step opens Background Tasks
        XCTAssertEqual(steps.last?.keypress, "cmd+9")
    }

    // MARK: - WorkflowExecutor with stub provider

    func testExecutorThrowsAppNotRunningWhenActivationFails() async throws {
        let stub = CapturingComputerUseProvider()
        // Use a deliberately fake app name that will never be running
        let steps = [WorkflowStep.activateApp("__NonExistentApp__")]
        let sessionId = try await stub.startSession()
        let executor = WorkflowExecutor(provider: stub)

        do {
            try await executor.run(steps: steps, sessionId: sessionId) { _ in }
            XCTFail("Expected WorkflowError.appNotRunning")
        } catch WorkflowError.appNotRunning(let name) {
            XCTAssertEqual(name, "__NonExistentApp__")
        }
    }

    func testExecutorRunsAllKeyPressSteps() async throws {
        let stub = CapturingComputerUseProvider()
        let steps = [
            WorkflowStep.keypress("Step 1", key: "cmd+tab"),
            WorkflowStep.keypress("Step 2", key: "cmd+e"),
        ]

        let sessionId = try await stub.startSession()
        let executor = WorkflowExecutor(provider: stub)
        let log = MessageLog()

        try await executor.run(steps: steps, sessionId: sessionId) { message in
            log.append(message)
        }

        let actions = await stub.executedActions
        XCTAssertEqual(actions.count, 2)
        XCTAssertEqual(actions[0].type, .keypress)
        XCTAssertEqual(actions[0].target, "cmd+tab")
        XCTAssertEqual(actions[1].target, "cmd+e")
        XCTAssertTrue(log.messages.contains("Workflow complete."))
    }

    func testExecutorFallsBackToCoordinatesWhenAXFails() async throws {
        let stub = CapturingComputerUseProvider()
        // AX query will fail because the app name is fake, but there is a fallback coordinate.
        let steps = [
            WorkflowStep.click(
                "Click Export",
                app: "__NonExistentApp__",
                buttonTitled: "Export",
                fallback: "640,400"
            ),
        ]

        let sessionId = try await stub.startSession()
        let executor = WorkflowExecutor(provider: stub)
        try await executor.run(steps: steps, sessionId: sessionId) { _ in }

        let actions = await stub.executedActions
        XCTAssertEqual(actions.count, 1)
        XCTAssertEqual(actions[0].type, .click)
        XCTAssertEqual(actions[0].target, "640,400")
    }

    func testExecutorThrowsWhenAXFailsAndNoFallback() async throws {
        let stub = CapturingComputerUseProvider()
        let steps = [
            WorkflowStep.click("Click Export", app: "__NonExistentApp__", buttonTitled: "Export"),
        ]

        let sessionId = try await stub.startSession()
        let executor = WorkflowExecutor(provider: stub)

        do {
            try await executor.run(steps: steps, sessionId: sessionId) { _ in }
            XCTFail("Expected WorkflowError.elementNotFound")
        } catch is WorkflowError {
            // expected
        }
    }

    func testExecutorThrowsWhenApprovalIsRejected() async throws {
        let stub = CapturingComputerUseProvider()
        let steps = [
            WorkflowStep.keypress("Approve Export", key: "cmd+e", approvalPrompt: "Confirm export settings"),
        ]

        let sessionId = try await stub.startSession()
        let executor = WorkflowExecutor(provider: stub)

        do {
            try await executor.run(
                steps: steps,
                sessionId: sessionId,
                onProgress: { _ in },
                onApprovalRequested: { _, _ in false }
            )
            XCTFail("Expected WorkflowError.approvalRejected")
        } catch WorkflowError.approvalRejected(let description) {
            XCTAssertEqual(description, "Approve Export")
        }

        let actions = await stub.executedActions
        XCTAssertTrue(actions.isEmpty)
    }
}

// MARK: - Test doubles

/// Thread-safe string log for capturing @Sendable progress callbacks.
final class MessageLog: @unchecked Sendable {
    private(set) var messages: [String] = []
    func append(_ message: String) { messages.append(message) }
}

actor CapturingComputerUseProvider: ComputerUseProvider {
    let name = "capturing-stub"
    private(set) var executedActions: [ComputerUseAction] = []
    private var sessions: Set<String> = []

    func startSession() async throws -> String {
        let id = UUID().uuidString
        sessions.insert(id)
        return id
    }

    func captureState(sessionId: String) async throws -> ComputerUseState {
        ComputerUseState(appName: "capturing-stub", screenshotData: nil, timestamp: Date())
    }

    func execute(sessionId: String, action: ComputerUseAction) async throws -> ComputerUseResult {
        executedActions.append(action)
        return ComputerUseResult(success: true, message: "captured", screenshotAfter: nil)
    }

    func stopSession(sessionId: String) async throws {
        sessions.remove(sessionId)
    }
}
