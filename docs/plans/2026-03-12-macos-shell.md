# macOS Shell Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a native SwiftUI macOS shell that unifies the 10 existing MCP servers, a swappable computer-use layer for FCP/Motion, and a three-tier agent router into a cockpit/terminal/dashboard app.

**Architecture:** SPM-based SwiftUI app in `shell/` at repo root. A `DaemonManager` spawns the 10 Node MCP servers as child processes. An `MCPClient` speaks JSON-RPC over stdio. A three-tier `Router` (deterministic → Claude → OpenAI) dispatches intents. A `ComputerUseProvider` protocol isolates screen-capture logic behind a swappable seam.

**Tech Stack:** Swift 5.9 + SwiftUI (macOS 14+), Swift Package Manager, Foundation.Process for daemon management, URLSession for Anthropic/OpenAI REST calls, XCTest for unit tests.

**Branch:** `feat/macos-shell`
**Design doc:** `docs/macos-shell-architecture.md`

---

## Task 1: Scaffold the Swift Package

**Files:**
- Create: `shell/Package.swift`
- Create: `shell/Sources/MojoShell/App/MojoShellApp.swift`
- Create: `shell/Sources/MojoShell/App/ContentView.swift`
- Create: `shell/Tests/MojoShellTests/MojoShellTests.swift`

**Step 1: Create the directory structure**

```bash
mkdir -p shell/Sources/MojoShell/App
mkdir -p shell/Sources/MojoShell/Managers
mkdir -p shell/Sources/MojoShell/Router
mkdir -p shell/Sources/MojoShell/LLM
mkdir -p shell/Sources/MojoShell/ComputerUse
mkdir -p shell/Sources/MojoShell/Jobs
mkdir -p shell/Sources/MojoShell/Views
mkdir -p shell/Sources/MojoShell/Models
mkdir -p shell/Tests/MojoShellTests
```

**Step 2: Write `shell/Package.swift`**

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MojoShell",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "MojoShell",
            path: "Sources/MojoShell",
            swiftSettings: [.unsafeFlags(["-Xfrontend", "-disable-reflection-metadata"])]
        ),
        .testTarget(
            name: "MojoShellTests",
            dependencies: ["MojoShell"],
            path: "Tests/MojoShellTests"
        )
    ]
)
```

**Step 3: Write `shell/Sources/MojoShell/App/MojoShellApp.swift`**

```swift
import SwiftUI

@main
struct MojoShellApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 1000, minHeight: 650)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
```

**Step 4: Write `shell/Sources/MojoShell/App/ContentView.swift`**

```swift
import SwiftUI

enum ShellView: String, CaseIterable, Identifiable {
    case cockpit = "Cockpit"
    case terminal = "Agent Terminal"
    case production = "Production"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .cockpit: return "gauge.with.dots.needle.bottom.50percent"
        case .terminal: return "terminal"
        case .production: return "film.stack"
        }
    }
}

struct ContentView: View {
    @State private var selected: ShellView = .cockpit

    var body: some View {
        NavigationSplitView {
            List(ShellView.allCases, selection: $selected) { view in
                Label(view.rawValue, systemImage: view.icon)
                    .tag(view)
            }
            .navigationSplitViewColumnWidth(180)
        } detail: {
            switch selected {
            case .cockpit: Text("Cockpit — coming in Task 7")
            case .terminal: Text("Agent Terminal — coming in Task 8")
            case .production: Text("Production Dashboard — coming in Task 9")
            }
        }
    }
}
```

**Step 5: Write the test scaffold**

```swift
// shell/Tests/MojoShellTests/MojoShellTests.swift
import XCTest

final class MojoShellTests: XCTestCase {
    func testPlaceholder() {
        XCTAssertTrue(true)
    }
}
```

**Step 6: Verify it builds**

```bash
cd shell && swift build 2>&1
```

Expected: `Build complete!`

**Step 7: Commit**

```bash
git add shell/
git commit -m "feat(shell): scaffold SwiftUI SPM package with three-view navigation"
```

---

## Task 2: AppState + DaemonManager

**Files:**
- Create: `shell/Sources/MojoShell/App/AppState.swift`
- Create: `shell/Sources/MojoShell/Managers/DaemonManager.swift`
- Create: `shell/Tests/MojoShellTests/DaemonManagerTests.swift`

**Step 1: Write the failing test**

```swift
// shell/Tests/MojoShellTests/DaemonManagerTests.swift
import XCTest
@testable import MojoShell

final class DaemonManagerTests: XCTestCase {
    func testKnownServersCount() {
        let manager = DaemonManager()
        XCTAssertEqual(manager.serverDefinitions.count, 10)
    }

