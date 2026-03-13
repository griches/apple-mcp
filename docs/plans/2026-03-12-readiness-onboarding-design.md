# Readiness Onboarding Design

**Goal:** Add a persistent, non-blocking readiness layer to MojoShell that checks environment health at launch, surfaces exact fix instructions for missing prerequisites, and gates only the features that actually depend on each check.

**Architecture:** `ReadinessState: ObservableObject` as a separate `@EnvironmentObject` alongside `AppState`. A single `DaemonManager` is owned by `MojoShellApp` and shared between both. No global modal — core issues show a dismissible banner; feature issues disable only the dependent controls.

**Tech Stack:** SwiftUI, `@EnvironmentObject`, `AXIsProcessTrusted()`, `CGPreflightScreenCaptureAccess()`, `ProcessInfo.processInfo.environment`, injected `UserDefaults` suite for first-run state.

---

## Data Model

### `ReadinessSeverity`

```swift
enum ReadinessSeverity: Equatable, Sendable {
    case info       // visible but doesn't disable anything
    case warning    // shown in UI, doesn't block
    case blocking   // disables the dependent feature
}
```

### `ReadinessIssue`

```swift
struct ReadinessIssue: Identifiable, Equatable, Sendable {
    let id: String                  // stable key, e.g. "accessibility", "anthropic_key"
    let title: String               // "Accessibility permission missing"
    let fixInstruction: String      // "Open System Settings → Privacy → Accessibility"
    let actionURL: URL?             // deep-link to the relevant pref pane
    let severity: ReadinessSeverity
}
```

Issues are **ordered deterministically**: blocking first, then warning, then info; within each severity group, sorted by `id` lexicographically. This prevents UI churn across repeated refresh calls.

### `ReadinessFeature`

```swift
enum ReadinessFeature: String, Hashable, Sendable {
    case computerUse    // AX + Screen Recording
    case llm            // at least one API key present
}
```

Daemon artifact presence lives in `coreIssues` only — not duplicated as a `ReadinessFeature`.

### `ReadinessState`

```swift
@MainActor
final class ReadinessState: ObservableObject {
    @Published var coreIssues: [ReadinessIssue] = []
    @Published var featureIssues: [ReadinessFeature: [ReadinessIssue]] = [:]
    @Published var showFirstRunSheet: Bool = false
    @Published var isRefreshing: Bool = false   // only meaningful if refresh is async

    init(daemonManager: DaemonManager, defaults: UserDefaults = .standard)

    func refresh()           // re-runs all checks; sets isRefreshing while running
    func refreshComputerUse()  // AX + Screen Recording only

    func isReady(for feature: ReadinessFeature) -> Bool
    // true iff featureIssues[feature] contains no .blocking issues

    func axPermissionGranted() -> Bool
    // narrow check used by Discover FCP Elements (AX only, not full computerUse)
}
```

---

## Checks

### Core issues (single source of truth)

| id | Condition | Severity |
|----|-----------|----------|
| `repo_root` | `DaemonManager.repoRoot` path is not a valid directory | blocking |
| `brain_file` | Resolved brain path does not exist (see Brain Path Resolution) | blocking |
| `daemon_artifacts` | Any of the 10 `DaemonManager.serverDefinitions` scriptPaths is missing | warning |

**Brain Path Resolution:** `ReadinessState` checks `ProcessInfo.processInfo.environment["BRAIN_PATH"]` first. If set and non-empty, validates that path. Otherwise falls back to `<repoRoot>/knowledge-corpus/data/mojosolo_operating_brain.json`.

**Daemon artifacts** are derived from `DaemonManager.serverDefinitions` — no duplicated path strings in `ReadinessState`.

### Feature issues

**`.computerUse`**

| id | Condition | Severity |
|----|-----------|----------|
| `accessibility` | `AXIsProcessTrusted()` returns `false` | blocking |
| `screen_recording` | `CGPreflightScreenCaptureAccess()` returns `false` | warning |

**`.llm`**

| id | Condition | Severity |
|----|-----------|----------|
| `llm_no_keys` | Neither `ANTHROPIC_API_KEY` nor `OPENAI_API_KEY` is set | blocking |
| `llm_one_key` | Exactly one key is set | info |

---

## UI Wiring

### `MojoShellApp`

```swift
@main struct MojoShellApp: App {
    private let daemons = DaemonManager()
    @StateObject private var appState: AppState
    @StateObject private var readiness: ReadinessState

    init() {
        let d = DaemonManager()
        _appState = StateObject(wrappedValue: AppState(daemons: d))
        _readiness = StateObject(wrappedValue: ReadinessState(daemonManager: d))
    }
}
```

One `DaemonManager` instance, shared by both. `appState` uses it for MCP process management; `readiness` uses it to derive artifact paths.

### `ContentView`

- Wraps the detail column in a `VStack` with `CoreIssuesBanner` at the top — one place covers all three views.
- Triggers `readiness.refresh()` on `.task {}` (initial load) and on `.onChange(of: scenePhase) { if $0 == .active { readiness.refresh() } }`.
- Shows `FirstRunSheet` via `.sheet(isPresented: $readiness.showFirstRunSheet)`.

### `CoreIssuesBanner`

- Shown when `readiness.coreIssues` has any `.blocking` issues.
- Collapses to a non-intrusive indicator when only `.warning`/`.info` issues are present.
- Dismissible per-session (not persisted).

### `AgentTerminalView`

- Soft info label only when `.llm` has blocking issues: "LLM fallback unavailable; deterministic routing still works."
- Does **not** disable or block terminal interactions.

### `ProductionDashboardView`

- **"Run Assembly Workflow"**: `disabled(isRunningWorkflow || !readiness.isReady(for: .computerUse))`
  - Shows the first blocking fix instruction below the button when not ready.
- **"Discover FCP Elements"**: `disabled(!readiness.axPermissionGranted())`
  - Narrower gate — AX only, not full `.computerUse`. Screen Recording is irrelevant for discovery.

### `FirstRunSheet`

- Shown once per install state: `showFirstRunSheet` is set to `true` on first `refresh()` if any issues exist **and** `UserDefaults["readiness.firstRunShown"]` is absent.
- Dismissing sets `UserDefaults["readiness.firstRunShown"] = true` and is never shown again for this install.
- Lists issues grouped by severity. "Open System Settings" for permission issues uses `actionURL`. "Retry" calls `readiness.refresh()`. "Continue anyway" dismisses.

---

## Testing

All tests inject a stub `DaemonManager` (controllable artifact presence) and a dedicated `UserDefaults` suite so first-run tests stay isolated from system state.

| Test | What it verifies |
|------|-----------------|
| Core issue derivation | Missing repo root / brain file / daemon artifacts → correct `coreIssues` with correct severities |
| Brain path override | `BRAIN_PATH` set → validates that path; unset → falls back to default |
| `isReady(.computerUse)` | `false` when AX is blocking; `true` when only Screen Recording is warning |
| `isReady(.llm)` | No keys → blocking; one key → info; two keys → no issues |
| First-run gating | `showFirstRunSheet` `true` when issues present and key absent; `false` when key set — using injected `UserDefaults` suite |
| Stable issue ordering | Same readiness state → same issue order across repeated refresh calls |
| No duplicate issues | Calling `refresh()` twice → no duplicate entries in `coreIssues` or `featureIssues` |
| AX-only discovery gate | `axPermissionGranted()` returns `false` when AX denied, independent of Screen Recording state |
| `isRefreshing` (conditional) | Only if `refresh()` is meaningfully async; skip if effectively immediate |

No snapshot tests. No scenePhase UI tests. Phase 1 only.
