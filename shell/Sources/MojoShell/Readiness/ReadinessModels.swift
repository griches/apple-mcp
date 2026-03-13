import Foundation

enum ReadinessSeverity: Equatable, Sendable {
    case info
    case warning
    case blocking
}

struct ReadinessIssue: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let fixInstruction: String
    let actionURL: URL?
    let severity: ReadinessSeverity
}

enum ReadinessFeature: String, Hashable, Sendable {
    case computerUse
    case llm
}