    func testServerDefinitionsHaveValidPaths() {
        let manager = DaemonManager()
        for server in manager.serverDefinitions {
            XCTAssertFalse(server.name.isEmpty)
            XCTAssertTrue(server.scriptPath.hasSuffix("index.js"),
                "\(server.name) path should end in index.js")
        }
    }
}
```

**Step 2: Run to verify it fails**

```bash
cd shell && swift test --filter DaemonManagerTests 2>&1
```

Expected: `error: cannot find type 'DaemonManager'`

**Step 3: Write `shell/Sources/MojoShell/Managers/DaemonManager.swift`**

```swift
import Foundation
import Combine

struct MCPServerDefinition {
    let name: String
    let scriptPath: String
}

@MainActor
final class DaemonManager: ObservableObject {
    @Published private(set) var runningServers: [String: Process] = [:]

    private let repoRoot: String

    init(repoRoot: String = defaultRepoRoot()) {
        self.repoRoot = repoRoot
    }

    var serverDefinitions: [MCPServerDefinition] {
        let servers = [
            "apple-notes", "apple-messages", "apple-contacts", "apple-reminders",
            "apple-calendar", "apple-maps", "apple-mail", "apple-music",
            "mail-intelligence", "knowledge-corpus"
        ]
        return servers.map { name in
            // Map server names to directory names
            let dir = name == "mail-intelligence" ? "mail-intelligence"
                    : name == "knowledge-corpus" ? "knowledge-corpus"
                    : String(name.dropFirst("apple-".count))
            return MCPServerDefinition(
                name: name,
                scriptPath: "\(repoRoot)/\(dir)/build/index.js"
            )
        }
    }

    func startAll() {
        for definition in serverDefinitions {
            start(definition)
        }
    }

    func stopAll() {
        runningServers.values.forEach { $0.terminate() }
        runningServers.removeAll()
    }

    private func start(_ definition: MCPServerDefinition) {
        guard FileManager.default.fileExists(atPath: definition.scriptPath) else {
            print("[DaemonManager] Missing build artifact: \(definition.scriptPath)")
            return
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["node", definition.scriptPath]
        process.standardInput = Pipe()
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
            runningServers[definition.name] = process
            print("[DaemonManager] Started \(definition.name) (pid \(process.processIdentifier))")
        } catch {
            print("[DaemonManager] Failed to start \(definition.name): \(error)")
        }
    }

    private static func defaultRepoRoot() -> String {
        // Resolve relative to the shell package root at runtime
        let url = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()  // Managers/
            .deletingLastPathComponent()  // MojoShell/
            .deletingLastPathComponent()  // Sources/
            .deletingLastPathComponent()  // shell/
        return url.path
    }
}
```

**Step 4: Write `shell/Sources/MojoShell/App/AppState.swift`**

```swift
import Foundation

@MainActor
final class AppState: ObservableObject {
    let daemons = DaemonManager()

    init() {
        daemons.startAll()
    }

    deinit {
        daemons.stopAll()
    }
}
```

**Step 5: Run tests**

```bash
cd shell && swift test --filter DaemonManagerTests 2>&1
```

Expected: `Test Suite 'DaemonManagerTests' passed`

**Step 6: Commit**

```bash
git add shell/
git commit -m "feat(shell): add DaemonManager that spawns all 10 MCP server processes"
```

---

## Task 3: MCPClient (JSON-RPC over stdio)

**Files:**
- Create: `shell/Sources/MojoShell/Managers/MCPClient.swift`
- Create: `shell/Tests/MojoShellTests/MCPClientTests.swift`

**Step 1: Write the failing test**

```swift
// shell/Tests/MojoShellTests/MCPClientTests.swift
import XCTest
@testable import MojoShell

final class MCPClientTests: XCTestCase {
    func testRequestSerialization() throws {
        let request = MCPRequest(id: 1, method: "tools/list", params: [:])
        let data = try JSONEncoder().encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json["jsonrpc"] as? String, "2.0")
        XCTAssertEqual(json["method"] as? String, "tools/list")
    }

    func testResponseParsing() throws {
        let json = """
        {"jsonrpc":"2.0","id":1,"result":{"tools":[{"name":"list_notes","description":"List notes"}]}}
        """.data(using: .utf8)!
        let response = try JSONDecoder().decode(MCPResponse.self, from: json)
        XCTAssertNil(response.error)
        XCTAssertNotNil(response.result)
    }
}
```

**Step 2: Run to verify it fails**

```bash
cd shell && swift test --filter MCPClientTests 2>&1
```

Expected: `error: cannot find type 'MCPRequest'`

**Step 3: Write `shell/Sources/MojoShell/Managers/MCPClient.swift`**

```swift
import Foundation

