import XCTest
@testable import MojoShell

@MainActor
final class AppStateTests: XCTestCase {

    func testDefaultProviderNameIsSetFromInjectedProvider() {
        let daemonManager = DaemonManager(repoRoot: "/tmp/apple-mcp")
        let executor = MCPToolExecutor(daemonManager: daemonManager)
        let appState = AppState(
            daemons: daemonManager,
            executor: executor,
            computerUseProvider: FakeComputerUseProvider()
        )
        XCTAssertEqual(appState.computerUseProviderName, "fake-cu")
    }

    func testLLMStackDescriptionReflectsInjectedProviders() {
        let daemonManager = DaemonManager(repoRoot: "/tmp/apple-mcp")
        let executor = MCPToolExecutor(daemonManager: daemonManager)
        let appState = AppState(
            daemons: daemonManager,
            executor: executor,
            computerUseProvider: FakeComputerUseProvider(),
            llmProviders: [
                FakeLLMProvider(name: "claude", response: LLMResponse(text: "", resolvedTool: nil)),
                FakeLLMProvider(name: "openai", response: LLMResponse(text: "", resolvedTool: nil)),
            ]
        )
        XCTAssertEqual(appState.llmProviderStackDescription, "claude -> openai")
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

// MARK: - Test doubles

actor FakeComputerUseProvider: ComputerUseProvider {
    let name = "fake-cu"

    func startSession() async throws -> String { "fake-session" }

    func captureState(sessionId _: String) async throws -> ComputerUseState {
        ComputerUseState(appName: "fake-cu", screenshotData: nil, timestamp: Date())
    }

    func execute(sessionId _: String, action _: ComputerUseAction) async throws -> ComputerUseResult {
        ComputerUseResult(success: true, message: "executed", screenshotAfter: nil)
    }

    func stopSession(sessionId _: String) async throws {}
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
        case .failed(let name): return "\(name) failed"
        }
    }
}
