import AppKit
import Charts
import Combine
import Darwin
import DroppyKit
import SwiftUI

@objc(CodexusagePrincipal)
public final class CodexusagePrincipal: NSObject, DropletPrincipal {
    public override init() { super.init() }
    @MainActor public func makeDroplet() -> AnyObject { CodexusageDroplet() }
}

@MainActor
public final class CodexusageDroplet: NSObject, ObservableObject, Droplet {
    public nonisolated static let id: DropletID = "codexusage"
    @Published private(set) var snapshot: MonitorSnapshot?
    @Published private(set) var message: String?
    private var host: DropletHost?
    private var refreshTask: Task<Void, Never>?

    private static var snapshotURL: URL {
        let home = getpwuid(getuid()).map { String(cString: $0.pointee.pw_dir) }
            ?? FileManager.default.homeDirectoryForCurrentUser.path
        return URL(fileURLWithPath: home)
            .appendingPathComponent("Library/Application Support/CodexUsageMonitor/snapshot.json")
    }

    public func activate(host: DropletHost) throws {
        self.host = host
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.reload()
                do { try await Task.sleep(for: .seconds(5)) } catch { return }
            }
        }
    }

    public func deactivate() {
        refreshTask?.cancel()
        refreshTask = nil
        host = nil
    }

    private func reload() async {
        let url = Self.snapshotURL
        let result = await Task.detached(priority: .utility) {
            Result { () throws -> MonitorSnapshot in
                let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                guard let size = attributes[.size] as? Int, size <= 8_000_000 else {
                    throw CocoaError(.fileReadTooLarge)
                }
                return try JSONDecoder().decode(MonitorSnapshot.self, from: Data(contentsOf: url))
            }
        }.value
        guard !Task.isCancelled, host != nil else { return }
        switch result {
        case .success(let value):
            snapshot = value
            message = value.isFresh(at: .now) ? nil : "Open Runway to refresh."
        case .failure:
            message = "Open Runway to prepare local data."
        }
    }

    func openMonitor() {
        let workspace = NSWorkspace.shared
        guard let url = workspace.urlForApplication(withBundleIdentifier: "com.codexusage.CodexUsageMonitor")
            ?? workspace.urlForApplication(withBundleIdentifier: "com.codexusage.CodexUsageMonitor.debug") else {
            message = "Install or open Runway first."
            return
        }
        _ = host?.workspace.open(url)
    }
}

extension CodexusageDroplet: ShelfWidgetProviding {
    public var widgetDescriptors: [ShelfWidgetDescriptor] {
        [ShelfWidgetDescriptor(
            id: "activity", title: "Codex Usage", systemImage: "terminal",
            layoutTraits: ShelfWidgetLayoutTraits(
                preferredSoloWidth: 380, preferredPairedWidth: 210, contentHeight: .fixed(148)
            )
        )]
    }

    public func makeWidgetView(_ id: ShelfWidgetID, context: ShelfWidgetContext) -> AnyView {
        AnyView(CodexActivityWidget(droplet: self, context: context))
    }

    public func makeWidgetSettingsPopover(_ id: ShelfWidgetID) -> AnyView? { nil }
}

private struct CodexActivityWidget: View {
    @ObservedObject var droplet: CodexusageDroplet
    let context: ShelfWidgetContext

    private var accent: Color {
        // Mirrors Runway's AppTheme accents so the shelf matches the app.
        switch droplet.snapshot?.appearanceTheme {
        case "crimson": Color(red: 0.12, green: 0.78, blue: 0.76)
        case "classicRed": Color(red: 0.98, green: 0.16, blue: 0.21)
        case "graphite": Color(red: 0.42, green: 0.67, blue: 1)
        case "rain": Color(red: 0.48, green: 0.76, blue: 0.91)
        case "autumn": Color(red: 0.96, green: 0.64, blue: 0.35)
        case "runway": Color(red: 0.86, green: 0.42, blue: 0.16)
        default: Color(red: 0.45, green: 0.68, blue: 1)
        }
    }

    private var stale: Bool { droplet.snapshot.map { !$0.isFresh(at: .now) } ?? false }

    private var updatedText: String {
        guard let date = droplet.snapshot?.generatedAt else { return "not updated" }
        return date.formatted(.relative(presentation: .numeric, unitsStyle: .abbreviated))
    }

