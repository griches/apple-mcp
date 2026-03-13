import Combine
import Foundation

struct MCPServerDefinition: Equatable {
    let name: String
    let directoryPath: String
    let scriptPath: String

    var packagePath: String {
        "\(directoryPath)/package.json"
    }

    var buildCommand: [String] {
        ["npm", "run", "build"]
    }

    var buildCommandDescription: String {
        buildCommand.joined(separator: " ")
    }
}

enum DaemonRuntimeStatus: String, Equatable {
    case notBuilt
    case stopped
    case starting
    case running
    case failed
}

struct DaemonRuntimeState: Identifiable, Equatable {
    let id: String
    let serverName: String
    let scriptPath: String
    let status: DaemonRuntimeStatus
    let pid: Int32?
    let lastError: String?
    let logPath: String
    let updatedAt: Date

    init(
        serverName: String,
        scriptPath: String,
        status: DaemonRuntimeStatus,
        pid: Int32? = nil,
        lastError: String? = nil,
        logPath: String,
        updatedAt: Date = Date()
    ) {
        self.id = serverName
        self.serverName = serverName
        self.scriptPath = scriptPath
        self.status = status
        self.pid = pid
        self.lastError = lastError
        self.logPath = logPath
        self.updatedAt = updatedAt
    }
}

@MainActor
final class DaemonManager: ObservableObject {
    @Published private(set) var runningServers: [String: Process] = [:]
    @Published private(set) var runtimeStates: [String: DaemonRuntimeState] = [:]
    @Published private(set) var buildStates: [String: DaemonBuildState] = [:]
    @Published private(set) var runtimeLogSnippets: [String: String] = [:]

    let repoRoot: String
    private let logStore: DaemonLogStore
    private let brainPathProvider: @MainActor () -> String?
    private let onRuntimeStateChanged: @MainActor (DaemonRuntimeState?, DaemonRuntimeState) -> Void
    private let buildOperation: @Sendable (MCPServerDefinition) async throws -> DaemonBuildResult

    init(
        repoRoot: String = DaemonManager.defaultRepoRoot(),
        logStore: DaemonLogStore = DaemonLogStore(),
        brainPathProvider: @escaping @MainActor () -> String? = { nil },
        onRuntimeStateChanged: @escaping @MainActor (DaemonRuntimeState?, DaemonRuntimeState) -> Void = { _, _ in },
        buildOperation: (@Sendable (MCPServerDefinition) async throws -> DaemonBuildResult)? = nil
    ) {
        self.repoRoot = repoRoot
        self.logStore = logStore
        self.brainPathProvider = brainPathProvider
        self.onRuntimeStateChanged = onRuntimeStateChanged
        self.buildOperation = buildOperation ?? DaemonManager.defaultBuildOperation
        refreshRuntimeStates()
    }

    var serverDefinitions: [MCPServerDefinition] {
        let mapping: [(name: String, directory: String)] = [
            ("apple-notes", "notes"),
            ("apple-messages", "messages"),
            ("apple-contacts", "contacts"),
            ("apple-reminders", "reminders"),
            ("apple-calendar", "calendar"),
            ("apple-maps", "maps"),
            ("apple-mail", "mail"),
            ("apple-music", "music"),
            ("mail-intelligence", "mail-intelligence"),
            ("knowledge-corpus", "knowledge-corpus"),
        ]

        return mapping.map { entry in
            let directoryPath = "\(repoRoot)/\(entry.directory)"
            return MCPServerDefinition(
                name: entry.name,
                directoryPath: directoryPath,
                scriptPath: "\(directoryPath)/build/index.js"
            )
        }
    }

    var allRuntimeStates: [DaemonRuntimeState] {
        serverDefinitions
            .map { runtimeStates[$0.name] ?? defaultRuntimeState(for: $0) }
            .sorted { $0.serverName < $1.serverName }
    }

    var allBuildStates: [DaemonBuildState] {
        serverDefinitions
            .map { buildStates[$0.name] ?? defaultBuildState(for: $0) }
            .sorted { $0.serverName < $1.serverName }
    }

    func startAll() {
        for definition in serverDefinitions {
            start(definition)
        }
    }

    func stopAll() {
        for definition in serverDefinitions {
            stop(serverName: definition.name)
        }
    }

