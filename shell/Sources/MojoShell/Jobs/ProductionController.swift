import Foundation

struct WorkflowApprovalRequest: Identifiable, Equatable, Sendable {
    let id = UUID()
    let jobID: UUID
    let stepIndex: Int
    let stepDescription: String
    let prompt: String
    let createdAt: Date
}

@MainActor
final class ProductionController: ObservableObject {
    @Published private(set) var jobs: [MediaJob] = []
    @Published private(set) var recentEvents: [JobEvent] = []
    @Published var workflowLog = "Ready. Queue a job, then run the assembly workflow."
    @Published var isRunningWorkflow = false
    @Published private(set) var pendingApproval: WorkflowApprovalRequest?

    private let computerUseProvider: any ComputerUseProvider
    private let notifications: any AppNotifying
    private let jobStore: JobStore
    private let eventStore: JobEventStore
    private let screenshotStore: ScreenshotStore
    private let preflightCheck: @MainActor () throws -> Void
    private let stepsProvider: () -> [WorkflowStep]
    private let now: () -> Date
    private var approvalContinuation: CheckedContinuation<Bool, Never>?

    init(
        computerUseProvider: any ComputerUseProvider,
        notifications: (any AppNotifying)? = nil,
        jobStore: JobStore = JobStore(),
        eventStore: JobEventStore = JobEventStore(),
        screenshotStore: ScreenshotStore = ScreenshotStore(),
        preflightCheck: @escaping @MainActor () throws -> Void = ProductionController.defaultPreflightCheck,
        stepsProvider: @escaping () -> [WorkflowStep] = { FcpWorkflowDefinition.assemblyWorkflow() },
        now: @escaping () -> Date = Date.init
    ) {
        self.computerUseProvider = computerUseProvider
        self.notifications = notifications ?? NullNotificationManager()
        self.jobStore = jobStore
        self.eventStore = eventStore
        self.screenshotStore = screenshotStore
        self.preflightCheck = preflightCheck
        self.stepsProvider = stepsProvider
        self.now = now
        loadFromDisk()
    }

    func queueAssemblyJob(name: String, client: String) {
        let job = MediaJob(
            name: name,
            client: client,
            status: .queued,
            progress: 0.0,
            createdAt: now(),
            completedAt: nil,
            errorMessage: nil
        )
        jobs.append(job)
        persistJobs()
        recordEvent(jobID: job.id, type: .queued, message: "Job queued: \(name)", progress: 0.0)
    }

    func retryFailedJob(id: UUID) {
        guard let index = jobs.firstIndex(where: { $0.id == id && ($0.status == .failed || $0.status == .canceled) }) else {
            return
        }

        jobs[index].status = .queued
        jobs[index].progress = 0.0
        jobs[index].completedAt = nil
        jobs[index].errorMessage = nil
        persistJobs()
        recordEvent(jobID: id, type: .queued, message: "Job requeued for retry", progress: 0.0)
    }

    func approvePendingStep() {
        guard let request = pendingApproval else {
            return
        }
        pendingApproval = nil
        recordEvent(jobID: request.jobID, type: .info, message: "Approval granted for step \(request.stepIndex + 1)")
        approvalContinuation?.resume(returning: true)
        approvalContinuation = nil
    }

    func rejectPendingStep() {
        guard let request = pendingApproval else {
            return
        }
        pendingApproval = nil
        recordEvent(jobID: request.jobID, type: .canceled, message: "Approval rejected for step \(request.stepIndex + 1)")
        approvalContinuation?.resume(returning: false)
        approvalContinuation = nil
    }

