import XCTest
@testable import MojoShell

final class ComputerUseProviderTests: XCTestCase {
    func testStubStartsSession() async throws {
        let provider = StubComputerUseProvider()
        let sessionID = try await provider.startSession()
        XCTAssertFalse(sessionID.isEmpty)
    }

    func testStubCapturesState() async throws {
        let provider = StubComputerUseProvider()
        let sessionID = try await provider.startSession()
        let state = try await provider.captureState(sessionId: sessionID)
        XCTAssertEqual(state.appName, "stub")
    }

    func testStubExecutesAction() async throws {
        let provider = StubComputerUseProvider()
        let sessionID = try await provider.startSession()
        let result = try await provider.execute(
            sessionId: sessionID,
            action: ComputerUseAction(type: .click, target: "Export Button")
        )
        XCTAssertTrue(result.success)
    }
}
