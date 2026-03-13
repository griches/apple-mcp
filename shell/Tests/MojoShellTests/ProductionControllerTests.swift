import XCTest
@testable import MojoShell

@MainActor
final class ProductionControllerTests: XCTestCase {
    func testQueueAssemblyJobPersistsToDisk() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mojoshell-production-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let jobStore = JobStore(fileURL: root.appendingPathComponent("jobs.json"))
        let eventStore = JobEventStore(fileURL: root.appendingPathComponent("events.json"))
        let screenshotStore = ScreenshotStore(directoryURL: root.appendingPathComponent("screens"))

        let controller = ProductionController(
            computerUseProvider: ControllerTestComputerUseProvider(),
            jobStore: jobStore,
            eventStore: eventStore,
            screenshotStore: screenshotStore,
            preflightCheck: {},
            stepsProvider: { [] }
        )

        controller.queueAssemblyJob(name: "Queued Job", client: "QA")
        XCTAssertEqual(controller.jobs.count, 1)

        let onDisk = try jobStore.load()
        XCTAssertEqual(onDisk.count, 1)
        XCTAssertEqual(onDisk[0].name, "Queued Job")
    }

    func testRunNextAssemblyWorkflowCompletesAndPersistsEvents() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mojoshell-production-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let jobStore = JobStore(fileURL: root.appendingPathComponent("jobs.json"))
        let eventStore = JobEventStore(fileURL: root.appendingPathComponent("events.json"))
        let screenshotStore = ScreenshotStore(directoryURL: root.appendingPathComponent("screens"))
        let provider = ControllerTestComputerUseProvider(screenshotAfter: Data([1, 2, 3]))

        let controller = ProductionController(
            computerUseProvider: provider,
            jobStore: jobStore,
            eventStore: eventStore,
            screenshotStore: screenshotStore,
            preflightCheck: {},
            stepsProvider: { [WorkflowStep.keypress("Test Step", key: "cmd+e", delay: 0)] }
        )

        controller.queueAssemblyJob(name: "Run Job", client: "QA")
        await controller.runNextAssemblyWorkflow()

        XCTAssertEqual(controller.jobs.first?.status, .completed)
        XCTAssertEqual(controller.jobs.first?.progress, 1.0)

        let events = try eventStore.load()
        XCTAssertTrue(events.contains(where: { $0.type == .queued }))
        XCTAssertTrue(events.contains(where: { $0.type == .started }))
        XCTAssertTrue(events.contains(where: { $0.type == .completed }))

        let screenshotEvent = events.first(where: { $0.screenshotPath != nil })
        XCTAssertNotNil(screenshotEvent)
        if let screenshotPath = screenshotEvent?.screenshotPath {
            XCTAssertTrue(FileManager.default.fileExists(atPath: screenshotPath))
        }
    }

    func testPreflightFailureMarksJobAsFailed() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mojoshell-production-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let jobStore = JobStore(fileURL: root.appendingPathComponent("jobs.json"))
        let eventStore = JobEventStore(fileURL: root.appendingPathComponent("events.json"))
        let screenshotStore = ScreenshotStore(directoryURL: root.appendingPathComponent("screens"))

        let controller = ProductionController(
            computerUseProvider: ControllerTestComputerUseProvider(),
            jobStore: jobStore,
            eventStore: eventStore,
            screenshotStore: screenshotStore,
            preflightCheck: { throw ProductionControllerError.noExportSelection },
            stepsProvider: { [] }
        )

        controller.queueAssemblyJob(name: "Run Job", client: "QA")
        await controller.runNextAssemblyWorkflow()

        XCTAssertEqual(controller.jobs.first?.status, .failed)
        XCTAssertTrue(controller.jobs.first?.errorMessage?.contains("No exportable clip selected") ?? false)

        let events = try eventStore.load()
        XCTAssertTrue(events.contains(where: { $0.type == .failed }))
    }
}

private actor ControllerTestComputerUseProvider: ComputerUseProvider {
    let name = "controller-test-provider"
    private var sessions: Set<String> = []
    private let screenshotAfter: Data?

    init(screenshotAfter: Data? = nil) {
        self.screenshotAfter = screenshotAfter
    }

    func startSession() async throws -> String {
        let id = UUID().uuidString
        sessions.insert(id)
        return id
    }

    func captureState(sessionId: String) async throws -> ComputerUseState {
        guard sessions.contains(sessionId) else { throw ControllerProviderError.unknownSession }
        return ComputerUseState(appName: "test", screenshotData: nil, timestamp: Date())
    }

    func execute(sessionId: String, action: ComputerUseAction) async throws -> ComputerUseResult {
        guard sessions.contains(sessionId) else { throw ControllerProviderError.unknownSession }
        return ComputerUseResult(success: true, message: "ok \(action.type.rawValue)", screenshotAfter: screenshotAfter)
    }

    func stopSession(sessionId: String) async throws {
        sessions.remove(sessionId)
    }
}

private enum ControllerProviderError: Error {
    case unknownSession
}
