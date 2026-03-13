import SwiftUI

struct TerminalEntry: Identifiable, Equatable, Codable, Sendable {
    let id: UUID
    let role: Role
    let text: String
    let timestamp: Date

    enum Role: String, Codable, Equatable, Sendable {
        case user
        case agent
        case system
    }

    init(
        id: UUID = UUID(),
        role: Role,
        text: String,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.timestamp = timestamp
    }

    static let initialSystemEntry = TerminalEntry(
        role: .system,
        text: "MojoShell Agent Terminal ready. Type a command."
    )
}

struct AgentTerminalView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var readiness: ReadinessState
    @EnvironmentObject private var session: ShellSessionController
    @State private var input = ""
    @State private var isProcessing = false

    private let deterministicRouter = DeterministicRouter()

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(session.terminalHistory) { entry in
                            TerminalEntryRow(entry: entry)
                                .id(entry.id)
                        }
                    }
                    .padding()
                }
                .onChange(of: session.terminalHistory.count) { _, _ in
                    if let id = session.terminalHistory.last?.id {
                        proxy.scrollTo(id, anchor: .bottom)
                    }
                }
            }

            Divider()

            if !readiness.isReady(for: .llm) {
                Text("LLM fallback unavailable; deterministic routing still works.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 4)
            }

            HStack {
                Button("Clear") {
                    session.clearTerminalHistory()
                }
                .disabled(isProcessing)

                TextField("Type a command...", text: $input)
                    .font(.system(.body, design: .monospaced))
                    .textFieldStyle(.plain)
                    .onSubmit {
                        Task {
                            await submit()
                        }
                    }
                    .disabled(isProcessing)

                Button(isProcessing ? "..." : "↵") {
                    Task {
                        await submit()
                    }
                }
                .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isProcessing)
                .keyboardShortcut(.return, modifiers: [])
            }
            .padding(10)
            .background(.background)
        }
        .navigationTitle("Agent Terminal")
    }

    private func submit() async {
        let command = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else {
            return
        }

        input = ""
        isProcessing = true
        session.appendTerminalEntry(TerminalEntry(role: .user, text: command))

        if let tool = deterministicRouter.route(command) {
            session.appendTerminalEntry(TerminalEntry(role: .system, text: "→ deterministic route: \(tool.server)/\(tool.tool)"))
            let result = await appState.execute(tool)
            switch result {
            case .success(let output):
                session.appendTerminalEntry(TerminalEntry(role: .agent, text: output.text))
            case .failure(let error):
                session.appendTerminalEntry(TerminalEntry(role: .agent, text: "Error: \(error.localizedDescription)"))
            }
        } else {
            session.appendTerminalEntry(TerminalEntry(role: .system, text: "→ escalating to LLM stack (\(appState.llmProviderStackDescription))..."))
            let result = await appState.resolveWithLLM(
                prompt: command,
                availableTools: deterministicRouter.availableTools
            )
            switch result {
            case .success(let text):
                session.appendTerminalEntry(TerminalEntry(role: .agent, text: text))
            case .failure(let error):
                session.appendTerminalEntry(TerminalEntry(role: .agent, text: "LLM error: \(error.localizedDescription)"))
            }
        }

        isProcessing = false
    }
}

struct TerminalEntryRow: View {
    let entry: TerminalEntry

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(prefix)
                .foregroundStyle(color)
                .font(.system(.body, design: .monospaced))
                .frame(width: 60, alignment: .trailing)
            Text(entry.text)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
        }
    }

    private var prefix: String {
        switch entry.role {
        case .user:
            return "you"
        case .agent:
            return "agent"
        case .system:
            return "sys"
        }
    }

    private var color: Color {
        switch entry.role {
        case .user:
            return .primary
        case .agent:
            return .blue
        case .system:
            return .secondary
        }
    }
}
