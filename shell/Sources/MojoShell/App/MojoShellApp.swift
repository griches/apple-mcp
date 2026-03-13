import SwiftUI

@MainActor
@main
struct MojoShellApp: App {
    @StateObject private var appState: AppState
    @StateObject private var readiness: ReadinessState
    @StateObject private var production: ProductionController

    init() {
        let daemonManager = DaemonManager()
        let computerUseProvider: any ComputerUseProvider = CuaComputerUseProvider()
        _appState = StateObject(
            wrappedValue: AppState(
                daemons: daemonManager,
                computerUseProvider: computerUseProvider
            )
        )
        _readiness = StateObject(wrappedValue: ReadinessState(daemonManager: daemonManager))
        _production = StateObject(
            wrappedValue: ProductionController(computerUseProvider: computerUseProvider)
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
