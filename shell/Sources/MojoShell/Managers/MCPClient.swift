import Foundation

struct MCPRequest: Encodable {
    let jsonrpc = "2.0"
    let id: Int
    let method: String
    let params: [String: AnyCodable]
}

struct MCPResponse: Decodable {
    let jsonrpc: String
    let id: Int?
    let result: MCPResult?
    let error: MCPError?
}

struct MCPResult: Decodable {
    let tools: [MCPTool]?
    let content: [MCPContent]?
}

struct MCPTool: Decodable, Equatable {
    let name: String
    let description: String
}

struct MCPContent: Decodable, Equatable {
    let type: String
    let text: String?
}

struct MCPError: Decodable, Equatable, Error {
    let code: Int
    let message: String
}

enum MCPClientError: Error {
    case invalidProcessPipes
    case emptyResponse
    case decodingFailed(String)
}

actor MCPClient {
    private let stdinHandle: FileHandle
    private let stdoutHandle: FileHandle
    private var nextID = 1

    init(process: Process) throws {
        guard
            let stdin = process.standardInput as? Pipe,
            let stdout = process.standardOutput as? Pipe
        else {
            throw MCPClientError.invalidProcessPipes
        }

        self.stdinHandle = stdin.fileHandleForWriting
        self.stdoutHandle = stdout.fileHandleForReading
    }

    func call(method: String, params: [String: AnyCodable] = [:]) async throws -> MCPResponse {
        let request = MCPRequest(id: nextID, method: method, params: params)
        nextID += 1

        let data = try JSONEncoder().encode(request)
        var payload = data
        payload.append(0x0A)
        stdinHandle.write(payload)

        return try readResponse()
    }

    func callTool(name: String, arguments: [String: AnyCodable] = [:]) async throws -> MCPResponse {
        try await call(
            method: "tools/call",
            params: [
                "name": .string(name),
                "arguments": .object(arguments),
            ]
        )
    }

    private func readResponse() throws -> MCPResponse {
        let rawData = stdoutHandle.availableData
        guard !rawData.isEmpty else {
            throw MCPClientError.emptyResponse
        }

        let output = String(decoding: rawData, as: UTF8.self)
        let lines = output
            .split(separator: "\n")
            .map(String.init)
            .reversed()

        for line in lines {
            guard let lineData = line.data(using: .utf8) else {
                continue
            }

            if let response = try? JSONDecoder().decode(MCPResponse.self, from: lineData) {
                return response
            }
        }

        throw MCPClientError.decodingFailed(output)
    }
}

extension MCPResponse {
    var primaryTextContent: String? {
        result?.content?
            .compactMap(\.text)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum AnyCodable: Codable, Equatable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case object([String: AnyCodable])
    case array([AnyCodable])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode([String: AnyCodable].self) {
            self = .object(value)
        } else if let value = try? container.decode([AnyCodable].self) {
            self = .array(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case .string(let value):
            try container.encode(value)
        case .int(let value):
            try container.encode(value)
        case .double(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
}
