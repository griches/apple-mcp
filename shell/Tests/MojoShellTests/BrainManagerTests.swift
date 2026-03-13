import XCTest
@testable import MojoShell

@MainActor
final class BrainManagerTests: XCTestCase {
    func testUseLocalBrainSeedsCopyAndPersistsMode() throws {
        let root = try makeBrainRepoRoot()
        defer { try? FileManager.default.removeItem(atPath: root) }

        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("brain-config-\(UUID().uuidString).json")
        let localBrainURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("local-brain-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: storeURL) }
        defer { try? FileManager.default.removeItem(at: localBrainURL) }

        let manager = BrainManager(
            repoRoot: root,
            localBrainPath: localBrainURL.path,
            store: BrainConfigStore(fileURL: storeURL)
        )

        try manager.useLocalBrain()

        XCTAssertEqual(manager.sourceMode, .localCopy)
        XCTAssertTrue(FileManager.default.fileExists(atPath: manager.localBrainPath))
        XCTAssertEqual(try BrainConfigStore(fileURL: storeURL).load()?.mode, .localCopy)
    }

    func testUseCustomBrainRequiresExistingFile() throws {
        let root = try makeBrainRepoRoot()
        defer { try? FileManager.default.removeItem(atPath: root) }

        let manager = BrainManager(repoRoot: root)
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-brain-\(UUID().uuidString).json")

        XCTAssertThrowsError(try manager.useCustomBrain(path: missing.path))
    }

    func testStoredConfigurationReloadsLocalBrain() throws {
        let root = try makeBrainRepoRoot()
        defer { try? FileManager.default.removeItem(atPath: root) }

        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("brain-config-\(UUID().uuidString).json")
        let localBrainURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("local-brain-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: storeURL) }
        defer { try? FileManager.default.removeItem(at: localBrainURL) }

        let original = BrainManager(
            repoRoot: root,
            localBrainPath: localBrainURL.path,
            store: BrainConfigStore(fileURL: storeURL)
        )
        try original.useLocalBrain()

        let reloaded = BrainManager(
            repoRoot: root,
            localBrainPath: localBrainURL.path,
            store: BrainConfigStore(fileURL: storeURL)
        )

        XCTAssertEqual(reloaded.sourceMode, .localCopy)
        XCTAssertEqual(reloaded.activeBrainPath, original.localBrainPath)
    }

    private func makeBrainRepoRoot() throws -> String {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mojoshell-brain-\(UUID().uuidString)")
        let brainURL = root
            .appendingPathComponent("knowledge-corpus")
            .appendingPathComponent("data")
        try FileManager.default.createDirectory(at: brainURL, withIntermediateDirectories: true)
        try Data("{\"brain\":true}".utf8).write(to: brainURL.appendingPathComponent("mojosolo_operating_brain.json"))
        return root.path
    }
}