    var body: some View {
        Group {
            let snapshot = droplet.snapshot
            let activity = snapshot?.latest
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 5) {
                    Label(stale ? "Runway · \(updatedText)" : "Runway", systemImage: "chart.xyaxis.line")
                        .font(.system(size: 11, weight: .semibold)).lineLimit(1)
                    Spacer(minLength: 0)
                    Button { droplet.openMonitor() } label: { Image(systemName: "arrow.up.forward.app") }
                        .buttonStyle(DroppyCircleButtonStyle(size: 20))
                        .help(droplet.message ?? "Open Runway").accessibilityLabel("Open Runway")
                }.foregroundStyle(AdaptiveColors.notchSurfaceSecondaryText)
                if let snapshot {
                    Text(activity?.model ?? snapshot.currentModel ?? "Model unavailable")
                        .font(.system(size: context.isPaired ? 13 : 15, weight: .semibold))
                        .lineLimit(1).minimumScaleFactor(0.7)
                    let usage = activity?.usage ?? snapshot.currentSession
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(usage.compact)
                            .font(.system(size: context.isPaired ? 22 : 25, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                        Text("tokens").font(.system(size: 10))
                            .foregroundStyle(AdaptiveColors.notchSurfaceSecondaryText)
                        Spacer(minLength: 0)
                        if !context.isPaired {
                            Text("\(activity?.requests ?? snapshot.currentSessionTurns ?? 0) requests")
                                .font(.system(size: 10)).foregroundStyle(AdaptiveColors.notchSurfaceSecondaryText)
                        }
                    }
                    TokenSparkline(points: activity?.usageHistory ?? [], accent: accent).frame(height: context.isPaired ? 30 : 34)
                    if let limits = snapshot.rateLimits {
                        HStack(spacing: 10) {
                            if let five = limits.fiveHour { AllowanceBar(title: "5H", window: five, accent: accent) }
                            if let weekly = limits.weekly { AllowanceBar(title: "W", window: weekly, accent: accent) }
                        }
                    }
                } else {
                    Text("Connect the monitor").font(.system(size: 14, weight: .semibold))
                    Text(droplet.message ?? "Reading the local snapshot…")
                        .font(.system(size: 11)).foregroundStyle(AdaptiveColors.notchSurfaceSecondaryText)
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(AdaptiveColors.notchSurfacePrimaryText)
            .opacity(stale ? 0.62 : 1)
            .padding(context.contentInsets)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

private struct TokenSparkline: View {
    var points: [MonitorSnapshot.Point]
    var accent: Color

    /// Tokens used in each slice of the session. A running total looks flat with a
    /// cliff wherever the session went quiet; bars show when work actually happened.
    private var buckets: [Double] {
        guard points.count > 1, let first = points.first?.date, let last = points.last?.date,
              last > first else { return [] }
        let count = 40
        let span = last.timeIntervalSince(first)
        var values = Array(repeating: 0.0, count: count)
        for (previous, point) in zip(points, points.dropFirst()) {
            let delta = Double(max(0, point.totalTokens - previous.totalTokens))
            let index = min(count - 1, Int(point.date.timeIntervalSince(first) / span * Double(count)))
            values[index] += delta
        }
        return values
    }

    var body: some View {
        let values = buckets
        let peak = values.max() ?? 0
        Group {
            if peak > 0 {
                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(values.indices, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                            .fill(values[index] > 0 ? accent : accent.opacity(0.18))
                            .frame(maxWidth: .infinity)
                            .frame(height: values[index] > 0 ? max(3, values[index] / peak * 30) : 2)
                    }
                }
                .frame(maxHeight: .infinity, alignment: .bottom)
            } else {
                Text(points.isEmpty ? "Awaiting token events" : "No token activity yet")
                    .font(.system(size: 9)).foregroundStyle(AdaptiveColors.notchSurfaceSecondaryText)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Session token activity")
        .accessibilityValue(points.last.map { "\($0.totalTokens) tokens" } ?? "No recorded events")
    }
}

private struct AllowanceBar: View {
    var title: String
    var window: MonitorSnapshot.Window
    var accent: Color

    private var fraction: Double {
        guard window.resetsAt > .now, window.usedPercent.isFinite else { return 0 }
        return max(0, min(1, (100 - window.usedPercent) / 100))
    }

    var body: some View {
        HStack(spacing: 5) {
            Text(title).font(.system(size: 10, weight: .semibold)).foregroundStyle(AdaptiveColors.notchSurfaceSecondaryText)
            GeometryReader { proxy in
                Capsule().fill(AdaptiveColors.notchSurfaceSecondaryText.opacity(0.25))
                    .overlay(alignment: .leading) {
                        Capsule().fill(accent).frame(width: fraction > 0 ? max(4, proxy.size.width * fraction) : 0)
                    }
            }
            .frame(height: 4)
            Text(window.remaining(at: .now)).font(.system(size: 10, weight: .semibold)).monospacedDigit()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title == "W" ? "Weekly" : "Five-hour") allowance")
        .accessibilityValue(window.remaining(at: .now))
    }
}
