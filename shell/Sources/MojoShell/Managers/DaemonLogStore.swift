import Foundation

enum DaemonLogKind: String, CaseIterable, Sendable {
    case runtime
    case build
}

struct DaemonBuildResult: Equatable, Sendable {
    let output: String
    let exitStatus: Int32
}

enum DaemonBuildStatus: String, Equatable, Sendable {
    case idle
    case building
    case succeeded
    case failed
}

struct DaemonBuildState: Identifiable, Equatable, Sendable {
    let id: String
    let serverName: String
    let status: DaemonBuildStatus
    let command: String
    let logPath: String
    let lastOutput: String
    let updatedAt: Date
    let startedAt: Date?
    let finishedAt: Date?
    let lastExitCode: Int32?

    init(
        serverName: String,
        status: DaemonBuildStatus,
        command: String,
        logPath: String,
        lastOutput: String = "",
        updatedAt: Date = Date(),
        startedAt: Date? = nil,
        finishedAt: Date? = nil,
        lastExitCode: Int32? = nil
    ) {
        self.id = serverName
        self.serverName = serverName
        self.status = status
        self.command = command
        self.logPath = logPath
        self.lastOutput = lastOutput
        self.updatedAt = updatedAt
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.lastExitCode = lastExitCode
    }
}

struct DaemonLogStore {
    let directoryURL: URL
    private let fileManager: FileManager

    init(
        directoryURL: URL = DaemonLogStore.defaultDirectoryURL(),
        fileManager: FileManager = .default
    ) {
        self.directoryURL = directoryURL
        self.fileManager = fileManager
    }

    func logURL(for serverName: String, kind: DaemonLogKind) -> URL {
        directoryURL
            .appendingPathComponent(serverName, isDirectory: true)
            .appendingPathComponent("\(kind.rawValue).log")
    }

    func reset(serverName: String, kind: DaemonLogKind) throws {
        let url = logURL(for: serverName, kind: kind)
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: url, options: .atomic)
    }

    func append(_ text: String, serverName: String, kind: DaemonLogKind) throws {
        let url = logURL(for: serverName, kind: kind)
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = Data(text.utf8)

        if fileManager.fileExists(atPath: url.path) {
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } else {
            try data.write(to: url, options: .atomic)
        }
    }

    func load(serverName: String, kind: DaemonLogKind) throws -> String {
        let url = logURL(for: serverName, kind: kind)
        guard fileManager.fileExists(atPath: url.path) else {
            return ""
        }

        let data = try Data(contentsOf: url)
        return String(decoding: data, as: UTF8.self)
    }

    static func defaultDirectoryURL() -> URL {
        JobStore.defaultFileURL()
            .deletingLastPathComponent()
            .appendingPathComponent("daemon-logs", isDirectory: true)
    }
}
