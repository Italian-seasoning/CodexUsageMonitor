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
            _ = await RefreshCoordinator.shared.refresh(trigger: .manual, force: true)
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
        let lines = labelLines
        let image = Self.labelImage(lines: lines)
        Image(nsImage: image)
            .resizable()
            .frame(width: image.size.width, height: image.size.height)
            .foregroundStyle(stale ? .secondary : .primary)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Codex usage")
            .accessibilityValue(lines.joined(separator: ", "))
    }

    private static func labelImage(lines: [String]) -> NSImage {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 8, weight: .semibold)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white,
        ]
        let sizes = lines.map { ($0 as NSString).size(withAttributes: attributes) }
        let size = NSSize(width: ceil(sizes.map(\.width).max() ?? 1), height: 18)
        let image = NSImage(size: size, flipped: true) { _ in
            (lines[0] as NSString).draw(at: NSPoint(x: 0, y: 0), withAttributes: attributes)
            (lines[1] as NSString).draw(at: NSPoint(x: 0, y: 9), withAttributes: attributes)
            return true
        }
        image.isTemplate = true
        return image
    }

    private var labelLines: [String] {
        let limits = model.snapshot.rateLimits
        let mode = settingsModel.settings.menuBarDisplayMode
        return [
            Self.labelText(prefix: "5H", window: limits?.fiveHour, mode: mode),
            Self.labelText(prefix: "W", window: limits?.weekly, mode: mode),
        ]
    }

    static func labelText(prefix: String, window: RateLimitWindow?, mode: MenuBarDisplayMode) -> String {
        guard let window else { return "\(prefix) —" }
        switch mode {
        case .percentage:
            return "\(prefix) \(Int(window.remainingPercent.rounded()))%"
        case .meter:
            let filled = min(5, max(0, Int(ceil(window.remainingPercent / 20))))
            return "\(prefix) " + String(repeating: "●", count: filled) + String(repeating: "○", count: 5 - filled)
        case .reset:
            return "\(prefix) \(window.resetText())"
        case .hidden:
            return ""
        }
    }
}

struct CodexMenuBarView: View {
    @ObservedObject var model: MenuBarSnapshotModel
    @EnvironmentObject private var settingsModel: CodexUsageSettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            limitRows(title: "5-hour", window: model.snapshot.rateLimits?.fiveHour)
            limitRows(title: "Weekly", window: model.snapshot.rateLimits?.weekly)

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
    private func limitRows(title: String, window: RateLimitWindow?) -> some View {
        if let window {
            Text("\(title) · \(Int(window.remainingPercent.rounded()))% left")
                .fontWeight(.semibold)
                .monospacedDigit()
            Text("Resets in \(window.resetText())")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            Text("\(title) · Unavailable")
                .foregroundStyle(.secondary)
        }
    }
}
