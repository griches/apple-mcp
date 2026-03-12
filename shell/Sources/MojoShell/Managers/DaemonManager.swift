import Combine
import Foundation

struct MCPServerDefinition: Equatable {
    let name: String
    let scriptPath: String
}

@MainActor
final class DaemonManager: ObservableObject {
    @Published private(set) var runningServers: [String: Process] = [:]

    private let repoRoot: String

    init(repoRoot: String = Self.defaultRepoRoot()) {
        self.repoRoot = repoRoot
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

    func startAll() {
        for definition in serverDefinitions {
            start(definition)
        }
    }

    func stopAll() {
        for process in runningServers.values where process.isRunning {
            process.terminate()
        }
        runningServers.removeAll()
    }

    func process(for serverName: String) -> Process? {
        runningServers[serverName]
    }

    private func start(_ definition: MCPServerDefinition) {
        guard runningServers[definition.name] == nil else {
            return
        }

        guard FileManager.default.fileExists(atPath: definition.scriptPath) else {
            print("[DaemonManager] Missing build artifact: \(definition.scriptPath)")
            return
        }

        let process = Process()
        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["node", definition.scriptPath]
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
        process.terminationHandler = { [weak self] _ in
            Task { @MainActor in
                self?.runningServers.removeValue(forKey: definition.name)
            }
        }

        do {
            try process.run()
            runningServers[definition.name] = process
            print("[DaemonManager] Started \(definition.name) (pid \(process.processIdentifier))")
        } catch {
            print("[DaemonManager] Failed to start \(definition.name): \(error)")
        }
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
}
