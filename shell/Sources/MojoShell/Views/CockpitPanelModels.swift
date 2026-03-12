import Foundation

struct PersonaCardData: Identifiable, Equatable {
    let id: String
    let persona: String
    let account: String
    let role: String
    let lane: String
    let isPrimaryReply: Bool
    let isCatchAll: Bool
}

struct BrainOverviewCardData: Identifiable, Equatable {
    let id: String
    let title: String
    let value: String
    let detail: String
}

struct BrainOverviewPanelData: Equatable {
    let headline: String
    let subtitle: String
    let cards: [BrainOverviewCardData]
    let sections: [String]
    let machineEntities: [String]
    let corpusPath: String?
    let reportPath: String?
}

enum NowPlayingStatus: Equatable {
    case live
    case stopped
    case error
}

struct NowPlayingPanelData: Equatable {
    let title: String
    let subtitle: String
    let detail: String
    let status: NowPlayingStatus
    let rawText: String
}

func parsePersonas(from json: String) -> [PersonaCardData] {
    guard
        let data = json.data(using: .utf8),
        let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
        let accounts = root["accounts"] as? [[String: Any]]
    else { return [] }

    return accounts.compactMap { dict in
        guard
            let id = dict["persona_id"] as? String,
            let persona = dict["persona"] as? String,
            let account = dict["account"] as? String
        else { return nil }
        return PersonaCardData(
            id: id,
            persona: persona,
            account: account,
            role: dict["role"] as? String ?? "",
            lane: dict["default_lane"] as? String ?? "",
            isPrimaryReply: dict["primary_reply_from"] as? Bool ?? false,
            isCatchAll: dict["catch_all"] as? Bool ?? false
        )
    }
}

func parseBrainOverview(from json: String) -> BrainOverviewPanelData? {
    guard
        let data = json.data(using: .utf8),
        let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return nil }

    let corpusName = root["corpus_name"] as? String ?? "Unknown Corpus"
    let version = root["corpus_version"] as? String ?? "unknown"
    let company = root["target_company"] as? String ?? "Unknown Company"
    let domain = root["target_domain"] as? String ?? "unknown"
    let sectionCount = root["section_count"] as? Int ?? 0
    let sourceCount = root["source_count"] as? Int ?? 0
    let reportAvailable = root["report_available"] as? Bool ?? false
    let reportSectionCount = root["report_section_count"] as? Int ?? 0
    let machineEntities = stringList(from: root["machine_ingest_entities"])
    let sections = stringList(from: root["sections"])
    let generatedOn = root["generated_on"] as? String ?? "unknown"

    let cards = [
        BrainOverviewCardData(
            id: "sections",
            title: "Sections",
            value: "\(sectionCount)",
            detail: sections.prefix(3).joined(separator: " • ").ifEmpty("No sections reported")
        ),
        BrainOverviewCardData(
            id: "sources",
            title: "Sources",
            value: "\(sourceCount)",
            detail: "Machine entities: \(machineEntities.count)"
        ),
        BrainOverviewCardData(
            id: "report",
            title: "Report",
            value: reportAvailable ? "Ready" : "Missing",
            detail: "Sections: \(reportSectionCount) • Generated: \(generatedOn)"
        ),
    ]

    return BrainOverviewPanelData(
        headline: "\(corpusName) v\(version)",
        subtitle: "\(company) • \(domain)",
        cards: cards,
        sections: sections,
        machineEntities: machineEntities,
        corpusPath: root["corpus_path"] as? String,
        reportPath: root["report_path"] as? String
    )
}

func parseNowPlaying(from text: String) -> NowPlayingPanelData {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
        return NowPlayingPanelData(
            title: "Music idle",
            subtitle: "No playback state available yet",
            detail: "Auto-refresh every 30s",
            status: .stopped,
            rawText: text
        )
    }

    if trimmed.hasPrefix("Error:") {
        return NowPlayingPanelData(
            title: "Music unavailable",
            subtitle: trimmed.replacingOccurrences(of: "Error: ", with: ""),
            detail: "Auto-refresh will retry in 30s",
            status: .error,
            rawText: text
        )
    }

    guard
        let data = trimmed.data(using: .utf8),
        let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
        return NowPlayingPanelData(
            title: "Music response",
            subtitle: trimmed,
            detail: "Auto-refresh every 30s",
            status: .live,
            rawText: text
        )
    }

    let state = (root["state"] as? String ?? "stopped").capitalized
    let volume = root["volume"] as? Int ?? 0
    let shuffleEnabled = root["shuffle"] as? Bool ?? false
    let repeatMode = root["repeat"] as? String ?? "off"

    if let track = root["track"] as? [String: Any] {
        let trackName = track["name"] as? String ?? "Unknown Track"
        let artist = track["artist"] as? String ?? "Unknown Artist"
        let album = track["album"] as? String ?? "Unknown Album"
        let duration = formatDuration(track["duration"] as? Double)
        let position = formatDuration(track["position"] as? Double)
        return NowPlayingPanelData(
            title: trackName,
            subtitle: "\(artist) • \(album)",
            detail: "\(state) • \(position) / \(duration) • Vol \(volume)% • Shuffle \(shuffleEnabled ? "On" : "Off") • Repeat \(repeatMode.capitalized)",
            status: .live,
            rawText: text
        )
    }

    return NowPlayingPanelData(
        title: state,
        subtitle: "Nothing is currently playing",
        detail: "Vol \(volume)% • Shuffle \(shuffleEnabled ? "On" : "Off") • Repeat \(repeatMode.capitalized)",
        status: .stopped,
        rawText: text
    )
}

private func stringList(from value: Any?) -> [String] {
    (value as? [String]) ?? []
}

private func formatDuration(_ seconds: Double?) -> String {
    guard let seconds else { return "--:--" }
    let rounded = max(Int(seconds.rounded()), 0)
    let minutes = rounded / 60
    let remainder = rounded % 60
    return String(format: "%d:%02d", minutes, remainder)
}

private extension String {
    func ifEmpty(_ fallback: String) -> String {
        isEmpty ? fallback : self
    }
}
