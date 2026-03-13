import SwiftUI

@MainActor
@main
struct MojoShellApp: App {
    @StateObject private var appState: AppState
    @StateObject private var readiness: ReadinessState

    init() {
        let daemonManager = DaemonManager()
        _appState = StateObject(wrappedValue: AppState(daemons: daemonManager))
        _readiness = StateObject(wrappedValue: ReadinessState(daemonManager: daemonManager))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(readiness)
                .frame(minWidth: 1000, minHeight: 650)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
