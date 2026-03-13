import Foundation

struct ShellSessionSnapshot: Codable, Equatable, Sendable {
    var selectedView: ShellView
    var terminalHistory: [TerminalEntry]
    var preferredPreset: ProductionWorkflowPreset
    var preferredExportTargetID: UUID?
    var preferredApprovalMode: WorkflowApprovalMode
}

struct ShellSessionStore {
    let fileURL: URL
    private let fileManager: FileManager

    init(
        fileURL: URL = ShellSessionStore.defaultFileURL(),
        fileManager: FileManager = .default
    ) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    func load() throws -> ShellSessionSnapshot? {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return nil
        }

        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else {
            return nil
        }

        return try JSONDecoder().decode(ShellSessionSnapshot.self, from: data)
    }

    func save(_ snapshot: ShellSessionSnapshot) throws {
        let parent = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: fileURL, options: .atomic)
    }

    static func defaultFileURL() -> URL {
        JobStore.defaultFileURL()
            .deletingLastPathComponent()
            .appendingPathComponent("shell-session.json")
    }
}

@MainActor
final class ShellSessionController: ObservableObject {
    @Published var selectedView: ShellView { didSet { persistIfReady() } }
    @Published var terminalHistory: [TerminalEntry] { didSet { persistIfReady() } }
    @Published var preferredPreset: ProductionWorkflowPreset { didSet { persistIfReady() } }
    @Published var preferredExportTargetID: UUID? { didSet { persistIfReady() } }
    @Published var preferredApprovalMode: WorkflowApprovalMode { didSet { persistIfReady() } }
    @Published var morningOpsRequestID: UUID?

    private let store: ShellSessionStore
    private var isHydrating = true

    init(store: ShellSessionStore = ShellSessionStore()) {
        self.store = store

        let snapshot = (try? store.load()) ?? nil
        self.selectedView = snapshot?.selectedView ?? .cockpit
        self.terminalHistory = snapshot?.terminalHistory ?? [TerminalEntry.initialSystemEntry]
        self.preferredPreset = snapshot?.preferredPreset ?? .fcpExportCurrentTimeline
        self.preferredExportTargetID = snapshot?.preferredExportTargetID
        self.preferredApprovalMode = snapshot?.preferredApprovalMode ?? .smart
        self.isHydrating = false
        persistIfReady()
    }

    func appendTerminalEntry(_ entry: TerminalEntry) {
        terminalHistory.append(entry)
        if terminalHistory.count > 500 {
            terminalHistory.removeFirst(terminalHistory.count - 500)
        }
    }

    func clearTerminalHistory() {
        terminalHistory = [TerminalEntry.initialSystemEntry]
    }

    func requestMorningOpsRun() {
        morningOpsRequestID = UUID()
    }

    private func persistIfReady() {
        guard !isHydrating else {
            return
        }

        do {
            try store.save(
                ShellSessionSnapshot(
                    selectedView: selectedView,
                    terminalHistory: terminalHistory,
                    preferredPreset: preferredPreset,
                    preferredExportTargetID: preferredExportTargetID,
                    preferredApprovalMode: preferredApprovalMode
                )
            )
        } catch {
            // Session persistence should never crash the shell.
        }
    }
}