// MARK: - JSON-RPC wire types

struct MCPRequest: Encodable {
    let jsonrpc = "2.0"
    let id: Int
    let method: String
    let params: [String: AnyCodable]
}

struct MCPResponse: Decodable {
    let jsonrpc: String
    let id: Int?
    let result: MCPResult?
    let error: MCPError?
}

struct MCPResult: Decodable {
    let tools: [MCPTool]?
    let content: [MCPContent]?
}

struct MCPTool: Decodable {
    let name: String
    let description: String
}

struct MCPContent: Decodable {
    let type: String
    let text: String?
}

struct MCPError: Decodable {
    let code: Int
    let message: String
}

// MARK: - Client

actor MCPClient {
    private let process: Process
    private let stdin: Pipe
    private let stdout: Pipe
    private var pendingRequests: [Int: CheckedContinuation<MCPResponse, Error>] = [:]
    private var nextId = 1

    init(process: Process) {
        self.process = process
        self.stdin = process.standardInput as! Pipe
        self.stdout = process.standardOutput as! Pipe
    }

    func callTool(name: String, arguments: [String: AnyCodable] = [:]) async throws -> MCPResponse {
        let id = nextId
        nextId += 1
        let request = MCPRequest(
            id: id,
            method: "tools/call",
            params: ["name": .string(name), "arguments": .object(arguments)]
        )
        let line = try JSONEncoder().encode(request)
        var lineWithNewline = line
        lineWithNewline.append(0x0A)
        stdin.fileHandleForWriting.write(lineWithNewline)

        return try await withCheckedThrowingContinuation { continuation in
            Task { await self.registerContinuation(id: id, continuation: continuation) }
        }
    }

    private func registerContinuation(id: Int, continuation: CheckedContinuation<MCPResponse, Error>) {
        pendingRequests[id] = continuation
        // Simple synchronous read — sufficient for Phase 1 sequential tool calls
        if let data = try? stdout.fileHandleForReading.availableData,
           !data.isEmpty,
           let response = try? JSONDecoder().decode(MCPResponse.self, from: data) {
            pendingRequests.removeValue(forKey: id)?.resume(returning: response)
        }
    }
}

// MARK: - AnyCodable helper (minimal)

enum AnyCodable: Codable {
    case string(String)
    case int(Int)
    case bool(Bool)
    case object([String: AnyCodable])
    case array([AnyCodable])
    case null

    static func string(_ v: String) -> AnyCodable { .string(v) }

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let v = try? c.decode(String.self) { self = .string(v); return }
        if let v = try? c.decode(Int.self) { self = .int(v); return }
        if let v = try? c.decode(Bool.self) { self = .bool(v); return }
        self = .null
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let v): try c.encode(v)
        case .int(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }
}
```

**Step 4: Run tests**

```bash
cd shell && swift test --filter MCPClientTests 2>&1
```

Expected: `Test Suite 'MCPClientTests' passed`

**Step 5: Commit**

```bash
git add shell/
git commit -m "feat(shell): add MCPClient JSON-RPC layer for stdio communication with MCP servers"
```

---

## Task 4: Intent Model + Deterministic Router

**Files:**
- Create: `shell/Sources/MojoShell/Router/Intent.swift`
- Create: `shell/Sources/MojoShell/Router/DeterministicRouter.swift`
- Create: `shell/Tests/MojoShellTests/DeterministicRouterTests.swift`

**Step 1: Write the failing test**

```swift
// shell/Tests/MojoShellTests/DeterministicRouterTests.swift
import XCTest
@testable import MojoShell

final class DeterministicRouterTests: XCTestCase {
    let router = DeterministicRouter()

    func testScanInboxesIntent() {
        let result = router.route("scan today's inboxes")
        XCTAssertEqual(result?.server, "mail-intelligence")
        XCTAssertEqual(result?.tool, "scan_persona_inboxes")
    }

    func testPauseMusicIntent() {
        let result = router.route("pause the music")
        XCTAssertEqual(result?.server, "apple-music")
        XCTAssertEqual(result?.tool, "pause")
    }

    func testFCPIntent() {
        // FCP has no MCP tool — should return nil so router escalates to LLM + computer use
        let result = router.route("export the current FCP timeline")
        XCTAssertNil(result)
    }

