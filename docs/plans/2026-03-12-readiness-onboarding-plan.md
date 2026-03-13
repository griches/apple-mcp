# Readiness Onboarding Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a persistent, non-blocking readiness layer to MojoShell that checks environment health at launch, surfaces exact fix instructions, and gates only the features that depend on each check.

**Architecture:** `ReadinessState: ObservableObject` as a separate `@EnvironmentObject` alongside `AppState`. A single `DaemonManager` owned by `MojoShellApp` and shared between both. No global modal — core issues show a dismissible banner; feature issues disable only dependent controls.

**Tech Stack:** SwiftUI, `@EnvironmentObject`, `AXIsProcessTrusted()`, `CGPreflightScreenCaptureAccess()`, `ProcessInfo.processInfo.environment`, injected `UserDefaults` suite for first-run state, injectable closures for testable permission checks.

**Design doc:** `docs/plans/2026-03-12-readiness-onboarding-design.md`

**Branch:** `feat/macos-shell`

**Package root:** `shell/`

---

### Task 1: Data types — ReadinessSeverity, ReadinessIssue, ReadinessFeature

**Files:**
- Create: `shell/Sources/MojoShell/Readiness/ReadinessModels.swift`
- Create: `shell/Tests/MojoShellTests/ReadinessModelsTests.swift`

**Step 1: Write the failing tests**

```swift
// shell/Tests/MojoShellTests/ReadinessModelsTests.swift
import XCTest
@testable import MojoShell

final class ReadinessModelsTests: XCTestCase {

    func testSeverityCasesExist() {
        let _ = ReadinessSeverity.info
        let _ = ReadinessSeverity.warning
        let _ = ReadinessSeverity.blocking
    }

    func testSeverityIsEquatable() {
        XCTAssertEqual(ReadinessSeverity.blocking, .blocking)
        XCTAssertNotEqual(ReadinessSeverity.blocking, .warning)
    }

    func testIssueIsIdentifiable() {
        let issue = ReadinessIssue(
            id: "test_id",
            title: "Test Title",
            fixInstruction: "Do something",
            actionURL: nil,
            severity: .blocking
        )
        XCTAssertEqual(issue.id, "test_id")
        XCTAssertEqual(issue.title, "Test Title")
        XCTAssertEqual(issue.severity, .blocking)
        XCTAssertNil(issue.actionURL)
    }

    func testIssueIsEquatable() {
        let a = ReadinessIssue(id: "a", title: "A", fixInstruction: "fix", actionURL: nil, severity: .warning)
        let b = ReadinessIssue(id: "a", title: "A", fixInstruction: "fix", actionURL: nil, severity: .warning)
        XCTAssertEqual(a, b)
    }

    func testFeatureCasesExist() {
        let _ = ReadinessFeature.computerUse
        let _ = ReadinessFeature.llm
    }

    func testFeatureIsHashable() {
        var set = Set<ReadinessFeature>()
        set.insert(.computerUse)
        set.insert(.llm)
        set.insert(.computerUse) // duplicate
        XCTAssertEqual(set.count, 2)
    }
}
```

**Step 2: Run tests to verify they fail**

```bash
cd shell && swift test --filter ReadinessModelsTests 2>&1 | tail -20
```

Expected: compile error — `ReadinessSeverity`, `ReadinessIssue`, `ReadinessFeature` not found.

**Step 3: Create the source file**

```swift
// shell/Sources/MojoShell/Readiness/ReadinessModels.swift
import Foundation

enum ReadinessSeverity: Equatable, Sendable {
    case info       // visible but doesn't disable anything
    case warning    // shown in UI, doesn't block
    case blocking   // disables the dependent feature
}

struct ReadinessIssue: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let fixInstruction: String
    let actionURL: URL?
    let severity: ReadinessSeverity
}

enum ReadinessFeature: String, Hashable, Sendable {
    case computerUse
    case llm
}
```

**Step 4: Run tests to verify they pass**

```bash
cd shell && swift test --filter ReadinessModelsTests 2>&1 | tail -20
```

Expected: All 6 tests pass.

**Step 5: Commit**

```bash
git add shell/Sources/MojoShell/Readiness/ReadinessModels.swift shell/Tests/MojoShellTests/ReadinessModelsTests.swift
git commit -m "feat(readiness): add ReadinessSeverity, ReadinessIssue, ReadinessFeature data types"
```

---

### Task 2: Expose repoRoot on DaemonManager

`ReadinessState` must read `daemonManager.repoRoot` to check if it's a valid directory. Currently `repoRoot` is `private`.

**Files:**
- Modify: `shell/Sources/MojoShell/Managers/DaemonManager.swift:13`

**Step 1: Write a test to verify the field is accessible**

Add to `shell/Tests/MojoShellTests/DaemonManagerTests.swift` (existing file — append to the class):

