import Combine
import Foundation

@MainActor
final class AppState: ObservableObject {
    let daemons: DaemonManager
    let executor: MCPToolExecutor
    let computerUseProvider: any ComputerUseProvider
    private let llmProvider: (any LLMProvider)?

    init(
        daemons: DaemonManager? = nil,
        executor: MCPToolExecutor? = nil,
        computerUseProvider: (any ComputerUseProvider)? = nil,
        llmProvider: (any LLMProvider)? = nil
    ) {
        let resolvedDaemons = daemons ?? DaemonManager()
        self.daemons = resolvedDaemons
        self.executor = executor ?? MCPToolExecutor(daemonManager: resolvedDaemons)
        self.computerUseProvider = computerUseProvider ?? StubComputerUseProvider()

        if let llmProvider {
            self.llmProvider = llmProvider
        } else if let key = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"], !key.isEmpty {
            self.llmProvider = ClaudeProvider(apiKey: key)
        } else {
            self.llmProvider = nil
        }

        resolvedDaemons.startAll()
    }

    var llmProviderName: String { llmProvider?.name ?? "none" }

    func resolveWithLLM(prompt: String, availableTools: [LLMToolDefinition]) async -> Result<String, Error> {
        guard let provider = llmProvider else {
            return .failure(LLMRoutingError.noAPIKey)
        }
        do {
            let response = try await provider.resolve(prompt: prompt, availableTools: availableTools)
            if let tool = response.resolvedTool {
                let execResult = try await executor.execute(tool)
                return .success(execResult.text)
            }
            return .success(response.text)
        } catch {
            return .failure(error)
        }
    }

    func execute(_ resolvedTool: ResolvedTool) async -> Result<MCPToolExecutionResult, Error> {
        do {
            return .success(try await executor.execute(resolvedTool))
        } catch {
            return .failure(error)
        }
    }

    func scanInboxes() async -> Result<MCPToolExecutionResult, Error> {
        await execute(
            ResolvedTool(
                server: "mail-intelligence",
                tool: "scan_persona_inboxes",
                arguments: [
                    "lookback_days": .int(1),
                    "limit_per_account": .int(10),
                ]
            )
        )
    }

    func fetchPersonaMap() async -> Result<MCPToolExecutionResult, Error> {
        await execute(
            ResolvedTool(
                server: "mail-intelligence",
                tool: "get_persona_map",
                arguments: [:]
            )
        )
    }

    func fetchBrainOverview() async -> Result<MCPToolExecutionResult, Error> {
        await execute(
            ResolvedTool(
                server: "knowledge-corpus",
                tool: "get_corpus_overview",
                arguments: [:]
            )
        )
    }

    func fetchNowPlaying() async -> Result<MCPToolExecutionResult, Error> {
        await execute(
            ResolvedTool(
                server: "apple-music",
                tool: "now_playing",
                arguments: [:]
            )
        )
    }

    func runAssemblyWorkflow(jobName: String) async -> Result<String, Error> {
        do {
            let sessionID = try await computerUseProvider.startSession()
            let state = try await computerUseProvider.captureState(sessionId: sessionID)
            let actionResult = try await computerUseProvider.execute(
                sessionId: sessionID,
                action: ComputerUseAction(type: .click, target: "Run Assembly Workflow")
            )
            try await computerUseProvider.stopSession(sessionId: sessionID)

            return .success(
                """
                Session: \(sessionID)
                Job: \(jobName)
                Provider: \(state.appName)
                Result: \(actionResult.message)
                """
            )
        } catch {
            return .failure(error)
        }
    }
}
