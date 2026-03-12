import XCTest
@testable import MojoShell

final class MCPClientTests: XCTestCase {
    func testRequestSerialization() throws {
        let request = MCPRequest(id: 1, method: "tools/list", params: [:])
        let data = try JSONEncoder().encode(request)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["jsonrpc"] as? String, "2.0")
        XCTAssertEqual(json["method"] as? String, "tools/list")
    }

    func testResponseParsing() throws {
        let json = """
        {"jsonrpc":"2.0","id":1,"result":{"tools":[{"name":"list_notes","description":"List notes"}]}}
        """.data(using: .utf8)!
        let response = try JSONDecoder().decode(MCPResponse.self, from: json)
        XCTAssertNil(response.error)
        XCTAssertNotNil(response.result)
    }
}
