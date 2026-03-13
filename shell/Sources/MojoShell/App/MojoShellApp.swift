import SwiftUI

@MainActor
@main
struct MojoShellApp: App {
    @StateObject private var appState: AppState
    @StateObject private var audit: AuditController
    @StateObject private var readiness: ReadinessState
    @StateObject private var production: ProductionController

    init() {
        let notifications = AppNotificationManager()
        let audit = AuditController()
        let daemonManager = DaemonManager(
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
        let nativeExecutor: any NativeToolExecuting = NativeToolExecutor(repoRoot: daemonManager.repoRoot)
        _audit = StateObject(wrappedValue: audit)
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
        _readiness = StateObject(wrappedValue: ReadinessState(daemonManager: daemonManager))
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
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(audit)
                .environmentObject(readiness)
                .environmentObject(production)
                .frame(minWidth: 1000, minHeight: 650)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