    func testUnknownReturnsNil() {
        let result = router.route("zxqwerty something unknown")
        XCTAssertNil(result)
    }
}
```

**Step 2: Run to verify it fails**

```bash
cd shell && swift test --filter DeterministicRouterTests 2>&1
```

Expected: `error: cannot find type 'DeterministicRouter'`

**Step 3: Write `shell/Sources/MojoShell/Router/Intent.swift`**

```swift
import Foundation

struct ResolvedTool {
    let server: String
    let tool: String
    let arguments: [String: String]
}

struct Intent {
    let raw: String
    let resolved: ResolvedTool?
}
```

**Step 4: Write `shell/Sources/MojoShell/Router/DeterministicRouter.swift`**

```swift
import Foundation

struct DeterministicRouter {
    private struct Rule {
        let keywords: [String]
        let server: String
        let tool: String
    }

    private let rules: [Rule] = [
        // mail-intelligence
        Rule(keywords: ["scan", "inbox", "inboxes", "daily intel", "brief"], server: "mail-intelligence", tool: "scan_persona_inboxes"),
        Rule(keywords: ["persona map", "persona"], server: "mail-intelligence", tool: "get_persona_map"),
        Rule(keywords: ["signal trend", "trends"], server: "mail-intelligence", tool: "analyze_signal_trends"),
        Rule(keywords: ["daily brief", "generate brief"], server: "mail-intelligence", tool: "generate_daily_brief"),
        // apple-music
        Rule(keywords: ["pause", "stop music"], server: "apple-music", tool: "pause"),
        Rule(keywords: ["play music", "resume music", "unpause"], server: "apple-music", tool: "play"),
        Rule(keywords: ["next track", "next song", "skip"], server: "apple-music", tool: "next_track"),
        Rule(keywords: ["previous track", "previous song"], server: "apple-music", tool: "previous_track"),
        Rule(keywords: ["now playing", "what's playing", "current track"], server: "apple-music", tool: "now_playing"),
        Rule(keywords: ["volume"], server: "apple-music", tool: "set_volume"),
        // apple-notes
        Rule(keywords: ["create note", "new note"], server: "apple-notes", tool: "create_note"),
        Rule(keywords: ["search notes", "find note"], server: "apple-notes", tool: "search_notes"),
        Rule(keywords: ["list notes"], server: "apple-notes", tool: "list_notes"),
        // apple-calendar
        Rule(keywords: ["today's events", "what's on", "calendar today", "my schedule"], server: "apple-calendar", tool: "list_all_events"),
        Rule(keywords: ["create event", "new event", "schedule meeting"], server: "apple-calendar", tool: "create_event"),
        // apple-reminders
        Rule(keywords: ["remind me", "add reminder", "create reminder"], server: "apple-reminders", tool: "create_reminder"),
        Rule(keywords: ["my reminders", "list reminders"], server: "apple-reminders", tool: "list_reminders"),
        // knowledge-corpus
        Rule(keywords: ["brain", "corpus", "persona rules", "operator rules"], server: "knowledge-corpus", tool: "get_persona_map"),
    ]

    func route(_ input: String) -> ResolvedTool? {
        let lowered = input.lowercased()
        for rule in rules {
            if rule.keywords.contains(where: { lowered.contains($0) }) {
                return ResolvedTool(server: rule.server, tool: rule.tool, arguments: [:])
            }
        }
        return nil
    }
}
```

**Step 5: Run tests**

```bash
cd shell && swift test --filter DeterministicRouterTests 2>&1
```

Expected: `Test Suite 'DeterministicRouterTests' passed`

**Step 6: Commit**

```bash
git add shell/
git commit -m "feat(shell): add Intent model and DeterministicRouter with keyword rules for all 10 MCP servers"
```

---

## Task 5: LLM Provider (Claude primary, OpenAI fallback)

**Files:**
- Create: `shell/Sources/MojoShell/LLM/LLMProvider.swift`
- Create: `shell/Sources/MojoShell/LLM/ClaudeProvider.swift`
- Create: `shell/Tests/MojoShellTests/LLMProviderTests.swift`

**Step 1: Write the failing test**

```swift
// shell/Tests/MojoShellTests/LLMProviderTests.swift
import XCTest
@testable import MojoShell

final class LLMProviderTests: XCTestCase {
    func testClaudeProviderName() {
        let provider = ClaudeProvider(apiKey: "test-key")
        XCTAssertEqual(provider.name, "claude")
    }

    func testRequestBuildsCorrectURL() throws {
        let provider = ClaudeProvider(apiKey: "test-key")
        let request = try provider.buildURLRequest(prompt: "scan my inbox", tools: [])
        XCTAssertEqual(request.url?.host, "api.anthropic.com")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertNotNil(request.value(forHTTPHeaderField: "x-api-key"))
    }
}
```

**Step 2: Run to verify it fails**

```bash
cd shell && swift test --filter LLMProviderTests 2>&1
```

Expected: `error: cannot find type 'ClaudeProvider'`

**Step 3: Write `shell/Sources/MojoShell/LLM/LLMProvider.swift`**

```swift
import Foundation

