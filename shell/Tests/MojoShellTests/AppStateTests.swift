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
            computerUseProvider: FakeComputerUseProvider(),
            nativeExecutor: FakeNativeToolExecutor()
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
            nativeExecutor: FakeNativeToolExecutor(),
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
            nativeExecutor: FakeNativeToolExecutor(),
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

    func testExecuteRoutesShellNativeToolsToNativeExecutor() async {
        let daemonManager = DaemonManager(repoRoot: "/tmp/apple-mcp")
        let executor = MCPToolExecutor(daemonManager: daemonManager)
        let nativeExecutor = FakeNativeToolExecutor()
        let appState = AppState(
            daemons: daemonManager,
            executor: executor,
            computerUseProvider: FakeComputerUseProvider(),
            nativeExecutor: nativeExecutor
        )

        let result = await appState.execute(
            ResolvedTool(
                server: NativeToolExecutor.serverName,
                tool: NativeToolName.shortcutsList.rawValue,
                arguments: [:]
            )
        )

        switch result {
        case .success(let output):
            XCTAssertEqual(output.text, "native result")
        case .failure(let error):
            XCTFail("Expected native execution success, got \(error)")
        }
    }

    func testResolveWithLLMExecutesShellNativeResolvedTool() async {
        let daemonManager = DaemonManager(repoRoot: "/tmp/apple-mcp")
        let executor = MCPToolExecutor(daemonManager: daemonManager)
        let nativeExecutor = FakeNativeToolExecutor()
        let appState = AppState(
            daemons: daemonManager,
            executor: executor,
            computerUseProvider: FakeComputerUseProvider(),
            nativeExecutor: nativeExecutor,
            llmProviders: [
                FakeLLMProvider(
                    name: "claude",
                    response: LLMResponse(
                        text: "",
                        resolvedTool: ResolvedTool(
                            server: NativeToolExecutor.serverName,
                            tool: NativeToolName.systemSettingsOpen.rawValue,
                            arguments: ["pane": .string("accessibility")]
                        )
                    )
                ),
            ]
        )

        let result = await appState.resolveWithLLM(prompt: "open accessibility settings", availableTools: [])

        switch result {
        case .success(let text):
            XCTAssertEqual(text, "native result")
        case .failure(let error):
            XCTFail("Expected native tool execution success, got \(error)")
        }
    }

    func testExecuteRecordsNativeAuditEvent() async {
        let daemonManager = DaemonManager(repoRoot: "/tmp/apple-mcp")
        let executor = MCPToolExecutor(daemonManager: daemonManager)
        let nativeExecutor = FakeNativeToolExecutor()
        var recorded: [(AuditCategory, String, String, [String: String])] = []
        let appState = AppState(
            daemons: daemonManager,
            executor: executor,
            computerUseProvider: FakeComputerUseProvider(),
            nativeExecutor: nativeExecutor,
            auditRecorder: { category, title, detail, metadata in
                recorded.append((category, title, detail, metadata))
            }
        )

        let result = await appState.execute(
            ResolvedTool(
                server: NativeToolExecutor.serverName,
                tool: NativeToolName.finderOpenRepoRoot.rawValue,
                arguments: [:]
            )
        )

        switch result {
        case .success:
            XCTAssertEqual(recorded.last?.0, .native)
            XCTAssertEqual(recorded.last?.1, "Tool executed")
            XCTAssertEqual(recorded.last?.2, "\(NativeToolExecutor.serverName)/\(NativeToolName.finderOpenRepoRoot.rawValue)")
        case .failure(let error):
            XCTFail("Expected native tool execution success, got \(error)")
        }
    }

    func testOpenFinderSelectionInPreviewUsesNativeSelectionTool() async {
        let daemonManager = DaemonManager(repoRoot: "/tmp/apple-mcp")
        let executor = MCPToolExecutor(daemonManager: daemonManager)
        let nativeExecutor = FakeNativeToolExecutor()
        let appState = AppState(
            daemons: daemonManager,
            executor: executor,
            computerUseProvider: FakeComputerUseProvider(),
            nativeExecutor: nativeExecutor
        )

        let result = await appState.openFinderSelectionInPreview()

        switch result {
        case .success:
            let invocation = await nativeExecutor.invocations.last
            XCTAssertEqual(invocation?.tool, NativeToolName.finderSelectionOpenInPreview.rawValue)
        case .failure(let error):
            XCTFail("Expected preview selection success, got \(error)")
        }
    }

    func testOpenRepoInTerminalUsesNativeTerminalTool() async {
        let daemonManager = DaemonManager(repoRoot: "/tmp/apple-mcp")
        let executor = MCPToolExecutor(daemonManager: daemonManager)
        let nativeExecutor = FakeNativeToolExecutor()
        let appState = AppState(
            daemons: daemonManager,
            executor: executor,
            computerUseProvider: FakeComputerUseProvider(),
            nativeExecutor: nativeExecutor
        )

        let result = await appState.openRepoInTerminal()

        switch result {
        case .success:
            let invocation = await nativeExecutor.invocations.last
            XCTAssertEqual(invocation?.tool, NativeToolName.terminalOpenRepo.rawValue)
        case .failure(let error):
            XCTFail("Expected terminal open success, got \(error)")
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

actor FakeNativeToolExecutor: NativeToolExecuting {
    struct Invocation: Equatable {
        let tool: String
        let arguments: [String: AnyCodable]
    }

    private(set) var invocations: [Invocation] = []

    func execute(tool: String, arguments: [String: AnyCodable]) async throws -> MCPToolExecutionResult {
        invocations.append(Invocation(tool: tool, arguments: arguments))
        return MCPToolExecutionResult(server: NativeToolExecutor.serverName, tool: tool, text: "native result")
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
        case .failed(let name): return "\(name) failed"
        }
    }
}
