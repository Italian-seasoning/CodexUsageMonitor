import AppKit
import SwiftUI
import WidgetKit

struct CodexUsageEntry: TimelineEntry {
    var date: Date
    var snapshot: CodexUsageSnapshot
    var configuration: WidgetDisplayConfiguration
}

struct CodexUsageProvider: TimelineProvider {
    func placeholder(in context: Context) -> CodexUsageEntry {
        entry(at: .now, family: context.family)
    }

    func getSnapshot(in context: Context, completion: @escaping (CodexUsageEntry) -> Void) {
        completion(entry(at: .now, family: context.family))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CodexUsageEntry>) -> Void) {
        let now = Date()
        let next = Calendar.current.date(byAdding: .minute, value: 3, to: now)
            ?? now.addingTimeInterval(180)
        completion(Timeline(entries: [entry(at: now, family: context.family)], policy: .after(next)))
    }

    private func entry(at date: Date, family: WidgetFamily) -> CodexUsageEntry {
        CodexUsageEntry(
            date: date,
            snapshot: CodexUsageSnapshotStore.load() ?? .empty,
            configuration: DesktopWidgetConfigurationsStore.load()
                .configuration(for: family.desktopWidgetSize)
                .normalized()
        )
    }
}

struct CodexUsageWidgetView: View {
    @Environment(\.widgetFamily) private var widgetFamily

    var entry: CodexUsageEntry

    var body: some View {
        let customBackground = entry.configuration.backgroundMode == .customImage
            ? NSImage(contentsOf: WidgetBackgroundImageStore.url(for: widgetFamily.desktopWidgetSize))
            : nil

        CodexWidgetFamilyView(
            snapshot: entry.snapshot,
            configuration: entry.configuration,
            size: widgetFamily.cardSize,
            monochrome: customBackground != nil || entry.configuration.theme == .monochrome
        )
        .containerBackground(for: .widget) {
            if let customBackground {
                CodexWidgetCustomImageBackground(image: customBackground)
            } else {
                CodexWidgetStyleBackground(
                    style: entry.configuration.style,
                    theme: entry.configuration.theme,
                    monochrome: entry.configuration.theme == .monochrome
                )
            }
        }
    }
}

struct CodexUsageWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: CodexWidgetKind.primary, provider: CodexUsageProvider()) { entry in
            CodexUsageWidgetView(entry: entry)
        }
        .configurationDisplayName("Codex Usage")
        .description("Configure each widget size in the Codex Usage app.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

private struct LegacyCodexUsageWidget: Widget {
    var kind = CodexWidgetKind.dashboard
    var name: LocalizedStringKey = "Modular Dashboard"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CodexUsageProvider()) { entry in
            CodexUsageWidgetView(entry: entry)
        }
        .configurationDisplayName(name)
        .description("Now configured by size in the Codex Usage app.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

@main
struct CodexUsageWidgets: WidgetBundle {
    var body: some Widget {
        CodexUsageWidget()
        LegacyCodexUsageWidget(kind: CodexWidgetKind.limits, name: "Limits")
        LegacyCodexUsageWidget(kind: CodexWidgetKind.costLens, name: "Cost Lens")
        LegacyCodexUsageWidget(kind: CodexWidgetKind.modelMix, name: "Model Mix")
        LegacyCodexUsageWidget(kind: CodexWidgetKind.headroomImpact, name: "Headroom Impact")
        LegacyCodexUsageWidget(kind: CodexWidgetKind.sessionLive, name: "Session Live")
        LegacyCodexUsageWidget(kind: CodexWidgetKind.dashboard, name: "Modular Dashboard")
    }
}

private extension WidgetFamily {
    var desktopWidgetSize: CodexUsageWidgetSize {
        switch self {
        case .systemSmall: .small
        case .systemLarge: .large
        default: .medium
        }
    }

    var cardSize: CodexUsageCardSize {
        switch self {
        case .systemSmall: .small
        case .systemLarge: .large
        default: .medium
        }
    }
}
