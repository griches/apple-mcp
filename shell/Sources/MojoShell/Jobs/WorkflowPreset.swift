import Foundation

enum WorkflowAppTarget: String, Codable, CaseIterable, Equatable, Sendable {
    case finalCutPro = "Final Cut Pro"
    case motion = "Motion"
}

enum ProductionWorkflowPreset: String, Codable, CaseIterable, Identifiable, Sendable {
    case fcpExportCurrentTimeline
    case fcpMonitorBackgroundTasks
    case motionPlaceholderReview
    case motionPlaceholderExport

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fcpExportCurrentTimeline:
            return "FCP Export Current Timeline"
        case .fcpMonitorBackgroundTasks:
            return "FCP Monitor Background Tasks"
        case .motionPlaceholderReview:
            return "Motion Placeholder Review"
        case .motionPlaceholderExport:
            return "Motion Placeholder Export"
        }
    }

    var summary: String {
        switch self {
        case .fcpExportCurrentTimeline:
            return "Open Final Cut Pro, prepare the share sheet, and guide export approval."
        case .fcpMonitorBackgroundTasks:
            return "Open Final Cut Pro background tasks for render/export monitoring."
        case .motionPlaceholderReview:
            return "Reserve a Motion review workflow slot while real automation is still pending."
        case .motionPlaceholderExport:
            return "Reserve a Motion export workflow slot until Motion automation is implemented."
        }
    }

    var appTarget: WorkflowAppTarget {
        switch self {
        case .fcpExportCurrentTimeline, .fcpMonitorBackgroundTasks:
            return .finalCutPro
        case .motionPlaceholderReview, .motionPlaceholderExport:
            return .motion
        }
    }

    var requiresExportTarget: Bool {
        switch self {
        case .fcpExportCurrentTimeline, .motionPlaceholderExport:
            return true
        case .fcpMonitorBackgroundTasks, .motionPlaceholderReview:
            return false
        }
    }

    var isPlaceholder: Bool {
        switch self {
        case .motionPlaceholderReview, .motionPlaceholderExport:
            return true
        case .fcpExportCurrentTimeline, .fcpMonitorBackgroundTasks:
            return false
        }
    }

    var workflowVersion: String {
        switch self {
        case .fcpExportCurrentTimeline:
            return "fcp-export-v2"
        case .fcpMonitorBackgroundTasks:
            return "fcp-monitor-v1"
        case .motionPlaceholderReview:
            return "motion-review-v1"
        case .motionPlaceholderExport:
            return "motion-export-v1"
        }
    }

    var supportsSourceAssets: Bool {
        switch self {
        case .fcpExportCurrentTimeline, .motionPlaceholderReview, .motionPlaceholderExport:
            return true
        case .fcpMonitorBackgroundTasks:
            return false
        }
    }
}

struct WorkflowPlan: Sendable {
    let preset: ProductionWorkflowPreset
    let steps: [WorkflowStep]
    let requiresExportPreflight: Bool
    let completionMessage: String
    let placeholderMessage: String?
}
