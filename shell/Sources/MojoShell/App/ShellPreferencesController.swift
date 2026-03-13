import Foundation

struct ShellPreferencesSnapshot: Codable, Equatable, Sendable {
    var autoStartDaemonsOnLaunch: Bool
    var autoRefreshNowPlaying: Bool
    var morningOpsOnLaunch: Bool
    var lastMorningOpsRunAt: Date?
}

struct ShellPreferencesStore {
    let fileURL: URL
    private let fileManager: FileManager

    init(
        fileURL: URL = ShellPreferencesStore.defaultFileURL(),
        fileManager: FileManager = .default
    ) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    func load() throws -> ShellPreferencesSnapshot? {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return nil
        }

        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else {
            return nil
        }

        return try JSONDecoder().decode(ShellPreferencesSnapshot.self, from: data)
    }

    func save(_ snapshot: ShellPreferencesSnapshot) throws {
        let parent = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: fileURL, options: .atomic)
    }

    static func defaultFileURL() -> URL {
        JobStore.defaultFileURL()
            .deletingLastPathComponent()
            .appendingPathComponent("shell-preferences.json")
    }
}

@MainActor
final class ShellPreferencesController: ObservableObject {
    @Published var autoStartDaemonsOnLaunch: Bool { didSet { persistIfReady() } }
    @Published var autoRefreshNowPlaying: Bool { didSet { persistIfReady() } }
    @Published var morningOpsOnLaunch: Bool { didSet { persistIfReady() } }
    @Published private(set) var lastMorningOpsRunAt: Date? { didSet { persistIfReady() } }

    private let store: ShellPreferencesStore
    private var isHydrating = true

    init(store: ShellPreferencesStore = ShellPreferencesStore()) {
        self.store = store
        let snapshot = (try? store.load()) ?? nil
        self.autoStartDaemonsOnLaunch = snapshot?.autoStartDaemonsOnLaunch ?? true
        self.autoRefreshNowPlaying = snapshot?.autoRefreshNowPlaying ?? true
        self.morningOpsOnLaunch = snapshot?.morningOpsOnLaunch ?? false
        self.lastMorningOpsRunAt = snapshot?.lastMorningOpsRunAt
        self.isHydrating = false
        persistIfReady()
    }

    func recordMorningOpsRun(at date: Date = Date()) {
        lastMorningOpsRunAt = date
    }

    private func persistIfReady() {
        guard !isHydrating else {
            return
        }

        do {
            try store.save(
                ShellPreferencesSnapshot(
                    autoStartDaemonsOnLaunch: autoStartDaemonsOnLaunch,
                    autoRefreshNowPlaying: autoRefreshNowPlaying,
                    morningOpsOnLaunch: morningOpsOnLaunch,
                    lastMorningOpsRunAt: lastMorningOpsRunAt
                )
            )
        } catch {
            // Preferences persistence must never crash the shell.
        }
    }
}
