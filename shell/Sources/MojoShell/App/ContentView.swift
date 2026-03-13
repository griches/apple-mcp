import SwiftUI

enum ShellView: String, CaseIterable, Identifiable {
    case cockpit = "Cockpit"
    case terminal = "Agent Terminal"
    case production = "Production"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .cockpit:
            return "gauge.with.dots.needle.bottom.50percent"
        case .terminal:
            return "terminal"
        case .production:
            return "film.stack"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var readiness: ReadinessState
    @Environment(\.scenePhase) private var scenePhase
    @State private var selected: ShellView? = .cockpit

    var body: some View {
        NavigationSplitView {
            List(ShellView.allCases, selection: $selected) { view in
                Label(view.rawValue, systemImage: view.icon)
                    .tag(view)
            }
            .navigationSplitViewColumnWidth(220)
            .listStyle(.sidebar)
        } detail: {
            VStack(spacing: 0) {
                CoreIssuesBanner()
                Group {
                    switch selected ?? .cockpit {
                    case .cockpit:
                        CockpitView()
                    case .terminal:
                        AgentTerminalView()
                    case .production:
                        ProductionDashboardView()
                    }
                }
            }
        }
        .sheet(isPresented: $readiness.showFirstRunSheet) {
            FirstRunSheet()
        }
        .task {
            await readiness.refresh()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task {
                    await readiness.refresh()
                }
            }
        }
    }
}
