import Foundation

enum WorkflowApprovalMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case smart
    case alwaysAsk
    case neverAsk

    var id: String { rawValue }

    var title: String {
        switch self {
        case .smart:
            return "Smart"
        case .alwaysAsk:
            return "Always Ask"
        case .neverAsk:
            return "Never Ask"
        }
    }

    var summary: String {
        switch self {
        case .smart:
            return "Only steps that explicitly request approval will pause."
        case .alwaysAsk:
            return "Every workflow step pauses for operator approval."
        case .neverAsk:
            return "All workflow steps auto-run without pausing."
        }
    }
}
