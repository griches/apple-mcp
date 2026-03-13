import Foundation

struct WorkflowApprovalRequest: Identifiable, Equatable, Sendable {
    let id = UUID()
    let jobID: UUID
    let stepIndex: Int
    let stepDescription: String
    let prompt: String
    let createdAt: Date
}

enum ExportTargetError: LocalizedError {
    case emptyName
    case emptyPath

    var errorDescription: String? {
        switch self {
        case .emptyName:
            return "Export target name cannot be empty."
        case .emptyPath:
            return "Export target path cannot be empty."
        }
    }
}

@MainActor
final class ProductionController: ObservableObject {
    @Published private(set) var jobs: [MediaJob] = []
    @Published private(set) var recentEvents: [JobEvent] = []
    @Published private(set) var exportTargets: [ExportTarget] = []
    @Published var workflowLog = "Ready. Queue a workflow, then run the next job."
    @Published var isRunningWorkflow = false
    @Published private(set) var pendingApproval: WorkflowApprovalRequest?

    private let computerUseProvider: any ComputerUseProvider
    private let notifications: any AppNotifying
    private let jobStore: JobStore
    private let eventStore: JobEventStore
    private let screenshotStore: ScreenshotStore
    private let exportTargetStore: ExportTargetStore
    private let preflightCheck: @MainActor () throws -> Void
    private let workflowPlanProvider: @MainActor (MediaJob) throws -> WorkflowPlan
    private let auditRecorder: @MainActor (AuditCategory, String, String, [String: String]) -> Void
    private let now: () -> Date
    private var approvalContinuation: CheckedContinuation<Bool, Never>?

    init(
        computerUseProvider: any ComputerUseProvider,
        notifications: (any AppNotifying)? = nil,
        jobStore: JobStore = JobStore(),
        eventStore: JobEventStore = JobEventStore(),
        screenshotStore: ScreenshotStore = ScreenshotStore(),
        exportTargetStore: ExportTargetStore = ExportTargetStore(),
        preflightCheck: @escaping @MainActor () throws -> Void = ProductionController.defaultPreflightCheck,
        stepsProvider: @escaping () -> [WorkflowStep] = { FcpWorkflowDefinition.assemblyWorkflow() },
        workflowPlanProvider: (@MainActor (MediaJob) throws -> WorkflowPlan)? = nil,
        auditRecorder: (@MainActor (AuditCategory, String, String, [String: String]) -> Void)? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.computerUseProvider = computerUseProvider
        self.notifications = notifications ?? NullNotificationManager()
        self.jobStore = jobStore
        self.eventStore = eventStore
        self.screenshotStore = screenshotStore
        self.exportTargetStore = exportTargetStore
        self.preflightCheck = preflightCheck
        self.workflowPlanProvider = workflowPlanProvider ?? { job in
            try ProductionController.defaultWorkflowPlan(for: job, stepsProvider: stepsProvider)
        }
        self.auditRecorder = auditRecorder ?? { _, _, _, _ in }
        self.now = now
        loadFromDisk()
    }

    var defaultExportTarget: ExportTarget? {
        exportTargets.first(where: \.isDefault) ?? exportTargets.first
    }

    func queueAssemblyJob(name: String, client: String) {
        queueWorkflowJob(
            name: name,
            client: client,
            preset: .fcpExportCurrentTimeline,
            exportTargetID: defaultExportTarget?.id
        )
    }

