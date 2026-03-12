import XCTest
@testable import MojoShell

final class ComputerUseProviderTests: XCTestCase {

    // MARK: - Stub

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

    // MARK: - CuaComputerUseProvider lifecycle (no display needed)

    func testCuaStartAndStop() async throws {
        let provider = CuaComputerUseProvider()
        let id = try await provider.startSession()
        XCTAssertFalse(id.isEmpty)
        try await provider.stopSession(sessionId: id)
    }

    func testCuaUnknownSessionThrows() async throws {
        let provider = CuaComputerUseProvider()
        do {
            _ = try await provider.captureState(sessionId: "nonexistent")
            XCTFail("Expected CuaError.unknownSession")
        } catch CuaError.unknownSession {
            // expected
        }
    }

    func testCuaInvalidCoordinatesThrows() async throws {
        let provider = CuaComputerUseProvider()
        let id = try await provider.startSession()
        do {
            _ = try await provider.execute(
                sessionId: id,
                action: ComputerUseAction(type: .click, target: "not-coordinates")
            )
            XCTFail("Expected CuaError.invalidCoordinates")
        } catch CuaError.invalidCoordinates {
            // expected
        }
    }

    func testCuaUnknownKeyThrows() async throws {
        let provider = CuaComputerUseProvider()
        let id = try await provider.startSession()
        do {
            _ = try await provider.execute(
                sessionId: id,
                action: ComputerUseAction(type: .keypress, target: "superkey")
            )
            XCTFail("Expected CuaError.unknownKey")
        } catch CuaError.unknownKey {
            // expected
        }
    }
}
