import Foundation

struct ExportTarget: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var name: String
    var path: String
    var isDefault: Bool

    init(id: UUID = UUID(), name: String, path: String, isDefault: Bool) {
        self.id = id
        self.name = name
        self.path = path
        self.isDefault = isDefault
    }
}

struct ExportTargetStore {
    let fileURL: URL
    private let fileManager: FileManager

    init(
        fileURL: URL = ExportTargetStore.defaultFileURL(),
        fileManager: FileManager = .default
    ) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    func load() throws -> [ExportTarget] {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return defaultTargets()
        }

        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else {
            return defaultTargets()
        }

        let decoded = try JSONDecoder().decode([ExportTarget].self, from: data)
        return decoded.isEmpty ? defaultTargets() : decoded
    }

    func save(_ targets: [ExportTarget]) throws {
        try ensureParentDirectory()
        let data = try JSONEncoder().encode(targets)
        try data.write(to: fileURL, options: .atomic)
    }

    private func ensureParentDirectory() throws {
        let parent = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
    }

    static func defaultFileURL() -> URL {
        JobStore.defaultFileURL()
            .deletingLastPathComponent()
            .appendingPathComponent("export-targets.json")
    }

    private func defaultTargets() -> [ExportTarget] {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        return [
            ExportTarget(
                id: UUID(uuidString: "10000000-0000-0000-0000-000000000001") ?? UUID(),
                name: "Movies",
                path: home.appendingPathComponent("Movies").path,
                isDefault: true
            ),
            ExportTarget(
                id: UUID(uuidString: "10000000-0000-0000-0000-000000000002") ?? UUID(),
                name: "Downloads",
                path: home.appendingPathComponent("Downloads").path,
                isDefault: false
            ),
            ExportTarget(
                id: UUID(uuidString: "10000000-0000-0000-0000-000000000003") ?? UUID(),
                name: "Desktop",
                path: home.appendingPathComponent("Desktop").path,
                isDefault: false
            ),
        ]
    }
}
