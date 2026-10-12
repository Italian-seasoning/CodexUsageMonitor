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
    @Published private(set) var refreshRecord = BackgroundRefreshAgent.loadRecord()
    private var timer: Timer?

    var health: SnapshotHealth {
        SnapshotHealth(snapshot: snapshot, record: refreshRecord, isRefreshing: isRefreshing)
    }

    init() {
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.reload() }
        }
    }

    deinit {
        timer?.invalidate()
    }

    func reload() {
        snapshot = CodexUsageSnapshotStore.load() ?? snapshot
        refreshRecord = BackgroundRefreshAgent.loadRecord()
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
        let stale = model.health.kind != .freshComplete && model.health.kind != .freshPartial
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
        let font = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .semibold)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white,
        ]
        let sizes = lines.map { ($0 as NSString).size(withAttributes: attributes) }
        let size = NSSize(width: ceil(sizes.map(\.width).max() ?? 1), height: 22)
        let image = NSImage(size: size, flipped: true) { _ in
            for (index, line) in lines.enumerated() {
                (line as NSString).draw(at: NSPoint(x: 0, y: lines.count == 1 ? 5 : index * 11), withAttributes: attributes)
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    private var labelLines: [String] {
        let limits = model.snapshot.rateLimits
        let mode = settingsModel.settings.menuBarDisplayMode
        var lines = [Self.labelText(prefix: "W", window: limits?.weekly, mode: mode)]
        if limits?.showsFiveHour == true { lines.insert(Self.labelText(prefix: "5H", window: limits?.fiveHour, mode: mode), at: 0) }
        return lines
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
    @State private var showsDetails = false

    private var activity: CodexSessionActivity? {
        model.snapshot.sessionActivity.first { $0.status() == "Working" } ?? model.snapshot.sessionActivity.first
    }
    private var accent: Color { settingsModel.settings.appTheme.accent }

    var body: some View {
        ZStack {
            WindowBackdrop()
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("Codex Usage", systemImage: "terminal")
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Text(activity?.status() ?? "Last recorded")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(ModelPricingCatalog.displayName(for: activity?.model ?? model.snapshot.currentModel))
                        .font(.system(size: 21, weight: .semibold)).lineLimit(1)
                    Text(activity?.project ?? "Local Codex activity")
                        .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
                SessionUsageChart(points: activity?.usageHistory ?? [], accent: accent).frame(height: 80)
                let usage = activity?.usage ?? model.snapshot.currentSession
                HStack {
                    Text("\(usage.total.compactTokenString) tokens").fontWeight(.semibold)
                    Spacer()
                    Text("\(activity?.requests ?? model.snapshot.currentSessionTurns ?? 0) requests")
                        .foregroundStyle(.secondary)
                }
                .font(.system(size: 11)).monospacedDigit()
                Divider()
                if model.snapshot.rateLimits?.showsFiveHour == true {
                    CompactLimitRow(title: "5-hour", window: model.snapshot.rateLimits?.fiveHour, accent: accent)
                }
                CompactLimitRow(title: "Weekly", window: model.snapshot.rateLimits?.weekly, accent: accent)
                DisclosureGroup("More details", isExpanded: $showsDetails) {
                    VStack(spacing: 8) {
                        LabeledContent("Tools", value: (activity?.toolCalls ?? 0).formatted())
                        LabeledContent("Cached input", value: usage.input > 0 ? (Double(usage.cachedInput) / Double(usage.input) * 100).compactPercentString : "—")
                        LabeledContent("Reasoning", value: activity?.reasoningEffort?.capitalized ?? "—")
                        Picker("Menu label", selection: $settingsModel.settings.menuBarDisplayMode) {
                            ForEach(MenuBarDisplayMode.allCases) { Text($0.label).tag($0) }
                        }
                    }.font(.system(size: 11)).padding(.top, 8)
                }.font(.system(size: 11))
                HStack {
                    Circle().fill(model.health.color).frame(width: 5, height: 5)
                    Text(model.health.title)
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                        .help(model.health.detail)
                    Spacer()
                    Button { model.refresh() } label: {
                        Image(systemName: "arrow.clockwise").rotationEffect(.degrees(model.isRefreshing ? 180 : 0))
                    }
                    .disabled(model.isRefreshing).help("Refresh now").accessibilityLabel("Refresh now")
                    Button { NotificationCenter.default.post(name: .showCodexUsageCompactPreview, object: nil) } label: {
                        Image(systemName: "arrow.up.forward.app")
                    }
                    .help("Open workspace").accessibilityLabel("Open workspace")
                    Menu {
                        Button("Open workspace") {
                            NotificationCenter.default.post(name: .showCodexUsageCompactPreview, object: nil)
                        }
                        Button("Quit Codex Usage") { NSApp.terminate(nil) }
                    } label: { Image(systemName: "ellipsis") }
                    .menuStyle(.borderlessButton).fixedSize()
                }.buttonStyle(.plain)
            }.padding(20)
        }
        .frame(width: 330)
        .preferredColorScheme(.dark)
        .tint(accent)
        .onReceive(NotificationCenter.default.publisher(for: .codexUsageSnapshotDidChange)) { _ in model.reload() }
    }
}
