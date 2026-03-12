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

enum LLMRoutingError: LocalizedError {
    case noAvailableProviders
    case providersFailed(String)

    var errorDescription: String? {
        switch self {
        case .noAvailableProviders:
            return "No LLM providers are configured. Set ANTHROPIC_API_KEY or OPENAI_API_KEY to enable fallback routing."
        case .providersFailed(let detail):
            return "All configured LLM providers failed. \(detail)"
        }
    }
}
