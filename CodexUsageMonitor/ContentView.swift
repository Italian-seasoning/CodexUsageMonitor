import SwiftUI

struct ContentView: View {
    @State private var section = AppSection.analysis
    @State private var analysisSelection = AnalysisSelection()
    @State private var snapshot = CodexUsageSnapshotStore.load() ?? .empty
    @State private var refreshRecord = BackgroundRefreshAgent.loadRecord()
    @State private var isRefreshing = false
    @State private var presentsDataHealth = false

    private var health: SnapshotHealth {
        SnapshotHealth(snapshot: snapshot, record: refreshRecord, isRefreshing: isRefreshing)
    }

    var body: some View {
        ZStack {
            WindowBackdrop().ignoresSafeArea()
            AppPalette.windowTint.ignoresSafeArea()

            HStack(spacing: 0) {
                AppRail(
                    selection: $section,
                    presentsDataHealth: $presentsDataHealth,
                    health: health
                )
                .popover(isPresented: $presentsDataHealth, arrowEdge: .trailing) {
                    DataHealthView(
                        snapshot: $snapshot,
                        record: $refreshRecord,
                        isRefreshing: $isRefreshing
                    )
                }

                Group {
                    switch section {
                    case .analysis:
                        AnalysisView(snapshot: snapshot, health: health, selection: $analysisSelection)
                    case .models:
                        ModelsView(snapshot: snapshot, health: health)
                    case .widgets:
                        WidgetsView(snapshot: snapshot)
                    case .settings:
                        SettingsView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 980, idealWidth: 1080, minHeight: 660, idealHeight: 720)
        .foregroundStyle(AppPalette.text)
        .tint(AppPalette.accent)
        .onReceive(NotificationCenter.default.publisher(for: .codexUsageSnapshotDidChange)) { _ in
            snapshot = CodexUsageSnapshotStore.load() ?? snapshot
            refreshRecord = BackgroundRefreshAgent.loadRecord()
        }
    }
}
