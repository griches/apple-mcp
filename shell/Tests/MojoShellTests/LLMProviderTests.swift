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
}
