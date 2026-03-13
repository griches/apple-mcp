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
            XCTAssertTrue(server.packagePath.hasSuffix("package.json"), "\(server.name) package should end in package.json")
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
        let root = try makeRoot()
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

    func testRuntimeStateCallbackCapturesDaemonFailure() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        var transitions: [(DaemonRuntimeStatus?, DaemonRuntimeStatus)] = []
        let manager = DaemonManager(
            repoRoot: root.path,
            onRuntimeStateChanged: { previous, current in
                transitions.append((previous?.status, current.status))
            }
        )
        transitions.removeAll()

        guard let first = manager.serverDefinitions.first else {
            XCTFail("Expected at least one server definition")
            return
        }

        let scriptURL = URL(fileURLWithPath: first.scriptPath)
        try FileManager.default.createDirectory(at: scriptURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("setTimeout(() => process.exit(1), 20)".utf8).write(to: scriptURL, options: .atomic)

        _ = manager.ensureProcess(for: first.name)
        try await waitUntil {
            manager.runtimeState(for: first.name)?.status == .failed
        }

        let state = manager.runtimeState(for: first.name)
        XCTAssertEqual(state?.status, .failed)
        XCTAssertNotNil(state?.lastError)
        XCTAssertTrue(transitions.contains(where: { $0.1 == .failed }))
    }

    func testBuildSuccessUpdatesBuildStateAndCreatesStoppedRuntime() async throws {
        let root = try makeRoot()
        let logStore = DaemonLogStore(directoryURL: root.appendingPathComponent("logs"))
        defer { try? FileManager.default.removeItem(at: root) }

        let manager = DaemonManager(
            repoRoot: root.path,
            logStore: logStore,
            buildOperation: { definition in
                let scriptURL = URL(fileURLWithPath: definition.scriptPath)
                try FileManager.default.createDirectory(at: scriptURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data("console.log('built')".utf8).write(to: scriptURL)
                return DaemonBuildResult(output: "build ok", exitStatus: 0)
            }
        )

        let first = try XCTUnwrap(manager.serverDefinitions.first)
        await manager.build(serverName: first.name)

        XCTAssertEqual(manager.buildState(for: first.name)?.status, .succeeded)
        XCTAssertEqual(manager.runtimeState(for: first.name)?.status, .stopped)
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.scriptPath))
    }

    func testBuildFailureUpdatesBuildState() async throws {
        let root = try makeRoot()
        let logStore = DaemonLogStore(directoryURL: root.appendingPathComponent("logs"))
        defer { try? FileManager.default.removeItem(at: root) }

        let manager = DaemonManager(
            repoRoot: root.path,
            logStore: logStore,
            buildOperation: { _ in
                DaemonBuildResult(output: "build failed", exitStatus: 1)
            }
        )

        let first = try XCTUnwrap(manager.serverDefinitions.first)
        await manager.build(serverName: first.name)

        XCTAssertEqual(manager.buildState(for: first.name)?.status, .failed)
        XCTAssertEqual(manager.runtimeState(for: first.name)?.status, .notBuilt)
        XCTAssertTrue(manager.buildState(for: first.name)?.lastOutput.contains("build failed") ?? false)
    }

    func testDaemonReceivesBrainPathEnvironmentAndCapturesRuntimeLog() async throws {
        let root = try makeRoot()
        let logStore = DaemonLogStore(directoryURL: root.appendingPathComponent("logs"))
        defer { try? FileManager.default.removeItem(at: root) }

        let manager = DaemonManager(
            repoRoot: root.path,
            logStore: logStore,
            brainPathProvider: { "/tmp/test-active-brain.json" }
        )

        let first = try XCTUnwrap(manager.serverDefinitions.first)
        let scriptURL = URL(fileURLWithPath: first.scriptPath)
        try FileManager.default.createDirectory(at: scriptURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("console.error(process.env.BRAIN_PATH || 'missing'); setTimeout(() => process.exit(1), 20)".utf8)
            .write(to: scriptURL, options: .atomic)

        _ = manager.ensureProcess(for: first.name)
        try await waitUntil {
            manager.runtimeState(for: first.name)?.status == .failed
        }

        XCTAssertTrue(manager.recentRuntimeLog(for: first.name).contains("/tmp/test-active-brain.json"))
        let logContents = try logStore.load(serverName: first.name, kind: .runtime)
        XCTAssertTrue(logContents.contains("/tmp/test-active-brain.json"))
    }

    private func waitUntil(
        timeoutIterations: Int = 200,
        condition: @escaping () -> Bool
    ) async throws {
        for _ in 0..<timeoutIterations {
            if condition() {
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTFail("Timed out waiting for condition")
    }

    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mojoshell-daemon-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}