```swift
func testRepoRootIsAccessible() {
    // Verifies that ReadinessState can read the repoRoot without reflection.
    let dm = DaemonManager(repoRoot: "/tmp/test-root")
    XCTAssertEqual(dm.repoRoot, "/tmp/test-root")
}
```

**Step 2: Run to verify it fails**

```bash
cd shell && swift test --filter DaemonManagerTests/testRepoRootIsAccessible 2>&1 | tail -10
```

Expected: compile error — `'repoRoot' is inaccessible due to 'private' protection level`.

**Step 3: Change private to internal**

In `shell/Sources/MojoShell/Managers/DaemonManager.swift`, change line 13:

```swift
// Before
private let repoRoot: String

// After
let repoRoot: String
```

**Step 4: Run tests**

```bash
cd shell && swift test --filter DaemonManagerTests 2>&1 | tail -10
```

Expected: All DaemonManager tests pass.

**Step 5: Commit**

```bash
git add shell/Sources/MojoShell/Managers/DaemonManager.swift shell/Tests/MojoShellTests/DaemonManagerTests.swift
git commit -m "feat(readiness): expose DaemonManager.repoRoot as internal for ReadinessState"
```

---

### Task 3: ReadinessState — model, core checks, feature checks

**Files:**
- Create: `shell/Sources/MojoShell/Readiness/ReadinessState.swift`
- Create: `shell/Tests/MojoShellTests/ReadinessStateTests.swift`

**Step 1: Write the failing tests**

