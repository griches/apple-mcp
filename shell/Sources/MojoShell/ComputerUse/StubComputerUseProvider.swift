import Foundation

actor StubComputerUseProvider: ComputerUseProvider {
    let name = "stub"

    private var sessions: Set<String> = []

    func startSession() async throws -> String {
        let id = UUID().uuidString
        sessions.insert(id)
        print("[StubCU] Session started: \(id)")
        return id
    }

    func captureState(sessionId: String) async throws -> ComputerUseState {
        guard sessions.contains(sessionId) else {
            throw StubComputerUseError.unknownSession
        }

        return ComputerUseState(appName: "stub", screenshotData: nil, timestamp: Date())
    }

    func execute(sessionId: String, action: ComputerUseAction) async throws -> ComputerUseResult {
        guard sessions.contains(sessionId) else {
            throw StubComputerUseError.unknownSession
        }

        print("[StubCU] \(action.type.rawValue) -> \(action.target) (session: \(sessionId))")
        return ComputerUseResult(
            success: true,
            message: "Stub executed: \(action.type.rawValue)",
            screenshotAfter: nil
        )
    }

    func stopSession(sessionId: String) async throws {
        sessions.remove(sessionId)
        print("[StubCU] Session stopped: \(sessionId)")
    }
}

enum StubComputerUseError: Error {
    case unknownSession
}
