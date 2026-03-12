import AppKit
import ApplicationServices
import Foundation

/// A UI element discovered via the macOS Accessibility API.
struct FoundAXElement: Identifiable, Equatable, Sendable {
    let id: String        // AX identifier or generated UUID string
    let role: String      // e.g. "AXButton", "AXMenuItem"
    let title: String     // AXTitle or AXDescription
    let screenPoint: CGPoint  // Center of the element in global screen coordinates
}

/// Discovers accessible UI elements in a running macOS application.
///
/// Requires the Accessibility permission (System Settings → Privacy & Security → Accessibility).
enum AccessibilityElementFinder {

    enum FinderError: LocalizedError {
        case accessibilityPermissionDenied
        case appNotRunning(String)
        case noElementsFound(String)

        var errorDescription: String? {
            switch self {
            case .accessibilityPermissionDenied:
                return "Accessibility permission denied. Grant access in System Settings → Privacy & Security → Accessibility."
            case .appNotRunning(let name):
                return "\(name) is not running."
            case .noElementsFound(let context):
                return "No accessible elements found: \(context)"
            }
        }
    }

    /// Find all interactive elements (buttons, menu items, text fields) in the named app.
    ///
    /// - Parameters:
    ///   - appName: The app's `localizedName` (e.g. "Final Cut Pro", "Motion").
    ///   - roles: AX roles to include. Pass nil to include all interactive roles.
    ///   - titleContaining: Optional substring filter on element title.
    ///   - maxDepth: How deep to recurse into the AX tree (default: 8).
    static func findElements(
        inApp appName: String,
        roles: [String]? = nil,
        titleContaining titleSubstring: String? = nil,
        maxDepth: Int = 8
    ) throws -> [FoundAXElement] {
        guard AXIsProcessTrusted() else {
            throw FinderError.accessibilityPermissionDenied
        }

        guard let app = runningApp(named: appName) else {
            throw FinderError.appNotRunning(appName)
        }

        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var results: [FoundAXElement] = []
        let interactiveRoles = roles ?? [
            "AXButton", "AXMenuItem", "AXMenuBarItem", "AXComboBox",
            "AXPopUpButton", "AXTextField", "AXCheckBox", "AXRadioButton",
        ]

        collectElements(
            from: axApp,
            roles: interactiveRoles,
            titleFilter: titleSubstring.map { $0.lowercased() },
            depth: 0,
            maxDepth: maxDepth,
            into: &results
        )

        return results
    }

    /// Convenience: find buttons in the named app, optionally filtered by title.
    static func findButtons(
        inApp appName: String,
        titleContaining substring: String? = nil
    ) throws -> [FoundAXElement] {
        try findElements(inApp: appName, roles: ["AXButton"], titleContaining: substring)
    }

    // MARK: - Private

    private static func runningApp(named name: String) -> NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first {
            $0.localizedName == name || $0.bundleIdentifier?.hasSuffix(name) == true
        }
    }

    private static func collectElements(
        from element: AXUIElement,
        roles: [String],
        titleFilter: String?,
        depth: Int,
        maxDepth: Int,
        into results: inout [FoundAXElement]
    ) {
        guard depth <= maxDepth else { return }

        // Check if this element matches
        if let role = stringAttribute(of: element, key: kAXRoleAttribute as CFString),
           roles.contains(role)
        {
            let title = stringAttribute(of: element, key: kAXTitleAttribute as CFString)
                ?? stringAttribute(of: element, key: kAXDescriptionAttribute as CFString)
                ?? stringAttribute(of: element, key: kAXValueAttribute as CFString)
                ?? ""

            let passes = titleFilter == nil || title.lowercased().contains(titleFilter!)

            if passes, let center = elementCenter(of: element) {
                let identifier = stringAttribute(of: element, key: kAXIdentifierAttribute as CFString)
                    ?? "\(role)-\(title)-\(Int(center.x))-\(Int(center.y))"
                results.append(FoundAXElement(
                    id: identifier,
                    role: role,
                    title: title,
                    screenPoint: center
                ))
            }
        }

        // Recurse into children
        var childrenRef: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement]
        else { return }

        for child in children {
            collectElements(
                from: child,
                roles: roles,
                titleFilter: titleFilter,
                depth: depth + 1,
                maxDepth: maxDepth,
                into: &results
            )
        }
    }

    private static func stringAttribute(of element: AXUIElement, key: CFString) -> String? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, key, &value) == .success else { return nil }
        return value as? String
    }

    private static func elementCenter(of element: AXUIElement) -> CGPoint? {
        var positionValue: AnyObject?
        var sizeValue: AnyObject?

        guard
            AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
            AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
            let posAX = positionValue,
            let sizeAX = sizeValue
        else { return nil }

        var position = CGPoint.zero
        var size = CGSize.zero

        // AXValue wraps CGPoint and CGSize
        AXValueGetValue(posAX as! AXValue, .cgPoint, &position)
        AXValueGetValue(sizeAX as! AXValue, .cgSize, &size)

        guard size.width > 0, size.height > 0 else { return nil }

        return CGPoint(
            x: position.x + size.width / 2,
            y: position.y + size.height / 2
        )
    }
}
