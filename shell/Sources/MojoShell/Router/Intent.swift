import Foundation

struct ResolvedTool: Equatable, Sendable {
    let server: String
    let tool: String
    let arguments: [String: AnyCodable]
}

struct Intent: Equatable {
    let raw: String
    let resolved: ResolvedTool?
}
