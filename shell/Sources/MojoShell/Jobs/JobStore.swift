import Foundation

struct JobStore {
    let fileURL: URL
    private let fileManager: FileManager

    init(
        fileURL: URL = JobStore.defaultFileURL(),
        fileManager: FileManager = .default
    ) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    func load() throws -> [MediaJob] {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return []
        }

        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else {
            return []
        }

        return try JSONDecoder().decode([MediaJob].self, from: data)
    }

    func save(_ jobs: [MediaJob]) throws {
        try ensureParentDirectory()
        let data = try JSONEncoder().encode(jobs)
        try data.write(to: fileURL, options: .atomic)
    }

    private func ensureParentDirectory() throws {
        let parent = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
    }

    static func defaultFileURL() -> URL {
        appSupportDirectory().appendingPathComponent("jobs.json")
    }
}

struct JobEventStore {
    let fileURL: URL
    private let fileManager: FileManager

    init(
        fileURL: URL = JobEventStore.defaultFileURL(),
        fileManager: FileManager = .default
    ) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    func load() throws -> [JobEvent] {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return []
        }

        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else {
            return []
        }

        return try JSONDecoder().decode([JobEvent].self, from: data)
    }

    func loadRecent(limit: Int) throws -> [JobEvent] {
        let all = try load()
        guard all.count > limit else {
            return all
        }
        return Array(all.suffix(limit))
    }

    func append(_ event: JobEvent) throws {
        var all = try load()
        all.append(event)
        try save(all)
    }

    func save(_ events: [JobEvent]) throws {
        try ensureParentDirectory()
        let data = try JSONEncoder().encode(events)
        try data.write(to: fileURL, options: .atomic)
    }

    private func ensureParentDirectory() throws {
        let parent = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
    }

    static func defaultFileURL() -> URL {
        appSupportDirectory().appendingPathComponent("job-events.json")
    }
}

struct ScreenshotStore {
    let directoryURL: URL
    private let fileManager: FileManager

    init(
        directoryURL: URL = ScreenshotStore.defaultDirectoryURL(),
        fileManager: FileManager = .default
    ) {
        self.directoryURL = directoryURL
        self.fileManager = fileManager
    }

    func save(_ data: Data, jobID: UUID, stepIndex: Int) throws -> URL {
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let stamp = Int(Date().timeIntervalSince1970 * 1000)
        let fileName = "\(jobID.uuidString)-step\(stepIndex + 1)-\(stamp).png"
        let url = directoryURL.appendingPathComponent(fileName)
        try data.write(to: url, options: .atomic)
        return url
    }

    static func defaultDirectoryURL() -> URL {
        appSupportDirectory().appendingPathComponent("screenshots")
    }
}

private func appSupportDirectory() -> URL {
    let fm = FileManager.default
    if let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
        return base.appendingPathComponent("MojoShell", isDirectory: true)
    }

    return URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent("Library")
        .appendingPathComponent("Application Support")
        .appendingPathComponent("MojoShell", isDirectory: true)
}
