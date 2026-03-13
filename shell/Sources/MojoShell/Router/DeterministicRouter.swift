import Foundation

struct DeterministicRouter {
    private struct Rule {
        let phrases: [String]
        let resolvedTool: ResolvedTool
    }

    private let rules: [Rule] = [
        Rule(
            phrases: ["scan today's inboxes", "scan inboxes", "scan my inboxes", "scan inbox", "daily intel scan"],
            resolvedTool: ResolvedTool(server: "mail-intelligence", tool: "scan_persona_inboxes", arguments: [:])
        ),
        Rule(
            phrases: ["persona map", "show personas", "inbox personas"],
            resolvedTool: ResolvedTool(server: "mail-intelligence", tool: "get_persona_map", arguments: [:])
        ),
        Rule(
            phrases: ["signal trends", "signal trend", "compare inbox trends"],
            resolvedTool: ResolvedTool(server: "mail-intelligence", tool: "analyze_signal_trends", arguments: [:])
        ),
        Rule(
            phrases: ["daily brief", "generate brief", "generate daily intel"],
            resolvedTool: ResolvedTool(server: "mail-intelligence", tool: "generate_daily_brief", arguments: [:])
        ),
        Rule(
            phrases: ["pause the music", "pause music", "stop music"],
            resolvedTool: ResolvedTool(server: "apple-music", tool: "pause", arguments: [:])
        ),
        Rule(
            phrases: ["play music", "resume music", "start music"],
            resolvedTool: ResolvedTool(server: "apple-music", tool: "play", arguments: [:])
        ),
        Rule(
            phrases: ["next track", "next song", "skip track"],
            resolvedTool: ResolvedTool(server: "apple-music", tool: "next_track", arguments: [:])
        ),
        Rule(
            phrases: ["previous track", "previous song"],
            resolvedTool: ResolvedTool(server: "apple-music", tool: "previous_track", arguments: [:])
        ),
        Rule(
            phrases: ["now playing", "what's playing", "current track"],
            resolvedTool: ResolvedTool(server: "apple-music", tool: "now_playing", arguments: [:])
        ),
        Rule(
            phrases: ["create note", "new note"],
            resolvedTool: ResolvedTool(server: "apple-notes", tool: "create_note", arguments: [:])
        ),
        Rule(
            phrases: ["search notes", "find note"],
            resolvedTool: ResolvedTool(server: "apple-notes", tool: "search_notes", arguments: [:])
        ),
        Rule(
            phrases: ["list notes", "show my notes"],
            resolvedTool: ResolvedTool(server: "apple-notes", tool: "list_notes", arguments: [:])
        ),
        Rule(
            phrases: ["today's events", "calendar today", "my schedule", "what's on my calendar"],
            resolvedTool: ResolvedTool(server: "apple-calendar", tool: "list_all_events", arguments: [:])
        ),
        Rule(
            phrases: ["create event", "new event", "schedule meeting"],
            resolvedTool: ResolvedTool(server: "apple-calendar", tool: "create_event", arguments: [:])
        ),
        Rule(
            phrases: ["remind me", "add reminder", "create reminder"],
            resolvedTool: ResolvedTool(server: "apple-reminders", tool: "create_reminder", arguments: [:])
        ),
        Rule(
            phrases: ["my reminders", "list reminders"],
            resolvedTool: ResolvedTool(server: "apple-reminders", tool: "list_reminders", arguments: [:])
        ),
        Rule(
            phrases: ["search contacts", "find contact"],
            resolvedTool: ResolvedTool(server: "apple-contacts", tool: "search_contacts", arguments: [:])
        ),
        Rule(
            phrases: ["list contacts", "show contacts"],
            resolvedTool: ResolvedTool(server: "apple-contacts", tool: "list_contacts", arguments: [:])
        ),
        Rule(
            phrases: ["search messages", "find message"],
            resolvedTool: ResolvedTool(server: "apple-messages", tool: "search_messages", arguments: [:])
        ),
        Rule(
            phrases: ["list chats", "show my chats"],
            resolvedTool: ResolvedTool(server: "apple-messages", tool: "list_chats", arguments: [:])
        ),
        Rule(
            phrases: ["search location", "find place", "find location"],
            resolvedTool: ResolvedTool(server: "apple-maps", tool: "search_location", arguments: [:])
        ),
        Rule(
            phrases: ["get directions", "directions to"],
            resolvedTool: ResolvedTool(server: "apple-maps", tool: "get_directions", arguments: [:])
        ),
        Rule(
            phrases: ["list messages", "show my email", "show unread mail"],
            resolvedTool: ResolvedTool(server: "apple-mail", tool: "list_messages", arguments: [:])
        ),
        Rule(
            phrases: ["search email", "search mail"],
            resolvedTool: ResolvedTool(server: "apple-mail", tool: "search_messages", arguments: [:])
        ),
        Rule(
            phrases: ["unread count", "how many unread emails"],
            resolvedTool: ResolvedTool(server: "apple-mail", tool: "get_unread_count", arguments: [:])
        ),
        Rule(
            phrases: ["operator rules", "persona rules", "brain rules"],
            resolvedTool: ResolvedTool(
                server: "knowledge-corpus",
                tool: "get_corpus_section",
                arguments: ["section": .string("persona_architecture")]
            )
        ),
        Rule(
            phrases: ["search brain", "search corpus"],
            resolvedTool: ResolvedTool(server: "knowledge-corpus", tool: "search_corpus", arguments: [:])
        ),
        Rule(
            phrases: ["laravel blueprint", "brain blueprint"],
            resolvedTool: ResolvedTool(server: "knowledge-corpus", tool: "get_laravel_brain_blueprint", arguments: [:])
        ),
        Rule(
            phrases: ["open downloads folder", "show downloads"],
            resolvedTool: ResolvedTool(
                server: NativeToolExecutor.serverName,
                tool: NativeToolName.finderOpenPath.rawValue,
                arguments: ["path": .string("~/Downloads")]
            )
        ),
        Rule(
            phrases: ["open desktop folder", "show desktop folder"],
            resolvedTool: ResolvedTool(
                server: NativeToolExecutor.serverName,
                tool: NativeToolName.finderOpenPath.rawValue,
                arguments: ["path": .string("~/Desktop")]
            )
        ),
        Rule(
            phrases: ["open repo folder", "open repo in finder", "show repo folder"],
            resolvedTool: ResolvedTool(
                server: NativeToolExecutor.serverName,
                tool: NativeToolName.finderOpenRepoRoot.rawValue,
                arguments: [:]
            )
        ),
        Rule(
            phrases: ["reveal brain file", "show brain file"],
            resolvedTool: ResolvedTool(
                server: NativeToolExecutor.serverName,
                tool: NativeToolName.finderRevealBrainFile.rawValue,
                arguments: [:]
            )
        ),
        Rule(
            phrases: ["finder selection", "what is selected in finder", "what's selected in finder"],
            resolvedTool: ResolvedTool(
                server: NativeToolExecutor.serverName,
                tool: NativeToolName.finderListSelection.rawValue,
                arguments: [:]
            )
        ),
        Rule(
            phrases: ["current safari tab", "what's the current safari tab", "what is the current safari tab"],
            resolvedTool: ResolvedTool(
                server: NativeToolExecutor.serverName,
                tool: NativeToolName.safariCurrentTab.rawValue,
                arguments: [:]
            )
        ),
        Rule(
            phrases: ["list shortcuts", "show shortcuts"],
            resolvedTool: ResolvedTool(
                server: NativeToolExecutor.serverName,
                tool: NativeToolName.shortcutsList.rawValue,
                arguments: [:]
            )
        ),
        Rule(
            phrases: ["open accessibility settings"],
            resolvedTool: ResolvedTool(
                server: NativeToolExecutor.serverName,
                tool: NativeToolName.systemSettingsOpen.rawValue,
                arguments: ["pane": .string("accessibility")]
            )
        ),
        Rule(
            phrases: ["open screen recording settings"],
            resolvedTool: ResolvedTool(
                server: NativeToolExecutor.serverName,
                tool: NativeToolName.systemSettingsOpen.rawValue,
                arguments: ["pane": .string("screen_recording")]
            )
        ),
    ]