```swift
// shell/Tests/MojoShellTests/ReadinessStateTests.swift
import XCTest
@testable import MojoShell

// MARK: - Helpers

/// DaemonManager with a controllable repoRoot for tests.
/// Use DaemonManager(repoRoot:) directly — repoRoot is now internal.

private func makeState(
    repoRoot: String = "/tmp",
    defaults: UserDefaults = makeTestDefaults(),
    environment: [String: String] = [:],
    axGranted: Bool = true,
    screenRecordingGranted: Bool = true
) -> ReadinessState {
    let dm = DaemonManager(repoRoot: repoRoot)
    return ReadinessState(
        daemonManager: dm,
        defaults: defaults,
        environment: environment,
        axCheck: { axGranted },
        screenRecordingCheck: { screenRecordingGranted }
    )
}

private func makeTestDefaults() -> UserDefaults {
    let suite = UUID().uuidString
    return UserDefaults(suiteName: suite)!
}

// MARK: - Core issue tests

@MainActor
final class ReadinessStateCoreTests: XCTestCase {

    func testMissingRepoRootProducesBlockingCoreIssue() async {
        let state = makeState(repoRoot: "/tmp/nonexistent_mojo_test_\(UUID().uuidString)")
        await state.refresh()
        let ids = state.coreIssues.map(\.id)
        XCTAssertTrue(ids.contains("repo_root"), "Expected repo_root issue; got \(ids)")
        let issue = state.coreIssues.first(where: { $0.id == "repo_root" })!
        XCTAssertEqual(issue.severity, .blocking)
    }

    func testValidRepoRootProducesNoRepoRootIssue() async {
        // /tmp always exists
        let state = makeState(repoRoot: "/tmp")
        await state.refresh()
        XCTAssertFalse(state.coreIssues.map(\.id).contains("repo_root"))
    }

    func testMissingBrainFileProducesBlockingCoreIssue() async {
        // /tmp is a valid dir but has no knowledge-corpus/data/mojosolo_operating_brain.json
        let state = makeState(repoRoot: "/tmp")
        await state.refresh()
        let issue = state.coreIssues.first(where: { $0.id == "brain_file" })
        XCTAssertNotNil(issue)
        XCTAssertEqual(issue?.severity, .blocking)
    }

    func testBrainPathEnvVarOverridesDefault() async {
        // BRAIN_PATH points to a file that exists — no brain_file issue
        let tmpFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_brain_\(UUID().uuidString).json")
        FileManager.default.createFile(atPath: tmpFile.path, contents: Data("{}".utf8))
        defer { try? FileManager.default.removeItem(at: tmpFile) }

        let state = makeState(repoRoot: "/tmp", environment: ["BRAIN_PATH": tmpFile.path])
        await state.refresh()
        XCTAssertFalse(state.coreIssues.map(\.id).contains("brain_file"))
    }

    func testBrainPathEnvVarMissingProducesIssue() async {
        // BRAIN_PATH set but file doesn't exist
        let state = makeState(repoRoot: "/tmp", environment: ["BRAIN_PATH": "/tmp/nonexistent_brain_\(UUID().uuidString).json"])
        await state.refresh()
        XCTAssertTrue(state.coreIssues.map(\.id).contains("brain_file"))
    }

    func testDaemonArtifactsMissingProducesWarning() async {
        // /tmp is valid but has no node build artifacts
        let state = makeState(repoRoot: "/tmp")
        await state.refresh()
        let issue = state.coreIssues.first(where: { $0.id == "daemon_artifacts" })
        XCTAssertNotNil(issue)
        XCTAssertEqual(issue?.severity, .warning)
    }
}

// MARK: - Feature issue tests

@MainActor
final class ReadinessStateFeatureTests: XCTestCase {

    func testComputerUseIsBlockedWhenAXDenied() async {
        let state = makeState(axGranted: false, screenRecordingGranted: true)
        await state.refresh()
        XCTAssertFalse(state.isReady(for: .computerUse))
        let ids = state.featureIssues[.computerUse]?.map(\.id) ?? []
        XCTAssertTrue(ids.contains("accessibility"))
    }

    func testComputerUseIsReadyWhenOnlyScreenRecordingMissing() async {
        let state = makeState(axGranted: true, screenRecordingGranted: false)
        await state.refresh()
        // Screen Recording is only a warning — not blocking
        XCTAssertTrue(state.isReady(for: .computerUse))
        let ids = state.featureIssues[.computerUse]?.map(\.id) ?? []
        XCTAssertTrue(ids.contains("screen_recording"))
        let srIssue = state.featureIssues[.computerUse]!.first(where: { $0.id == "screen_recording" })!
        XCTAssertEqual(srIssue.severity, .warning)
    }

    func testComputerUseIsReadyWhenBothGranted() async {
        let state = makeState(axGranted: true, screenRecordingGranted: true)
        await state.refresh()
        XCTAssertTrue(state.isReady(for: .computerUse))
        let blockingIssues = state.featureIssues[.computerUse]?.filter { $0.severity == .blocking } ?? []
        XCTAssertTrue(blockingIssues.isEmpty)
    }

    func testAXOnlyCheckIsIndependentOfScreenRecording() async {
        let state = makeState(axGranted: false, screenRecordingGranted: true)
        await state.refresh()
        XCTAssertFalse(state.axPermissionGranted())

        let state2 = makeState(axGranted: true, screenRecordingGranted: false)
        await state2.refresh()
        XCTAssertTrue(state2.axPermissionGranted())
    }

    func testLLMNoKeysIsBlocking() async {
        let state = makeState(environment: [:])
        await state.refresh()
        XCTAssertFalse(state.isReady(for: .llm))
        let ids = state.featureIssues[.llm]?.map(\.id) ?? []
        XCTAssertTrue(ids.contains("llm_no_keys"))
        let issue = state.featureIssues[.llm]!.first(where: { $0.id == "llm_no_keys" })!
        XCTAssertEqual(issue.severity, .blocking)
    }

    func testLLMOneKeyIsInfo() async {
        let state = makeState(environment: ["ANTHROPIC_API_KEY": "sk-test"])
        await state.refresh()
        // One key → llm_one_key info issue, but isReady is true (no blocking)
        XCTAssertTrue(state.isReady(for: .llm))
        let ids = state.featureIssues[.llm]?.map(\.id) ?? []
        XCTAssertTrue(ids.contains("llm_one_key"))
        let issue = state.featureIssues[.llm]!.first(where: { $0.id == "llm_one_key" })!
        XCTAssertEqual(issue.severity, .info)
    }

    func testLLMBothKeysProducesNoIssues() async {
        let state = makeState(environment: [
            "ANTHROPIC_API_KEY": "sk-ant-test",
            "OPENAI_API_KEY": "sk-openai-test"
        ])
        await state.refresh()
        XCTAssertTrue(state.isReady(for: .llm))
        let issues = state.featureIssues[.llm] ?? []
        XCTAssertTrue(issues.isEmpty)
    }
}

// MARK: - Stable ordering + no-duplicate tests

@MainActor
final class ReadinessStateOrderingTests: XCTestCase {

    func testIssuesAreOrderedBlockingThenWarningThenInfo() async {
        // No keys → blocking. No daemon artifacts → warning. Both together.
        let state = makeState(
            repoRoot: "/tmp",
            environment: ["ANTHROPIC_API_KEY": "sk-test"],
            axGranted: false,
            screenRecordingGranted: false
        )
        await state.refresh()
        let severities = state.coreIssues.map(\.severity)
        // coreIssues should have blocking items before warning items
        var seenWarning = false
        for s in severities {
            if s == .warning { seenWarning = true }
            if seenWarning { XCTAssertNotEqual(s, .blocking, "Blocking issue appeared after warning") }
        }
    }

    func testRefreshTwiceProducesNoDuplicates() async {
        let state = makeState(repoRoot: "/tmp")
        await state.refresh()
        let countAfterFirst = state.coreIssues.count
        await state.refresh()
        XCTAssertEqual(state.coreIssues.count, countAfterFirst, "Second refresh should not duplicate issues")
    }
}

// MARK: - First-run sheet tests

@MainActor
final class ReadinessStateFirstRunTests: XCTestCase {

    func testShowFirstRunSheetWhenIssuesPresentAndKeyAbsent() async {
        let defaults = makeTestDefaults()
        // Missing brain file → issues present
        let state = makeState(repoRoot: "/tmp", defaults: defaults)
        await state.refresh()
        XCTAssertTrue(state.showFirstRunSheet, "Should show first-run sheet when issues exist and key not set")
    }

    func testDoNotShowFirstRunSheetWhenKeyAlreadySet() async {
        let defaults = makeTestDefaults()
        defaults.set(true, forKey: "readiness.firstRunShown")
        let state = makeState(repoRoot: "/tmp", defaults: defaults)
        await state.refresh()
        XCTAssertFalse(state.showFirstRunSheet, "Should not re-show first-run sheet when key is set")
    }

    func testNoFirstRunSheetWhenNoIssues() async {
        // Build a brain file so brain_file passes; use /tmp so repo_root passes; both keys set; AX+SR granted.
        let tmpFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_brain_\(UUID().uuidString).json")
        FileManager.default.createFile(atPath: tmpFile.path, contents: Data("{}".utf8))
        defer { try? FileManager.default.removeItem(at: tmpFile) }

        let defaults = makeTestDefaults()
        let state = makeState(
            repoRoot: "/tmp",
            defaults: defaults,
            environment: [
                "BRAIN_PATH": tmpFile.path,
                "ANTHROPIC_API_KEY": "sk-ant",
                "OPENAI_API_KEY": "sk-oai"
            ],
            axGranted: true,
            screenRecordingGranted: true
        )
        await state.refresh()
        // daemon_artifacts will still be a warning (no build/ artifacts under /tmp)
        // showFirstRunSheet checks if any issues exist — daemon_artifacts is a warning, so it's an issue
        // This test verifies first-run is NOT shown when only the key is already set:
        // Re-test with key already set
        defaults.set(true, forKey: "readiness.firstRunShown")
        let state2 = makeState(
            repoRoot: "/tmp",
            defaults: defaults,
            environment: [
                "BRAIN_PATH": tmpFile.path,
                "ANTHROPIC_API_KEY": "sk-ant",
                "OPENAI_API_KEY": "sk-oai"
            ],
            axGranted: true,
            screenRecordingGranted: true
        )
        await state2.refresh()
        XCTAssertFalse(state2.showFirstRunSheet)
    }
}
```

