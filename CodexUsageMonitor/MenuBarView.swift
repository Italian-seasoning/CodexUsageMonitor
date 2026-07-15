import AppKit
import Combine
import SwiftUI

enum MenuBarDisplayMode: String, CaseIterable, Identifiable {
    case percentage
    case meter
    case reset

    var id: String { rawValue }

    var label: String {
        switch self {
        case .percentage: "Percentage"
        case .meter: "Meter"
        case .reset: "Reset countdown"
        }
    }
}

@MainActor
final class MenuBarSnapshotModel: ObservableObject {
    @Published private(set) var snapshot = CodexUsageSnapshotStore.load() ?? .empty
    @Published private(set) var isRefreshing = false
    private var timer: Timer?

    init() {
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.reload() }
        }
    }

    deinit {
        timer?.invalidate()
    }

    func reload() {
        snapshot = CodexUsageSnapshotStore.load() ?? snapshot
    }

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        Task {
            _ = await Task.detached(priority: .utility) { SnapshotRefresh.run() }.value
            reload()
            isRefreshing = false
        }
    }
}

struct CodexMenuBarLabel: View {
    @ObservedObject var model: MenuBarSnapshotModel
    @AppStorage("CodexUsageMonitor.menuBarDisplayMode") private var mode = MenuBarDisplayMode.percentage.rawValue

    var body: some View {
        let stale = model.snapshot.generatedAt.map { Date().timeIntervalSince($0) > 6 * 60 } ?? true
        HStack(spacing: 4) {
            Image(systemName: stale ? "exclamationmark.triangle.fill" : "gauge.with.dots.needle.50percent")
            Text(labelText)
        }
        .accessibilityLabel("Codex usage")
        .accessibilityValue(labelText)
    }

    private var labelText: String {
        guard let limits = model.snapshot.rateLimits,
              let window = limits.preferredWindow
        else { return "—" }
        switch MenuBarDisplayMode(rawValue: mode) ?? .percentage {
        case .percentage:
            return window.windowMinutes == 10_080
                ? "W \(Int(window.usedPercent.rounded()))%"
                : "\(Int(window.usedPercent.rounded()))%"
        case .meter:
            let filled = min(5, max(0, Int(ceil(window.usedPercent / 20))))
            return String(repeating: "●", count: filled) + String(repeating: "○", count: 5 - filled)
        case .reset:
            return window.resetText()
        }
    }
}

struct CodexMenuBarView: View {
    @ObservedObject var model: MenuBarSnapshotModel
    @AppStorage("CodexUsageMonitor.menuBarDisplayMode") private var mode = MenuBarDisplayMode.percentage.rawValue

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            limitRow(title: "5-hour", window: model.snapshot.rateLimits?.fiveHour)
            limitRow(title: "Weekly", window: model.snapshot.rateLimits?.weekly)

            if let limits = model.snapshot.rateLimits {
                Divider()
                LabeledContent("Pace", value: limits.pace.label)
                if let reset = limits.nearestReset {
                    LabeledContent("Next reset", value: reset.resetText())
                }
            }

            Picker("Menu bar", selection: $mode) {
                ForEach(MenuBarDisplayMode.allCases) { mode in
                    Text(mode.label).tag(mode.rawValue)
                }
            }

            Divider()
            Button("Open Codex Usage") {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.windows.first { $0.identifier?.rawValue == "CodexUsageMonitor.MainWindow" }?
                    .makeKeyAndOrderFront(nil)
            }
            Button(model.isRefreshing ? "Refreshing…" : "Refresh now") { model.refresh() }
                .disabled(model.isRefreshing)
            Button("Quit Codex Usage") { NSApp.terminate(nil) }
        }
        .frame(width: 240)
        .padding(10)
        .onReceive(NotificationCenter.default.publisher(for: .codexUsageSnapshotDidChange)) { _ in
            model.reload()
        }
    }

    @ViewBuilder
    private func limitRow(title: String, window: RateLimitWindow?) -> some View {
        if let window {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title).fontWeight(.semibold)
                    Spacer()
                    Text("\(Int(window.usedPercent.rounded()))%")
                        .monospacedDigit()
                }
                ProgressView(value: window.usedPercent, total: 100)
                Text("Resets in \(window.resetText())")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            LabeledContent(title, value: "Unavailable")
                .foregroundStyle(.secondary)
        }
    }
}
