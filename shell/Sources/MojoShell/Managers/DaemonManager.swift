import Combine
import Foundation

struct MCPServerDefinition: Equatable {
    let name: String
    let scriptPath: String
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
    let updatedAt: Date

    init(
        serverName: String,
        scriptPath: String,
        status: DaemonRuntimeStatus,
        pid: Int32? = nil,
        lastError: String? = nil,
        updatedAt: Date = Date()
    ) {
        self.id = serverName
        self.serverName = serverName
        self.scriptPath = scriptPath
        self.status = status
        self.pid = pid
        self.lastError = lastError
        self.updatedAt = updatedAt
    }
}

@MainActor
final class DaemonManager: ObservableObject {
    @Published private(set) var runningServers: [String: Process] = [:]
    @Published private(set) var runtimeStates: [String: DaemonRuntimeState] = [:]

    let repoRoot: String
    private let onRuntimeStateChanged: @MainActor (DaemonRuntimeState?, DaemonRuntimeState) -> Void

    init(
        repoRoot: String = DaemonManager.defaultRepoRoot(),
        onRuntimeStateChanged: @escaping @MainActor (DaemonRuntimeState?, DaemonRuntimeState) -> Void = { _, _ in }
    ) {
        self.repoRoot = repoRoot
        self.onRuntimeStateChanged = onRuntimeStateChanged
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
            MCPServerDefinition(
                name: entry.name,
                scriptPath: "\(repoRoot)/\(entry.directory)/build/index.js"
            )
        }
    }

    var allRuntimeStates: [DaemonRuntimeState] {
        serverDefinitions
            .map { runtimeStates[$0.name] ?? defaultRuntimeState(for: $0) }
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

        if let process = runningServers[serverName], process.isRunning {
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

    func process(for serverName: String) -> Process? {
        runningServers[serverName]
    }

    func runtimeState(for serverName: String) -> DaemonRuntimeState? {
        runtimeStates[serverName]
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
            setRuntimeState(
                for: definition,
                status: .notBuilt,
                pid: nil,
                lastError: "Missing build artifact"
            )
            return
        }

        setRuntimeState(for: definition, status: .starting, pid: nil, lastError: nil)

        let process = Process()
        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["node", definition.scriptPath]
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
        process.terminationHandler = { [weak self] process in
            Task { @MainActor in
                guard let self else { return }
                self.runningServers.removeValue(forKey: definition.name)

                let status: DaemonRuntimeStatus
                let errorMessage: String?
                if process.terminationReason == .exit && process.terminationStatus == 0 {
                    status = .stopped
                    errorMessage = nil
                } else {
                    status = .failed
                    errorMessage = "Exited with status \(process.terminationStatus)"
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
            setRuntimeState(
                for: definition,
                status: .running,
                pid: process.processIdentifier,
                lastError: nil
            )
            print("[DaemonManager] Started \(definition.name) (pid \(process.processIdentifier))")
        } catch {
            setRuntimeState(
                for: definition,
                status: .failed,
                pid: nil,
                lastError: error.localizedDescription
            )
            print("[DaemonManager] Failed to start \(definition.name): \(error)")
        }
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
            lastError: lastError
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
            lastError: artifactExists ? nil : "Missing build artifact"
        )
    }

    private static func defaultRepoRoot() -> String {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Managers
            .deletingLastPathComponent() // MojoShell
            .deletingLastPathComponent() // Sources
            .deletingLastPathComponent() // shell
            .deletingLastPathComponent() // repo root
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
}
