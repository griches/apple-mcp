import XCTest
@testable import MojoShell

final class ReadinessModelsTests: XCTestCase {
    func testSeverityCasesExist() {
        let severities: [ReadinessSeverity] = [.info, .warning, .blocking]
        XCTAssertEqual(severities.count, 3)
    }

    func testSeverityIsEquatable() {
        XCTAssertEqual(ReadinessSeverity.blocking, .blocking)
        XCTAssertNotEqual(ReadinessSeverity.blocking, .warning)
    }

    func testIssueStoresValues() {
        let issue = ReadinessIssue(
            id: "test_id",
            title: "Test Title",
            fixInstruction: "Do something",
            actionURL: nil,
            severity: .blocking
        )
        XCTAssertEqual(issue.id, "test_id")
        XCTAssertEqual(issue.title, "Test Title")
        XCTAssertEqual(issue.fixInstruction, "Do something")
        XCTAssertEqual(issue.severity, .blocking)
        XCTAssertNil(issue.actionURL)
    }

    func testIssueIsEquatable() {
        let first = ReadinessIssue(id: "a", title: "A", fixInstruction: "fix", actionURL: nil, severity: .warning)
        let second = ReadinessIssue(id: "a", title: "A", fixInstruction: "fix", actionURL: nil, severity: .warning)
        XCTAssertEqual(first, second)
    }

    func testFeatureCasesExist() {
        let features: Set<ReadinessFeature> = [.computerUse, .llm]
        XCTAssertEqual(features.count, 2)
    }
}