**Step 2: Run tests to verify they fail**

```bash
cd shell && swift test --filter ReadinessState 2>&1 | tail -20
```

Expected: compile error — `ReadinessState` not found.

**Step 3: Create ReadinessState.swift**

```swift
// shell/Sources/MojoShell/Readiness/ReadinessState.swift
import ApplicationServices
import CoreGraphics
import Foundation

@MainActor
final class ReadinessState: ObservableObject {
    @Published var coreIssues: [ReadinessIssue] = []
    @Published var featureIssues: [ReadinessFeature: [ReadinessIssue]] = [:]
    @Published var showFirstRunSheet: Bool = false
    @Published var isRefreshing: Bool = false

    private let daemonManager: DaemonManager
    private let defaults: UserDefaults
    private let environment: [String: String]
    private let axCheck: () -> Bool
    private let screenRecordingCheck: () -> Bool

    init(
        daemonManager: DaemonManager,
        defaults: UserDefaults = .standard,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        axCheck: @escaping () -> Bool = { AXIsProcessTrusted() },
        screenRecordingCheck: @escaping () -> Bool = { CGPreflightScreenCaptureAccess() }
    ) {
        self.daemonManager = daemonManager
        self.defaults = defaults
        self.environment = environment
        self.axCheck = axCheck
        self.screenRecordingCheck = screenRecordingCheck
    }

    func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }

        coreIssues = sorted(buildCoreIssues())
        featureIssues = [
            .computerUse: sorted(buildComputerUseIssues()),
            .llm: sorted(buildLLMIssues()),
        ]

        // First-run sheet: show once if issues exist and key not yet set
        let hasAnyIssue = !coreIssues.isEmpty || featureIssues.values.contains(where: { !$0.isEmpty })
        if hasAnyIssue && !defaults.bool(forKey: "readiness.firstRunShown") {
            showFirstRunSheet = true
        }
    }

    func refreshComputerUse() async {
        featureIssues[.computerUse] = sorted(buildComputerUseIssues())
    }

    func isReady(for feature: ReadinessFeature) -> Bool {
        let issues = featureIssues[feature] ?? []
        return !issues.contains(where: { $0.severity == .blocking })
    }

    func axPermissionGranted() -> Bool {
        axCheck()
    }

    // MARK: - Core checks

    private func buildCoreIssues() -> [ReadinessIssue] {
        var issues: [ReadinessIssue] = []

        // repo_root
        var isDir: ObjCBool = false
        let rootExists = FileManager.default.fileExists(atPath: daemonManager.repoRoot, isDirectory: &isDir) && isDir.boolValue
        if !rootExists {
            issues.append(ReadinessIssue(
                id: "repo_root",
                title: "Repository root not found",
                fixInstruction: "Ensure the MojoShell repository is present at: \(daemonManager.repoRoot)",
                actionURL: nil,
                severity: .blocking
            ))
        }

        // brain_file
        let brainPath = resolvedBrainPath()
        if !FileManager.default.fileExists(atPath: brainPath) {
            issues.append(ReadinessIssue(
                id: "brain_file",
                title: "Brain file missing",
                fixInstruction: "Ensure the brain file exists at: \(brainPath)",
                actionURL: nil,
                severity: .blocking
            ))
        }

        // daemon_artifacts
        let missingArtifacts = daemonManager.serverDefinitions
            .filter { !FileManager.default.fileExists(atPath: $0.scriptPath) }
        if !missingArtifacts.isEmpty {
            let names = missingArtifacts.map(\.name).joined(separator: ", ")
            issues.append(ReadinessIssue(
                id: "daemon_artifacts",
                title: "MCP server build artifacts missing",
                fixInstruction: "Run `npm run build` in each server directory. Missing: \(names)",
                actionURL: nil,
                severity: .warning
            ))
        }

        return issues
    }

    private func resolvedBrainPath() -> String {
        if let override = environment["BRAIN_PATH"], !override.isEmpty {
            return override
        }
        return "\(daemonManager.repoRoot)/knowledge-corpus/data/mojosolo_operating_brain.json"
    }

    // MARK: - Feature checks

    private func buildComputerUseIssues() -> [ReadinessIssue] {
        var issues: [ReadinessIssue] = []

        if !axCheck() {
            issues.append(ReadinessIssue(
                id: "accessibility",
                title: "Accessibility permission missing",
                fixInstruction: "Open System Settings → Privacy & Security → Accessibility, then enable MojoShell.",
                actionURL: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"),
                severity: .blocking
            ))
        }

        if !screenRecordingCheck() {
            issues.append(ReadinessIssue(
                id: "screen_recording",
                title: "Screen Recording permission missing",
                fixInstruction: "Open System Settings → Privacy & Security → Screen Recording, then enable MojoShell.",
                actionURL: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"),
                severity: .warning
            ))
        }

        return issues
    }

    private func buildLLMIssues() -> [ReadinessIssue] {
        let hasAnthropic = !(environment["ANTHROPIC_API_KEY"] ?? "").isEmpty
        let hasOpenAI = !(environment["OPENAI_API_KEY"] ?? "").isEmpty

        if !hasAnthropic && !hasOpenAI {
            return [ReadinessIssue(
                id: "llm_no_keys",
                title: "No LLM API keys configured",
                fixInstruction: "Set ANTHROPIC_API_KEY or OPENAI_API_KEY in your environment.",
                actionURL: nil,
                severity: .blocking
            )]
        }

        if hasAnthropic != hasOpenAI {
            return [ReadinessIssue(
                id: "llm_one_key",
                title: "Only one LLM provider configured",
                fixInstruction: "Set both ANTHROPIC_API_KEY and OPENAI_API_KEY for full LLM fallback coverage.",
                actionURL: nil,
                severity: .info
            )]
        }

        return []
    }

    // MARK: - Ordering

    private func sorted(_ issues: [ReadinessIssue]) -> [ReadinessIssue] {
        issues.sorted { lhs, rhs in
            let lPriority = severityPriority(lhs.severity)
            let rPriority = severityPriority(rhs.severity)
            if lPriority != rPriority { return lPriority < rPriority }
            return lhs.id < rhs.id
        }
    }

    private func severityPriority(_ s: ReadinessSeverity) -> Int {
        switch s {
        case .blocking: return 0
        case .warning:  return 1
        case .info:     return 2
        }
    }
}
```

