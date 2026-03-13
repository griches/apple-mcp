import XCTest
@testable import MojoShell

private func makeTestDefaults() -> UserDefaults {
    let suite = "ReadinessTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return defaults
}

@MainActor
private func makeRepoRoot(
    createBrainFile: Bool = true,
    createArtifacts: Bool = true
) -> String {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("mojoshell-readiness-\(UUID().uuidString)")
    try! FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

    if createBrainFile {
        let brainURL = root
            .appendingPathComponent("knowledge-corpus")
            .appendingPathComponent("data")
        try! FileManager.default.createDirectory(at: brainURL, withIntermediateDirectories: true)
        let fileURL = brainURL.appendingPathComponent("mojosolo_operating_brain.json")
        try! "{}".data(using: .utf8)!.write(to: fileURL)
    }

    if createArtifacts {
        let manager = DaemonManager(repoRoot: root.path)
        for server in manager.serverDefinitions {
            let fileURL = URL(fileURLWithPath: server.scriptPath)
            try! FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try! Data().write(to: fileURL)
        }
    }

    return root.path
}

@MainActor
private func makeState(
    repoRoot: String,
    defaults: UserDefaults = makeTestDefaults(),
    environment: [String: String] = [:],
    brainPathProvider: @escaping @MainActor () -> String? = { nil },
    axGranted: Bool = true,
    screenRecordingGranted: Bool = true
) -> ReadinessState {
    ReadinessState(
        daemonManager: DaemonManager(repoRoot: repoRoot),
        defaults: defaults,
        environment: environment,
        brainPathProvider: brainPathProvider,
        axCheck: { axGranted },
        screenRecordingCheck: { screenRecordingGranted }
    )
}

@MainActor
final class ReadinessStateCoreTests: XCTestCase {
    func testMissingRepoRootProducesBlockingCoreIssue() async {
        let repoRoot = "/tmp/nonexistent-readiness-\(UUID().uuidString)"
        let state = makeState(repoRoot: repoRoot)

        await state.refresh()

        let issue = state.coreIssues.first(where: { $0.id == "repo_root" })
        XCTAssertNotNil(issue)
        XCTAssertEqual(issue?.severity, .blocking)
    }

    func testValidRepoRootProducesNoRepoRootIssue() async {
        let repoRoot = makeRepoRoot()
        defer { try? FileManager.default.removeItem(atPath: repoRoot) }
        let state = makeState(repoRoot: repoRoot)

        await state.refresh()

        XCTAssertFalse(state.coreIssues.map(\.id).contains("repo_root"))
    }

    func testMissingBrainFileProducesBlockingCoreIssue() async {
        let repoRoot = makeRepoRoot(createBrainFile: false)
        defer { try? FileManager.default.removeItem(atPath: repoRoot) }
        let state = makeState(repoRoot: repoRoot)

        await state.refresh()

        let issue = state.coreIssues.first(where: { $0.id == "brain_file" })
        XCTAssertNotNil(issue)
        XCTAssertEqual(issue?.severity, .blocking)
    }

    func testBrainPathEnvVarOverridesDefault() async {
        let repoRoot = makeRepoRoot(createBrainFile: false, createArtifacts: true)
        defer { try? FileManager.default.removeItem(atPath: repoRoot) }

        let brainURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-brain-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: brainURL) }
        try! "{\"brain\":true}".data(using: .utf8)!.write(to: brainURL)

        let state = makeState(
            repoRoot: repoRoot,
            environment: ["BRAIN_PATH": brainURL.path]
        )

        await state.refresh()

        XCTAssertFalse(state.coreIssues.map(\.id).contains("brain_file"))
    }

    func testBrainPathProviderOverridesDefault() async {
        let repoRoot = makeRepoRoot(createBrainFile: false, createArtifacts: true)
        defer { try? FileManager.default.removeItem(atPath: repoRoot) }

        let brainURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("provider-brain-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: brainURL) }
        try! "{\"brain\":true}".data(using: .utf8)!.write(to: brainURL)

        let state = makeState(
            repoRoot: repoRoot,
            brainPathProvider: { brainURL.path }
        )

        await state.refresh()

        XCTAssertFalse(state.coreIssues.map(\.id).contains("brain_file"))
    }

    func testMissingDaemonArtifactsProducesWarningCoreIssue() async {
        let repoRoot = makeRepoRoot(createBrainFile: true, createArtifacts: false)
        defer { try? FileManager.default.removeItem(atPath: repoRoot) }
        let state = makeState(repoRoot: repoRoot)

        await state.refresh()

        let issue = state.coreIssues.first(where: { $0.id == "daemon_artifacts" })
        XCTAssertNotNil(issue)
        XCTAssertEqual(issue?.severity, .warning)
    }

    func testIssuesAreSortedBySeverityThenId() async {
        let repoRoot = "/tmp/nonexistent-readiness-\(UUID().uuidString)"
        let state = makeState(repoRoot: repoRoot)

        await state.refresh()

        XCTAssertEqual(state.coreIssues.map(\.id), ["brain_file", "repo_root", "daemon_artifacts"])
    }

    func testRefreshDoesNotDuplicateIssues() async {
        let repoRoot = makeRepoRoot(createBrainFile: false, createArtifacts: false)
        defer { try? FileManager.default.removeItem(atPath: repoRoot) }
        let state = makeState(repoRoot: repoRoot)

        await state.refresh()
        let firstIDs = state.coreIssues.map(\.id)

        await state.refresh()
        let secondIDs = state.coreIssues.map(\.id)

        XCTAssertEqual(firstIDs, secondIDs)
        XCTAssertEqual(Set(secondIDs).count, secondIDs.count)
    }
}

