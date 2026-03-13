import XCTest
@testable import MojoShell

final class MediaSupportTests: XCTestCase {
    func testSourceAssetFromTextFileClassifiesDocument() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).txt")
        try "hello".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let asset = try XCTUnwrap(SourceAsset.from(path: url.path))
        XCTAssertEqual(asset.name, url.lastPathComponent)
        XCTAssertEqual(asset.kind, .document)
        XCTAssertEqual(asset.byteSize, 5)
    }

    func testDocumentInspectorReturnsMetadataForFile() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).txt")
        try "hello".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let metadata = try XCTUnwrap(DocumentInspector.inspect(path: url.path))
        XCTAssertEqual(metadata.name, url.lastPathComponent)
        XCTAssertEqual(metadata.kind, .document)
        XCTAssertEqual(metadata.byteSize, 5)
        XCTAssertNotNil(metadata.modifiedAt)
    }
}
