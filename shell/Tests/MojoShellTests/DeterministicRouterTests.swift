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

    func testFCPIntentFallsBack() {
        let result = router.route("export the current FCP timeline")
        XCTAssertNil(result)
    }

    func testUnknownReturnsNil() {
        let result = router.route("zxqwerty something unknown")
        XCTAssertNil(result)
    }
}