struct LLMToolDefinition {
    let name: String
    let description: String
    let server: String
}

struct LLMResponse {
    let text: String
    let resolvedTool: ResolvedTool?
}

protocol LLMProvider {
    var name: String { get }
    func resolve(prompt: String, availableTools: [LLMToolDefinition]) async throws -> LLMResponse
    func buildURLRequest(prompt: String, tools: [LLMToolDefinition]) throws -> URLRequest
}
```

**Step 4: Write `shell/Sources/MojoShell/LLM/ClaudeProvider.swift`**

```swift
import Foundation

struct ClaudeProvider: LLMProvider {
    let name = "claude"
    private let apiKey: String
    private let model = "claude-sonnet-4-6"
    private let baseURL = URL(string: "https://api.anthropic.com/v1/messages")!

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    func buildURLRequest(prompt: String, tools: [LLMToolDefinition]) throws -> URLRequest {
        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        let toolSchemas = tools.map { tool -> [String: Any] in
            ["name": tool.name,
             "description": tool.description,
             "input_schema": ["type": "object", "properties": [:]] as [String: Any]]
        }

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 1024,
            "system": """
                You are the MojoShell agent router. Given a user command, decide which MCP tool to call.
                Return a JSON object: {"tool": "<tool_name>", "server": "<server_name>", "arguments": {}}.
                If no tool applies, return {"text": "<plain response>"}.
                """,
            "messages": [["role": "user", "content": prompt]],
            "tools": toolSchemas
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    func resolve(prompt: String, availableTools: [LLMToolDefinition]) async throws -> LLMResponse {
        let request = try buildURLRequest(prompt: prompt, tools: availableTools)
        let (data, _) = try await URLSession.shared.data(for: request)

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = (json["content"] as? [[String: Any]])?.first,
              let text = content["text"] as? String else {
            return LLMResponse(text: "No response", resolvedTool: nil)
        }

        // Try to parse tool call from response text
        if let jsonData = text.data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
           let toolName = parsed["tool"] as? String,
           let serverName = parsed["server"] as? String {
            return LLMResponse(
                text: text,
                resolvedTool: ResolvedTool(server: serverName, tool: toolName, arguments: [:])
            )
        }

        return LLMResponse(text: text, resolvedTool: nil)
    }
}
```

**Step 5: Run tests**

```bash
cd shell && swift test --filter LLMProviderTests 2>&1
```

Expected: `Test Suite 'LLMProviderTests' passed`

**Step 6: Commit**

```bash
git add shell/
git commit -m "feat(shell): add LLMProvider protocol + ClaudeProvider (claude-sonnet-4-6 primary)"
```

---

## Task 6: ComputerUseProvider Protocol + Stub

**Files:**
- Create: `shell/Sources/MojoShell/ComputerUse/ComputerUseProvider.swift`
- Create: `shell/Sources/MojoShell/ComputerUse/StubComputerUseProvider.swift`
- Create: `shell/Tests/MojoShellTests/ComputerUseProviderTests.swift`

**Step 1: Write the failing test**

```swift
// shell/Tests/MojoShellTests/ComputerUseProviderTests.swift
import XCTest
@testable import MojoShell

final class ComputerUseProviderTests: XCTestCase {
    func testStubStartsSession() async throws {
        let provider = StubComputerUseProvider()
        let sessionId = try await provider.startSession()
        XCTAssertFalse(sessionId.isEmpty)
    }

    func testStubCapturesState() async throws {
        let provider = StubComputerUseProvider()
        let sessionId = try await provider.startSession()
        let state = try await provider.captureState(sessionId: sessionId)
        XCTAssertEqual(state.appName, "stub")
    }

    func testStubExecutesAction() async throws {
        let provider = StubComputerUseProvider()
        let sessionId = try await provider.startSession()
        let result = try await provider.execute(
            sessionId: sessionId,
            action: ComputerUseAction(type: .click, target: "Export Button")
        )
        XCTAssertTrue(result.success)
    }
}
```

**Step 2: Run to verify it fails**

```bash
cd shell && swift test --filter ComputerUseProviderTests 2>&1
```

Expected: `error: cannot find type 'ComputerUseProvider'`

**Step 3: Write `shell/Sources/MojoShell/ComputerUse/ComputerUseProvider.swift`**

```swift
import Foundation

struct ComputerUseState {
    let appName: String
    let screenshotData: Data?
    let timestamp: Date
}

enum ComputerUseActionType: String {
    case click, type, keypress, scroll, drag
}

struct ComputerUseAction {
    let type: ComputerUseActionType
    let target: String
    let value: String?

