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
    ]

    func route(_ input: String) -> ResolvedTool? {
        let normalized = input
            .lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalized.contains("fcp"), !normalized.contains("final cut"), !normalized.contains("motion") else {
            return nil
        }

        return rules.first(where: { rule in
            rule.phrases.contains(where: { normalized.contains($0) })
        })?.resolvedTool
    }
}