    func stop(serverName: String) {
        guard let definition = serverDefinitions.first(where: { $0.name == serverName }) else {
            return
        }

        appendRuntimeLog("Stopping \(serverName)\n", serverName: serverName)

        if let process = runningServers[serverName], process.isRunning {
            if let stderr = process.standardError as? Pipe {
                stderr.fileHandleForReading.readabilityHandler = nil
            }
            process.terminate()
        }
        runningServers.removeValue(forKey: serverName)

        let artifactExists = FileManager.default.fileExists(atPath: definition.scriptPath)
        setRuntimeState(
            for: definition,
            status: artifactExists ? .stopped : .notBuilt,
            pid: nil,
            lastError: artifactExists ? nil : "Missing build artifact"
        )
    }

    func restart(serverName: String) {
        stop(serverName: serverName)
        guard let definition = serverDefinitions.first(where: { $0.name == serverName }) else {
            return
        }
        start(definition)
    }

    func restartAll() {
        for definition in serverDefinitions {
            restart(serverName: definition.name)
        }
    }

    func build(serverName: String) async {
        guard let definition = serverDefinitions.first(where: { $0.name == serverName }) else {
            return
        }

        let previous = buildStates[definition.name] ?? defaultBuildState(for: definition)
        guard previous.status != .building else {
            return
        }

        do {
            try logStore.reset(serverName: definition.name, kind: .build)
        } catch {
            // Best effort only.
        }

        let startedAt = Date()
        setBuildState(
            DaemonBuildState(
                serverName: definition.name,
                status: .building,
                command: definition.buildCommandDescription,
                logPath: logStore.logURL(for: definition.name, kind: .build).path,
                lastOutput: "Building \(definition.name)...",
                startedAt: startedAt,
                finishedAt: nil,
                lastExitCode: nil
            )
        )
        appendBuildLog("$ \(definition.buildCommandDescription)\n", serverName: definition.name)

        do {
            let result = try await buildOperation(definition)
            appendBuildLog(result.output, serverName: definition.name)

            let artifactExists = FileManager.default.fileExists(atPath: definition.scriptPath)
            let finishedAt = Date()
            if result.exitStatus == 0 && artifactExists {
                setBuildState(
                    DaemonBuildState(
                        serverName: definition.name,
                        status: .succeeded,
                        command: definition.buildCommandDescription,
                        logPath: logStore.logURL(for: definition.name, kind: .build).path,
                        lastOutput: Self.tailSnippet(result.output, fallback: "Build succeeded."),
                        startedAt: startedAt,
                        finishedAt: finishedAt,
                        lastExitCode: result.exitStatus
                    )
                )
            } else {
                let failureOutput = result.exitStatus == 0
                    ? result.output + "\nBuild finished without producing build/index.js."
                    : result.output
                setBuildState(
                    DaemonBuildState(
                        serverName: definition.name,
                        status: .failed,
                        command: definition.buildCommandDescription,
                        logPath: logStore.logURL(for: definition.name, kind: .build).path,
                        lastOutput: Self.tailSnippet(failureOutput, fallback: "Build failed."),
                        startedAt: startedAt,
                        finishedAt: finishedAt,
                        lastExitCode: result.exitStatus == 0 ? 1 : result.exitStatus
                    )
                )
            }
        } catch {
            let finishedAt = Date()
            let message = error.localizedDescription
            appendBuildLog(message + "\n", serverName: definition.name)
            setBuildState(
                DaemonBuildState(
                    serverName: definition.name,
                    status: .failed,
                    command: definition.buildCommandDescription,
                    logPath: logStore.logURL(for: definition.name, kind: .build).path,
                    lastOutput: Self.tailSnippet(message, fallback: "Build failed."),
                    startedAt: startedAt,
                    finishedAt: finishedAt,
                    lastExitCode: 1
                )
            )
        }

        refreshRuntimeStates()
    }

    func buildAll() async {
        for definition in serverDefinitions {
            await build(serverName: definition.name)
        }
    }

    func process(for serverName: String) -> Process? {
        runningServers[serverName]
    }

    func runtimeState(for serverName: String) -> DaemonRuntimeState? {
        runtimeStates[serverName]
    }

    func buildState(for serverName: String) -> DaemonBuildState? {
        buildStates[serverName]
    }

    func recentRuntimeLog(for serverName: String) -> String {
        runtimeLogSnippets[serverName] ?? ""
    }

