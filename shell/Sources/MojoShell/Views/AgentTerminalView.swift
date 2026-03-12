import SwiftUI

struct TerminalEntry: Identifiable, Equatable {
    let id = UUID()
    let role: Role
    let text: String
    let timestamp = Date()

    enum Role: Equatable {
        case user
        case agent
        case system
    }
}

struct AgentTerminalView: View {
    @EnvironmentObject private var appState: AppState
    @State private var input = ""
    @State private var history: [TerminalEntry] = [
        TerminalEntry(role: .system, text: "MojoShell Agent Terminal ready. Type a command.")
    ]
    @State private var isProcessing = false

    private let deterministicRouter = DeterministicRouter()

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(history) { entry in
                            TerminalEntryRow(entry: entry)
                                .id(entry.id)
                        }
                    }
                    .padding()
                }
                .onChange(of: history.count) { _, _ in
                    if let id = history.last?.id {
                        proxy.scrollTo(id, anchor: .bottom)
                    }
                }
            }

            Divider()

            HStack {
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
        history.append(TerminalEntry(role: .user, text: command))

        if let tool = deterministicRouter.route(command) {
            history.append(TerminalEntry(role: .system, text: "→ deterministic route: \(tool.server)/\(tool.tool)"))
            let result = await appState.execute(tool)
            switch result {
            case .success(let output):
                history.append(TerminalEntry(role: .agent, text: output.text))
            case .failure(let error):
                history.append(TerminalEntry(role: .agent, text: "Error: \(error.localizedDescription)"))
            }
        } else {
            history.append(TerminalEntry(role: .system, text: "→ escalating to Claude (\(appState.llmProviderName))..."))
            let result = await appState.resolveWithLLM(
                prompt: command,
                availableTools: deterministicRouter.availableTools
            )
            switch result {
            case .success(let text):
                history.append(TerminalEntry(role: .agent, text: text))
            case .failure(let error):
                history.append(TerminalEntry(role: .agent, text: "LLM error: \(error.localizedDescription)"))
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
