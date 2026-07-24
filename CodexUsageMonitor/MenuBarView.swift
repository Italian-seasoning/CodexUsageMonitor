import AppKit
import Combine
import SwiftUI

extension AppPresenceMode {
    var label: String {
        switch self {
        case .menuBar: "Menu Bar"
        case .dock: "Dock"
        case .background: "Background"
        }
    }

    @MainActor
    static func apply(_ mode: AppPresenceMode) {
        NSApp.setActivationPolicy(mode == .dock ? .regular : .accessory)
    }
}

extension MenuBarDisplayMode {
    var label: String {
        switch self {
        case .percentage: "Remaining percentage"
        case .meter: "Meter"
        case .reset: "Reset countdown"
        case .hidden: "Hidden"
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
    @EnvironmentObject private var settingsModel: CodexUsageSettingsModel

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
              let window = limits.weekly ?? limits.fiveHour
        else { return "—" }
        let prefix = limits.weekly == nil ? "5h" : "W"
        switch settingsModel.settings.menuBarDisplayMode {
        case .percentage:
            return "\(prefix) \(Int(window.remainingPercent.rounded()))%"
        case .meter:
            let filled = min(5, max(0, Int(ceil(window.remainingPercent / 20))))
            return "\(prefix) " + String(repeating: "●", count: filled) + String(repeating: "○", count: 5 - filled)
        case .reset:
            return window.resetText()
        case .hidden:
            return ""
        }
    }
}

struct CodexMenuBarView: View {
    @ObservedObject var model: MenuBarSnapshotModel
    @EnvironmentObject private var settingsModel: CodexUsageSettingsModel

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

            Picker("Menu label", selection: $settingsModel.settings.menuBarDisplayMode) {
                ForEach(MenuBarDisplayMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }

            Picker("Show app in", selection: $settingsModel.settings.appPresence) {
                ForEach(AppPresenceMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .onChange(of: settingsModel.settings.appPresence) { _, value in
                AppPresenceMode.apply(value)
            }

            Divider()
            Button("Open Codex Usage") {
                NSApp.setActivationPolicy(.regular)
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
                    Text("\(Int(window.remainingPercent.rounded()))% left")
                        .monospacedDigit()
                }
                ProgressView(value: window.remainingPercent, total: 100)
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
