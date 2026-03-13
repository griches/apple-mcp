import XCTest
@testable import MojoShell

@MainActor
final class DaemonManagerTests: XCTestCase {
    func testKnownServersCount() {
        let manager = DaemonManager(repoRoot: "/tmp/apple-mcp")
        XCTAssertEqual(manager.serverDefinitions.count, 10)
    }

    func testServerDefinitionsHaveValidPaths() {
        let manager = DaemonManager(repoRoot: "/tmp/apple-mcp")
        for server in manager.serverDefinitions {
            XCTAssertFalse(server.name.isEmpty)
            XCTAssertTrue(server.scriptPath.hasSuffix("index.js"), "\(server.name) path should end in index.js")
        }
    }

    func testRepoRootIsAccessible() {
        let manager = DaemonManager(repoRoot: "/tmp/test-root")
        XCTAssertEqual(manager.repoRoot, "/tmp/test-root")
    }
}
