import Foundation

enum MediaJobStatus: String, Equatable {
    case queued
    case running
    case completed
    case failed
}

struct MediaJob: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let client: String
    var status: MediaJobStatus
    var progress: Double
    let createdAt: Date
    var completedAt: Date?
    var errorMessage: String?
}
