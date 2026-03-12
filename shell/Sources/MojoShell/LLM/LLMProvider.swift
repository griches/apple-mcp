import Foundation

struct LLMToolDefinition: Equatable {
    let name: String
    let description: String
    let server: String
}

struct LLMResponse: Equatable {
    let text: String
    let resolvedTool: ResolvedTool?
}

protocol LLMProvider {
    var name: String { get }
    func resolve(prompt: String, availableTools: [LLMToolDefinition]) async throws -> LLMResponse
    func buildURLRequest(prompt: String, tools: [LLMToolDefinition]) throws -> URLRequest
}