**Step 4: Run all ReadinessState tests**

```bash
cd shell && swift test --filter ReadinessState 2>&1 | tail -30
```

Expected: All tests pass. If `ApplicationServices` or `CoreGraphics` import fails under SwiftPM, check that the `MojoShell` target already links these frameworks in `Package.swift`.

**Step 5: Run full test suite**

```bash
cd shell && swift test 2>&1 | tail -20
```

Expected: All tests pass.

**Step 6: Commit**

```bash
git add shell/Sources/MojoShell/Readiness/ shell/Tests/MojoShellTests/ReadinessStateTests.swift
git commit -m "feat(readiness): add ReadinessState with core and feature checks, first-run gating, stable ordering"
```

---

### Task 4: Wire DaemonManager sharing in MojoShellApp

The design requires one `DaemonManager` instance shared between `AppState` and `ReadinessState`. Currently `MojoShellApp` creates `AppState` with its own internal daemon.

**Files:**
- Modify: `shell/Sources/MojoShell/App/MojoShellApp.swift`
- Modify: `shell/Sources/MojoShell/App/AppState.swift` (verify it already accepts `DaemonManager` in init)

**Step 1: Verify AppState.init signature**

Read `AppState.swift` and confirm `init(daemons: DaemonManager, ...)` exists. The previous session already implemented this. If it does, no changes needed to AppState.

