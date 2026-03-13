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

    func testRuntimeStatesAreAvailableForAllServers() {
        let manager = DaemonManager(repoRoot: "/tmp/nonexistent-\(UUID().uuidString)")
        XCTAssertEqual(manager.allRuntimeStates.count, 10)
    }

    func testStartAllMarksMissingArtifactsAsNotBuilt() {
        let manager = DaemonManager(repoRoot: "/tmp/nonexistent-\(UUID().uuidString)")
        manager.startAll()
        XCTAssertTrue(manager.allRuntimeStates.allSatisfy { $0.status == .notBuilt })
    }

    func testRefreshRuntimeStatesMarksBuiltServerAsStopped() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mojoshell-daemon-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let manager = DaemonManager(repoRoot: root.path)
        guard let first = manager.serverDefinitions.first else {
            XCTFail("Expected at least one server definition")
            return
        }

        let scriptURL = URL(fileURLWithPath: first.scriptPath)
        try FileManager.default.createDirectory(at: scriptURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("console.log('ok')".utf8).write(to: scriptURL, options: .atomic)

        manager.refreshRuntimeStates()
        let state = manager.runtimeState(for: first.name)
        XCTAssertEqual(state?.status, .stopped)
    }
}
