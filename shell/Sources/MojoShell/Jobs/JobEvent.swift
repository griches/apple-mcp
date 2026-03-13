import Foundation

enum JobEventType: String, Codable, Equatable, Sendable {
    case queued
    case started
    case stepProgress
    case completed
    case failed
    case canceled
    case info
}

struct JobEvent: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let jobID: UUID
    let timestamp: Date
    let type: JobEventType
    let message: String
    let progress: Double?
    let screenshotPath: String?

    init(
        id: UUID = UUID(),
        jobID: UUID,
        timestamp: Date = Date(),
        type: JobEventType,
        message: String,
        progress: Double? = nil,
        screenshotPath: String? = nil
    ) {
        self.id = id
        self.jobID = jobID
        self.timestamp = timestamp
        self.type = type
        self.message = message
        self.progress = progress
        self.screenshotPath = screenshotPath
    }
}
