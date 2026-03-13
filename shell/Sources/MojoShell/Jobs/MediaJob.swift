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

    init(
        id: UUID = UUID(),
        name: String,
        client: String,
        status: MediaJobStatus,
        progress: Double,
        createdAt: Date,
        completedAt: Date?,
        errorMessage: String?
    ) {
        self.id = id
        self.name = name
        self.client = client
        self.status = status
        self.progress = progress
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.errorMessage = errorMessage
    }
}
