import Combine
import Foundation

@MainActor
final class AppState: ObservableObject {
    let daemons: DaemonManager
    let executor: MCPToolExecutor
    let computerUseProvider: any ComputerUseProvider
    private let llmProviders: [any LLMProvider]
    private let assemblyClickTarget: String?

    init(
        daemons: DaemonManager? = nil,
        executor: MCPToolExecutor? = nil,
        computerUseProvider: (any ComputerUseProvider)? = nil,
        llmProviders: [any LLMProvider]? = nil,
        assemblyClickTarget: String? = nil
    ) {
        let resolvedDaemons = daemons ?? DaemonManager()
        self.daemons = resolvedDaemons
        self.executor = executor ?? MCPToolExecutor(daemonManager: resolvedDaemons)
        self.computerUseProvider = computerUseProvider ?? CuaComputerUseProvider()
        self.assemblyClickTarget = AppState.normalizedAssemblyClickTarget(
            assemblyClickTarget ?? ProcessInfo.processInfo.environment["MOJOSHELL_ASSEMBLY_CLICK_TARGET"]
        )

        if let llmProviders {
            self.llmProviders = llmProviders
        } else {
            var providers: [any LLMProvider] = []
            if let key = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"], !key.isEmpty {
                providers.append(ClaudeProvider(apiKey: key))
            }
            if let key = ProcessInfo.processInfo.environment["OPENAI_API_KEY"], !key.isEmpty {
                providers.append(OpenAIProvider(apiKey: key))
            }
            self.llmProviders = providers
        }

        resolvedDaemons.startAll()
    }

    var computerUseProviderName: String {
        computerUseProvider.name
    }

    var llmProviderStackDescription: String {
        guard !llmProviders.isEmpty else {
            return "none"
        }
        return llmProviders.map { $0.name }.joined(separator: " -> ")
    }

    func resolveWithLLM(prompt: String, availableTools: [LLMToolDefinition]) async -> Result<String, Error> {
        guard !llmProviders.isEmpty else {
            return .failure(LLMRoutingError.noAvailableProviders)
        }

        var failures: [String] = []

        for provider in llmProviders {
            do {
                let response = try await provider.resolve(prompt: prompt, availableTools: availableTools)
                if let tool = response.resolvedTool {
                    let execResult = try await executor.execute(tool)
                    return .success(execResult.text)
                }
                return .success(response.text)
            } catch {
                failures.append("\(provider.name): \(error.localizedDescription)")
            }
        }

        return .failure(LLMRoutingError.providersFailed(failures.joined(separator: " | ")))
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
        let clickTarget = assemblyClickTarget ?? (computerUseProviderName == "stub" ? "Export Button" : nil)
        guard let clickTarget else {
            return .failure(AssemblyWorkflowError.missingClickTarget)
        }

        do {
            let sessionID = try await computerUseProvider.startSession()
            do {
                let state = try await computerUseProvider.captureState(sessionId: sessionID)
                let actionResult = try await computerUseProvider.execute(
                    sessionId: sessionID,
                    action: ComputerUseAction(type: .click, target: clickTarget)
                )
                try await computerUseProvider.stopSession(sessionId: sessionID)

                return .success(
                    """
                    Session: \(sessionID)
                    Job: \(jobName)
                    Provider: \(state.appName)
                    Target: \(clickTarget)
                    Result: \(actionResult.message)
                    """
                )
            } catch {
                try? await computerUseProvider.stopSession(sessionId: sessionID)
                return .failure(error)
            }
        } catch {
            return .failure(error)
        }
    }

    private static func normalizedAssemblyClickTarget(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

enum AssemblyWorkflowError: LocalizedError, Equatable {
    case missingClickTarget

    var errorDescription: String? {
        switch self {
        case .missingClickTarget:
            return "Assembly click target is not configured. Set MOJOSHELL_ASSEMBLY_CLICK_TARGET to coordinates like '640,400'."
        }
    }
}