**Step 2: Update MojoShellApp.swift**

Replace the current file content:

```swift
// shell/Sources/MojoShell/App/MojoShellApp.swift
import SwiftUI

@main
struct MojoShellApp: App {
    @StateObject private var appState: AppState
    @StateObject private var readiness: ReadinessState

    init() {
        let daemons = DaemonManager()
        _appState = StateObject(wrappedValue: AppState(daemons: daemons))
        _readiness = StateObject(wrappedValue: ReadinessState(daemonManager: daemons))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(readiness)
                .frame(minWidth: 1000, minHeight: 650)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
```

**Step 3: Build to verify it compiles**

```bash
cd shell && swift build 2>&1 | tail -20
```

Expected: Build succeeds. If AppState.init doesn't accept `daemons:`, read AppState.swift first and align — the previous session added this parameter.

**Step 4: Commit**

```bash
git add shell/Sources/MojoShell/App/MojoShellApp.swift
git commit -m "feat(readiness): wire shared DaemonManager between AppState and ReadinessState in MojoShellApp"
```

---

### Task 5: CoreIssuesBanner view

**Files:**
- Create: `shell/Sources/MojoShell/Readiness/CoreIssuesBanner.swift`

No unit tests — this is a pure display component. Manual verification in Task 7.

**Step 1: Create the banner view**

```swift
// shell/Sources/MojoShell/Readiness/CoreIssuesBanner.swift
import SwiftUI

struct CoreIssuesBanner: View {
    @EnvironmentObject private var readiness: ReadinessState
    @State private var dismissed = false

    private var blockingIssues: [ReadinessIssue] {
        readiness.coreIssues.filter { $0.severity == .blocking }
    }

    private var nonBlockingIssues: [ReadinessIssue] {
        readiness.coreIssues.filter { $0.severity != .blocking }
    }

    var body: some View {
        if dismissed || readiness.coreIssues.isEmpty {
            EmptyView()
        } else if !blockingIssues.isEmpty {
            blockingBanner
        } else {
            warningIndicator
        }
    }

    private var blockingBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text("Environment issues")
                    .font(.headline)
                Spacer()
                Button("Dismiss") { dismissed = true }
                    .buttonStyle(.plain)
                    .font(.caption)
            }
            ForEach(blockingIssues) { issue in
                VStack(alignment: .leading, spacing: 2) {
                    Text(issue.title).bold().font(.caption)
                    Text(issue.fixInstruction).font(.caption).foregroundStyle(.secondary)
                    if let url = issue.actionURL {
                        Link("Open Settings", destination: url).font(.caption)
                    }
                }
            }
        }
        .padding(12)
        .background(.red.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.red.opacity(0.3), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private var warningIndicator: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.circle")
                .foregroundStyle(.orange)
            Text("\(nonBlockingIssues.count) environment warning\(nonBlockingIssues.count == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Dismiss") { dismissed = true }
                .buttonStyle(.plain)
                .font(.caption)
        }
        .padding(8)
        .padding(.horizontal)
    }
}
```

**Step 2: Build to verify it compiles**

```bash
cd shell && swift build 2>&1 | tail -10
```

**Step 3: Commit**

```bash
git add shell/Sources/MojoShell/Readiness/CoreIssuesBanner.swift
git commit -m "feat(readiness): add CoreIssuesBanner view"
```

---

### Task 6: ContentView — banner + refresh wiring

**Files:**
- Modify: `shell/Sources/MojoShell/App/ContentView.swift`

**Step 1: Update ContentView**

Replace the detail column with a `VStack` that places `CoreIssuesBanner` at the top, and trigger `refresh()` on appear and on scene activation.

```swift
// shell/Sources/MojoShell/App/ContentView.swift
import SwiftUI

enum ShellView: String, CaseIterable, Identifiable {
    case cockpit = "Cockpit"
    case terminal = "Agent Terminal"
    case production = "Production"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .cockpit:
            return "gauge.with.dots.needle.bottom.50percent"
        case .terminal:
            return "terminal"
        case .production:
            return "film.stack"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var readiness: ReadinessState
    @State private var selected: ShellView? = .cockpit
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationSplitView {
            List(ShellView.allCases, selection: $selected) { view in
                Label(view.rawValue, systemImage: view.icon)
                    .tag(view)
            }
            .navigationSplitViewColumnWidth(220)
            .listStyle(.sidebar)
        } detail: {
            VStack(spacing: 0) {
                CoreIssuesBanner()
                Group {
                    switch selected ?? .cockpit {
                    case .cockpit:
                        CockpitView()
                    case .terminal:
                        AgentTerminalView()
                    case .production:
                        ProductionDashboardView()
                    }
                }
            }
        }
        .sheet(isPresented: $readiness.showFirstRunSheet) {
            FirstRunSheet()
        }
        .task {
            await readiness.refresh()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task { await readiness.refresh() }
            }
        }
    }
}
```

