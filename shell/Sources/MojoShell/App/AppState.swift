import Combine
import Foundation

@MainActor
final class AppState: ObservableObject {
    let daemons: DaemonManager
    let executor: MCPToolExecutor
    let computerUseProvider: any ComputerUseProvider

    init(
        daemons: DaemonManager? = nil,
        executor: MCPToolExecutor? = nil,
        computerUseProvider: (any ComputerUseProvider)? = nil
    ) {
        let resolvedDaemons = daemons ?? DaemonManager()
        self.daemons = resolvedDaemons
        self.executor = executor ?? MCPToolExecutor(daemonManager: resolvedDaemons)
        self.computerUseProvider = computerUseProvider ?? StubComputerUseProvider()
        resolvedDaemons.startAll()
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
