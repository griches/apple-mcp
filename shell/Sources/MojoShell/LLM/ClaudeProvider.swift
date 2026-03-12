import Foundation

struct ClaudeProvider: LLMProvider {
    let name = "claude"

    private let apiKey: String
    private let model = "claude-sonnet-4-6"
    private let baseURL = URL(string: "https://api.anthropic.com/v1/messages")!

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    func buildURLRequest(prompt: String, tools: [LLMToolDefinition]) throws -> URLRequest {
        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        let toolSchemas = tools.map { tool in
            [
                "name": tool.name,
                "description": tool.description,
                "input_schema": [
                    "type": "object",
                    "properties": [:],
                ] as [String: Any],
            ] as [String: Any]
        }

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 1024,
            "system": """
            You are the MojoShell agent router. Prefer deterministic MCP tool calls.
            When a tool applies, return JSON like:
            {"tool":"<tool_name>","server":"<server_name>","arguments":{}}
            When no tool applies, return JSON like:
            {"text":"<plain response>"}
            """,
            "messages": [
                [
                    "role": "user",
                    "content": prompt,
                ],
            ],
            "tools": toolSchemas,
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    func resolve(prompt: String, availableTools: [LLMToolDefinition]) async throws -> LLMResponse {
        let request = try buildURLRequest(prompt: prompt, tools: availableTools)
        let (data, _) = try await URLSession.shared.data(for: request)

        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let content = json["content"] as? [[String: Any]]
        else {
            return LLMResponse(text: "No response", resolvedTool: nil)
        }

        let text = content
            .compactMap { item in item["text"] as? String }
            .joined(separator: "\n")

        guard !text.isEmpty else {
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

private extension AnyCodable {
    init(_ value: Any) {
        switch value {
        case let string as String:
            self = .string(string)
        case let int as Int:
            self = .int(int)
        case let double as Double:
            self = .double(double)
        case let bool as Bool:
            self = .bool(bool)
        case let object as [String: Any]:
            self = .object(object.mapValues(AnyCodable.init))
        case let array as [Any]:
            self = .array(array.map(AnyCodable.init))
        default:
            self = .null
        }
    }
}
