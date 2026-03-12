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
            computerUseProvider: provider,
            assemblyClickTarget: "640,400"
        )

        let result = await appState.runAssemblyWorkflow(jobName: "Demo Job")

        switch result {
        case .success(let output):
            XCTAssertTrue(output.contains("Demo Job"))
            XCTAssertTrue(output.contains("fake-cu"))
            XCTAssertTrue(output.contains("640,400"))
            XCTAssertTrue(output.contains("executed"))
        case .failure(let error):
            XCTFail("Expected success, got \(error)")
        }
    }

    func testRunAssemblyWorkflowFailsWhenClickTargetIsMissing() async {
        let daemonManager = DaemonManager(repoRoot: "/tmp/apple-mcp")
        let executor = MCPToolExecutor(daemonManager: daemonManager)
        let appState = AppState(
            daemons: daemonManager,
            executor: executor,
            computerUseProvider: FakeComputerUseProvider(),
            assemblyClickTarget: nil
        )

        let result = await appState.runAssemblyWorkflow(jobName: "Demo Job")

        switch result {
        case .success(let output):
            XCTFail("Expected missing target failure, got \(output)")
        case .failure(let error as AssemblyWorkflowError):
            XCTAssertEqual(error, .missingClickTarget)
        case .failure(let error):
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testRunAssemblyWorkflowStopsSessionAfterFailure() async {
        let daemonManager = DaemonManager(repoRoot: "/tmp/apple-mcp")
        let executor = MCPToolExecutor(daemonManager: daemonManager)
        let provider = RecordingFailingComputerUseProvider()
        let appState = AppState(
            daemons: daemonManager,
            executor: executor,
            computerUseProvider: provider,
            assemblyClickTarget: "640,400"
        )

        let result = await appState.runAssemblyWorkflow(jobName: "Demo Job")

        switch result {
        case .success(let output):
            XCTFail("Expected failure, got \(output)")
        case .failure:
            XCTAssertTrue(await provider.didStopSession)
        }
    }

    func testResolveWithLLMFallsBackToSecondProvider() async {
        let daemonManager = DaemonManager(repoRoot: "/tmp/apple-mcp")
        let executor = MCPToolExecutor(daemonManager: daemonManager)
        let llmProviders: [any LLMProvider] = [
            FailingLLMProvider(name: "claude"),
            FakeLLMProvider(name: "openai", response: LLMResponse(text: "fallback response", resolvedTool: nil)),
        ]
        let appState = AppState(
            daemons: daemonManager,
            executor: executor,
            computerUseProvider: FakeComputerUseProvider(),
            llmProviders: llmProviders
        )

        let result = await appState.resolveWithLLM(prompt: "something ambiguous", availableTools: [])

        switch result {
        case .success(let text):
            XCTAssertEqual(text, "fallback response")
        case .failure(let error):
            XCTFail("Expected fallback success, got \(error)")
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

actor RecordingFailingComputerUseProvider: ComputerUseProvider {
    let name = "recording-cu"

    private(set) var didStopSession = false

    func startSession() async throws -> String {
        "recording-session"
    }

    func captureState(sessionId _: String) async throws -> ComputerUseState {
        ComputerUseState(appName: "recording-cu", screenshotData: nil, timestamp: Date())
    }

    func execute(sessionId _: String, action _: ComputerUseAction) async throws -> ComputerUseResult {
        throw TestComputerUseError.executionFailed
    }

    func stopSession(sessionId _: String) async throws {
        didStopSession = true
    }
}

struct FailingLLMProvider: LLMProvider {
    let name: String

    func resolve(prompt _: String, availableTools _: [LLMToolDefinition]) async throws -> LLMResponse {
        throw TestLLMError.failed(name)
    }

    func buildURLRequest(prompt _: String, tools _: [LLMToolDefinition]) throws -> URLRequest {
        URLRequest(url: URL(string: "https://example.com")!)
    }
}

struct FakeLLMProvider: LLMProvider {
    let name: String
    let response: LLMResponse

    func resolve(prompt _: String, availableTools _: [LLMToolDefinition]) async throws -> LLMResponse {
        response
    }

    func buildURLRequest(prompt _: String, tools _: [LLMToolDefinition]) throws -> URLRequest {
        URLRequest(url: URL(string: "https://example.com")!)
    }
}

enum TestLLMError: LocalizedError {
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .failed(let name):
            return "\(name) failed"
        }
    }
}

enum TestComputerUseError: LocalizedError {
    case executionFailed

    var errorDescription: String? {
        switch self {
        case .executionFailed:
            return "execution failed"
        }
    }
}
