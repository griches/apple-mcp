import XCTest
@testable import MojoShell

final class ExportTargetStoreTests: XCTestCase {
    func testLoadReturnsDefaultTargetsWhenFileMissing() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mojoshell-export-targets-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = ExportTargetStore(fileURL: root.appendingPathComponent("export-targets.json"))
        let targets = try store.load()

        XCTAssertFalse(targets.isEmpty)
        XCTAssertTrue(targets.contains(where: { $0.isDefault }))
    }

    func testSaveRoundTripsTargets() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mojoshell-export-targets-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = ExportTargetStore(fileURL: root.appendingPathComponent("export-targets.json"))
        let targets = [
            ExportTarget(name: "Exports", path: "/tmp/exports", isDefault: true),
            ExportTarget(name: "Archive", path: "/tmp/archive", isDefault: false),
        ]

        try store.save(targets)
        let loaded = try store.load()
        XCTAssertEqual(loaded, targets)
    }
}
