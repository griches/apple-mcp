import XCTest
@testable import MojoShell

final class DeterministicRouterTests: XCTestCase {
    private let router = DeterministicRouter()

    func testScanInboxesIntent() {
        let result = router.route("scan today's inboxes")
        XCTAssertEqual(result?.server, "mail-intelligence")
        XCTAssertEqual(result?.tool, "scan_persona_inboxes")
    }

    func testPauseMusicIntent() {
        let result = router.route("pause the music")
        XCTAssertEqual(result?.server, "apple-music")
        XCTAssertEqual(result?.tool, "pause")
    }

    func testOpenDownloadsFolderRoutesToNativeFinderTool() {
        let result = router.route("open downloads folder")
        XCTAssertEqual(result?.server, NativeToolExecutor.serverName)
        XCTAssertEqual(result?.tool, NativeToolName.finderOpenPath.rawValue)
        XCTAssertEqual(result?.arguments["path"], .string("~/Downloads"))
    }

    func testOpenSafariURLBuildsNativeURLAction() {
        let result = router.route("open openai.com in safari")
        XCTAssertEqual(result?.server, NativeToolExecutor.serverName)
        XCTAssertEqual(result?.tool, NativeToolName.safariOpenURL.rawValue)
        XCTAssertEqual(result?.arguments["url"], .string("https://openai.com"))
    }

    func testRunShortcutParsesNameAndInput() {
        let result = router.route("run shortcut Daily Brief with input inbox summary")
        XCTAssertEqual(result?.server, NativeToolExecutor.serverName)
        XCTAssertEqual(result?.tool, NativeToolName.shortcutsRun.rawValue)
        XCTAssertEqual(result?.arguments["name"], .string("Daily Brief"))
        XCTAssertEqual(result?.arguments["input"], .string("inbox summary"))
    }

    func testFCPIntentFallsBack() {
        let result = router.route("export the current FCP timeline")
        XCTAssertNil(result)
    }

    func testUnknownReturnsNil() {
        let result = router.route("zxqwerty something unknown")
        XCTAssertNil(result)
    }
}
