import AppKit
import Foundation
import UniformTypeIdentifiers

struct DocumentMetadata: Equatable, Sendable {
    let path: String
    let name: String
    let kind: SourceAssetKind
    let byteSize: Int64?
    let createdAt: Date?
    let modifiedAt: Date?
    let pixelWidth: Int?
    let pixelHeight: Int?
    let contentType: String?
}

enum DocumentInspector {
    static func inspect(path: String) -> DocumentMetadata? {
        let expanded = (path as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expanded)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }

        let values = try? url.resourceValues(forKeys: [
            .nameKey,
            .contentTypeKey,
            .isDirectoryKey,
            .fileSizeKey,
            .creationDateKey,
            .contentModificationDateKey,
        ])

        let type = values?.contentType
        let kind = SourceAsset.from(path: url.path)?.kind ?? .other
        let dimensions = pixelDimensions(for: url)

        return DocumentMetadata(
            path: url.path,
            name: values?.name ?? url.lastPathComponent,
            kind: kind,
            byteSize: values?.fileSize.map(Int64.init),
            createdAt: values?.creationDate,
            modifiedAt: values?.contentModificationDate,
            pixelWidth: dimensions?.0,
            pixelHeight: dimensions?.1,
            contentType: type?.preferredMIMEType ?? type?.identifier
        )
    }

    private static func pixelDimensions(for url: URL) -> (Int, Int)? {
        guard let image = NSImage(contentsOf: url) else {
            return nil
        }

        if let representation = image.representations.first {
            return (representation.pixelsWide, representation.pixelsHigh)
        }

        let size = image.size
        guard size.width > 0, size.height > 0 else {
            return nil
        }
        return (Int(size.width), Int(size.height))
    }
}