    func runNextAssemblyWorkflow() async {
        guard !isRunningWorkflow else {
            return
        }

        guard let queuedIndex = jobs.firstIndex(where: { $0.status == .queued }) else {
            workflowLog = "No queued media job available."
            return
        }

        isRunningWorkflow = true
        defer { isRunningWorkflow = false }

        let jobID = jobs[queuedIndex].id
        workflowLog = "Checking Final Cut Pro export state..."

        do {
            try preflightCheck()
        } catch {
            let message = humanReadablePreflightError(error)
            failJob(id: jobID, message: message)
            workflowLog = message
            await notifications.deliver(title: "MojoShell Job Failed", body: jobTitle(for: jobID))
            return
        }

        updateJob(id: jobID, status: .running, progress: 0.1, completedAt: nil, errorMessage: nil)
        workflowLog = "Starting assembly workflow..."
        recordEvent(jobID: jobID, type: .started, message: "Assembly workflow started", progress: 0.1)

        var sessionId: String?
        do {
            sessionId = try await computerUseProvider.startSession()
            let steps = stepsProvider()
            let stepCount = max(steps.count, 1)
            let executor = WorkflowExecutor(provider: computerUseProvider)

            try await executor.run(
                steps: steps,
                sessionId: sessionId!,
                onProgress: { [weak self] message in
                    Task { @MainActor [weak self] in
                        self?.workflowLog = message
                        if let progress = Self.progressValue(from: message, totalSteps: stepCount) {
                            self?.updateJob(id: jobID, status: .running, progress: progress, completedAt: nil, errorMessage: nil)
                            self?.recordEvent(jobID: jobID, type: .stepProgress, message: message, progress: progress)
                        }
                    }
                },
                onStepResult: { [weak self] stepIndex, _, result in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        guard let screenshot = result.screenshotAfter else { return }
                        do {
                            let url = try self.screenshotStore.save(screenshot, jobID: jobID, stepIndex: stepIndex)
                            self.recordEvent(
                                jobID: jobID,
                                type: .info,
                                message: "Step \(stepIndex + 1): \(result.message)",
                                progress: nil,
                                screenshotPath: url.path
                            )
                        } catch {
                            self.workflowLog = "Screenshot persistence failed: \(error.localizedDescription)"
                        }
                    }
                },
                onApprovalRequested: { [weak self] stepIndex, step in
                    guard let self else { return false }
                    return await self.requestApproval(jobID: jobID, stepIndex: stepIndex, step: step)
                }
            )

            if let sessionId {
                try await computerUseProvider.stopSession(sessionId: sessionId)
            }

            updateJob(id: jobID, status: .completed, progress: 1.0, completedAt: now(), errorMessage: nil)
            workflowLog = "Assembly workflow complete."
            recordEvent(jobID: jobID, type: .completed, message: "Assembly workflow complete", progress: 1.0)
            await notifications.deliver(title: "MojoShell Job Complete", body: jobTitle(for: jobID))
        } catch {
            if let sessionId {
                try? await computerUseProvider.stopSession(sessionId: sessionId)
            }
            pendingApproval = nil

            if let workflowError = error as? WorkflowError,
               case .approvalRejected = workflowError {
                let message = workflowError.localizedDescription
                cancelJob(id: jobID, message: message)
                workflowLog = message
                await notifications.deliver(title: "MojoShell Job Canceled", body: jobTitle(for: jobID))
            } else {
                let message = error.localizedDescription
                failJob(id: jobID, message: message)
                workflowLog = "Error: \(message)"
                await notifications.deliver(title: "MojoShell Job Failed", body: jobTitle(for: jobID))
            }
        }
    }

    private func failJob(id: UUID, message: String) {
        updateJob(id: id, status: .failed, progress: 0.0, completedAt: nil, errorMessage: message)
        recordEvent(jobID: id, type: .failed, message: message)
    }

    private func cancelJob(id: UUID, message: String) {
        updateJob(id: id, status: .canceled, progress: 0.0, completedAt: nil, errorMessage: message)
        recordEvent(jobID: id, type: .canceled, message: message)
    }

    private func updateJob(
        id: UUID,
        status: MediaJobStatus,
        progress: Double,
        completedAt: Date?,
        errorMessage: String?
    ) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else {
            return
        }
        jobs[index].status = status
        jobs[index].progress = progress
        jobs[index].completedAt = completedAt
        jobs[index].errorMessage = errorMessage
        persistJobs()
    }

    private func loadFromDisk() {
        do {
            jobs = try jobStore.load().sorted { $0.createdAt > $1.createdAt }
        } catch {
            jobs = []
            workflowLog = "Unable to load jobs: \(error.localizedDescription)"
        }

        do {
            recentEvents = try eventStore.loadRecent(limit: 100)
        } catch {
            recentEvents = []
            workflowLog = "Unable to load event history: \(error.localizedDescription)"
        }
    }

    private func persistJobs() {
        do {
            try jobStore.save(jobs)
        } catch {
            workflowLog = "Job persistence failed: \(error.localizedDescription)"
        }
    }

    private func recordEvent(
        jobID: UUID,
        type: JobEventType,
        message: String,
        progress: Double? = nil,
        screenshotPath: String? = nil
    ) {
        let event = JobEvent(
            jobID: jobID,
            timestamp: now(),
            type: type,
            message: message,
            progress: progress,
            screenshotPath: screenshotPath
        )

        do {
            try eventStore.append(event)
            recentEvents.append(event)
            if recentEvents.count > 100 {
                recentEvents.removeFirst(recentEvents.count - 100)
            }
        } catch {
            workflowLog = "Event persistence failed: \(error.localizedDescription)"
        }
    }

    private static func progressValue(from message: String, totalSteps: Int) -> Double? {
        guard message.hasPrefix("[") else { return nil }
        guard let close = message.firstIndex(of: "]") else { return nil }

        let bracket = message[message.index(after: message.startIndex)..<close]
        let components = bracket.split(separator: "/")
        guard components.count == 2 else { return nil }
        guard let step = Int(components[0]) else { return nil }
        guard totalSteps > 0 else { return nil }

        return min(max(Double(step) / Double(totalSteps), 0.0), 1.0)
    }

    private func requestApproval(jobID: UUID, stepIndex: Int, step: WorkflowStep) async -> Bool {
        let prompt = step.approvalPrompt ?? "Approve this computer-use action."
        let request = WorkflowApprovalRequest(
            jobID: jobID,
            stepIndex: stepIndex,
            stepDescription: step.description,
            prompt: prompt,
            createdAt: now()
        )
        pendingApproval = request
        workflowLog = "Awaiting approval for step \(stepIndex + 1): \(step.description)"
        recordEvent(jobID: jobID, type: .info, message: "Approval required for step \(stepIndex + 1): \(step.description)")

        return await withCheckedContinuation { continuation in
            approvalContinuation = continuation
        }
    }

    private func jobTitle(for id: UUID) -> String {
        jobs.first(where: { $0.id == id })?.name ?? "Unknown Job"
    }

    private static func defaultPreflightCheck() throws {
        let exportItems = try AccessibilityElementFinder.findElements(
            inApp: "Final Cut Pro",
            roles: ["AXMenuItem"],
            titleContaining: "Export File"
        )
        guard !exportItems.isEmpty else {
            throw ProductionControllerError.noExportSelection
        }
    }

    private func humanReadablePreflightError(_ error: Error) -> String {
        if let finderError = error as? AccessibilityElementFinder.FinderError {
            switch finderError {
            case .appNotRunning(_):
                return "Final Cut Pro is not running. Open it and load a project first."
            case .accessibilityPermissionDenied:
                return "Accessibility permission denied. Grant access in System Settings -> Privacy & Security -> Accessibility."
            case .noElementsFound(let context):
                return "No exportable clip selected in Final Cut Pro. \(context)"
            }
        }

        if error is ProductionControllerError {
            return "No exportable clip selected in Final Cut Pro. Select a timeline item and try again."
        }

        return "Preflight error: \(error.localizedDescription)"
    }
}

enum ProductionControllerError: LocalizedError {
    case noExportSelection

    var errorDescription: String? {
        switch self {
        case .noExportSelection:
            return "No exportable clip selected in Final Cut Pro."
        }
    }
}
