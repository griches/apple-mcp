import XCTest
@testable import MojoShell

final class JobStoreTests: XCTestCase {
    func testJobStoreRoundTripsJobs() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mojoshell-jobstore-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = JobStore(fileURL: root.appendingPathComponent("jobs.json"))
        let jobs = [
            MediaJob(
                name: "Test Job",
                client: "Client",
                status: .queued,
                progress: 0.0,
                createdAt: Date(timeIntervalSince1970: 100),
                completedAt: nil,
                errorMessage: nil,
                sourceAssets: [
                    SourceAsset(
                        path: "/tmp/input.mov",
                        name: "input.mov",
                        kind: .video,
                        byteSize: 1024
                    ),
                ],
                notes: "operator note",
                workflowVersion: "test-v2",
                approvalMode: .alwaysAsk
            ),
        ]

        try store.save(jobs)
        let loaded = try store.load()
        XCTAssertEqual(loaded, jobs)
    }

    func testEventStoreAppendAndLoadRecent() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mojoshell-eventstore-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = JobEventStore(fileURL: root.appendingPathComponent("events.json"))
        let jobID = UUID()
        try store.append(JobEvent(jobID: jobID, timestamp: Date(timeIntervalSince1970: 1), type: .queued, message: "q1"))
        try store.append(JobEvent(jobID: jobID, timestamp: Date(timeIntervalSince1970: 2), type: .started, message: "s1"))
        try store.append(JobEvent(jobID: jobID, timestamp: Date(timeIntervalSince1970: 3), type: .completed, message: "c1"))

        let recent = try store.loadRecent(limit: 2)
        XCTAssertEqual(recent.count, 2)
        XCTAssertEqual(recent[0].message, "s1")
        XCTAssertEqual(recent[1].message, "c1")
    }

    func testScreenshotStoreWritesPNGData() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mojoshell-screens-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        let store = ScreenshotStore(directoryURL: root)
        let data = Data([0x89, 0x50, 0x4E, 0x47]) // PNG signature prefix
        let url = try store.save(data, jobID: UUID(), stepIndex: 0)

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        let onDisk = try Data(contentsOf: url)
        XCTAssertEqual(onDisk, data)
    }
}