    init(type: ComputerUseActionType, target: String, value: String? = nil) {
        self.type = type
        self.target = target
        self.value = value
    }
}

struct ComputerUseResult {
    let success: Bool
    let message: String
    let screenshotAfter: Data?
}

protocol ComputerUseProvider {
    var name: String { get }
    func startSession() async throws -> String
    func captureState(sessionId: String) async throws -> ComputerUseState
    func execute(sessionId: String, action: ComputerUseAction) async throws -> ComputerUseResult
    func stopSession(sessionId: String) async throws
}
```

**Step 4: Write `shell/Sources/MojoShell/ComputerUse/StubComputerUseProvider.swift`**

```swift
import Foundation

/// Stub implementation used in Phase 1 before CUA is wired.
/// Logs all actions and returns success without performing real UI automation.
final class StubComputerUseProvider: ComputerUseProvider {
    let name = "stub"
    private var sessions: Set<String> = []

    func startSession() async throws -> String {
        let id = UUID().uuidString
        sessions.insert(id)
        print("[StubCU] Session started: \(id)")
        return id
    }

    func captureState(sessionId: String) async throws -> ComputerUseState {
        return ComputerUseState(appName: "stub", screenshotData: nil, timestamp: Date())
    }

    func execute(sessionId: String, action: ComputerUseAction) async throws -> ComputerUseResult {
        print("[StubCU] \(action.type.rawValue) → \(action.target) (session: \(sessionId))")
        return ComputerUseResult(success: true, message: "Stub executed: \(action.type.rawValue)", screenshotAfter: nil)
    }

    func stopSession(sessionId: String) async throws {
        sessions.remove(sessionId)
        print("[StubCU] Session stopped: \(sessionId)")
    }
}
```

**Step 5: Run tests**

```bash
cd shell && swift test --filter ComputerUseProviderTests 2>&1
```

Expected: `Test Suite 'ComputerUseProviderTests' passed`

**Step 6: Commit**

```bash
git add shell/
git commit -m "feat(shell): add ComputerUseProvider protocol and StubComputerUseProvider for FCP/Motion seam"
```

---

## Task 7: Cockpit View

**Files:**
- Create: `shell/Sources/MojoShell/Views/CockpitView.swift`
- Modify: `shell/Sources/MojoShell/App/ContentView.swift` (replace cockpit placeholder)

**Step 1: Write `shell/Sources/MojoShell/Views/CockpitView.swift`**

```swift
import SwiftUI

struct CockpitView: View {
    @EnvironmentObject var appState: AppState
    @State private var scanResult: String = "Tap Scan to load Daily Intel"
    @State private var isScanning = false

    var body: some View {
        HSplitView {
            // Left: Inbox intelligence
            VStack(alignment: .leading, spacing: 12) {
                Label("Inbox Intelligence", systemImage: "envelope.badge.shield.half.filled")
                    .font(.headline)
                Divider()
                ScrollView {
                    Text(scanResult)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Button(isScanning ? "Scanning…" : "Scan Inboxes") {
                    Task { await scanInboxes() }
                }
                .disabled(isScanning)
            }
            .padding()
            .frame(minWidth: 320)

            // Right: Calendar + Music
            VStack(alignment: .leading, spacing: 12) {
                Label("Active Servers", systemImage: "server.rack")
                    .font(.headline)
                Divider()
                ForEach(Array(appState.daemons.runningServers.keys.sorted()), id: \.self) { name in
                    HStack {
                        Circle().fill(.green).frame(width: 8, height: 8)
                        Text(name).font(.system(.body, design: .monospaced))
                    }
                }
                Spacer()
            }
            .padding()
            .frame(minWidth: 220)
        }
        .navigationTitle("Cockpit")
    }

    private func scanInboxes() async {
        isScanning = true
        scanResult = "Scanning…"
        // Phase 1: call mail-intelligence scan_persona_inboxes via DaemonManager
        // Full wiring in Task 3 integration — placeholder for now
        try? await Task.sleep(nanoseconds: 800_000_000)
        scanResult = "Scan complete — wire MCPClient in Task 3 integration step"
        isScanning = false
    }
}
```

**Step 2: Update ContentView to use real view**

Replace the `case .cockpit:` line in `ContentView.swift`:

```swift
case .cockpit: CockpitView()
```

**Step 3: Build**

```bash
cd shell && swift build 2>&1
```

Expected: `Build complete!`

**Step 4: Commit**

```bash
git add shell/
git commit -m "feat(shell): add CockpitView with inbox scan trigger and daemon status panel"
```

---

## Task 8: Agent Terminal View

**Files:**
- Create: `shell/Sources/MojoShell/Views/AgentTerminalView.swift`
- Modify: `shell/Sources/MojoShell/App/ContentView.swift` (replace terminal placeholder)

**Step 1: Write `shell/Sources/MojoShell/Views/AgentTerminalView.swift`**

```swift
import SwiftUI

struct TerminalEntry: Identifiable {
    let id = UUID()
    let role: Role
    let text: String
    let timestamp = Date()