@MainActor
final class ReadinessStateFeatureTests: XCTestCase {
    func testComputerUseIsNotReadyWhenAccessibilityMissing() async {
        let repoRoot = makeRepoRoot()
        defer { try? FileManager.default.removeItem(atPath: repoRoot) }
        let state = makeState(repoRoot: repoRoot, axGranted: false, screenRecordingGranted: true)

        await state.refresh()

        XCTAssertFalse(state.isReady(for: .computerUse))
        XCTAssertEqual(state.blockingIssue(for: .computerUse)?.id, "accessibility")
    }

    func testComputerUseIsReadyWhenOnlyScreenRecordingMissing() async {
        let repoRoot = makeRepoRoot()
        defer { try? FileManager.default.removeItem(atPath: repoRoot) }
        let state = makeState(repoRoot: repoRoot, axGranted: true, screenRecordingGranted: false)

        await state.refresh()

        XCTAssertTrue(state.isReady(for: .computerUse))
        XCTAssertEqual(state.featureIssues[.computerUse]?.map(\.id), ["screen_recording"])
    }

    func testLLMIsNotReadyWhenNoKeysPresent() async {
        let repoRoot = makeRepoRoot()
        defer { try? FileManager.default.removeItem(atPath: repoRoot) }
        let state = makeState(repoRoot: repoRoot)

        await state.refresh()

        XCTAssertFalse(state.isReady(for: .llm))
        XCTAssertEqual(state.blockingIssue(for: .llm)?.id, "llm_no_keys")
    }

    func testLLMShowsInfoWhenOnlyOneKeyPresent() async {
        let repoRoot = makeRepoRoot()
        defer { try? FileManager.default.removeItem(atPath: repoRoot) }
        let state = makeState(repoRoot: repoRoot, environment: ["ANTHROPIC_API_KEY": "sk-ant"])

        await state.refresh()

        XCTAssertTrue(state.isReady(for: .llm))
        XCTAssertEqual(state.featureIssues[.llm]?.map(\.id), ["llm_single_provider"])
        XCTAssertEqual(state.featureIssues[.llm]?.first?.severity, .info)
    }

    func testLLMHasNoIssuesWhenBothKeysPresent() async {
        let repoRoot = makeRepoRoot()
        defer { try? FileManager.default.removeItem(atPath: repoRoot) }
        let state = makeState(
            repoRoot: repoRoot,
            environment: [
                "ANTHROPIC_API_KEY": "sk-ant",
                "OPENAI_API_KEY": "sk-oai",
            ]
        )

        await state.refresh()

        XCTAssertEqual(state.featureIssues[.llm] ?? [], [])
        XCTAssertTrue(state.isReady(for: .llm))
    }

    func testAXPermissionGrantedUsesInjectedClosure() {
        let repoRoot = makeRepoRoot()
        defer { try? FileManager.default.removeItem(atPath: repoRoot) }
        let state = makeState(repoRoot: repoRoot, axGranted: false)
        XCTAssertFalse(state.axPermissionGranted())
    }
}

@MainActor
final class ReadinessStateFirstRunTests: XCTestCase {
    func testShowFirstRunSheetWhenIssuesPresentAndKeyAbsent() async {
        let repoRoot = makeRepoRoot(createBrainFile: false, createArtifacts: false)
        defer { try? FileManager.default.removeItem(atPath: repoRoot) }
        let defaults = makeTestDefaults()
        let state = makeState(repoRoot: repoRoot, defaults: defaults)

        await state.refresh()

        XCTAssertTrue(state.showFirstRunSheet)
    }

    func testDoNotShowFirstRunSheetWhenKeyAlreadySet() async {
        let repoRoot = makeRepoRoot(createBrainFile: false, createArtifacts: false)
        defer { try? FileManager.default.removeItem(atPath: repoRoot) }
        let defaults = makeTestDefaults()
        defaults.set(true, forKey: "readiness.firstRunShown")
        let state = makeState(repoRoot: repoRoot, defaults: defaults)

        await state.refresh()

        XCTAssertFalse(state.showFirstRunSheet)
    }

    func testNoFirstRunSheetWhenNoIssues() async {
        let repoRoot = makeRepoRoot()
        defer { try? FileManager.default.removeItem(atPath: repoRoot) }
        let defaults = makeTestDefaults()
        let state = makeState(
            repoRoot: repoRoot,
            defaults: defaults,
            environment: [
                "ANTHROPIC_API_KEY": "sk-ant",
                "OPENAI_API_KEY": "sk-oai",
            ],
            axGranted: true,
            screenRecordingGranted: true
        )

        await state.refresh()

        XCTAssertFalse(state.showFirstRunSheet)
    }

    func testMarkFirstRunShownPersistsAndDismissesSheet() async {
        let repoRoot = makeRepoRoot(createBrainFile: false, createArtifacts: false)
        defer { try? FileManager.default.removeItem(atPath: repoRoot) }
        let defaults = makeTestDefaults()
        let state = makeState(repoRoot: repoRoot, defaults: defaults)

        await state.refresh()
        XCTAssertTrue(state.showFirstRunSheet)

        state.markFirstRunShown()

        XCTAssertTrue(defaults.bool(forKey: "readiness.firstRunShown"))
        XCTAssertFalse(state.showFirstRunSheet)
    }
}
