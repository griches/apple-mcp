import Combine
import Foundation

@MainActor
final class AppState: ObservableObject {
    let daemons: DaemonManager
    let executor: MCPToolExecutor
    let computerUseProvider: any ComputerUseProvider
    let nativeExecutor: any NativeToolExecuting
    private let llmProviders: [any LLMProvider]

    init(
        daemons: DaemonManager? = nil,
        executor: MCPToolExecutor? = nil,
        computerUseProvider: (any ComputerUseProvider)? = nil,
        nativeExecutor: (any NativeToolExecuting)? = nil,
        llmProviders: [any LLMProvider]? = nil
    ) {
        let resolvedDaemons = daemons ?? DaemonManager()
        self.daemons = resolvedDaemons
        self.executor = executor ?? MCPToolExecutor(daemonManager: resolvedDaemons)
        self.computerUseProvider = computerUseProvider ?? CuaComputerUseProvider()
        self.nativeExecutor = nativeExecutor ?? NativeToolExecutor(repoRoot: resolvedDaemons.repoRoot)

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
                    let execResult = await execute(tool)
                    switch execResult {
                    case .success(let output):
                        return .success(output.text)
                    case .failure(let error):
                        throw error
                    }
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
            if resolvedTool.server == NativeToolExecutor.serverName {
                return .success(
                    try await nativeExecutor.execute(
                        tool: resolvedTool.tool,
                        arguments: resolvedTool.arguments
                    )
                )
            }
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

    func openDownloadsFolder() async -> Result<MCPToolExecutionResult, Error> {
        await execute(
            ResolvedTool(
                server: NativeToolExecutor.serverName,
                tool: NativeToolName.finderOpenPath.rawValue,
                arguments: ["path": .string("~/Downloads")]
            )
        )
    }

    func openRepoFolder() async -> Result<MCPToolExecutionResult, Error> {
        await execute(
            ResolvedTool(
                server: NativeToolExecutor.serverName,
                tool: NativeToolName.finderOpenRepoRoot.rawValue,
                arguments: [:]
            )
        )
    }

    func revealBrainFile() async -> Result<MCPToolExecutionResult, Error> {
        await execute(
            ResolvedTool(
                server: NativeToolExecutor.serverName,
                tool: NativeToolName.finderRevealBrainFile.rawValue,
                arguments: [:]
            )
        )
    }

    func fetchFinderSelection() async -> Result<MCPToolExecutionResult, Error> {
        await execute(
            ResolvedTool(
                server: NativeToolExecutor.serverName,
                tool: NativeToolName.finderListSelection.rawValue,
                arguments: [:]
            )
        )
    }

    func fetchSafariCurrentTab() async -> Result<MCPToolExecutionResult, Error> {
        await execute(
            ResolvedTool(
                server: NativeToolExecutor.serverName,
                tool: NativeToolName.safariCurrentTab.rawValue,
                arguments: [:]
            )
        )
    }

    func listShortcuts() async -> Result<MCPToolExecutionResult, Error> {
        await execute(
            ResolvedTool(
                server: NativeToolExecutor.serverName,
                tool: NativeToolName.shortcutsList.rawValue,
                arguments: [:]
            )
        )
    }

    func openAccessibilitySettings() async -> Result<MCPToolExecutionResult, Error> {
        await execute(
            ResolvedTool(
                server: NativeToolExecutor.serverName,
                tool: NativeToolName.systemSettingsOpen.rawValue,
                arguments: ["pane": .string("accessibility")]
            )
        )
    }

}
