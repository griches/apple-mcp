import XCTest
@testable import MojoShell

final class NativeToolExecutorTests: XCTestCase {
    func testFinderOpenPathExpandsTildeAndRunsAppleScript() async throws {
        let capture = ScriptCapture()
        let executor = NativeToolExecutor(
            repoRoot: "/tmp/apple-mcp",
            appleScriptRunner: { script in
                await capture.record(script)
                return ""
            },
            commandRunner: { _, _, _ in "" },
            urlOpener: { _ in true }
        )

        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let currentDir = FileManager.default.currentDirectoryPath
        FileManager.default.changeCurrentDirectoryPath(tempRoot.path)
        defer { FileManager.default.changeCurrentDirectoryPath(currentDir) }

        let downloads = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads")
        try? FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)

        let result = try await executor.execute(
            tool: NativeToolName.finderOpenPath.rawValue,
            arguments: ["path": .string("~/Downloads")]
        )

        let scripts = await capture.scripts
        XCTAssertEqual(result.text, "Opened in Finder: \((downloads.path as NSString).standardizingPath)")
        XCTAssertTrue(scripts.first?.contains(downloads.path) ?? false)
    }

    func testShortcutsRunUsesCLIAndInput() async throws {
        let capture = CommandCapture()
        let executor = NativeToolExecutor(
            repoRoot: "/tmp/apple-mcp",
            appleScriptRunner: { _ in "" },
            commandRunner: { executable, arguments, stdin in
                await capture.record(executable: executable, arguments: arguments, stdin: stdin)
                return "shortcut output"
            },
            urlOpener: { _ in true }
        )

        let result = try await executor.execute(
            tool: NativeToolName.shortcutsRun.rawValue,
            arguments: [
                "name": .string("Daily Brief"),
                "input": .string("hello world"),
            ]
        )

        let invocation = await capture.invocations.first
        XCTAssertEqual(invocation?.executable, "/usr/bin/shortcuts")
        XCTAssertEqual(invocation?.arguments, ["run", "Daily Brief", "--output-path", "-", "--input-path", "-"])
        XCTAssertEqual(invocation?.stdin, "hello world")
        XCTAssertEqual(result.text, "shortcut output")
        XCTAssertEqual(
            result.payload,
            .object([
                "name": .string("Daily Brief"),
                "input_provided": .bool(true),
                "stdout": .string("shortcut output"),
            ])
        )
    }

    func testSystemSettingsOpenUsesDeepLink() async throws {
        let capture = URLCapture()
        let executor = NativeToolExecutor(
            repoRoot: "/tmp/apple-mcp",
            appleScriptRunner: { _ in "" },
            commandRunner: { _, _, _ in "" },
            urlOpener: { url in
                await capture.record(url)
                return true
            }
        )

        let result = try await executor.execute(
            tool: NativeToolName.systemSettingsOpen.rawValue,
            arguments: ["pane": .string("accessibility")]
        )

        let opened = await capture.urls.first
        XCTAssertEqual(opened?.absoluteString, "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        XCTAssertEqual(result.text, "Opened System Settings: accessibility")
    }

    func testShortcutsListReturnsStructuredPayload() async throws {
        let executor = NativeToolExecutor(
            repoRoot: "/tmp/apple-mcp",
            appleScriptRunner: { _ in "" },
            commandRunner: { _, _, _ in "Daily Brief\nExport Deliverable\n" },
            urlOpener: { _ in true }
        )

        let result = try await executor.execute(
            tool: NativeToolName.shortcutsList.rawValue,
            arguments: [:]
        )

        XCTAssertEqual(result.text, "Daily Brief\nExport Deliverable")
        XCTAssertEqual(
            result.payload,
            .array([.string("Daily Brief"), .string("Export Deliverable")])
        )
    }
}

private actor ScriptCapture {
    private(set) var scripts: [String] = []

    func record(_ script: String) {
        scripts.append(script)
    }
}

private actor URLCapture {
    private(set) var urls: [URL] = []

    func record(_ url: URL) {
        urls.append(url)
    }
}

private actor CommandCapture {
    struct Invocation: Equatable {
        let executable: String
        let arguments: [String]
        let stdin: String?
    }

    private(set) var invocations: [Invocation] = []

    func record(executable: String, arguments: [String], stdin: String?) {
        invocations.append(Invocation(executable: executable, arguments: arguments, stdin: stdin))
    }
}
