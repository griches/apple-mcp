import Foundation

struct ComputerUseState: Equatable, Sendable {
    let appName: String
    let screenshotData: Data?
    let timestamp: Date
}

enum ComputerUseActionType: String, Equatable, Sendable {
    case click
    case type
    case keypress
    case scroll
    case drag
}

struct ComputerUseAction: Equatable, Sendable {
    let type: ComputerUseActionType
    let target: String
    let value: String?

    init(type: ComputerUseActionType, target: String, value: String? = nil) {
        self.type = type
        self.target = target
        self.value = value
    }
}

struct ComputerUseResult: Equatable, Sendable {
    let success: Bool
    let message: String
    let screenshotAfter: Data?
}

protocol ComputerUseProvider: Sendable {
    var name: String { get }
    func startSession() async throws -> String
    func captureState(sessionId: String) async throws -> ComputerUseState
    func execute(sessionId: String, action: ComputerUseAction) async throws -> ComputerUseResult
    func stopSession(sessionId: String) async throws
}
