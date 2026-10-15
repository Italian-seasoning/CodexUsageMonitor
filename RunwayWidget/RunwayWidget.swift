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
        let next = Calendar.current.date(byAdding: .minute, value: 1, to: now)
            ?? now.addingTimeInterval(60)
        let current = entry(at: now, family: context.family)
        // Age cached readings even when the system delays the requested reload.
        let entries = (0...15).map { minute in
            CodexUsageEntry(date: now.addingTimeInterval(Double(minute) * 60),
                snapshot: current.snapshot, configuration: current.configuration)
        }
        completion(Timeline(entries: entries, policy: .after(next)))
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
            monochrome: entry.configuration.theme == .monochrome,
            now: entry.date
        )
        .containerBackground(for: .widget) {
            if let customBackground {
                CodexWidgetCustomImageBackground(image: customBackground, light: entry.configuration.theme == .runway)
            } else {
                CodexWidgetStyleBackground(
                    style: entry.configuration.style,
                    theme: entry.configuration.theme,
                    monochrome: entry.configuration.theme == .monochrome
                )
            }
        }
        .id(entry.date)
    }
}

struct RunwayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: CodexWidgetKind.primary, provider: CodexUsageProvider()) { entry in
            CodexUsageWidgetView(entry: entry)
        }
        .configurationDisplayName(Bundle.main.bundleIdentifier?.contains(".debug.") == true ? "Runway (Debug)" : "Runway")
        .description("Configure each widget size in the Runway app.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

@main
struct RunwayWidgets: WidgetBundle {
    var body: some Widget {
        RunwayWidget()
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
