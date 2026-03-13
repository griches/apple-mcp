import XCTest
@testable import MojoShell

@MainActor
final class AuditControllerTests: XCTestCase {
    func testRecordPersistsAuditEvents() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mojoshell-audit-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = AuditStore(fileURL: root.appendingPathComponent("audit.json"))
        let controller = AuditController(store: store, now: { Date(timeIntervalSince1970: 10) })

        controller.record(category: .native, title: "Tool executed", detail: "shell-native/finder_open_path", metadata: ["path": "/tmp"])
        controller.record(category: .daemon, title: "Daemon state changed", detail: "apple-mail -> running")

        let loaded = try store.load()
        XCTAssertEqual(loaded.count, 2)
        XCTAssertEqual(loaded.first?.category, .native)
        XCTAssertEqual(loaded.first?.metadata["path"], "/tmp")
        XCTAssertEqual(controller.events.count, 2)
    }

    func testClearRemovesPersistedAuditEvents() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mojoshell-audit-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = AuditStore(fileURL: root.appendingPathComponent("audit.json"))
        let controller = AuditController(store: store)

        controller.record(category: .system, title: "Before clear", detail: "event")
        controller.clear()

        XCTAssertEqual(try store.load().count, 0)
        XCTAssertEqual(controller.events.count, 0)
    }
}