    enum Role { case user, agent, system }
}

struct AgentTerminalView: View {
    @State private var input = ""
    @State private var history: [TerminalEntry] = [
        TerminalEntry(role: .system, text: "MojoShell Agent Terminal ready. Type a command.")
    ]
    @State private var isProcessing = false

    private let deterministicRouter = DeterministicRouter()

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(history) { entry in
                            TerminalEntryRow(entry: entry)
                                .id(entry.id)
                        }
                    }
                    .padding()
                }
                .onChange(of: history.count) { _ in
                    proxy.scrollTo(history.last?.id)
                }
            }

            Divider()

            HStack {
                TextField("Type a command…", text: $input)
                    .font(.system(.body, design: .monospaced))
                    .textFieldStyle(.plain)
                    .onSubmit { Task { await submit() } }
                    .disabled(isProcessing)

                Button(isProcessing ? "…" : "↵") {
                    Task { await submit() }
                }
                .disabled(input.isEmpty || isProcessing)
                .keyboardShortcut(.return, modifiers: [])
            }
            .padding(10)
            .background(.background)
        }
        .navigationTitle("Agent Terminal")
    }

    private func submit() async {
        let command = input.trimmingCharacters(in: .whitespaces)
        guard !command.isEmpty else { return }
        input = ""
        isProcessing = true
        history.append(TerminalEntry(role: .user, text: command))

        if let tool = deterministicRouter.route(command) {
            history.append(TerminalEntry(role: .system,
                text: "→ deterministic route: \(tool.server)/\(tool.tool)"))
            // Phase 1: log route; full MCP execution wired in integration step
            history.append(TerminalEntry(role: .agent,
                text: "Routed to \(tool.tool) on \(tool.server). MCP call pending integration."))
        } else {
            history.append(TerminalEntry(role: .system, text: "→ escalating to Claude…"))
            history.append(TerminalEntry(role: .agent,
                text: "LLM routing not yet wired. Add ANTHROPIC_API_KEY env var and connect ClaudeProvider."))
        }
        isProcessing = false
    }
}

struct TerminalEntryRow: View {
    let entry: TerminalEntry

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(prefix)
                .foregroundStyle(color)
                .font(.system(.body, design: .monospaced))
                .frame(width: 60, alignment: .trailing)
            Text(entry.text)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
        }
    }

    private var prefix: String {
        switch entry.role {
        case .user: return "you"
        case .agent: return "agent"
        case .system: return "sys"
        }
    }

    private var color: Color {
        switch entry.role {
        case .user: return .primary
        case .agent: return .blue
        case .system: return .secondary
        }
    }
}
```

**Step 2: Update ContentView**

Replace `case .terminal:` line:

```swift
case .terminal: AgentTerminalView()
```

**Step 3: Build and verify**

```bash
cd shell && swift build 2>&1
```

Expected: `Build complete!`

**Step 4: Commit**

```bash
git add shell/
git commit -m "feat(shell): add AgentTerminalView with deterministic routing display and LLM escalation stub"
```

---

## Task 9: Production Dashboard View

**Files:**
- Create: `shell/Sources/MojoShell/Jobs/MediaJob.swift`
- Create: `shell/Sources/MojoShell/Views/ProductionDashboardView.swift`
- Modify: `shell/Sources/MojoShell/App/ContentView.swift`

**Step 1: Write `shell/Sources/MojoShell/Jobs/MediaJob.swift`**

```swift
import Foundation

enum MediaJobStatus: String {
    case queued, running, completed, failed
}

struct MediaJob: Identifiable {
    let id = UUID()
    let name: String
    let client: String
    var status: MediaJobStatus
    var progress: Double  // 0.0 – 1.0
    let createdAt: Date
    var completedAt: Date?
    var errorMessage: String?
}
```

**Step 2: Write `shell/Sources/MojoShell/Views/ProductionDashboardView.swift`**

```swift
import SwiftUI

