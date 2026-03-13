import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ProductionDashboardView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var readiness: ReadinessState
    @EnvironmentObject private var production: ProductionController
    @EnvironmentObject private var session: ShellSessionController

    @State private var discoveredElements: [FoundAXElement] = []
    @State private var isDiscovering = false
    @State private var selectedPreset: ProductionWorkflowPreset = .fcpExportCurrentTimeline
    @State private var selectedExportTargetID: UUID?
    @State private var selectedApprovalMode: WorkflowApprovalMode = .smart
    @State private var newExportTargetName = ""
    @State private var newExportTargetPath = ""
    @State private var exportTargetStatus = ""
    @State private var selectedJobID: UUID?
    @State private var selectedArtifactPath: String?
    @State private var queuedSourceAssets: [SourceAsset] = []
    @State private var workflowNotes = ""
    @State private var isImportingSourceAssets = false

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 12) {
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Picker("Workflow Preset", selection: $selectedPreset) {
                            ForEach(ProductionWorkflowPreset.allCases) { preset in
                                Text(preset.title).tag(preset)
                            }
                        }

                        Text(selectedPreset.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Picker("Export Target", selection: $selectedExportTargetID) {
                            Text(defaultTargetLabel).tag(Optional<UUID>.none)
                            ForEach(production.exportTargets) { target in
                                Text(targetLabel(for: target)).tag(Optional(target.id))
                            }
                        }
                        .disabled(!selectedPreset.requiresExportTarget && production.exportTargets.isEmpty)

                        Picker("Approval Policy", selection: $selectedApprovalMode) {
                            ForEach(WorkflowApprovalMode.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }

                        Text(selectedApprovalMode.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack {
                            Button("Queue Workflow") {
                                queueSelectedWorkflow()
                            }
                            Button("Clear Finished") {
                                production.clearFinishedJobs()
                            }

                            Button("Set Default Target") {
                                setSelectedDefaultTarget()
                            }
                            .disabled(selectedExportTargetID == nil)

                            Button("Open Target") {
                                Task { await openSelectedExportTarget() }
                            }
                            .disabled(activeExportTarget == nil)
                        }

                        if selectedPreset.supportsSourceAssets {
                            Divider()

                            Text("Source Assets")
                                .font(.subheadline)

                            HStack {
                                Button("Add Files") {
                                    isImportingSourceAssets = true
                                }
                                Button("Use Finder Selection") {
                                    Task { await useFinderSelectionAsSourceAssets() }
                                }
                                Button("Clear") {
                                    queuedSourceAssets.removeAll()
                                }
                                .disabled(queuedSourceAssets.isEmpty)
                            }

                            if queuedSourceAssets.isEmpty {
                                Text("No source assets attached.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                VStack(alignment: .leading, spacing: 6) {
                                    ForEach(queuedSourceAssets) { asset in
                                        HStack {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(asset.name)
                                                    .font(.caption)
                                                Text(asset.path)
                                                    .font(.system(.caption2, design: .monospaced))
                                                    .foregroundStyle(.secondary)
                                                    .lineLimit(1)
                                            }
                                            Spacer()
                                            Text(asset.kind.rawValue)
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                            if let byteSize = asset.byteSize {
                                                Text(ByteCountFormatter.string(fromByteCount: byteSize, countStyle: .file))
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                            }
                                            Button("Remove") {
                                                removeSourceAsset(id: asset.id)
                                            }
                                        }
                                    }
                                }
                            }

                            Text("Operator Notes")
                                .font(.subheadline)
                            TextEditor(text: $workflowNotes)
                                .font(.system(.caption, design: .monospaced))
                                .frame(minHeight: 80)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(.separator, lineWidth: 1)
                                )
                        }

                        Divider()

                        Text("Add Export Target")
                            .font(.subheadline)
                        TextField("Name", text: $newExportTargetName)
                        TextField("Path", text: $newExportTargetPath)
                            .textFieldStyle(.roundedBorder)
                        HStack {
                            Button("Add Target") {
                                addExportTarget()
                            }
                            Spacer()
                            if !exportTargetStatus.isEmpty {
                                Text(exportTargetStatus)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } label: {
                    Label("Queue Builder", systemImage: "shippingbox")
                }

                GroupBox {
                    if production.jobs.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("No jobs yet")
                                .font(.headline)
                            Text("Queue a workflow preset, then run the next job.")
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        List(selection: $selectedJobID) {
                            ForEach(production.jobs) { job in
                                JobRow(job: job) {
                                    production.retryFailedJob(id: job.id)
                                }
                                .tag(job.id)
                            }
                        }
                        .frame(minHeight: 260)
                    }
                } label: {
                    Label("Job Queue", systemImage: "list.bullet.rectangle")
                }
            }
            .padding()
            .frame(minWidth: 420)

            VStack(alignment: .leading, spacing: 12) {
                Label("Production Runtime", systemImage: "film.stack")
                    .font(.headline)
                Divider()

                HStack {
                    Text("Provider: \(appState.computerUseProviderName)")
                    Spacer()
                    Button(isDiscovering ? "Scanning..." : "Discover FCP Elements") {
                        Task { await discoverFcpElements() }
                    }
                    .disabled(isDiscovering || !readiness.axPermissionGranted())
                }
                .foregroundStyle(.secondary)

                GroupBox {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Selected preset")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(selectedPreset.title)
                            .font(.headline)
                        Text(selectedPreset.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let target = activeExportTarget {
                            Text("Export target: \(target.name)")
                                .font(.caption)
                            Text(target.path)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                } label: {
                    Label("Preset Detail", systemImage: "slider.horizontal.3")
                }

                if let selectedJob {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(selectedJob.name)
                                        .font(.headline)
                                    Text(selectedJob.client)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(selectedJob.status.rawValue.capitalized)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            HStack(spacing: 12) {
                                Text("Created \(selectedJob.createdAt.formatted(date: .abbreviated, time: .shortened))")
                                if let completedAt = selectedJob.completedAt {
                                    Text("Completed \(completedAt.formatted(date: .abbreviated, time: .shortened))")
                                }
                            }
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                            if let preset = selectedJob.workflowPreset {
                                Text("Preset: \(preset.title)")
                                    .font(.caption)
                            }

                            Text("Workflow version: \(selectedJob.workflowVersion)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text("Approval policy: \(selectedJob.approvalMode.title)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)

                            HStack {
                                if selectedJob.status == .failed || selectedJob.status == .canceled {
                                    Button("Retry") {
                                        production.retryFailedJob(id: selectedJob.id)
                                    }
                                }
                                Button("Duplicate") {
                                    production.duplicateJob(id: selectedJob.id)
                                }
                                if selectedJob.status == .queued {
                                    Button("Prioritize") {
                                        production.prioritizeQueuedJob(id: selectedJob.id)
                                    }
                                    Button("Cancel") {
                                        production.cancelQueuedJob(id: selectedJob.id)
                                    }
                                }
                                if selectedJob.status != .running {
                                    Button("Remove") {
                                        let removedID = selectedJob.id
                                        production.removeJob(id: removedID)
                                        if selectedJobID == removedID {
                                            selectedJobID = production.jobs.first?.id
                                        }
                                    }
                                }
                            }
                            .font(.caption)

                            if let targetPath = selectedJob.exportTargetPath {
                                HStack {
                                    Text(targetPath)
                                        .font(.system(.caption2, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                    Spacer()
                                    Button("Open Target") {
                                        Task { _ = await appState.openFinderPath(targetPath) }
                                    }
                                }
                            }

                            if let notes = selectedJob.notes {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Notes")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    Text(notes)
                                        .font(.caption)
                                        .textSelection(.enabled)
                                }
                            }

                            if !selectedJob.sourceAssets.isEmpty {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Source Assets")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    ForEach(selectedJob.sourceAssets) { asset in
                                        HStack {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(asset.name)
                                                    .font(.caption)
                                                Text(asset.path)
                                                    .font(.system(.caption2, design: .monospaced))
                                                    .foregroundStyle(.secondary)
                                                    .lineLimit(1)
                                            }
                                            Spacer()
                                            Button("Open") {
                                                Task { _ = await appState.openFinderPath(asset.path) }
                                            }
                                        }
                                    }
                                }
                            }

                            let jobEvents = selectedJobEvents
                            if jobEvents.isEmpty {
                                Text("No recorded events for this job yet.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                ScrollView {
                                    VStack(alignment: .leading, spacing: 6) {
                                        ForEach(jobEvents) { event in
                                            InspectableEventRow(
                                                event: event,
                                                isSelectedArtifact: event.screenshotPath == activeArtifactPath
                                            ) { artifactPath in
                                                selectedArtifactPath = artifactPath
                                            }
                                        }
                                    }
                                }
                                .frame(minHeight: 180)
                            }
                        }
                    } label: {
                        Label("Selected Job", systemImage: "doc.text.magnifyingglass")
                    }

                    if let artifactPath = activeArtifactPath {
                        GroupBox {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(artifactPath)
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                                    .lineLimit(2)

                                if let metadata = activeArtifactMetadata {
                                    ArtifactMetadataView(metadata: metadata)
                                }

                                ArtifactPreview(path: artifactPath)

                                HStack {
                                    Button("Preview") {
                                        Task { _ = await appState.openPathInPreview(artifactPath) }
                                    }
                                    Button("Reveal") {
                                        Task { _ = await appState.revealFinderPath(artifactPath) }
                                    }
                                }
                            }
                        } label: {
                            Label("Artifact Preview", systemImage: "photo")
                        }
                    }
                }

                if !discoveredElements.isEmpty {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(discoveredElements) { element in
                                HStack(spacing: 8) {
                                    Text("\(Int(element.screenPoint.x)),\(Int(element.screenPoint.y))")
                                        .font(.system(.caption2, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 90, alignment: .leading)
                                    Text(element.title.isEmpty ? "(untitled)" : element.title)
                                        .font(.caption)
                                    Spacer()
                                    Text(element.role)
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                    } label: {
                        Label("Final Cut Pro - \(discoveredElements.count) elements", systemImage: "list.bullet.rectangle.portrait")
                    }
                }

                GroupBox {
                    ScrollView {
                        Text(production.workflowLog)
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(minHeight: 110)
                } label: {
                    Label("Workflow Log", systemImage: "terminal")
                }

                GroupBox {
                    if production.recentEvents.isEmpty {
                        Text("No events yet")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        ForEach(Array(production.recentEvents.suffix(12).reversed())) { event in
                            EventRow(event: event)
                        }
                    }
                } label: {
                    Label("Recent Events", systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                }

                if let approval = production.pendingApproval {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Step \(approval.stepIndex + 1): \(approval.stepDescription)")
                                .font(.headline)
                            Text(approval.prompt)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            HStack {
                                Button("Approve") {
                                    production.approvePendingStep()
                                }
                                Button("Reject") {
                                    production.rejectPendingStep()
                                }
                            }
                        }
                    } label: {
                        Label("Approval Required", systemImage: "hand.raised")
                    }
                }

                Spacer()

                VStack(alignment: .leading, spacing: 4) {
                    Button(production.isRunningWorkflow ? "Running..." : "Run Next Workflow") {
                        Task { await production.runNextWorkflow() }
                    }
                    .disabled(production.isRunningWorkflow || !readiness.isReady(for: .computerUse))

                    if !readiness.isReady(for: .computerUse),
                       let issue = readiness.blockingIssue(for: .computerUse) {
                        Text(issue.fixInstruction)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding()
            .frame(minWidth: 360)
        }
        .navigationTitle("Production")
        .task {
            await readiness.refreshComputerUse()
            hydrateSessionPreferencesIfNeeded()
        }
        .fileImporter(
            isPresented: $isImportingSourceAssets,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            handleImportedSourceAssets(result)
        }
        .onChange(of: selectedPreset) { _, newValue in
            session.preferredPreset = newValue
            if !newValue.supportsSourceAssets {
                queuedSourceAssets.removeAll()
                workflowNotes = ""
            }
        }
        .onChange(of: selectedExportTargetID) { _, newValue in
            session.preferredExportTargetID = newValue
        }
        .onChange(of: selectedApprovalMode) { _, newValue in
            session.preferredApprovalMode = newValue
        }
        .onChange(of: selectedJobID) { _, newValue in
            if let newValue, production.jobs.contains(where: { $0.id == newValue }) {
                selectedArtifactPath = production.events(for: newValue).compactMap(\.screenshotPath).first
            }
        }
    }

    private var activeExportTarget: ExportTarget? {
        if let selectedExportTargetID {
            return production.exportTargets.first(where: { $0.id == selectedExportTargetID })
        }
        return production.defaultExportTarget
    }

    private var defaultTargetLabel: String {
        if let target = production.defaultExportTarget {
            return "Default (\(target.name))"
        }
        return "No default target"
    }

    private var selectedJob: MediaJob? {
        if let selectedJobID, let selected = production.jobs.first(where: { $0.id == selectedJobID }) {
            return selected
        }
        return production.jobs.first
    }

    private var selectedJobEvents: [JobEvent] {
        guard let selectedJob else {
            return []
        }
        return production.events(for: selectedJob.id)
    }

    private var activeArtifactPath: String? {
        if let selectedArtifactPath,
           selectedJobEvents.contains(where: { $0.screenshotPath == selectedArtifactPath }) {
            return selectedArtifactPath
        }
        return selectedJobEvents.compactMap(\.screenshotPath).first
    }

    private var activeArtifactMetadata: DocumentMetadata? {
        guard let activeArtifactPath else {
            return nil
        }
        return DocumentInspector.inspect(path: activeArtifactPath)
    }

    private func targetLabel(for target: ExportTarget) -> String {
        target.isDefault ? "\(target.name) • default" : target.name
    }

    private func queueSelectedWorkflow() {
        production.queueWorkflowJob(
            client: "Manual",
            preset: selectedPreset,
            exportTargetID: selectedExportTargetID,
            sourceAssets: queuedSourceAssets,
            notes: workflowNotes,
            approvalMode: selectedApprovalMode
        )
        queuedSourceAssets.removeAll()
        workflowNotes = ""
    }

    private func setSelectedDefaultTarget() {
        guard let selectedExportTargetID else {
            return
        }
        production.setDefaultExportTarget(id: selectedExportTargetID)
        exportTargetStatus = "Default target updated."
    }

    private func addExportTarget() {
        do {
            try production.addExportTarget(name: newExportTargetName, path: newExportTargetPath)
            newExportTargetName = ""
            newExportTargetPath = ""
            selectedExportTargetID = production.defaultExportTarget?.id
            exportTargetStatus = "Export target added."
        } catch {
            exportTargetStatus = error.localizedDescription
        }
    }

    private func openSelectedExportTarget() async {
        guard let target = activeExportTarget else {
            return
        }
        _ = await appState.openFinderPath(target.path)
    }

    private func handleImportedSourceAssets(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            appendSourceAssets(paths: urls.map(\.path))
        case .failure(let error):
            exportTargetStatus = error.localizedDescription
        }
    }

    private func appendSourceAssets(paths: [String]) {
        let existingPaths = Set(queuedSourceAssets.map(\.path))
        let additions = paths.compactMap(SourceAsset.from).filter { !existingPaths.contains($0.path) }
        queuedSourceAssets.append(contentsOf: additions)
    }

    private func removeSourceAsset(id: UUID) {
        queuedSourceAssets.removeAll { $0.id == id }
    }

    private func useFinderSelectionAsSourceAssets() async {
        let result = await appState.fetchFinderSelectionPaths()
        switch result {
        case .success(let paths):
            appendSourceAssets(paths: paths)
            exportTargetStatus = paths.isEmpty ? "Finder selection is empty." : "Added \(paths.count) Finder-selected item(s)."
        case .failure(let error):
            exportTargetStatus = error.localizedDescription
        }
    }

    private func hydrateSessionPreferencesIfNeeded() {
        if selectedPreset != session.preferredPreset {
            selectedPreset = session.preferredPreset
        }
        if selectedExportTargetID == nil {
            selectedExportTargetID = session.preferredExportTargetID ?? production.defaultExportTarget?.id
        }
        if selectedApprovalMode != session.preferredApprovalMode {
            selectedApprovalMode = session.preferredApprovalMode
        }
        if selectedJobID == nil {
            selectedJobID = production.jobs.first?.id
        }
        if let selectedJobID {
            selectedArtifactPath = production.events(for: selectedJobID).compactMap(\.screenshotPath).first
        }
    }

    private func discoverFcpElements() async {
        isDiscovering = true
        production.workflowLog = "Scanning Final Cut Pro accessibility tree..."
        do {
            let elements = try AccessibilityElementFinder.findButtons(inApp: "Final Cut Pro")
            discoveredElements = elements
            production.workflowLog = "Found \(elements.count) buttons in Final Cut Pro. Coordinates are in global screen space (origin = top-left of primary display)."
        } catch {
            production.workflowLog = "Discovery error: \(error.localizedDescription)"
            discoveredElements = []
        }
        isDiscovering = false
    }
}

