import AppKit
import Combine
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
        case .reset: "Reset time"
        case .hidden: "Hidden"
        }
    }
}

@MainActor
final class MenuBarSnapshotModel: ObservableObject {
    @Published private(set) var snapshot = CodexUsageSnapshotStore.load() ?? .empty
    @Published private(set) var isRefreshing = false
    @Published private(set) var refreshRecord = BackgroundRefreshAgent.loadRecord()
    private var observation: AnyCancellable?

    init() {
        observation = NotificationCenter.default.publisher(for: .codexUsageSnapshotDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.reload() }
    }

    var health: SnapshotHealth {
        SnapshotHealth(snapshot: snapshot, record: refreshRecord, isRefreshing: isRefreshing)
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
        let image = Self.labelImage(lines: lines, fractions: labelFractions, mode: settingsModel.settings.menuBarDisplayMode)
        Image(nsImage: image)
            .resizable()
            .frame(width: image.size.width, height: image.size.height)
            .foregroundStyle(stale ? .secondary : .primary)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Codex usage")
            .accessibilityValue(lines.joined(separator: ", "))
    }

    /// Draws the status item at the real menu bar height (taller on notched displays)
    /// and at a fixed width per mode, so neighbouring items do not shift as values change.
    private static func labelImage(lines: [String], fractions: [Double?], mode: MenuBarDisplayMode) -> NSImage {
        let barHeight = max(22, NSStatusBar.system.thickness)
        let singleLine = lines.count == 1
        let fontSize = singleLine ? (barHeight * 0.56).rounded() : (barHeight * 0.42).rounded()
        let font = NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .semibold)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
        let lineHeight = singleLine ? barHeight : barHeight / 2
        let prefixes = lines.map { String($0.split(separator: " ").first ?? "") }

        if mode == .meter {
            let prefixWidth = ceil(("5H" as NSString).size(withAttributes: attributes).width)
            let meterWidth: CGFloat = singleLine ? 34 : 28
            let size = NSSize(width: prefixWidth + 4 + meterWidth, height: barHeight)
            let image = NSImage(size: size, flipped: true) { _ in
                for index in lines.indices {
                    let top = CGFloat(index) * lineHeight
                    let textHeight = (prefixes[index] as NSString).size(withAttributes: attributes).height
                    (prefixes[index] as NSString).draw(at: NSPoint(x: 0, y: top + (lineHeight - textHeight) / 2), withAttributes: attributes)
                    let thickness: CGFloat = singleLine ? 5 : 4
                    let track = NSRect(x: prefixWidth + 4, y: top + (lineHeight - thickness) / 2, width: meterWidth, height: thickness)
                    NSColor.white.withAlphaComponent(0.35).setFill()
                    NSBezierPath(roundedRect: track, xRadius: thickness / 2, yRadius: thickness / 2).fill()
                    if let fraction = fractions[index] {
                        var fill = track
                        fill.size.width = max(thickness, track.width * CGFloat(min(1, max(0, fraction))))
                        NSColor.white.setFill()
                        NSBezierPath(roundedRect: fill, xRadius: thickness / 2, yRadius: thickness / 2).fill()
                    }
                }
                return true
            }
            image.isTemplate = true
            return image
        }

        // Reserve the widest value this mode can show so the item never changes width.
        let widest: String = switch mode {
        case .reset: "5H 12:59 PM"
        default: "5H 100%"
        }
        let width = ceil(max((widest as NSString).size(withAttributes: attributes).width,
                             lines.map { ($0 as NSString).size(withAttributes: attributes).width }.max() ?? 1))
        let image = NSImage(size: NSSize(width: width, height: barHeight), flipped: true) { _ in
            for (index, line) in lines.enumerated() {
                let textSize = (line as NSString).size(withAttributes: attributes)
                let top = CGFloat(index) * lineHeight + (lineHeight - textSize.height) / 2
                (line as NSString).draw(at: NSPoint(x: width - textSize.width, y: top), withAttributes: attributes)
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    private var labelFractions: [Double?] {
        let limits = model.snapshot.rateLimits
        var values = [limits?.weekly.map { $0.remainingPercent / 100 }]
        if limits?.showsFiveHour == true { values.insert(limits?.fiveHour.map { $0.remainingPercent / 100 }, at: 0) }
        return values
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
            return "\(prefix) \(window.resetsAt.formatted(date: .omitted, time: .shortened))"
        case .hidden:
            return ""
        }
    }
}

struct CodexMenuBarView: View {
    @ObservedObject var model: MenuBarSnapshotModel
    @EnvironmentObject private var settingsModel: CodexUsageSettingsModel

    private var activity: CodexSessionActivity? {
        model.snapshot.sessionActivity.first { $0.status() == "Working" } ?? model.snapshot.sessionActivity.first
    }
    private var accent: Color { settingsModel.settings.appTheme.accent }

    var body: some View {
        ZStack {
            WindowBackdrop(light: settingsModel.settings.appTheme == .runway)
            if settingsModel.settings.appTheme == .runway {
                settingsModel.settings.appTheme.windowTint
            }
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                HStack {
                    Label("Runway", systemImage: "terminal")
                        .font(.system(size: AppTypeScale.label, weight: .semibold))
                    Spacer()
                    Text(activity?.status() ?? "Last recorded")
                        .font(.system(size: AppTypeScale.micro)).foregroundStyle(.secondary)
                }
                if model.snapshot.rateLimits?.showsFiveHour == true {
                    CompactLimitRow(title: "5-hour", window: model.snapshot.rateLimits?.fiveHour, accent: accent)
                }
                CompactLimitRow(title: "Weekly", window: model.snapshot.rateLimits?.weekly, accent: accent)
                Divider()
                let usage = activity?.usage ?? model.snapshot.currentSession
                HStack {
                    Text("\(usage.total.compactTokenString) tokens").fontWeight(.semibold)
                    Spacer()
                    Text(ModelPricingCatalog.displayName(for: activity?.model ?? model.snapshot.currentModel))
                        .foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
                .font(.system(size: AppTypeScale.caption)).monospacedDigit()
                HStack {
                    Circle().fill(model.health.color).frame(width: 5, height: 5)
                    Text(model.health.title)
                        .font(.system(size: AppTypeScale.micro)).foregroundStyle(.secondary)
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
                        Picker("Menu label", selection: $settingsModel.settings.menuBarDisplayMode) {
                            ForEach(MenuBarDisplayMode.allCases) { Text($0.label).tag($0) }
                        }
                        Divider()
                        Button("Open workspace") {
                            NotificationCenter.default.post(name: .showCodexUsageCompactPreview, object: nil)
                        }
                        Button("Quit Runway") { NSApp.terminate(nil) }
                    } label: { Image(systemName: "ellipsis") }
                    .menuStyle(.borderlessButton).fixedSize()
                }.buttonStyle(.plain)
            }.padding(AppSpacing.sm)
        }
        .frame(width: 280)
        .preferredColorScheme(settingsModel.settings.appTheme.colorScheme)
        .environment(\.colorScheme, settingsModel.settings.appTheme.colorScheme)
        .tint(accent)
        .onAppear { model.reload() }
    }
}
