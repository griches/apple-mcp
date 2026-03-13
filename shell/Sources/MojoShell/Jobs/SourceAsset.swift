import Foundation
import UniformTypeIdentifiers

enum SourceAssetKind: String, Codable, CaseIterable, Equatable, Sendable {
    case image
    case video
    case audio
    case folder
    case document
    case other
}

struct SourceAsset: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let path: String
    let name: String
    let kind: SourceAssetKind
    let byteSize: Int64?

    init(
        id: UUID = UUID(),
        path: String,
        name: String,
        kind: SourceAssetKind,
        byteSize: Int64?
    ) {
        self.id = id
        self.path = path
        self.name = name
        self.kind = kind
        self.byteSize = byteSize
    }

    static func from(path: String) -> SourceAsset? {
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
        ])

        let kind = classify(values: values)
        let byteSize = values?.fileSize.map(Int64.init)
        return SourceAsset(
            path: url.path,
            name: values?.name ?? url.lastPathComponent,
            kind: kind,
            byteSize: byteSize
        )
    }

    private static func classify(values: URLResourceValues?) -> SourceAssetKind {
        if values?.isDirectory == true {
            return .folder
        }

        guard let type = values?.contentType else {
            return .other
        }

        if type.conforms(to: .image) {
            return .image
        }
        if type.conforms(to: .movie) || type.conforms(to: .video) {
            return .video
        }
        if type.conforms(to: .audio) {
            return .audio
        }
        if type.conforms(to: .data) || type.conforms(to: .content) || type.conforms(to: .text) {
            return .document
        }
        return .other
    }
}