    func logPath(for serverName: String, kind: DaemonLogKind) -> String {
        logStore.logURL(for: serverName, kind: kind).path
    }

    func ensureProcess(for serverName: String) -> Process? {
        if let existing = runningServers[serverName], existing.isRunning {
            setRuntimeState(
                forName: serverName,
                status: .running,
                pid: existing.processIdentifier,
                lastError: nil
            )
            return existing
        }

        guard let definition = serverDefinitions.first(where: { $0.name == serverName }) else {
            return nil
        }

        start(definition)
        return runningServers[serverName]
    }

    func refreshRuntimeStates() {
        for definition in serverDefinitions {
            let artifactExists = FileManager.default.fileExists(atPath: definition.scriptPath)

            if let process = runningServers[definition.name], process.isRunning {
                setRuntimeState(
                    for: definition,
                    status: .running,
                    pid: process.processIdentifier,
                    lastError: nil
                )
                continue
            }

            runningServers.removeValue(forKey: definition.name)
            setRuntimeState(
                for: definition,
                status: artifactExists ? .stopped : .notBuilt,
                pid: nil,
                lastError: artifactExists ? nil : "Missing build artifact"
            )
        }
    }

    private func start(_ definition: MCPServerDefinition) {
        if let existing = runningServers[definition.name] {
            if existing.isRunning {
                setRuntimeState(
                    for: definition,
                    status: .running,
                    pid: existing.processIdentifier,
                    lastError: nil
                )
                return
            }
            runningServers.removeValue(forKey: definition.name)
        }

        guard FileManager.default.fileExists(atPath: definition.scriptPath) else {
            print("[DaemonManager] Missing build artifact: \(definition.scriptPath)")
            appendRuntimeLog("Missing build artifact: \(definition.scriptPath)\n", serverName: definition.name)
            setRuntimeState(
                for: definition,
                status: .notBuilt,
                pid: nil,
                lastError: "Missing build artifact"
            )
            return
        }

        do {
            try logStore.reset(serverName: definition.name, kind: .runtime)
        } catch {
            // Best effort only.
        }

        appendRuntimeLog("Starting \(definition.name)\n", serverName: definition.name)
        setRuntimeState(for: definition, status: .starting, pid: nil, lastError: nil)

        let process = Process()
        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["node", definition.scriptPath]
        process.environment = processEnvironment()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
        stderr.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                return
            }
            let chunk = String(decoding: data, as: UTF8.self)
            Task { @MainActor [weak self] in
                self?.appendRuntimeLog(chunk, serverName: definition.name)
            }
        }
        process.terminationHandler = { [weak self] process in
            Task { @MainActor in
                guard let self else { return }
                if let stderr = process.standardError as? Pipe {
                    stderr.fileHandleForReading.readabilityHandler = nil
                }
                self.runningServers.removeValue(forKey: definition.name)

                let status: DaemonRuntimeStatus
                let errorMessage: String?
                if process.terminationReason == .exit && process.terminationStatus == 0 {
                    status = .stopped
                    errorMessage = nil
                    self.appendRuntimeLog("Exited cleanly.\n", serverName: definition.name)
                } else {
                    status = .failed
                    errorMessage = "Exited with status \(process.terminationStatus)"
                    self.appendRuntimeLog("Exited with status \(process.terminationStatus).\n", serverName: definition.name)
                }

                self.setRuntimeState(
                    for: definition,
                    status: status,
                    pid: nil,
                    lastError: errorMessage
                )
            }
        }

        do {
            try process.run()
            runningServers[definition.name] = process
            appendRuntimeLog("Started pid \(process.processIdentifier).\n", serverName: definition.name)
            setRuntimeState(
                for: definition,
                status: .running,
                pid: process.processIdentifier,
                lastError: nil
            )
            print("[DaemonManager] Started \(definition.name) (pid \(process.processIdentifier))")
        } catch {
            appendRuntimeLog("Failed to start: \(error.localizedDescription)\n", serverName: definition.name)
            setRuntimeState(
                for: definition,
                status: .failed,
                pid: nil,
                lastError: error.localizedDescription
            )
            print("[DaemonManager] Failed to start \(definition.name): \(error)")
        }
    }

    private func processEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        if let brainPath = brainPathProvider()?.trimmingCharacters(in: .whitespacesAndNewlines), !brainPath.isEmpty {
            environment["BRAIN_PATH"] = brainPath
        }
        return environment
    }

    private func appendRuntimeLog(_ text: String, serverName: String) {
        do {
            try logStore.append(text, serverName: serverName, kind: .runtime)
        } catch {
            // Runtime log capture is best effort only.
        }
        let combined = (runtimeLogSnippets[serverName] ?? "") + text
        runtimeLogSnippets[serverName] = Self.tailSnippet(combined, fallback: "")
    }

    private func appendBuildLog(_ text: String, serverName: String) {
        do {
            try logStore.append(text, serverName: serverName, kind: .build)
        } catch {
            // Build log capture is best effort only.
        }
    }

    private func setBuildState(_ state: DaemonBuildState) {
        buildStates[state.serverName] = state
    }

    private func setRuntimeState(
        for definition: MCPServerDefinition,
        status: DaemonRuntimeStatus,
        pid: Int32?,
        lastError: String?
    ) {
        let previous = runtimeStates[definition.name]
        let next = DaemonRuntimeState(
            serverName: definition.name,
            scriptPath: definition.scriptPath,
            status: status,
            pid: pid,
            lastError: lastError,
            logPath: logStore.logURL(for: definition.name, kind: .runtime).path
        )
        runtimeStates[definition.name] = next

        guard hasMeaningfulChange(from: previous, to: next) else {
            return
        }
        onRuntimeStateChanged(previous, next)
    }

    private func setRuntimeState(
        forName serverName: String,
        status: DaemonRuntimeStatus,
        pid: Int32?,
        lastError: String?
    ) {
        guard let definition = serverDefinitions.first(where: { $0.name == serverName }) else {
            return
        }
        setRuntimeState(for: definition, status: status, pid: pid, lastError: lastError)
    }

    private func defaultRuntimeState(for definition: MCPServerDefinition) -> DaemonRuntimeState {
        let artifactExists = FileManager.default.fileExists(atPath: definition.scriptPath)
        return DaemonRuntimeState(
            serverName: definition.name,
            scriptPath: definition.scriptPath,
            status: artifactExists ? .stopped : .notBuilt,
            pid: nil,
            lastError: artifactExists ? nil : "Missing build artifact",
            logPath: logStore.logURL(for: definition.name, kind: .runtime).path
        )
    }

    private func defaultBuildState(for definition: MCPServerDefinition) -> DaemonBuildState {
        DaemonBuildState(
            serverName: definition.name,
            status: .idle,
            command: definition.buildCommandDescription,
            logPath: logStore.logURL(for: definition.name, kind: .build).path,
            lastOutput: "No build run recorded yet."
        )
    }

    static func defaultRepoRoot() -> String {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .path
    }

    private func hasMeaningfulChange(from previous: DaemonRuntimeState?, to next: DaemonRuntimeState) -> Bool {
        guard let previous else {
            return true
        }

        return previous.status != next.status
            || previous.pid != next.pid
            || previous.lastError != next.lastError
    }

    private static func tailSnippet(_ text: String, fallback: String) -> String {
        let lines = text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .suffix(8)
            .map(String.init)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return lines.isEmpty ? fallback : lines
    }

    private static func defaultBuildOperation(_ definition: MCPServerDefinition) async throws -> DaemonBuildResult {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let stdout = Pipe()
                let stderr = Pipe()

                process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                process.arguments = definition.buildCommand
                process.currentDirectoryURL = URL(fileURLWithPath: definition.directoryPath)
                process.standardOutput = stdout
                process.standardError = stderr

                do {
                    try process.run()
                    process.waitUntilExit()

                    let stdoutData = stdout.fileHandleForReading.readDataToEndOfFile()
                    let stderrData = stderr.fileHandleForReading.readDataToEndOfFile()
                    let stdoutText = String(decoding: stdoutData, as: UTF8.self)
                    let stderrText = String(decoding: stderrData, as: UTF8.self)
                    let combined = [stdoutText, stderrText]
                        .filter { !$0.isEmpty }
                        .joined(separator: stdoutText.isEmpty || stderrText.isEmpty ? "" : "\n")

                    continuation.resume(
                        returning: DaemonBuildResult(
                            output: combined,
                            exitStatus: process.terminationStatus
                        )
                    )
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
