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
            workflowPlanProvider: { job in
                WorkflowPlan(
                    preset: job.workflowPreset ?? .fcpExportCurrentTimeline,
                    steps: [WorkflowStep.keypress("Test Step", key: "cmd+e", delay: 0)],
                    requiresExportPreflight: false,
                    completionMessage: "Test workflow complete.",
                    placeholderMessage: nil
                )
            }
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
        let notifications = TestNotificationManager()

        let controller = ProductionController(
            computerUseProvider: ControllerTestComputerUseProvider(),
            notifications: notifications,
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

        let delivered = await notifications.delivered()
        XCTAssertEqual(delivered.last?.title, "MojoShell Job Failed")
        XCTAssertEqual(delivered.last?.body, "Run Job")
    }

    func testRetryFailedJobRequeuesIt() async throws {
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

        guard let failedID = controller.jobs.first?.id else {
            XCTFail("Expected failed job to exist")
            return
        }

        controller.retryFailedJob(id: failedID)

        XCTAssertEqual(controller.jobs.first?.status, .queued)
        XCTAssertNil(controller.jobs.first?.errorMessage)
        XCTAssertEqual(controller.jobs.first?.progress, 0.0)

        let events = try eventStore.load()
        XCTAssertTrue(events.contains(where: { $0.message == "Job requeued for retry" }))
    }

    func testQueueWorkflowJobStoresPresetAndExportTarget() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mojoshell-production-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let exportTargetStore = ExportTargetStore(fileURL: root.appendingPathComponent("export-targets.json"))
        let jobStore = JobStore(fileURL: root.appendingPathComponent("jobs.json"))
        let eventStore = JobEventStore(fileURL: root.appendingPathComponent("events.json"))
        let screenshotStore = ScreenshotStore(directoryURL: root.appendingPathComponent("screens"))
        let targetPath = root.appendingPathComponent("exports").path
        try exportTargetStore.save([
            ExportTarget(name: "Exports", path: targetPath, isDefault: true),
        ])

        let controller = ProductionController(
            computerUseProvider: ControllerTestComputerUseProvider(),
            jobStore: jobStore,
            eventStore: eventStore,
            screenshotStore: screenshotStore,
            exportTargetStore: exportTargetStore,
            preflightCheck: {},
            stepsProvider: { [] }
        )

        controller.queueWorkflowJob(
            client: "QA",
            preset: .fcpExportCurrentTimeline,
            sourceAssets: [
                SourceAsset(
                    path: "/tmp/input.mov",
                    name: "input.mov",
                    kind: .video,
                    byteSize: 1024
                ),
            ],
            notes: "operator note",
            approvalMode: .alwaysAsk
        )

        XCTAssertEqual(controller.jobs.last?.workflowPreset, .fcpExportCurrentTimeline)
        XCTAssertEqual(controller.jobs.last?.exportTargetPath, targetPath)
        XCTAssertEqual(controller.jobs.last?.appTarget, .finalCutPro)
        XCTAssertEqual(controller.jobs.last?.sourceAssets.count, 1)
        XCTAssertEqual(controller.jobs.last?.notes, "operator note")
        XCTAssertEqual(controller.jobs.last?.approvalMode, .alwaysAsk)
    }

    func testMotionPlaceholderCompletesWithoutStartingComputerUseSession() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mojoshell-production-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let provider = ControllerTestComputerUseProvider()
        let controller = ProductionController(
            computerUseProvider: provider,
            jobStore: JobStore(fileURL: root.appendingPathComponent("jobs.json")),
            eventStore: JobEventStore(fileURL: root.appendingPathComponent("events.json")),
            screenshotStore: ScreenshotStore(directoryURL: root.appendingPathComponent("screens"))
        )

        controller.queueWorkflowJob(client: "QA", preset: .motionPlaceholderReview)
        await controller.runNextWorkflow()

        let startedSessionCount = await provider.startedSessionCount()
        XCTAssertEqual(controller.jobs.first?.status, .completed)
        XCTAssertEqual(startedSessionCount, 0)
        XCTAssertTrue(controller.workflowLog.contains("placeholder"))
    }

    func testRunWorkflowWaitsForApprovalAndCompletesWhenApproved() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mojoshell-production-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let jobStore = JobStore(fileURL: root.appendingPathComponent("jobs.json"))
        let eventStore = JobEventStore(fileURL: root.appendingPathComponent("events.json"))
        let screenshotStore = ScreenshotStore(directoryURL: root.appendingPathComponent("screens"))
        let notifications = TestNotificationManager()

        let controller = ProductionController(
            computerUseProvider: ControllerTestComputerUseProvider(),
            notifications: notifications,
            jobStore: jobStore,
            eventStore: eventStore,
            screenshotStore: screenshotStore,
            preflightCheck: {},
            workflowPlanProvider: { job in
                WorkflowPlan(
                    preset: job.workflowPreset ?? .fcpExportCurrentTimeline,
                    steps: [
                        WorkflowStep.keypress(
                            "Approve Export",
                            key: "cmd+e",
                            approvalPrompt: "Confirm export settings",
                            delay: 0
                        ),
                    ],
                    requiresExportPreflight: false,
                    completionMessage: "Approval workflow complete.",
                    placeholderMessage: nil
                )
            }
        )

        controller.queueAssemblyJob(name: "Approval Job", client: "QA")
        let runTask = Task { await controller.runNextAssemblyWorkflow() }

        try await waitUntil { controller.pendingApproval != nil }
        XCTAssertEqual(controller.pendingApproval?.stepDescription, "Approve Export")
        XCTAssertEqual(controller.pendingApproval?.prompt, "Confirm export settings")

        controller.approvePendingStep()
        await runTask.value

        XCTAssertNil(controller.pendingApproval)
        XCTAssertEqual(controller.jobs.first?.status, .completed)

        let events = try eventStore.load()
        XCTAssertTrue(events.contains(where: { $0.message.contains("Approval required for step 1") }))
        XCTAssertTrue(events.contains(where: { $0.message.contains("Approval granted for step 1") }))

        let delivered = await notifications.delivered()
        XCTAssertEqual(delivered.last?.title, "MojoShell Job Complete")
        XCTAssertEqual(delivered.last?.body, "Approval Job")
    }

    func testApprovalRejectionCancelsJobAndAllowsRetry() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mojoshell-production-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let jobStore = JobStore(fileURL: root.appendingPathComponent("jobs.json"))
        let eventStore = JobEventStore(fileURL: root.appendingPathComponent("events.json"))
        let screenshotStore = ScreenshotStore(directoryURL: root.appendingPathComponent("screens"))
        let notifications = TestNotificationManager()

        let controller = ProductionController(
            computerUseProvider: ControllerTestComputerUseProvider(),
            notifications: notifications,
            jobStore: jobStore,
            eventStore: eventStore,
            screenshotStore: screenshotStore,
            preflightCheck: {},
            workflowPlanProvider: { job in
                WorkflowPlan(
                    preset: job.workflowPreset ?? .fcpExportCurrentTimeline,
                    steps: [
                        WorkflowStep.keypress(
                            "Approve Export",
                            key: "cmd+e",
                            approvalPrompt: "Confirm export settings",
                            delay: 0
                        ),
                    ],
                    requiresExportPreflight: false,
                    completionMessage: "Approval workflow complete.",
                    placeholderMessage: nil
                )
            }
        )

        controller.queueAssemblyJob(name: "Canceled Job", client: "QA")
        let runTask = Task { await controller.runNextAssemblyWorkflow() }

        try await waitUntil { controller.pendingApproval != nil }
        controller.rejectPendingStep()
        await runTask.value

        XCTAssertEqual(controller.jobs.first?.status, .canceled)
        XCTAssertTrue(controller.jobs.first?.errorMessage?.contains("Approval rejected") ?? false)

        let events = try eventStore.load()
        XCTAssertTrue(events.contains(where: { $0.type == .canceled }))
        XCTAssertTrue(events.contains(where: { $0.message.contains("Approval rejected for step 1") }))

        let delivered = await notifications.delivered()
        XCTAssertEqual(delivered.last?.title, "MojoShell Job Canceled")
        XCTAssertEqual(delivered.last?.body, "Canceled Job")

        guard let jobID = controller.jobs.first?.id else {
            XCTFail("Expected canceled job")
            return
        }

        controller.retryFailedJob(id: jobID)
        XCTAssertEqual(controller.jobs.first?.status, .queued)
        XCTAssertNil(controller.jobs.first?.errorMessage)
    }

    func testNeverAskApprovalModeRunsWithoutPendingApproval() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mojoshell-production-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let controller = ProductionController(
            computerUseProvider: ControllerTestComputerUseProvider(),
            jobStore: JobStore(fileURL: root.appendingPathComponent("jobs.json")),
            eventStore: JobEventStore(fileURL: root.appendingPathComponent("events.json")),
            screenshotStore: ScreenshotStore(directoryURL: root.appendingPathComponent("screens")),
            preflightCheck: {},
            workflowPlanProvider: { job in
                WorkflowPlan(
                    preset: job.workflowPreset ?? .fcpExportCurrentTimeline,
                    steps: [
                        WorkflowStep.keypress(
                            "Approve Export",
                            key: "cmd+e",
                            approvalPrompt: "Confirm export settings",
                            delay: 0
                        ),
                    ],
                    requiresExportPreflight: false,
                    completionMessage: "Approval workflow complete.",
                    placeholderMessage: nil
                )
            }
        )

        controller.queueWorkflowJob(client: "QA", preset: .fcpExportCurrentTimeline, approvalMode: .neverAsk)
        await controller.runNextWorkflow()

        XCTAssertNil(controller.pendingApproval)
        XCTAssertEqual(controller.jobs.first?.status, .completed)
    }

    func testAlwaysAskApprovalModePausesEvenWithoutStepPrompt() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mojoshell-production-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let controller = ProductionController(
            computerUseProvider: ControllerTestComputerUseProvider(),
            jobStore: JobStore(fileURL: root.appendingPathComponent("jobs.json")),
            eventStore: JobEventStore(fileURL: root.appendingPathComponent("events.json")),
            screenshotStore: ScreenshotStore(directoryURL: root.appendingPathComponent("screens")),
            preflightCheck: {},
            workflowPlanProvider: { job in
                WorkflowPlan(
                    preset: job.workflowPreset ?? .fcpExportCurrentTimeline,
                    steps: [
                        WorkflowStep.keypress("Background Step", key: "cmd+9", delay: 0),
                    ],
                    requiresExportPreflight: false,
                    completionMessage: "Approval workflow complete.",
                    placeholderMessage: nil
                )
            }
        )

        controller.queueWorkflowJob(client: "QA", preset: .fcpMonitorBackgroundTasks, approvalMode: .alwaysAsk)
        let runTask = Task { await controller.runNextWorkflow() }

        try await waitUntil { controller.pendingApproval != nil }
        XCTAssertEqual(controller.pendingApproval?.stepDescription, "Background Step")

        controller.approvePendingStep()
        await runTask.value

        XCTAssertEqual(controller.jobs.first?.status, .completed)
    }

    func testEventsForJobReturnsOnlyMatchingHistory() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mojoshell-production-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let jobOne = MediaJob(
            id: UUID(),
            name: "Job One",
            client: "QA",
            status: .completed,
            progress: 1.0,
            createdAt: Date(),
            completedAt: Date(),
            errorMessage: nil
        )
        let jobTwo = MediaJob(
            id: UUID(),
            name: "Job Two",
            client: "QA",
            status: .queued,
            progress: 0.0,
            createdAt: Date().addingTimeInterval(-60),
            completedAt: nil,
            errorMessage: nil
        )

        let jobStore = JobStore(fileURL: root.appendingPathComponent("jobs.json"))
        try jobStore.save([jobOne, jobTwo])

        let eventStore = JobEventStore(fileURL: root.appendingPathComponent("events.json"))
        try eventStore.save([
            JobEvent(jobID: jobOne.id, timestamp: Date(), type: .completed, message: "one"),
            JobEvent(jobID: jobTwo.id, timestamp: Date().addingTimeInterval(-10), type: .queued, message: "two"),
        ])

        let controller = ProductionController(
            computerUseProvider: ControllerTestComputerUseProvider(),
            jobStore: jobStore,
            eventStore: eventStore,
            screenshotStore: ScreenshotStore(directoryURL: root.appendingPathComponent("screens")),
            preflightCheck: {},
            stepsProvider: { [] }
        )

        let events = controller.events(for: jobOne.id)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.message, "one")
    }

    private func waitUntil(
        timeoutIterations: Int = 100,
        condition: @escaping () -> Bool
    ) async throws {
        for _ in 0..<timeoutIterations {
            if condition() {
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTFail("Timed out waiting for condition")
    }
}

private struct DeliveredNotification: Equatable {
    let title: String
    let body: String
}

private actor TestNotificationManager: AppNotifying {
    private var notifications: [DeliveredNotification] = []

    func deliver(title: String, body: String) async {
        notifications.append(DeliveredNotification(title: title, body: body))
    }

    func delivered() -> [DeliveredNotification] {
        notifications
    }
}

private actor ControllerTestComputerUseProvider: ComputerUseProvider {
    let name = "controller-test-provider"
    private var sessions: Set<String> = []
    private let screenshotAfter: Data?
    private var startCount = 0

    init(screenshotAfter: Data? = nil) {
        self.screenshotAfter = screenshotAfter
    }

    func startSession() async throws -> String {
        let id = UUID().uuidString
        startCount += 1
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

    func startedSessionCount() -> Int {
        startCount
    }
}

private enum ControllerProviderError: Error {
    case unknownSession
}
