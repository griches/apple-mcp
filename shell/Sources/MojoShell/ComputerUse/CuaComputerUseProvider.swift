import AppKit
import CoreGraphics
import Foundation

/// Phase 1 computer-use provider.
///
/// Uses CoreGraphics CGEvent for input injection (requires Accessibility permission)
/// and CGWindowListCreateImage for screenshots (requires Screen Recording permission).
/// No external processes or cloud dependency — runs fully local on the host Mac.
///
/// Coordinate format for `action.target`: "x,y" (e.g. "640,400")
/// Key combination format for keypress: "cmd+e", "shift+return", "escape"
/// Text to type: `action.value` (falls back to `action.target`)
actor CuaComputerUseProvider: ComputerUseProvider {
    let name = "cua"

    private var sessions: Set<String> = []

    // MARK: - Protocol

    func startSession() async throws -> String {
        let id = UUID().uuidString
        sessions.insert(id)
        return id
    }

    func captureState(sessionId: String) async throws -> ComputerUseState {
        try requireSession(sessionId)

        let appName = await MainActor.run {
            NSWorkspace.shared.frontmostApplication?.localizedName ?? "Unknown"
        }

        return ComputerUseState(
            appName: appName,
            screenshotData: captureScreenshot(),
            timestamp: Date()
        )
    }

    func execute(sessionId: String, action: ComputerUseAction) async throws -> ComputerUseResult {
        try requireSession(sessionId)

        switch action.type {
        case .click:
            try performClick(target: action.target)
        case .type:
            try performType(text: action.value ?? action.target)
        case .keypress:
            try performKeypress(key: action.target)
        case .scroll:
            try performScroll(target: action.target, deltaString: action.value)
        case .drag:
            try performDrag(from: action.target, to: action.value)
        }

        return ComputerUseResult(
            success: true,
            message: "executed \(action.type.rawValue) → \(action.target)",
            screenshotAfter: captureScreenshot()
        )
    }

    func stopSession(sessionId: String) async throws {
        sessions.remove(sessionId)
    }

    // MARK: - Screenshot

    private func captureScreenshot() -> Data? {
        guard let image = CGWindowListCreateImage(
            .infinite,
            .optionAll,
            kCGNullWindowID,
            [.bestResolution, .boundsIgnoreFraming]
        ) else { return nil }

        let nsImage = NSImage(
            cgImage: image,
            size: NSSize(width: image.width, height: image.height)
        )

        guard
            let tiff = nsImage.tiffRepresentation,
            let rep = NSBitmapImageRep(data: tiff)
        else { return nil }

        return rep.representation(using: .png, properties: [:])
    }

    // MARK: - Input

    private func performClick(target: String) throws {
        let point = try parseCoordinates(target)
        let src = CGEventSource(stateID: .hidSystemState)

        guard
            let down = CGEvent(mouseEventSource: src, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left),
            let up = CGEvent(mouseEventSource: src, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)
        else { throw CuaError.eventCreationFailed }

        down.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.05)
        up.post(tap: .cghidEventTap)
    }

    private func performType(text: String) throws {
        let src = CGEventSource(stateID: .hidSystemState)

        for scalar in text.unicodeScalars {
            var ch = scalar.value
            guard
                let down = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: true),
                let up = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: false)
            else { throw CuaError.eventCreationFailed }

            down.keyboardSetUnicodeString(stringLength: 1, unicodeString: &ch)
            up.keyboardSetUnicodeString(stringLength: 1, unicodeString: &ch)
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
            Thread.sleep(forTimeInterval: 0.02)
        }
    }

    private func performKeypress(key: String) throws {
        let parts = key.lowercased().components(separatedBy: "+")
        let keyName = parts.last ?? key.lowercased()

        guard let keyCode = virtualKeyCode(for: keyName) else {
            throw CuaError.unknownKey(key)
        }

        var flags: CGEventFlags = []
        if parts.contains("cmd") || parts.contains("command") { flags.insert(.maskCommand) }
        if parts.contains("shift") { flags.insert(.maskShift) }
        if parts.contains("opt") || parts.contains("option") || parts.contains("alt") { flags.insert(.maskAlternate) }
        if parts.contains("ctrl") || parts.contains("control") { flags.insert(.maskControl) }

        let src = CGEventSource(stateID: .hidSystemState)
        guard
            let down = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: true),
            let up = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: false)
        else { throw CuaError.eventCreationFailed }

        down.flags = flags
        up.flags = flags
        down.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.05)
        up.post(tap: .cghidEventTap)
    }

    private func performScroll(target: String, deltaString: String?) throws {
        let point = try parseCoordinates(target)
        let delta = deltaString.flatMap(Int32.init) ?? -3
        let src = CGEventSource(stateID: .hidSystemState)

        guard let event = CGEvent(
            scrollWheelEvent2Source: src,
            units: .line,
            wheelCount: 1,
            wheel1: delta,
            wheel2: 0,
            wheel3: 0
        ) else { throw CuaError.eventCreationFailed }

        event.location = point
        event.post(tap: .cghidEventTap)
    }

    private func performDrag(from fromString: String, to toString: String?) throws {
        let from = try parseCoordinates(fromString)
        let to = try toString.map(parseCoordinates) ?? from
        let src = CGEventSource(stateID: .hidSystemState)

        guard
            let down = CGEvent(mouseEventSource: src, mouseType: .leftMouseDown, mouseCursorPosition: from, mouseButton: .left),
            let drag = CGEvent(mouseEventSource: src, mouseType: .leftMouseDragged, mouseCursorPosition: to, mouseButton: .left),
            let up = CGEvent(mouseEventSource: src, mouseType: .leftMouseUp, mouseCursorPosition: to, mouseButton: .left)
        else { throw CuaError.eventCreationFailed }

        down.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.05)
        drag.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.1)
        up.post(tap: .cghidEventTap)
    }

    // MARK: - Helpers

    private func requireSession(_ id: String) throws {
        guard sessions.contains(id) else { throw CuaError.unknownSession }
    }

    private func parseCoordinates(_ string: String) throws -> CGPoint {
        let parts = string
            .split(separator: ",")
            .compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count == 2 else {
            throw CuaError.invalidCoordinates(string)
        }
        return CGPoint(x: parts[0], y: parts[1])
    }

    // swiftlint:disable cyclomatic_complexity
    private func virtualKeyCode(for key: String) -> CGKeyCode? {
        let map: [String: CGKeyCode] = [
            "return": 36, "enter": 36,
            "tab": 48, "space": 49,
            "delete": 51, "backspace": 51,
            "escape": 53, "esc": 53,
            "cmd": 55, "command": 55,
            "shift": 56,
            "option": 58, "alt": 58, "opt": 58,
            "ctrl": 59, "control": 59,
            "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96,
            "f6": 97, "f7": 98, "f8": 100, "f9": 101, "f10": 109,
            "left": 123, "right": 124, "down": 125, "up": 126,
            "a": 0, "b": 11, "c": 8, "d": 2, "e": 14, "f": 3,
            "g": 5, "h": 4, "i": 34, "j": 38, "k": 40, "l": 37,
            "m": 46, "n": 45, "o": 31, "p": 35, "q": 12, "r": 15,
            "s": 1, "t": 17, "u": 32, "v": 9, "w": 13, "x": 7,
            "y": 16, "z": 6,
            "0": 29, "1": 18, "2": 19, "3": 20, "4": 21, "5": 23,
            "6": 22, "7": 26, "8": 28, "9": 25,
        ]
        return map[key.lowercased()]
    }
    // swiftlint:enable cyclomatic_complexity
}

enum CuaError: LocalizedError {
    case unknownSession
    case eventCreationFailed
    case invalidCoordinates(String)
    case unknownKey(String)

    var errorDescription: String? {
        switch self {
        case .unknownSession:
            return "Unknown computer-use session."
        case .eventCreationFailed:
            return "Failed to create CGEvent — grant Accessibility permission in System Settings → Privacy & Security."
        case .invalidCoordinates(let s):
            return "Invalid coordinates '\(s)'. Expected 'x,y' (e.g. '640,400')."
        case .unknownKey(let k):
            return "Unknown key '\(k)'. Use names like 'return', 'esc', 'cmd+e', 'shift+tab'."
        }
    }
}
