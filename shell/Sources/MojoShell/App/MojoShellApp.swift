import SwiftUI

@MainActor
@main
struct MojoShellApp: App {
    @StateObject private var appState: AppState
    @StateObject private var readiness: ReadinessState
    @StateObject private var production: ProductionController

    init() {
        let notifications = AppNotificationManager()
        let daemonManager = DaemonManager(
            onRuntimeStateChanged: { previous, current in
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
        _appState = StateObject(
            wrappedValue: AppState(
                daemons: daemonManager,
                computerUseProvider: computerUseProvider,
                nativeExecutor: nativeExecutor
            )
        )
        _readiness = StateObject(wrappedValue: ReadinessState(daemonManager: daemonManager))
        _production = StateObject(
            wrappedValue: ProductionController(
                computerUseProvider: computerUseProvider,
                notifications: notifications
            )
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
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
