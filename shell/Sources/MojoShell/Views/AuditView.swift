import SwiftUI

struct AuditView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var audit: AuditController
    @State private var selectedCategory: AuditCategory?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Operator Audit", systemImage: "clock.arrow.circlepath")
                    .font(.headline)
                Spacer()
                Picker("Category", selection: $selectedCategory) {
                    Text("All").tag(Optional<AuditCategory>.none)
                    ForEach(AuditCategory.allCases, id: \.self) { category in
                        Text(category.rawValue.capitalized).tag(Optional(category))
                    }
                }
                .pickerStyle(.menu)
                Button("Refresh") {
                    audit.refresh()
                }
            }

            Divider()

            if filteredEvents.isEmpty {
                Text("No audit events recorded yet.")
                    .foregroundStyle(.secondary)
            } else {
                List(filteredEvents.reversed()) { event in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(event.timestamp.formatted(date: .abbreviated, time: .standard))
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Text(event.category.rawValue)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        Text(event.title)
                            .font(.headline)
                        Text(event.detail)
                            .font(.caption)
                            .textSelection(.enabled)
                        if !event.metadata.isEmpty {
                            ForEach(event.metadata.keys.sorted(), id: \.self) { key in
                                AuditMetadataRow(key: key, value: event.metadata[key] ?? "")
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .listStyle(.plain)
            }
        }
        .padding()
        .navigationTitle("Audit")
    }

    private var filteredEvents: [AuditEvent] {
        guard let selectedCategory else {
            return audit.events
        }
        return audit.events.filter { $0.category == selectedCategory }
    }
}

private struct AuditMetadataRow: View {
    @EnvironmentObject private var appState: AppState

    let key: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 4) {
                Text(key)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.caption2)
                    .textSelection(.enabled)
            }

            if let path = inspectablePath {
                HStack {
                    Button("Preview") {
                        Task { _ = await appState.openPathInPreview(path) }
                    }
                    Button("Reveal") {
                        Task { _ = await appState.revealFinderPath(path) }
                    }
                }
                .font(.caption2)

                if let metadata = DocumentInspector.inspect(path: path) {
                    Text(metadataSummary(metadata))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var inspectablePath: String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        guard key.lowercased().contains("path") || trimmed.hasPrefix("/") else {
            return nil
        }
        return FileManager.default.fileExists(atPath: trimmed) ? trimmed : nil
    }

    private func metadataSummary(_ metadata: DocumentMetadata) -> String {
        var parts: [String] = []
        if let byteSize = metadata.byteSize {
            parts.append(ByteCountFormatter.string(fromByteCount: byteSize, countStyle: .file))
        }
        if let width = metadata.pixelWidth, let height = metadata.pixelHeight {
            parts.append("\(width) × \(height)")
        }
        if let contentType = metadata.contentType {
            parts.append(contentType)
        }
        return parts.joined(separator: " • ")
    }
}
