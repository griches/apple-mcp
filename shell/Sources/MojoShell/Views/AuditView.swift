import SwiftUI

struct AuditView: View {
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
                                HStack(alignment: .top, spacing: 4) {
                                    Text(key)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    Text(event.metadata[key] ?? "")
                                        .font(.caption2)
                                        .textSelection(.enabled)
                                }
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
