import Foundation

protocol MCPToolCalling: Sendable {
    func callTool(name: String, arguments: [String: AnyCodable]) async throws -> MCPResponse
}

enum MCPToolExecutionError: LocalizedError, Equatable {
    case unknownServer(String)
    case unavailableServer(String)
    case invalidResponse(String)
    case rpc(String)

    var errorDescription: String? {
        switch self {
        case .unknownServer(let server):
            return "Unknown MCP server: \(server)"
        case .unavailableServer(let server):
            return "MCP server is not running: \(server)"
        case .invalidResponse(let detail):
            return "Invalid MCP response: \(detail)"
        case .rpc(let detail):
            return "MCP tool error: \(detail)"
        }
    }
}

struct MCPToolExecutionResult: Equatable {
    let server: String
    let tool: String
    let text: String
}

@MainActor
final class MCPToolExecutor {
    private let daemonManager: DaemonManager
    private var liveClients: [String: MCPClient] = [:]
    private let clientOverrides: [String: any MCPToolCalling]

    init(
        daemonManager: DaemonManager,
        clientOverrides: [String: any MCPToolCalling] = [:]
    ) {
        self.daemonManager = daemonManager
        self.clientOverrides = clientOverrides
    }

    func execute(_ resolvedTool: ResolvedTool) async throws -> MCPToolExecutionResult {
        try await execute(
            server: resolvedTool.server,
            tool: resolvedTool.tool,
            arguments: resolvedTool.arguments
        )
    }

    func execute(
        server: String,
        tool: String,
        arguments: [String: AnyCodable] = [:]
    ) async throws -> MCPToolExecutionResult {
        let client = try client(for: server)
        let response = try await client.callTool(name: tool, arguments: arguments)

        if let error = response.error {
            throw MCPToolExecutionError.rpc(error.message)
        }

        guard let text = response.primaryTextContent, !text.isEmpty else {
            throw MCPToolExecutionError.invalidResponse("\(server)/\(tool) returned no text content")
        }

        return MCPToolExecutionResult(server: server, tool: tool, text: text)
    }

    private func client(for server: String) throws -> any MCPToolCalling {
        if let override = clientOverrides[server] {
            return override
        }

        guard daemonManager.serverDefinitions.contains(where: { $0.name == server }) else {
            throw MCPToolExecutionError.unknownServer(server)
        }

        if let cached = liveClients[server] {
            return cached
        }

        guard let process = daemonManager.ensureProcess(for: server) else {
            throw MCPToolExecutionError.unavailableServer(server)
        }

        let client = try MCPClient(process: process)
        liveClients[server] = client
        return client
    }
}