    var availableTools: [LLMToolDefinition] {
        var seen = Set<String>()
        var tools: [LLMToolDefinition] = []
        for rule in rules {
            let key = "\(rule.resolvedTool.server)/\(rule.resolvedTool.tool)"
            guard seen.insert(key).inserted else { continue }
            tools.append(LLMToolDefinition(
                name: rule.resolvedTool.tool,
                description: rule.phrases.first ?? rule.resolvedTool.tool,
                server: rule.resolvedTool.server
            ))
        }
        tools.append(contentsOf: dynamicToolDefinitions.filter {
            seen.insert("\($0.server)/\($0.name)").inserted
        })
        return tools
    }

    func route(_ input: String) -> ResolvedTool? {
        let raw = input
            .replacingOccurrences(of: "’", with: "'")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = raw
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let dynamicRoute = dynamicRoute(raw: raw, normalized: normalized) {
            return dynamicRoute
        }

        guard !normalized.contains("fcp"), !normalized.contains("final cut"), !normalized.contains("motion") else {
            return nil
        }

        return rules.first(where: { rule in
            rule.phrases.contains(where: { normalized.contains($0) })
        })?.resolvedTool
    }

    private var dynamicToolDefinitions: [LLMToolDefinition] {
        [
            LLMToolDefinition(
                name: NativeToolName.safariOpenURL.rawValue,
                description: "Open a URL in Safari. Arguments: {url}",
                server: NativeToolExecutor.serverName
            ),
            LLMToolDefinition(
                name: NativeToolName.shortcutsRun.rawValue,
                description: "Run a named shortcut. Arguments: {name, input?}",
                server: NativeToolExecutor.serverName
            ),
        ]
    }

