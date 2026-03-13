import Foundation

enum MediaJobStatus: String, Codable, Equatable, Sendable {
    case queued
    case running
    case completed
    case failed
    case canceled
}

struct MediaJob: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let name: String
    let client: String
    var status: MediaJobStatus
    var progress: Double
    let createdAt: Date
    var completedAt: Date?
    var errorMessage: String?
    var workflowPreset: ProductionWorkflowPreset?
    var appTarget: WorkflowAppTarget?
    var exportTargetName: String?
    var exportTargetPath: String?
    var sourceAssets: [SourceAsset]
    var notes: String?
    var workflowVersion: String
    var approvalMode: WorkflowApprovalMode

    init(
        id: UUID = UUID(),
        name: String,
        client: String,
        status: MediaJobStatus,
        progress: Double,
        createdAt: Date,
        completedAt: Date?,
        errorMessage: String?,
        workflowPreset: ProductionWorkflowPreset? = nil,
        appTarget: WorkflowAppTarget? = nil,
        exportTargetName: String? = nil,
        exportTargetPath: String? = nil,
        sourceAssets: [SourceAsset] = [],
        notes: String? = nil,
        workflowVersion: String = "v1",
        approvalMode: WorkflowApprovalMode = .smart
    ) {
        self.id = id
        self.name = name
        self.client = client
        self.status = status
        self.progress = progress
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.errorMessage = errorMessage
        self.workflowPreset = workflowPreset
        self.appTarget = appTarget
        self.exportTargetName = exportTargetName
        self.exportTargetPath = exportTargetPath
        self.sourceAssets = sourceAssets
        self.notes = notes
        self.workflowVersion = workflowVersion
        self.approvalMode = approvalMode
    }
}
