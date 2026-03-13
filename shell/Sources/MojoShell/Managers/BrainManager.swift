import Foundation

enum BrainSourceMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case repoDefault
    case localCopy
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .repoDefault:
            return "Repo Brain"
        case .localCopy:
            return "Local Brain"
        case .custom:
            return "Custom Brain"
        }
    }

    var summary: String {
        switch self {
        case .repoDefault:
            return "Use the repo-bundled operating brain file."
        case .localCopy:
            return "Use a user-local copy under Application Support."
        case .custom:
            return "Use an operator-selected custom brain path."
        }
    }
}

struct BrainConfiguration: Codable, Equatable, Sendable {
    var mode: BrainSourceMode
    var customPath: String?
}

struct BrainConfigStore {
    let fileURL: URL
    private let fileManager: FileManager

    init(
        fileURL: URL = BrainConfigStore.defaultFileURL(),
        fileManager: FileManager = .default
    ) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    func load() throws -> BrainConfiguration? {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return nil
        }

        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else {
            return nil
        }

        return try JSONDecoder().decode(BrainConfiguration.self, from: data)
    }

    func save(_ configuration: BrainConfiguration) throws {
        let parent = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(configuration)
        try data.write(to: fileURL, options: .atomic)
    }

    static func defaultFileURL() -> URL {
        JobStore.defaultFileURL()
            .deletingLastPathComponent()
            .appendingPathComponent("brain-config.json")
    }
}

enum BrainManagerError: LocalizedError, Equatable {
    case repoBrainMissing(String)
    case customBrainMissing(String)
    case importSourceMissing(String)

    var errorDescription: String? {
        switch self {
        case .repoBrainMissing(let path):
            return "Repo brain file missing: \(path)"
        case .customBrainMissing(let path):
            return "Custom brain file missing: \(path)"
        case .importSourceMissing(let path):
            return "Import source missing: \(path)"
        }
    }
}

@MainActor
final class BrainManager: ObservableObject {
    @Published private(set) var sourceMode: BrainSourceMode
    @Published private(set) var activeBrainPath: String

    let repoDefaultPath: String
    let localBrainPath: String

    private let store: BrainConfigStore
    private let fileManager: FileManager

    init(
        repoRoot: String,
        localBrainPath: String? = nil,
        store: BrainConfigStore = BrainConfigStore(),
        fileManager: FileManager = .default
    ) {
        self.repoDefaultPath = "\(repoRoot)/knowledge-corpus/data/mojosolo_operating_brain.json"
        self.localBrainPath = localBrainPath ?? BrainManager.defaultLocalBrainPath()
        self.store = store
        self.fileManager = fileManager

        let configuration = (try? store.load()) ?? nil
        let mode = configuration?.mode ?? .repoDefault
        self.sourceMode = mode
        self.activeBrainPath = BrainManager.resolveActivePath(
            mode: mode,
            customPath: configuration?.customPath,
            repoDefaultPath: self.repoDefaultPath,
            localBrainPath: self.localBrainPath
        )

        persist()
    }

    var activeBrainName: String {
        URL(fileURLWithPath: activeBrainPath).lastPathComponent
    }

    func useRepoDefault() {
        sourceMode = .repoDefault
        activeBrainPath = repoDefaultPath
        persist()
    }

    func useLocalBrain() throws {
        try seedLocalBrainIfNeeded()
        sourceMode = .localCopy
        activeBrainPath = localBrainPath
        persist()
    }

    func useCustomBrain(path: String) throws {
        let resolved = (path as NSString).expandingTildeInPath
        guard fileManager.fileExists(atPath: resolved) else {
            throw BrainManagerError.customBrainMissing(resolved)
        }
        sourceMode = .custom
        activeBrainPath = resolved
        persist(customPath: resolved)
    }

    func importLocalBrain(from path: String) throws {
        let resolved = (path as NSString).expandingTildeInPath
        guard fileManager.fileExists(atPath: resolved) else {
            throw BrainManagerError.importSourceMissing(resolved)
        }

        let targetURL = URL(fileURLWithPath: localBrainPath)
        try fileManager.createDirectory(at: targetURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: localBrainPath) {
            try fileManager.removeItem(atPath: localBrainPath)
        }
        try fileManager.copyItem(atPath: resolved, toPath: localBrainPath)
        sourceMode = .localCopy
        activeBrainPath = localBrainPath
        persist()
    }

    func seedLocalBrainIfNeeded() throws {
        guard fileManager.fileExists(atPath: repoDefaultPath) else {
            throw BrainManagerError.repoBrainMissing(repoDefaultPath)
        }

        guard !fileManager.fileExists(atPath: localBrainPath) else {
            return
        }

        let targetURL = URL(fileURLWithPath: localBrainPath)
        try fileManager.createDirectory(at: targetURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.copyItem(atPath: repoDefaultPath, toPath: localBrainPath)
    }

    private func persist(customPath: String? = nil) {
        let storedCustomPath: String?
        if sourceMode == .custom {
            storedCustomPath = customPath ?? activeBrainPath
        } else {
            storedCustomPath = nil
        }

        do {
            try store.save(
                BrainConfiguration(
                    mode: sourceMode,
                    customPath: storedCustomPath
                )
            )
        } catch {
            // Brain path persistence must not crash the shell.
        }
    }

    private static func resolveActivePath(
        mode: BrainSourceMode,
        customPath: String?,
        repoDefaultPath: String,
        localBrainPath: String
    ) -> String {
        switch mode {
        case .repoDefault:
            return repoDefaultPath
        case .localCopy:
            return localBrainPath
        case .custom:
            return customPath?.isEmpty == false ? customPath! : repoDefaultPath
        }
    }

    private static func defaultLocalBrainPath() -> String {
        JobStore.defaultFileURL()
            .deletingLastPathComponent()
            .appendingPathComponent("brain.json")
            .path
    }
}