    func queueWorkflowJob(
        name: String? = nil,
        client: String,
        preset: ProductionWorkflowPreset,
        exportTargetID: UUID? = nil
    ) {
        let exportTarget = resolvedExportTarget(for: preset, requestedID: exportTargetID)
        let jobName = name ?? defaultJobName(for: preset)
        let job = MediaJob(
            name: jobName,
            client: client,
            status: .queued,
            progress: 0.0,
            createdAt: now(),
            completedAt: nil,
            errorMessage: nil,
            workflowPreset: preset,
            appTarget: preset.appTarget,
            exportTargetName: exportTarget?.name,
            exportTargetPath: exportTarget?.path
        )

        jobs.append(job)
        persistJobs()
        recordEvent(jobID: job.id, type: .queued, message: "Job queued: \(jobName)", progress: 0.0)
        if let exportTarget {
            recordEvent(jobID: job.id, type: .info, message: "Export target: \(exportTarget.name) -> \(exportTarget.path)")
        }
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

    func addExportTarget(name: String, path: String) throws {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPath = (path as NSString).expandingTildeInPath.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedName.isEmpty else {
            throw ExportTargetError.emptyName
        }
        guard !trimmedPath.isEmpty else {
            throw ExportTargetError.emptyPath
        }

        var isDirectory: ObjCBool = false
        if !FileManager.default.fileExists(atPath: trimmedPath, isDirectory: &isDirectory) {
            try FileManager.default.createDirectory(atPath: trimmedPath, withIntermediateDirectories: true, attributes: nil)
            isDirectory = true
        }

        let target = ExportTarget(
            name: trimmedName,
            path: trimmedPath,
            isDefault: exportTargets.isEmpty
        )
        exportTargets.append(target)
        persistExportTargets()
        auditRecorder(.production, "Export target added", trimmedName, ["path": trimmedPath])
    }

    func setDefaultExportTarget(id: UUID) {
        guard exportTargets.contains(where: { $0.id == id }) else {
            return
        }
        for index in exportTargets.indices {
            exportTargets[index].isDefault = exportTargets[index].id == id
        }
        persistExportTargets()
        if let target = exportTargets.first(where: { $0.id == id }) {
            auditRecorder(.production, "Default export target set", target.name, ["path": target.path])
        }
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
        await runNextWorkflow()
    }

    func runNextWorkflow() async {
        guard !isRunningWorkflow else {
            return
        }

        guard let queuedIndex = jobs.firstIndex(where: { $0.status == .queued }) else {
            workflowLog = "No queued media job available."
            return
        }

        isRunningWorkflow = true
        defer { isRunningWorkflow = false }

        let job = jobs[queuedIndex]
        let jobID = job.id
        let preset = job.workflowPreset ?? .fcpExportCurrentTimeline
        let plan: WorkflowPlan

        do {
            plan = try workflowPlanProvider(job)
        } catch {
            let message = "Workflow plan error: \(error.localizedDescription)"
            failJob(id: jobID, message: message)
            workflowLog = message
            await notifications.deliver(title: "MojoShell Job Failed", body: jobTitle(for: jobID))
            return
        }

        workflowLog = "Preparing \(preset.title)..."
        if let exportTargetPath = job.exportTargetPath {
            recordEvent(jobID: jobID, type: .info, message: "Using export target path: \(exportTargetPath)")
        }

        if plan.requiresExportPreflight {
            do {
                try preflightCheck()
            } catch {
                let message = humanReadablePreflightError(error)
                failJob(id: jobID, message: message)
                workflowLog = message
                await notifications.deliver(title: "MojoShell Job Failed", body: jobTitle(for: jobID))
                return
            }
        }

        updateJob(id: jobID, status: .running, progress: plan.steps.isEmpty ? 0.9 : 0.1, completedAt: nil, errorMessage: nil)
        workflowLog = "Starting \(preset.title)..."
        recordEvent(jobID: jobID, type: .started, message: "\(preset.title) started", progress: plan.steps.isEmpty ? 0.9 : 0.1)

        if let placeholderMessage = plan.placeholderMessage {
            workflowLog = placeholderMessage
            recordEvent(jobID: jobID, type: .info, message: placeholderMessage)
            completeJob(id: jobID, message: plan.completionMessage)
            await notifications.deliver(title: "MojoShell Job Complete", body: jobTitle(for: jobID))
            return
        }

        if plan.steps.isEmpty {
            completeJob(id: jobID, message: plan.completionMessage)
            await notifications.deliver(title: "MojoShell Job Complete", body: jobTitle(for: jobID))
            return
        }

        var sessionId: String?
        do {
            sessionId = try await computerUseProvider.startSession()
            let stepCount = max(plan.steps.count, 1)
            let executor = WorkflowExecutor(provider: computerUseProvider)

            try await executor.run(
                steps: plan.steps,
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

            completeJob(id: jobID, message: plan.completionMessage)
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

    private func completeJob(id: UUID, message: String) {
        updateJob(id: id, status: .completed, progress: 1.0, completedAt: now(), errorMessage: nil)
        workflowLog = message
        recordEvent(jobID: id, type: .completed, message: message, progress: 1.0)
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

        do {
            exportTargets = try exportTargetStore.load()
            persistExportTargets()
        } catch {
            exportTargets = []
            workflowLog = "Unable to load export targets: \(error.localizedDescription)"
        }
    }

    private func persistJobs() {
        do {
            try jobStore.save(jobs)
        } catch {
            workflowLog = "Job persistence failed: \(error.localizedDescription)"
        }
    }

    private func persistExportTargets() {
        do {
            try exportTargetStore.save(exportTargets)
        } catch {
            workflowLog = "Export target persistence failed: \(error.localizedDescription)"
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

            var metadata = ["job_id": jobID.uuidString, "event_type": type.rawValue]
            if let job = jobs.first(where: { $0.id == jobID }) {
                if let preset = job.workflowPreset?.title {
                    metadata["preset"] = preset
                }
                if let target = job.exportTargetPath {
                    metadata["export_target"] = target
                }
            }
            auditRecorder(.production, "Job event", message, metadata)
        } catch {
            workflowLog = "Event persistence failed: \(error.localizedDescription)"
        }
    }

    private func resolvedExportTarget(for preset: ProductionWorkflowPreset, requestedID: UUID?) -> ExportTarget? {
        if let requestedID, let target = exportTargets.first(where: { $0.id == requestedID }) {
            return target
        }
        if preset.requiresExportTarget {
            return defaultExportTarget
        }
        return nil
    }

    private func defaultJobName(for preset: ProductionWorkflowPreset) -> String {
        let stamp = now().formatted(date: .abbreviated, time: .shortened)
        return "\(preset.title) - \(stamp)"
    }

    private static func defaultWorkflowPlan(
        for job: MediaJob,
        stepsProvider: @escaping () -> [WorkflowStep]
    ) throws -> WorkflowPlan {
        let preset = job.workflowPreset ?? .fcpExportCurrentTimeline

        switch preset {
        case .fcpExportCurrentTimeline:
            return WorkflowPlan(
                preset: preset,
                steps: job.exportTargetPath == nil
                    ? stepsProvider()
                    : FcpWorkflowDefinition.assemblyWorkflow(exportTargetPath: job.exportTargetPath),
                requiresExportPreflight: true,
                completionMessage: "FCP export workflow complete.",
                placeholderMessage: nil
            )

        case .fcpMonitorBackgroundTasks:
            return WorkflowPlan(
                preset: preset,
                steps: FcpWorkflowDefinition.monitoringCheck(),
                requiresExportPreflight: false,
                completionMessage: "FCP background task monitor opened.",
                placeholderMessage: nil
            )

        case .motionPlaceholderReview:
            return WorkflowPlan(
                preset: preset,
                steps: [],
                requiresExportPreflight: false,
                completionMessage: "Motion placeholder review logged.",
                placeholderMessage: "Motion review workflow placeholder recorded. Real Motion automation is not implemented yet."
            )

        case .motionPlaceholderExport:
            let target = job.exportTargetPath.map { " Planned target: \($0)" } ?? ""
            return WorkflowPlan(
                preset: preset,
                steps: [],
                requiresExportPreflight: false,
                completionMessage: "Motion placeholder export logged.",
                placeholderMessage: "Motion export workflow placeholder recorded.\(target)"
            )
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
            case .appNotRunning:
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