struct JobRow: View {
    let job: MediaJob
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(job.name).bold()
                Spacer()
                Text(job.status.rawValue.capitalized)
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }

            if let preset = job.workflowPreset {
                Text(preset.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !job.sourceAssets.isEmpty {
                Text("\(job.sourceAssets.count) source asset(s)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if job.status == .running {
                ProgressView(value: job.progress)
            }

            Text(job.client)
                .font(.caption)
                .foregroundStyle(.secondary)

            if let target = job.exportTargetName ?? job.exportTargetPath {
                Text(target)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if let error = job.errorMessage, (job.status == .failed || job.status == .canceled) {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(job.status == .canceled ? .orange : .red)
                Button("Retry") {
                    onRetry()
                }
                .buttonStyle(.link)
            }
        }
        .padding(.vertical, 4)
    }

    private var statusColor: Color {
        switch job.status {
        case .queued:
            return .gray
        case .running:
            return .blue
        case .completed:
            return .green
        case .failed:
            return .red
        case .canceled:
            return .orange
        }
    }
}

private struct EventRow: View {
    let event: JobEvent

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(event.timestamp.formatted(date: .omitted, time: .standard))
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.type.rawValue)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(event.message)
                    .font(.caption)
                if let screenshotPath = event.screenshotPath {
                    Text(screenshotPath)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            Spacer()
        }
    }
}

