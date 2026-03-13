import XCTest
@testable import MojoShell

@MainActor
final class ShellPreferencesControllerTests: XCTestCase {
    func testPreferencesPersistAndReload() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mojoshell-preferences-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = ShellPreferencesStore(fileURL: root.appendingPathComponent("preferences.json"))
        let controller = ShellPreferencesController(store: store)

        controller.autoStartDaemonsOnLaunch = false
        controller.autoRefreshNowPlaying = false
        controller.morningOpsOnLaunch = true
        controller.recordMorningOpsRun(at: Date(timeIntervalSince1970: 42))

        let reloaded = ShellPreferencesController(store: store)
        XCTAssertFalse(reloaded.autoStartDaemonsOnLaunch)
        XCTAssertFalse(reloaded.autoRefreshNowPlaying)
        XCTAssertTrue(reloaded.morningOpsOnLaunch)
        XCTAssertEqual(reloaded.lastMorningOpsRunAt, Date(timeIntervalSince1970: 42))
    }
}
