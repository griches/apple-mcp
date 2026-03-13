import SwiftUI

@MainActor
@main
struct MojoShellApp: App {
    @StateObject private var appState: AppState
    @StateObject private var audit: AuditController
    @StateObject private var brain: BrainManager
    @StateObject private var readiness: ReadinessState
    @StateObject private var production: ProductionController
    @StateObject private var session: ShellSessionController

    init() {
        let notifications = AppNotificationManager()
        let audit = AuditController()
        let session = ShellSessionController()
        let repoRoot = DaemonManager.defaultRepoRoot()
        let brain = BrainManager(repoRoot: repoRoot)
        let daemonManager = DaemonManager(
            repoRoot: repoRoot,
            brainPathProvider: { brain.activeBrainPath },
            onRuntimeStateChanged: { previous, current in
                audit.record(
                    category: .daemon,
                    title: "Daemon state changed",
                    detail: "\(current.serverName) -> \(current.status.rawValue)",
                    metadata: [
                        "previous": previous?.status.rawValue ?? "none",
                        "error": current.lastError ?? "",
                    ]
                )

                guard current.status == .failed, previous?.status != .failed else {
                    return
                }

                let body: String
                if let lastError = current.lastError, !lastError.isEmpty {
                    body = "\(current.serverName): \(lastError)"
                } else {
                    body = current.serverName
                }

                Task {
                    await notifications.deliver(title: "MojoShell Daemon Failed", body: body)
                }
            }
        )
        let computerUseProvider: any ComputerUseProvider = CuaComputerUseProvider()
        let nativeExecutor: any NativeToolExecuting = NativeToolExecutor(
            repoRoot: daemonManager.repoRoot,
            brainPathProvider: { brain.activeBrainPath }
        )
        _audit = StateObject(wrappedValue: audit)
        _brain = StateObject(wrappedValue: brain)
        _session = StateObject(wrappedValue: session)
        _appState = StateObject(
            wrappedValue: AppState(
                daemons: daemonManager,
                computerUseProvider: computerUseProvider,
                nativeExecutor: nativeExecutor,
                auditRecorder: { category, title, detail, metadata in
                    audit.record(category: category, title: title, detail: detail, metadata: metadata)
                }
            )
        )
        _readiness = StateObject(
            wrappedValue: ReadinessState(
                daemonManager: daemonManager,
                brainPathProvider: { brain.activeBrainPath }
            )
        )
        _production = StateObject(
            wrappedValue: ProductionController(
                computerUseProvider: computerUseProvider,
                notifications: notifications,
                auditRecorder: { category, title, detail, metadata in
                    audit.record(category: category, title: title, detail: detail, metadata: metadata)
                }
            )
        )
    }

    var body: some Scene {
        WindowGroup("MojoShell", id: "main") {
            ContentView()
                .environmentObject(appState)
                .environmentObject(audit)
                .environmentObject(brain)
                .environmentObject(readiness)
                .environmentObject(production)
                .environmentObject(session)
                .frame(minWidth: 1000, minHeight: 650)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        MenuBarExtra("MojoShell", systemImage: "switch.2") {
            MenuBarShellView()
                .environmentObject(appState)
                .environmentObject(audit)
                .environmentObject(brain)
                .environmentObject(readiness)
                .environmentObject(production)
                .environmentObject(session)
        }
    }
}