struct ProductionDashboardView: View {
    @State private var jobs: [MediaJob] = [
        MediaJob(name: "Appalachian Community FCU — Benefits Overview",
                 client: "ElanPresentation", status: .completed, progress: 1.0,
                 createdAt: Date().addingTimeInterval(-3600), completedAt: Date()),
        MediaJob(name: "FedChoice FCU — Enrollment Video",
                 client: "ElanPresentation", status: .running, progress: 0.62,
                 createdAt: Date().addingTimeInterval(-600)),
        MediaJob(name: "Credit Union 1 — Annual Benefits",
                 client: "ElanPresentation", status: .queued, progress: 0,
                 createdAt: Date()),
    ]

    var body: some View {
        HSplitView {
            // Job queue
            VStack(alignment: .leading, spacing: 0) {
                Label("Job Queue", systemImage: "list.bullet.rectangle")
                    .font(.headline)
                    .padding()
                Divider()
                List(jobs) { job in
                    JobRow(job: job)
                }
            }
            .frame(minWidth: 340)

            // FCP status panel
            VStack(alignment: .leading, spacing: 12) {
                Label("FCP / Motion", systemImage: "film.stack")
                    .font(.headline)
                Divider()
                Text("Computer-use provider: Stub")
                    .foregroundStyle(.secondary)
                Text("Real FCP control wired in Task 10 (CuaComputerUseProvider).")
                    .foregroundStyle(.secondary)
                    .font(.callout)
                Spacer()
                Button("Run Assembly Workflow (Stub)") {
                    runAssemblyWorkflow()
                }
            }
            .padding()
            .frame(minWidth: 260)
        }
        .navigationTitle("Production")
    }

    private func runAssemblyWorkflow() {
        print("[Dashboard] Assembly workflow triggered — stub provider active")
    }
}

struct JobRow: View {
    let job: MediaJob

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Circle().fill(statusColor).frame(width: 8, height: 8)
                Text(job.name).bold()
                Spacer()
                Text(job.status.rawValue.capitalized)
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            if job.status == .running {
                ProgressView(value: job.progress)
            }
            Text(job.client)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var statusColor: Color {
        switch job.status {
        case .queued: return .gray
        case .running: return .blue
        case .completed: return .green
        case .failed: return .red
        }
    }
}
```

**Step 3: Update ContentView**

Replace `case .production:` line:

```swift
case .production: ProductionDashboardView()
```

**Step 4: Build**

```bash
cd shell && swift build 2>&1
```

Expected: `Build complete!`

**Step 5: Commit**

```bash
git add shell/
git commit -m "feat(shell): add ProductionDashboardView with job queue, ElanPresentation jobs, and FCP stub panel"
```

---

## Task 10: Wire Full Test Suite + Final Build Verification

**Files:**
- Run: all tests
- Verify: complete build

**Step 1: Run all tests**

```bash
cd shell && swift test 2>&1
```

Expected: All test suites pass (`DaemonManagerTests`, `MCPClientTests`, `DeterministicRouterTests`, `LLMProviderTests`, `ComputerUseProviderTests`).

**Step 2: Build in release mode**

```bash
cd shell && swift build -c release 2>&1
```

Expected: `Build complete!`

**Step 3: Verify binary runs**

```bash
cd shell && .build/release/MojoShell &
sleep 2
kill %1
```

Expected: App launches (window appears), no crash.

**Step 4: Final commit**

```bash
git add shell/
git commit -m "feat(shell): complete Phase 1 foundation — all views, router, daemon manager, CU seam, tests passing

- SwiftUI shell with Cockpit, Agent Terminal, Production Dashboard
- DaemonManager supervises all 10 MCP server processes
- MCPClient handles JSON-RPC over stdio
- DeterministicRouter routes known commands without LLM
- ClaudeProvider ready for ambiguous intent resolution
- ComputerUseProvider protocol isolates FCP/Motion control
- StubComputerUseProvider logs actions for Phase 1
- MediaJob model + job queue UI for ElanPresentation workflows
- CuaComputerUseProvider integration deferred to Phase 2"
```

---

## Next Phase (Phase 2 Preview)

- **Task 11:** `CuaComputerUseProvider` — real screen capture + input via `trycua/cua`
- **Task 12:** FCP assembly workflow — clip ingestion → timeline template → export trigger
- **Task 13:** FCP/Motion monitoring — render queue polling, export alerts
- **Task 14:** Claude LLM integration — wire `ClaudeProvider` to `AgentTerminalView` with real API calls
- **Task 15:** Brain connector — load `mojosolo_operating_brain.json` into `CockpitView` for persona-aware summaries
