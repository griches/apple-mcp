import XCTest
@testable import MojoShell

@MainActor
final class MCPToolExecutorTests: XCTestCase {
    func testExecutorReturnsToolTextFromOverrideClient() async throws {
        let daemonManager = DaemonManager(repoRoot: "/tmp/apple-mcp")
        let executor = MCPToolExecutor(
            daemonManager: daemonManager,
            clientOverrides: [
                "mail-intelligence": FakeMCPToolClient(
                    response: MCPResponse(
                        jsonrpc: "2.0",
                        id: 1,
                        result: MCPResult(
                            tools: nil,
                            content: [MCPContent(type: "text", text: "{\"ok\":true}")]
                        ),
                        error: nil
                    )
                )
            ]
        )

        let result = try await executor.execute(
            server: "mail-intelligence",
            tool: "scan_persona_inboxes"
        )

        XCTAssertEqual(result.server, "mail-intelligence")
        XCTAssertEqual(result.tool, "scan_persona_inboxes")
        XCTAssertEqual(result.text, "{\"ok\":true}")
    }

    func testExecutorThrowsForUnknownServer() async {
        let daemonManager = DaemonManager(repoRoot: "/tmp/apple-mcp")
        let executor = MCPToolExecutor(daemonManager: daemonManager)

        do {
            _ = try await executor.execute(server: "does-not-exist", tool: "noop")
            XCTFail("Expected unknown server error")
        } catch let error as MCPToolExecutionError {
            XCTAssertEqual(error, .unknownServer("does-not-exist"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

actor FakeMCPToolClient: MCPToolCalling {
    let response: MCPResponse

    init(response: MCPResponse) {
        self.response = response
    }

    func callTool(name _: String, arguments _: [String: AnyCodable]) async throws -> MCPResponse {
        response
    }
}
