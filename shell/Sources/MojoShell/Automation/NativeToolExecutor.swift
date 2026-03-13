import AppKit
import Foundation

protocol NativeToolExecuting: Sendable {
    func execute(tool: String, arguments: [String: AnyCodable]) async throws -> MCPToolExecutionResult
}

enum NativeToolName: String, Sendable {
    case finderOpenPath = "finder_open_path"
    case finderOpenRepoRoot = "finder_open_repo_root"
    case finderRevealPath = "finder_reveal_path"
    case finderRevealBrainFile = "finder_reveal_brain_file"
    case finderListSelection = "finder_list_selection"
    case safariOpenURL = "safari_open_url"
    case safariCurrentTab = "safari_current_tab"
    case shortcutsList = "shortcuts_list"
    case shortcutsRun = "shortcuts_run"
    case systemSettingsOpen = "system_settings_open"
}

enum NativeToolError: LocalizedError, Equatable {
    case unknownTool(String)
    case missingArgument(String)
    case invalidURL(String)
    case pathNotFound(String)
    case commandFailed(String)
    case cannotOpenURL(String)

    var errorDescription: String? {
        switch self {
        case .unknownTool(let tool):
            return "Unknown native tool: \(tool)"
        case .missingArgument(let name):
            return "Missing required argument: \(name)"
        case .invalidURL(let url):
            return "Invalid URL: \(url)"
        case .pathNotFound(let path):
            return "Path not found: \(path)"
        case .commandFailed(let detail):
            return detail
        case .cannotOpenURL(let pane):
            return "Could not open System Settings pane: \(pane)"
        }
    }
}

