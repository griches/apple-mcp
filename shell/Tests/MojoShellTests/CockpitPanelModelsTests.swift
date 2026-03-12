import XCTest
@testable import MojoShell

final class CockpitPanelModelsTests: XCTestCase {
    func testParseBrainOverviewBuildsStructuredPanel() {
        let json = """
        {
          "corpus_name": "mojosolo_operating_brain",
          "corpus_version": "2026.03.12",
          "generated_on": "2026-03-12",
          "target_company": "MojoSolo",
          "target_domain": "mojosolo.com",
          "section_count": 6,
          "sections": ["company_profile", "personas", "signals", "laravel", "ops", "media"],
          "source_count": 14,
          "report_available": true,
          "report_section_count": 9,
          "machine_ingest_entities": ["persona", "signal_rule", "workflow"],
          "corpus_path": "/tmp/brain.json",
          "report_path": "/tmp/brain-report.md"
        }
        """

        let panel = parseBrainOverview(from: json)

        XCTAssertNotNil(panel)
        XCTAssertEqual(panel?.headline, "mojosolo_operating_brain v2026.03.12")
        XCTAssertEqual(panel?.subtitle, "MojoSolo • mojosolo.com")
        XCTAssertEqual(panel?.cards.count, 3)
        XCTAssertEqual(panel?.cards[0].value, "6")
        XCTAssertEqual(panel?.cards[1].detail, "Machine entities: 3")
        XCTAssertEqual(panel?.cards[2].value, "Ready")
        XCTAssertEqual(panel?.sections.count, 6)
        XCTAssertEqual(panel?.machineEntities, ["persona", "signal_rule", "workflow"])
    }

    func testParseNowPlayingBuildsTrackSummary() {
        let json = """
        {
          "state": "playing",
          "volume": 57,
          "shuffle": true,
          "repeat": "all",
          "track": {
            "name": "Iris",
            "artist": "Goo Goo Dolls",
            "album": "Dizzy Up the Girl",
            "duration": 289.0,
            "position": 64.0,
            "loved": true,
            "rating": 100
          }
        }
        """

        let panel = parseNowPlaying(from: json)

        XCTAssertEqual(panel.title, "Iris")
        XCTAssertEqual(panel.subtitle, "Goo Goo Dolls • Dizzy Up the Girl")
        XCTAssertTrue(panel.detail.contains("Playing"))
        XCTAssertTrue(panel.detail.contains("1:04 / 4:49"))
        XCTAssertEqual(panel.status, .live)
    }

    func testParseNowPlayingHandlesErrors() {
        let panel = parseNowPlaying(from: "Error: AppleScript error: No tracks found")

        XCTAssertEqual(panel.title, "Music unavailable")
        XCTAssertEqual(panel.status, .error)
        XCTAssertTrue(panel.subtitle.contains("No tracks found"))
    }
}
