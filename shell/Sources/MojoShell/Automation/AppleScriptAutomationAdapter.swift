import Foundation

struct SafariTabState: Equatable, Sendable {
    let title: String
    let url: String
}

protocol AppleAutomationProviding: Sendable {
    func openFinderPath(_ path: String) async throws
    func revealFinderPath(_ path: String) async throws
    func listFinderSelection() async throws -> [String]
    func openSafariURL(_ url: String) async throws
    func currentSafariTab() async throws -> SafariTabState
    func runTerminalCommand(_ command: String, in path: String) async throws
    func runITermCommand(_ command: String, in path: String) async throws
}

actor AppleScriptAutomationAdapter: AppleAutomationProviding {
    private let scriptRunner: @Sendable (String) async throws -> String

    init(
        scriptRunner: @escaping @Sendable (String) async throws -> String = AppleScriptAutomationAdapter.defaultScriptRunner
    ) {
        self.scriptRunner = scriptRunner
    }

    func openFinderPath(_ path: String) async throws {
        _ = try await scriptRunner("""
        tell application "Finder"
            activate
            open POSIX file "\(escapeAppleScriptString(path))"
        end tell
        """)
    }

    func revealFinderPath(_ path: String) async throws {
        _ = try await scriptRunner("""
        tell application "Finder"
            activate
            reveal POSIX file "\(escapeAppleScriptString(path))"
        end tell
        """)
    }

    func listFinderSelection() async throws -> [String] {
        let selection = try await scriptRunner("""
        tell application "Finder"
            set selectedItems to selection
            set outList to {}
            repeat with anItem in selectedItems
                set end of outList to POSIX path of (anItem as alias)
            end repeat
            set AppleScript's text item delimiters to linefeed
            set joined to outList as string
            set AppleScript's text item delimiters to ""
            return joined
        end tell
        """)

        return selection
            .split(separator: "\n")
            .map(String.init)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    func openSafariURL(_ url: String) async throws {
        _ = try await scriptRunner("""
        tell application "Safari"
            activate
            if (count of windows) is 0 then
                make new document with properties {URL:"\(escapeAppleScriptString(url))"}
            else
                set URL of current tab of front window to "\(escapeAppleScriptString(url))"
            end if
        end tell
        """)
    }

    func currentSafariTab() async throws -> SafariTabState {
        let response = try await scriptRunner("""
        tell application "Safari"
            if (count of windows) is 0 then error "Safari has no open windows."
            set tabName to name of current tab of front window
            set tabURL to URL of current tab of front window
            return tabName & linefeed & tabURL
        end tell
        """)

        let lines = response
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)

        return SafariTabState(
            title: lines.first ?? "Unknown",
            url: lines.dropFirst().first ?? ""
        )
    }

    func runTerminalCommand(_ command: String, in path: String) async throws {
        _ = try await scriptRunner("""
        tell application "Terminal"
            activate
            if (count of windows) is 0 then
                do script ""
            end if
            do script "cd " & quoted form of "\(escapeAppleScriptString(path))" & "; " & "\(escapeAppleScriptString(command))" in front window
        end tell
        """)
    }

    func runITermCommand(_ command: String, in path: String) async throws {
        _ = try await scriptRunner("""
        tell application "iTerm"
            activate
            if (count of windows) is 0 then
                create window with default profile
            end if
            tell current session of current window
                write text "cd " & quoted form of "\(escapeAppleScriptString(path))" & "; " & "\(escapeAppleScriptString(command))"
            end tell
        end tell
        """)
    }

    private func escapeAppleScriptString(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func defaultScriptRunner(script: String) async throws -> String {
        try await ProcessCommandRunner.run("/usr/bin/osascript", ["-e", script], nil)
    }
}
