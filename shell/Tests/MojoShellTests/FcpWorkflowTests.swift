import XCTest
@testable import MojoShell

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
        XCTAssertEqual(
            steps.dropFirst().first?.axQuery?.titleContaining,
            "Share the project, event clip, or Timeline range"
        )
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
        var log: [String] = []

        try await executor.run(steps: steps, sessionId: sessionId) { message in
            log.append(message)
        }

        let actions = await stub.executedActions
        XCTAssertEqual(actions.count, 2)
        XCTAssertEqual(actions[0].type, .keypress)
        XCTAssertEqual(actions[0].target, "cmd+tab")
        XCTAssertEqual(actions[1].target, "cmd+e")
        XCTAssertTrue(log.contains("Workflow complete."))
    }

    func testExecutorFallsBackToCoordinatesWhenAXFails() async throws {
        let stub = CapturingComputerUseProvider()
        // AX query will fail (FCP not running), but there is a fallback coordinate
        let steps = [
            WorkflowStep.click(
                "Click Export",
                app: "Final Cut Pro",
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
            WorkflowStep.click("Click Export", app: "Final Cut Pro", buttonTitled: "Export"),
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
}

// MARK: - Test double

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