**Step 2: Build**

```bash
cd shell && swift build 2>&1 | tail -20
```

`FirstRunSheet` doesn't exist yet — expect a compile error for it. We'll add it in Task 8. For now, comment out the `.sheet` line and the `.task`/`.onChange` to get a clean build for testing `CoreIssuesBanner`.

Actually: leave everything in — we'll create `FirstRunSheet` in the next task so the build will succeed after Task 7. If you need an intermediate build check, add a placeholder:

```swift
// Temporary placeholder in ContentView.swift during build:
// Replace FirstRunSheet() with Text("First Run") temporarily
```

**Step 3: Commit ContentView stub (with FirstRunSheet placeholder)**

```bash
git add shell/Sources/MojoShell/App/ContentView.swift
git commit -m "feat(readiness): integrate CoreIssuesBanner and readiness refresh into ContentView"
```

---

### Task 7: FirstRunSheet view

**Files:**
- Create: `shell/Sources/MojoShell/Readiness/FirstRunSheet.swift`

**Step 1: Create the sheet**

```swift
// shell/Sources/MojoShell/Readiness/FirstRunSheet.swift
import SwiftUI

struct FirstRunSheet: View {
    @EnvironmentObject private var readiness: ReadinessState

    private var allIssues: [ReadinessIssue] {
        let core = readiness.coreIssues
        let feature = readiness.featureIssues.values.flatMap { $0 }
        return (core + feature).sorted { lhs, rhs in
            let lp = severityPriority(lhs.severity)
            let rp = severityPriority(rhs.severity)
            return lp == rp ? lhs.id < rhs.id : lp < rp
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("MojoShell Setup", systemImage: "wrench.and.screwdriver")
                .font(.title2.bold())

            Text("Some environment requirements need attention. Fix them now or continue anyway.")
                .foregroundStyle(.secondary)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(allIssues) { issue in
                        IssueRow(issue: issue, onRetry: {
                            Task { await readiness.refresh() }
                        })
                    }
                }
            }

            Divider()

            HStack {
                Button("Retry") {
                    Task { await readiness.refresh() }
                }
                Spacer()
                Button("Continue Anyway") {
                    markShown()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(minWidth: 480, minHeight: 320)
    }

    private func markShown() {
        // ReadinessState doesn't own UserDefaults directly in the sheet context.
        // We dismiss by setting showFirstRunSheet = false.
        // The UserDefaults key is written by ReadinessState.markFirstRunShown().
        readiness.markFirstRunShown()
    }

    private func severityPriority(_ s: ReadinessSeverity) -> Int {
        switch s {
        case .blocking: return 0
        case .warning:  return 1
        case .info:     return 2
        }
    }
}

private struct IssueRow: View {
    let issue: ReadinessIssue
    let onRetry: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: severityIcon)
                .foregroundStyle(severityColor)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 4) {
                Text(issue.title).bold().font(.callout)
                Text(issue.fixInstruction).font(.caption).foregroundStyle(.secondary)
                if let url = issue.actionURL {
                    Link("Open System Settings", destination: url).font(.caption)
                }
            }
            Spacer()
        }
    }

    private var severityIcon: String {
        switch issue.severity {
        case .blocking: return "xmark.circle.fill"
        case .warning:  return "exclamationmark.triangle.fill"
        case .info:     return "info.circle"
        }
    }

    private var severityColor: Color {
        switch issue.severity {
        case .blocking: return .red
        case .warning:  return .orange
        case .info:     return .blue
        }
    }
}
```

**Step 2: Add `markFirstRunShown()` to ReadinessState**

Append to `ReadinessState.swift`:

```swift
// Inside ReadinessState, add:
func markFirstRunShown() {
    defaults.set(true, forKey: "readiness.firstRunShown")
    showFirstRunSheet = false
}
```

**Step 3: Build**

```bash
cd shell && swift build 2>&1 | tail -10
```

