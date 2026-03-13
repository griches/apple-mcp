import SwiftUI

enum ShellView: String, CaseIterable, Identifiable {
    case cockpit = "Cockpit"
    case terminal = "Agent Terminal"
    case production = "Production"
    case audit = "Audit"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .cockpit:
            return "gauge.with.dots.needle.bottom.50percent"
        case .terminal:
            return "terminal"
        case .production:
            return "film.stack"
        case .audit:
            return "clock.arrow.circlepath"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var audit: AuditController
    @EnvironmentObject private var readiness: ReadinessState
    @Environment(\.scenePhase) private var scenePhase
    @State private var selected: ShellView? = .cockpit
    @State private var isCommandPalettePresented = false

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
                    case .audit:
                        AuditView()
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem {
                Button("Command Palette") {
                    isCommandPalettePresented = true
                }
                .keyboardShortcut("k", modifiers: [.command])
            }
        }
        .sheet(isPresented: $readiness.showFirstRunSheet) {
            FirstRunSheet()
        }
        .sheet(isPresented: $isCommandPalettePresented) {
            CommandPaletteView(isPresented: $isCommandPalettePresented, selectedView: $selected)
        }
        .task {
            await readiness.refresh()
        }
        .onChange(of: selected) { _, newValue in
            guard let newValue else { return }
            audit.record(category: .navigation, title: "Selected view", detail: newValue.rawValue)
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