    private func dynamicRoute(raw: String, normalized: String) -> ResolvedTool? {
        if normalized.hasPrefix("open "), normalized.hasSuffix(" in safari") {
            let start = raw.index(raw.startIndex, offsetBy: 5)
            let end = raw.index(raw.endIndex, offsetBy: -10)
            let target = String(raw[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)

            if let url = safariURL(from: target) {
                return ResolvedTool(
                    server: NativeToolExecutor.serverName,
                    tool: NativeToolName.safariOpenURL.rawValue,
                    arguments: ["url": .string(url)]
                )
            }
        }

        if normalized.hasPrefix("run shortcut ") {
            let prefixCount = "run shortcut ".count
            let rawRemainder = String(raw.dropFirst(prefixCount)).trimmingCharacters(in: .whitespacesAndNewlines)
            let lowerRemainder = String(normalized.dropFirst(prefixCount)).trimmingCharacters(in: .whitespacesAndNewlines)
            let delimiter = " with input "

            if let range = lowerRemainder.range(of: delimiter) {
                let lowerName = lowerRemainder[..<range.lowerBound]
                let nameEndDistance = lowerRemainder.distance(from: lowerRemainder.startIndex, to: lowerName.endIndex)
                let rawNameEnd = rawRemainder.index(rawRemainder.startIndex, offsetBy: nameEndDistance)
                let name = String(rawRemainder[..<rawNameEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
                let inputStart = rawRemainder.index(rawNameEnd, offsetBy: delimiter.count)
                let input = String(rawRemainder[inputStart...]).trimmingCharacters(in: .whitespacesAndNewlines)

                if !name.isEmpty {
                    var arguments: [String: AnyCodable] = ["name": .string(name)]
                    if !input.isEmpty {
                        arguments["input"] = .string(input)
                    }
                    return ResolvedTool(
                        server: NativeToolExecutor.serverName,
                        tool: NativeToolName.shortcutsRun.rawValue,
                        arguments: arguments
                    )
                }
            } else if !rawRemainder.isEmpty {
                return ResolvedTool(
                    server: NativeToolExecutor.serverName,
                    tool: NativeToolName.shortcutsRun.rawValue,
                    arguments: ["name": .string(rawRemainder)]
                )
            }
        }

        return nil
    }

    private func safariURL(from target: String) -> String? {
        let trimmed = target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        if trimmed.lowercased().hasPrefix("http://") || trimmed.lowercased().hasPrefix("https://") {
            return trimmed
        }

        guard !trimmed.contains(" ") else {
            return nil
        }

        guard trimmed.contains(".") else {
            return nil
        }

        return "https://\(trimmed)"
    }
}
