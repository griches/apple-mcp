import XCTest
@testable import MojoShell

@MainActor
final class AppStateTests: XCTestCase {
    func testRunAssemblyWorkflowIncludesJobNameAndProviderState() async {
        let daemonManager = DaemonManager(repoRoot: "/tmp/apple-mcp")
        let executor = MCPToolExecutor(daemonManager: daemonManager)
        let provider = FakeComputerUseProvider()
        let appState = AppState(
            daemons: daemonManager,
            executor: executor,
            computerUseProvider: provider
        )

        let result = await appState.runAssemblyWorkflow(jobName: "Demo Job")

        switch result {
        case .success(let output):
            XCTAssertTrue(output.contains("Demo Job"))
            XCTAssertTrue(output.contains("fake-cu"))
            XCTAssertTrue(output.contains("executed"))
        case .failure(let error):
            XCTFail("Expected success, got \(error)")
        }
    }
}

actor FakeComputerUseProvider: ComputerUseProvider {
    let name = "fake-cu"

    func startSession() async throws -> String {
        "fake-session"
    }

    func captureState(sessionId _: String) async throws -> ComputerUseState {
        ComputerUseState(appName: "fake-cu", screenshotData: nil, timestamp: Date())
    }

    func execute(sessionId _: String, action _: ComputerUseAction) async throws -> ComputerUseResult {
        ComputerUseResult(success: true, message: "executed", screenshotAfter: nil)
    }

    func stopSession(sessionId _: String) async throws {}
}