private struct InspectableEventRow: View {
    let event: JobEvent
    let isSelectedArtifact: Bool
    let onSelectArtifact: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 8) {
                Text(event.timestamp.formatted(date: .omitted, time: .standard))
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 80, alignment: .leading)
                VStack(alignment: .leading, spacing: 2) {
                    Text(event.type.rawValue)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(event.message)
                        .font(.caption)
                    if let progress = event.progress {
                        Text("Progress \(Int(progress * 100))%")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }

            if let screenshotPath = event.screenshotPath {
                HStack {
                    Text(screenshotPath)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                    Spacer()
                    Button(isSelectedArtifact ? "Selected" : "Inspect") {
                        onSelectArtifact(screenshotPath)
                    }
                    .disabled(isSelectedArtifact)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

private struct ArtifactPreview: View {
    let path: String

    var body: some View {
        Group {
            if let image = NSImage(contentsOfFile: path) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, minHeight: 180, maxHeight: 220)
                    .background(.background)
            } else {
                Text("No image preview available for this artifact.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
            }
        }
    }
}

private struct ArtifactMetadataView: View {
    let metadata: DocumentMetadata

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let byteSize = metadata.byteSize {
                Text("Size: \(ByteCountFormatter.string(fromByteCount: byteSize, countStyle: .file))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if let width = metadata.pixelWidth, let height = metadata.pixelHeight {
                Text("Dimensions: \(width) × \(height)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if let contentType = metadata.contentType {
                Text("Type: \(contentType)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if let modifiedAt = metadata.modifiedAt {
                Text("Modified: \(modifiedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