actor NativeToolExecutor: NativeToolExecuting {
    static let serverName = "shell-native"

    private let repoRoot: String
    private let appleAutomation: any AppleAutomationProviding
    private let commandRunner: @Sendable (String, [String], String?) async throws -> String
    private let urlOpener: @Sendable (URL) async -> Bool

    init(
        repoRoot: String,
        appleAutomation: (any AppleAutomationProviding)? = nil,
        commandRunner: @escaping @Sendable (String, [String], String?) async throws -> String = NativeToolExecutor.defaultCommandRunner,
        urlOpener: @escaping @Sendable (URL) async -> Bool = { url in
            await MainActor.run { NSWorkspace.shared.open(url) }
        }
    ) {
        self.repoRoot = repoRoot
        self.appleAutomation = appleAutomation ?? AppleScriptAutomationAdapter()
        self.commandRunner = commandRunner
        self.urlOpener = urlOpener
    }

    init(
        repoRoot: String,
        appleScriptRunner: @escaping @Sendable (String) async throws -> String,
        commandRunner: @escaping @Sendable (String, [String], String?) async throws -> String = NativeToolExecutor.defaultCommandRunner,
        urlOpener: @escaping @Sendable (URL) async -> Bool = { url in
            await MainActor.run { NSWorkspace.shared.open(url) }
        }
    ) {
        self.init(
            repoRoot: repoRoot,
            appleAutomation: ScriptBackedAppleAutomation(scriptRunner: appleScriptRunner),
            commandRunner: commandRunner,
            urlOpener: urlOpener
        )
    }

    func execute(tool: String, arguments: [String: AnyCodable]) async throws -> MCPToolExecutionResult {
        guard let name = NativeToolName(rawValue: tool) else {
            throw NativeToolError.unknownTool(tool)
        }

        switch name {
        case .finderOpenPath:
            let path = try requiredString("path", from: arguments)
            let expanded = expandPath(path)
            try ensurePathExists(expanded)
            try await appleAutomation.openFinderPath(expanded)
            return result(tool: tool, text: "Opened in Finder: \(expanded)")

        case .finderOpenRepoRoot:
            try await appleAutomation.openFinderPath(repoRoot)
            return result(tool: tool, text: "Opened repo root in Finder: \(repoRoot)")

        case .finderRevealPath:
            let path = try requiredString("path", from: arguments)
            let expanded = expandPath(path)
            try ensurePathExists(expanded)
            try await appleAutomation.revealFinderPath(expanded)
            return result(tool: tool, text: "Revealed in Finder: \(expanded)")

        case .finderRevealBrainFile:
            let path = "\(repoRoot)/knowledge-corpus/data/mojosolo_operating_brain.json"
            try ensurePathExists(path)
            try await appleAutomation.revealFinderPath(path)
            return result(tool: tool, text: "Revealed brain file in Finder: \(path)")

        case .finderListSelection:
            let selection = try await appleAutomation.listFinderSelection()
            let trimmed = selection.joined(separator: "\n")
            return result(
                tool: tool,
                text: trimmed.isEmpty ? "Finder selection is empty." : trimmed,
                payload: .array(selection.map(AnyCodable.string))
            )

        case .safariOpenURL:
            let rawURL = try requiredString("url", from: arguments)
            guard let normalizedURL = normalizedURL(from: rawURL) else {
                throw NativeToolError.invalidURL(rawURL)
            }
            try await appleAutomation.openSafariURL(normalizedURL)
            return result(tool: tool, text: "Opened in Safari: \(normalizedURL)")

        case .safariCurrentTab:
            let tab = try await appleAutomation.currentSafariTab()
            return result(
                tool: tool,
                text: "\(tab.title)\n\(tab.url)",
                payload: .object([
                    "title": .string(tab.title),
                    "url": .string(tab.url),
                ])
            )

        case .shortcutsList:
            let output = try await commandRunner("/usr/bin/shortcuts", ["list"], nil)
            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
            let names = trimmed.isEmpty ? [] : trimmed.split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            return result(
                tool: tool,
                text: trimmed.isEmpty ? "No shortcuts found." : trimmed,
                payload: .array(names.map(AnyCodable.string))
            )

        case .shortcutsRun:
            let name = try requiredString("name", from: arguments)
            let input = optionalString("input", from: arguments)
            var commandArguments = ["run", name, "--output-path", "-"]
            if input != nil {
                commandArguments.append(contentsOf: ["--input-path", "-"])
            }
            let output = try await commandRunner("/usr/bin/shortcuts", commandArguments, input)
            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
            return result(
                tool: tool,
                text: trimmed.isEmpty ? "Shortcut '\(name)' completed with no stdout." : trimmed,
                payload: .object([
                    "name": .string(name),
                    "input_provided": .bool(input != nil),
                    "stdout": .string(trimmed),
                ])
            )

        case .systemSettingsOpen:
            let pane = try requiredString("pane", from: arguments)
            guard let url = systemSettingsURL(for: pane) else {
                throw NativeToolError.cannotOpenURL(pane)
            }
            let didOpen = await urlOpener(url)
            guard didOpen else {
                throw NativeToolError.cannotOpenURL(pane)
            }
            return result(tool: tool, text: "Opened System Settings: \(pane)")
        }
    }

    private func result(tool: String, text: String, payload: AnyCodable? = nil) -> MCPToolExecutionResult {
        MCPToolExecutionResult(server: Self.serverName, tool: tool, text: text, payload: payload)
    }

    private func requiredString(_ key: String, from arguments: [String: AnyCodable]) throws -> String {
        guard case .string(let value)? = arguments[key], !value.isEmpty else {
            throw NativeToolError.missingArgument(key)
        }
        return value
    }

    private func optionalString(_ key: String, from arguments: [String: AnyCodable]) -> String? {
        guard case .string(let value)? = arguments[key], !value.isEmpty else {
            return nil
        }
        return value
    }

    private func expandPath(_ path: String) -> String {
        (path as NSString).expandingTildeInPath
    }

    private func ensurePathExists(_ path: String) throws {
        guard FileManager.default.fileExists(atPath: path) else {
            throw NativeToolError.pathNotFound(path)
        }
    }

    private func systemSettingsURL(for pane: String) -> URL? {
        let path: String
        switch pane {
        case "accessibility":
            path = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        case "screen_recording":
            path = "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        case "automation":
            path = "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"
        case "full_disk_access":
            path = "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
        default:
            return nil
        }
        return URL(string: path)
    }

    private func normalizedURL(from rawURL: String) -> String? {
        let trimmed = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        if trimmed.lowercased().hasPrefix("http://") || trimmed.lowercased().hasPrefix("https://") {
            return URL(string: trimmed) != nil ? trimmed : nil
        }

        if trimmed.contains(" "), !trimmed.contains(".") {
            return nil
        }

        let withScheme = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        return URL(string: withScheme) != nil ? withScheme : nil
    }

    private static func defaultCommandRunner(_ executable: String, _ arguments: [String], _ stdin: String?) async throws -> String {
        try await ProcessCommandRunner.run(executable, arguments, stdin)
    }
}

private actor ScriptBackedAppleAutomation: AppleAutomationProviding {
    private let scriptRunner: @Sendable (String) async throws -> String

    init(scriptRunner: @escaping @Sendable (String) async throws -> String) {
        self.scriptRunner = scriptRunner
    }

    func openFinderPath(_ path: String) async throws {
        _ = try await scriptRunner("""
        tell application "Finder"
            activate
            open POSIX file "\(escape(path))"
        end tell
        """)
    }

    func revealFinderPath(_ path: String) async throws {
        _ = try await scriptRunner("""
        tell application "Finder"
            activate
            reveal POSIX file "\(escape(path))"
        end tell
        """)
    }

    func listFinderSelection() async throws -> [String] {
        let output = try await scriptRunner("""
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

        return output
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
                make new document with properties {URL:"\(escape(url))"}
            else
                set URL of current tab of front window to "\(escape(url))"
            end if
        end tell
        """)
    }

    func currentSafariTab() async throws -> SafariTabState {
        let output = try await scriptRunner("""
        tell application "Safari"
            if (count of windows) is 0 then error "Safari has no open windows."
            set tabName to name of current tab of front window
            set tabURL to URL of current tab of front window
            return tabName & linefeed & tabURL
        end tell
        """)

        let lines = output
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        return SafariTabState(title: lines.first ?? "Unknown", url: lines.dropFirst().first ?? "")
    }

    private func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
