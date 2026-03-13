import XCTest
@testable import MojoShell

@MainActor
final class ShellSessionControllerTests: XCTestCase {
    func testShellSessionControllerPersistsAndReloadsState() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mojoshell-session-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = ShellSessionStore(fileURL: root.appendingPathComponent("session.json"))
        let controller = ShellSessionController(store: store)

        controller.selectedView = .production
        controller.preferredPreset = .motionPlaceholderExport
        controller.preferredApprovalMode = .alwaysAsk
        controller.appendTerminalEntry(TerminalEntry(role: .user, text: "scan inboxes"))

        let reloaded = ShellSessionController(store: store)
        XCTAssertEqual(reloaded.selectedView, .production)
        XCTAssertEqual(reloaded.preferredPreset, .motionPlaceholderExport)
        XCTAssertEqual(reloaded.preferredApprovalMode, .alwaysAsk)
        XCTAssertEqual(reloaded.terminalHistory.last?.text, "scan inboxes")
    }

    func testClearTerminalHistoryResetsToSystemEntry() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mojoshell-session-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let controller = ShellSessionController(
            store: ShellSessionStore(fileURL: root.appendingPathComponent("session.json"))
        )
        controller.appendTerminalEntry(TerminalEntry(role: .user, text: "hello"))
        controller.clearTerminalHistory()

        XCTAssertEqual(controller.terminalHistory.count, 1)
        XCTAssertEqual(controller.terminalHistory.first?.role, .system)
    }
}
