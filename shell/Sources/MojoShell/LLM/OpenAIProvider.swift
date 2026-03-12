import Foundation

struct OpenAIProvider: LLMProvider {
    let name = "openai"

    private let apiKey: String
    private let model: String
    private let baseURL = URL(string: "https://api.openai.com/v1/chat/completions")!

    init(apiKey: String, model: String = ProcessInfo.processInfo.environment["OPENAI_ROUTER_MODEL"] ?? "gpt-4o-mini") {
        self.apiKey = apiKey
        self.model = model
    }

    func buildURLRequest(prompt: String, tools: [LLMToolDefinition]) throws -> URLRequest {
        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let toolList = tools
            .map { "\($0.server)/\($0.name): \($0.description)" }
            .joined(separator: "\n")

        let body: [String: Any] = [
            "model": model,
            "messages": [
                [
                    "role": "system",
                    "content": """
                    You are the MojoShell fallback router.
                    Available tools:
                    \(toolList)

                    Return JSON like {"tool":"<tool_name>","server":"<server_name>","arguments":{}} when a tool applies.
                    Otherwise return JSON like {"text":"<plain response>"}.
                    """,
                ],
                [
                    "role": "user",
                    "content": prompt,
                ],
            ],
            "temperature": 0,
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    func resolve(prompt: String, availableTools: [LLMToolDefinition]) async throws -> LLMResponse {
        let request = try buildURLRequest(prompt: prompt, tools: availableTools)
        let (data, _) = try await URLSession.shared.data(for: request)

        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = json["choices"] as? [[String: Any]],
            let first = choices.first,
            let message = first["message"] as? [String: Any],
            let text = message["content"] as? String,
            !text.isEmpty
        else {
            return LLMResponse(text: "No response", resolvedTool: nil)
        }

        guard
            let jsonData = text.data(using: .utf8),
            let parsed = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
        else {
            return LLMResponse(text: text, resolvedTool: nil)
        }

        if
            let tool = parsed["tool"] as? String,
            let server = parsed["server"] as? String
        {
            let arguments = (parsed["arguments"] as? [String: Any] ?? [:]).reduce(into: [String: AnyCodable]()) { partialResult, entry in
                partialResult[entry.key] = AnyCodable(entry.value)
            }

            return LLMResponse(
                text: text,
                resolvedTool: ResolvedTool(server: server, tool: tool, arguments: arguments)
            )
        }

        return LLMResponse(text: text, resolvedTool: nil)
    }
}
