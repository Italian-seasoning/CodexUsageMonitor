import SwiftUI
import WidgetKit

struct CodexUsageEntry: TimelineEntry {
    var date: Date
    var snapshot: CodexUsageSnapshot
    var settingsBySize: CodexUsageWidgetSettingsBySize
}

struct CodexUsageProvider: TimelineProvider {
    func placeholder(in context: Context) -> CodexUsageEntry {
        CodexUsageEntry(date: .now, snapshot: .empty, settingsBySize: .default)
    }

    func getSnapshot(in context: Context, completion: @escaping (CodexUsageEntry) -> Void) {
        completion(entry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CodexUsageEntry>) -> Void) {
        let now = Date()
        let next = Calendar.current.date(byAdding: .minute, value: 3, to: now) ?? now.addingTimeInterval(180)
        completion(Timeline(entries: [entry(now: now)], policy: .after(next)))
    }

    private func entry(now: Date = .now) -> CodexUsageEntry {
        CodexUsageEntry(
            date: now,
            snapshot: CodexUsageSnapshotStore.load() ?? .empty,
            settingsBySize: CodexUsageSnapshotStore.loadAllSettings()
        )
    }
}

struct CodexUsageWidgetView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode

    var entry: CodexUsageEntry

    private var monochrome: Bool {
        renderingMode != .fullColor
    }

    var body: some View {
        let size = cardSize
        let settings = entry.settingsBySize.settings(for: size.widgetSettingsSize)
        let dark = isDark(for: settings)

        CodexUsageCardView(
            snapshot: entry.snapshot,
            settings: settings,
            size: size,
            monochrome: monochrome,
            dark: dark
        )
        .containerBackground(for: .widget) {
            CodexUsageCardBackground(dark: dark, theme: settings.theme)
        }
    }

    private var cardSize: CodexUsageCardSize {
        switch family {
        case .systemSmall: .small
        case .systemLarge: .large
        default: .medium
        }
    }

    private func isDark(for settings: CodexUsageWidgetSettings) -> Bool {
        if monochrome {
            return colorScheme == .dark
        }

        switch settings.theme {
        case .frostedWhite:
            return false
        case .crimson, .darkGlass:
            return true
        case .monochrome:
            return colorScheme == .dark
        }
    }
}

@main
struct CodexUsageWidget: Widget {
    let kind = "CodexUsageWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CodexUsageProvider()) { entry in
            CodexUsageWidgetView(entry: entry)
        }
        .configurationDisplayName("Codex Usage")
        .description("Local Codex usage and Headroom savings at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}
