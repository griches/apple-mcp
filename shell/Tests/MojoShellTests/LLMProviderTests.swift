import XCTest
@testable import MojoShell

final class LLMProviderTests: XCTestCase {
    func testClaudeProviderName() {
        let provider = ClaudeProvider(apiKey: "test-key")
        XCTAssertEqual(provider.name, "claude")
    }

    func testRequestBuildsCorrectURL() throws {
        let provider = ClaudeProvider(apiKey: "test-key")
        let request = try provider.buildURLRequest(prompt: "scan my inbox", tools: [])
        XCTAssertEqual(request.url?.host, "api.anthropic.com")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertNotNil(request.value(forHTTPHeaderField: "x-api-key"))
    }

    func testOpenAIRequestBuildsCorrectURL() throws {
        let provider = OpenAIProvider(apiKey: "test-key", model: "gpt-test")
        let request = try provider.buildURLRequest(prompt: "scan my inbox", tools: [])
        XCTAssertEqual(request.url?.host, "api.openai.com")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
    }
}
