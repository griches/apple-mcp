import Foundation

enum AuditCategory: String, Codable, CaseIterable, Sendable {
    case navigation
    case commandPalette
    case daemon
    case mcp
    case native
    case production
    case llm
    case system
}

struct AuditEvent: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let timestamp: Date
    let category: AuditCategory
    let title: String
    let detail: String
    let metadata: [String: String]

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        category: AuditCategory,
        title: String,
        detail: String,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.timestamp = timestamp
        self.category = category
        self.title = title
        self.detail = detail
        self.metadata = metadata
    }
}

struct AuditStore {
    let fileURL: URL
    private let fileManager: FileManager

    init(
        fileURL: URL = AuditStore.defaultFileURL(),
        fileManager: FileManager = .default
    ) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    func load() throws -> [AuditEvent] {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return []
        }

        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else {
            return []
        }

        return try JSONDecoder().decode([AuditEvent].self, from: data)
    }

    func append(_ event: AuditEvent, limit: Int = 500) throws {
        var all = try load()
        all.append(event)
        if all.count > limit {
            all.removeFirst(all.count - limit)
        }
        try save(all)
    }

    func save(_ events: [AuditEvent]) throws {
        let parent = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(events)
        try data.write(to: fileURL, options: .atomic)
    }

    static func defaultFileURL() -> URL {
        JobStore.defaultFileURL()
            .deletingLastPathComponent()
            .appendingPathComponent("audit-log.json")
    }
}

@MainActor
final class AuditController: ObservableObject {
    @Published private(set) var events: [AuditEvent] = []

    private let store: AuditStore
    private let now: () -> Date

    init(
        store: AuditStore = AuditStore(),
        now: @escaping () -> Date = Date.init
    ) {
        self.store = store
        self.now = now
        load()
    }

    var filePath: String {
        store.fileURL.path
    }

    func record(
        category: AuditCategory,
        title: String,
        detail: String,
        metadata: [String: String] = [:]
    ) {
        let event = AuditEvent(
            timestamp: now(),
            category: category,
            title: title,
            detail: detail,
            metadata: metadata
        )

        do {
            try store.append(event)
            events.append(event)
            if events.count > 500 {
                events.removeFirst(events.count - 500)
            }
        } catch {
            let fallback = AuditEvent(
                timestamp: now(),
                category: .system,
                title: "Audit persistence failure",
                detail: error.localizedDescription
            )
            events.append(fallback)
        }
    }

    func refresh() {
        load()
    }

    func clear() {
        do {
            try store.save([])
            events = []
        } catch {
            events = [
                AuditEvent(
                    timestamp: now(),
                    category: .system,
                    title: "Audit clear failure",
                    detail: error.localizedDescription
                ),
            ]
        }
    }

    private func load() {
        do {
            events = try store.load()
        } catch {
            events = [
                AuditEvent(
                    timestamp: now(),
                    category: .system,
                    title: "Audit load failure",
                    detail: error.localizedDescription
                ),
            ]
        }
    }
}