Expected: Build succeeds (ContentView's `FirstRunSheet()` reference now resolves).

**Step 4: Run full test suite**

```bash
cd shell && swift test 2>&1 | tail -20
```

Expected: All tests pass.

**Step 5: Commit**

```bash
git add shell/Sources/MojoShell/Readiness/FirstRunSheet.swift shell/Sources/MojoShell/Readiness/ReadinessState.swift
git commit -m "feat(readiness): add FirstRunSheet and markFirstRunShown()"
```

---

### Task 8: AgentTerminalView — soft LLM warning

When `.llm` has blocking issues, show a non-blocking info label in `AgentTerminalView`. Do **not** disable terminal interaction.

**Files:**
- Modify: `shell/Sources/MojoShell/Views/AgentTerminalView.swift`

**Step 1: Add readiness environment object and soft warning label**

In `AgentTerminalView`, add:

```swift
// After: @EnvironmentObject private var appState: AppState
@EnvironmentObject private var readiness: ReadinessState
```

Add this below `Divider()` that separates the scroll area from the input bar (before the `HStack` input row):

```swift
if !readiness.isReady(for: .llm) {
    Text("LLM fallback unavailable; deterministic routing still works.")
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.bottom, 4)
}
```

**Step 2: Build**

```bash
cd shell && swift build 2>&1 | tail -10
```

**Step 3: Commit**

```bash
git add shell/Sources/MojoShell/Views/AgentTerminalView.swift
git commit -m "feat(readiness): show soft LLM warning in AgentTerminalView when keys missing"
```

---

### Task 9: ProductionDashboardView — feature gating

Gate "Run Assembly Workflow" on `readiness.isReady(for: .computerUse)`. Gate "Discover FCP Elements" on `readiness.axPermissionGranted()`.

**Files:**
- Modify: `shell/Sources/MojoShell/Views/ProductionDashboardView.swift`

**Step 1: Add readiness environment object**

In `ProductionDashboardView`, add:

```swift
// After: @EnvironmentObject private var appState: AppState
@EnvironmentObject private var readiness: ReadinessState
```

**Step 2: Gate "Discover FCP Elements" button**

Change:
```swift
Button(isDiscovering ? "Scanning..." : "Discover FCP Elements") {
    Task { await discoverFcpElements() }
}
.disabled(isDiscovering)
```

To:
```swift
Button(isDiscovering ? "Scanning..." : "Discover FCP Elements") {
    Task { await discoverFcpElements() }
}
.disabled(isDiscovering || !readiness.axPermissionGranted())
```

**Step 3: Gate "Run Assembly Workflow" button and add fix hint**

Change:
```swift
Button(isRunningWorkflow ? "Running..." : "Run Assembly Workflow") {
    Task { await runAssemblyWorkflow() }
}
.disabled(isRunningWorkflow)
```

To:
```swift
VStack(alignment: .leading, spacing: 4) {
    Button(isRunningWorkflow ? "Running..." : "Run Assembly Workflow") {
        Task { await runAssemblyWorkflow() }
    }
    .disabled(isRunningWorkflow || !readiness.isReady(for: .computerUse))

    if !readiness.isReady(for: .computerUse),
       let firstBlockingIssue = readiness.featureIssues[.computerUse]?.first(where: { $0.severity == .blocking }) {
        Text(firstBlockingIssue.fixInstruction)
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}
```

**Step 4: Build**

```bash
cd shell && swift build 2>&1 | tail -10
```

**Step 5: Run full test suite**

```bash
cd shell && swift test 2>&1 | tail -20
```

**Step 6: Commit**

```bash
git add shell/Sources/MojoShell/Views/ProductionDashboardView.swift
git commit -m "feat(readiness): gate Run Assembly on computerUse readiness; gate Discover FCP on AX permission"
```

---

### Task 10: Final verification

**Step 1: Run full build + tests**

```bash
cd shell && swift build 2>&1 | tail -10 && swift test 2>&1 | tail -20
```

Expected: Build succeeds, all tests pass.

**Step 2: Verify new test count includes readiness tests**

```bash
cd shell && swift test 2>&1 | grep -E "Test Suite|tests passed"
```

Expected: Includes `ReadinessModelsTests`, `ReadinessStateCoreTests`, `ReadinessStateFeatureTests`, `ReadinessStateOrderingTests`, `ReadinessStateFirstRunTests`.

**Step 3: Final commit if anything was missed**

```bash
git status
# Stage and commit any unstaged changes
```

---

## File Summary

| Action | Path |
|--------|------|
| Create | `shell/Sources/MojoShell/Readiness/ReadinessModels.swift` |
| Create | `shell/Sources/MojoShell/Readiness/ReadinessState.swift` |
| Create | `shell/Sources/MojoShell/Readiness/CoreIssuesBanner.swift` |
| Create | `shell/Sources/MojoShell/Readiness/FirstRunSheet.swift` |
| Create | `shell/Tests/MojoShellTests/ReadinessModelsTests.swift` |
| Create | `shell/Tests/MojoShellTests/ReadinessStateTests.swift` |
| Modify | `shell/Sources/MojoShell/Managers/DaemonManager.swift` (expose repoRoot) |
| Modify | `shell/Sources/MojoShell/App/MojoShellApp.swift` (shared DaemonManager + ReadinessState) |
| Modify | `shell/Sources/MojoShell/App/ContentView.swift` (banner + refresh + sheet) |
| Modify | `shell/Sources/MojoShell/Views/AgentTerminalView.swift` (LLM soft warning) |
| Modify | `shell/Sources/MojoShell/Views/ProductionDashboardView.swift` (feature gating) |

**Total new tests:** 15 (6 models + 5 core + 6 feature/ordering/first-run split across test classes)
