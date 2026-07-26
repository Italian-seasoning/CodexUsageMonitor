import AppIntents
import SwiftUI
import WidgetKit

protocol CodexWidgetIntent: WidgetConfigurationIntent {
    var displayConfiguration: WidgetDisplayConfiguration { get }
}

struct CodexUsageEntry: TimelineEntry {
    var date: Date
    var snapshot: CodexUsageSnapshot
    var settingsBySize: CodexUsageWidgetSettingsBySize
    var configuration: WidgetDisplayConfiguration
}

struct CodexUsageProvider<Intent: CodexWidgetIntent>: AppIntentTimelineProvider {
    var family: CodexWidgetFamily

    func placeholder(in context: Context) -> CodexUsageEntry {
        entry(configuration: defaultConfiguration)
    }

    func snapshot(for configuration: Intent, in context: Context) async -> CodexUsageEntry {
        entry(configuration: configuration.displayConfiguration)
    }

    func timeline(for configuration: Intent, in context: Context) async -> Timeline<CodexUsageEntry> {
        let now = Date()
        let next = Calendar.current.date(byAdding: .minute, value: 3, to: now) ?? now.addingTimeInterval(180)
        return Timeline(entries: [entry(now: now, configuration: configuration.displayConfiguration)], policy: .after(next))
    }

    private var defaultConfiguration: WidgetDisplayConfiguration {
        WidgetDisplayConfiguration(
            family: family,
            style: .precisionInstrument,
            theme: .crimson,
            period: .today,
            dashboardArrangement: .balanced
        )
    }

    private func entry(
        now: Date = .now,
        configuration: WidgetDisplayConfiguration
    ) -> CodexUsageEntry {
        CodexUsageEntry(
            date: now,
            snapshot: CodexUsageSnapshotStore.load() ?? .empty,
            settingsBySize: CodexUsageSnapshotStore.loadAllSettings(),
            configuration: configuration.normalized()
        )
    }
}

struct CodexUsageWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode
    var entry: CodexUsageEntry

    private var monochrome: Bool { renderingMode != .fullColor }

    var body: some View {
        let size = cardSize
        let configuration = resolvedConfiguration(for: size)
        CodexWidgetFamilyView(
            snapshot: entry.snapshot,
            configuration: configuration,
            size: size,
            monochrome: monochrome
        )
        .containerBackground(for: .widget) {
            CodexWidgetStyleBackground(
                style: configuration.style,
                theme: configuration.theme,
                monochrome: monochrome
            )
        }
    }

    private var cardSize: CodexUsageCardSize {
        switch family {
        case .systemSmall: .small
        case .systemLarge: .large
        default: .medium
        }
    }

    private func resolvedConfiguration(for size: CodexUsageCardSize) -> WidgetDisplayConfiguration {
        var configuration = entry.configuration
        guard configuration.family == .usagePulse,
              configuration.style == .precisionInstrument,
              configuration.theme == .crimson,
              configuration.period == .today else {
            return configuration
        }
        let legacy = entry.settingsBySize.settings(for: size.widgetSettingsSize)
        configuration.theme = legacy.theme
        switch legacy.primaryMetric {
        case .last7Days:
            configuration.period = .sevenDays
        case .lifetime:
            configuration.period = .lifetime
        default:
            break
        }
        return configuration
    }
}

struct LimitsIntent: CodexWidgetIntent {
    static var title: LocalizedStringResource = "Limits"
    static var description = IntentDescription("Configure limit presentation.")
    @Parameter(title: "Style", default: .precisionInstrument) var style: CodexWidgetStyle
    @Parameter(title: "Theme", default: .crimson) var theme: WidgetTheme

    var displayConfiguration: WidgetDisplayConfiguration {
        .init(family: .limits, style: style, theme: theme, period: .today, dashboardArrangement: .balanced)
    }
}

struct UsagePulseIntent: CodexWidgetIntent {
    static var title: LocalizedStringResource = "Usage Pulse"
    static var description = IntentDescription("Configure usage activity.")
    @Parameter(title: "Style", default: .precisionInstrument) var style: CodexWidgetStyle
    @Parameter(title: "Theme", default: .crimson) var theme: WidgetTheme
    @Parameter(title: "Period", default: .today) var period: UsagePeriod

    var displayConfiguration: WidgetDisplayConfiguration {
        .init(family: .usagePulse, style: style, theme: theme, period: period, dashboardArrangement: .balanced)
    }
}

struct CostLensIntent: CodexWidgetIntent {
    static var title: LocalizedStringResource = "Cost Lens"
    static var description = IntentDescription("Configure API-equivalent estimates.")
    @Parameter(title: "Style", default: .precisionInstrument) var style: CodexWidgetStyle
    @Parameter(title: "Theme", default: .crimson) var theme: WidgetTheme
    @Parameter(title: "Period", default: .today) var period: UsagePeriod

    var displayConfiguration: WidgetDisplayConfiguration {
        .init(family: .costLens, style: style, theme: theme, period: period, dashboardArrangement: .balanced)
    }
}

struct ModelMixIntent: CodexWidgetIntent {
    static var title: LocalizedStringResource = "Model Mix"
    static var description = IntentDescription("Configure model attribution.")
    @Parameter(title: "Style", default: .precisionInstrument) var style: CodexWidgetStyle
    @Parameter(title: "Theme", default: .crimson) var theme: WidgetTheme
    @Parameter(title: "Period", default: .today) var period: UsagePeriod

    var displayConfiguration: WidgetDisplayConfiguration {
        .init(family: .modelMix, style: style, theme: theme, period: period, dashboardArrangement: .balanced)
    }
}

struct HeadroomImpactIntent: CodexWidgetIntent {
    static var title: LocalizedStringResource = "Headroom Impact"
    static var description = IntentDescription("Configure local compression savings.")
    @Parameter(title: "Style", default: .precisionInstrument) var style: CodexWidgetStyle
    @Parameter(title: "Theme", default: .crimson) var theme: WidgetTheme
    @Parameter(title: "Period", default: .today) var period: UsagePeriod

    var displayConfiguration: WidgetDisplayConfiguration {
        .init(family: .headroomImpact, style: style, theme: theme, period: period, dashboardArrangement: .balanced)
    }
}

struct SessionLiveIntent: CodexWidgetIntent {
    static var title: LocalizedStringResource = "Session Live"
    static var description = IntentDescription("Configure current-session presentation.")
    @Parameter(title: "Style", default: .precisionInstrument) var style: CodexWidgetStyle
    @Parameter(title: "Theme", default: .crimson) var theme: WidgetTheme

    var displayConfiguration: WidgetDisplayConfiguration {
        .init(family: .sessionLive, style: style, theme: theme, period: .today, dashboardArrangement: .balanced)
    }
}

struct DashboardIntent: CodexWidgetIntent {
    static var title: LocalizedStringResource = "Modular Dashboard"
    static var description = IntentDescription("Configure the modular dashboard.")
    @Parameter(title: "Style", default: .precisionInstrument) var style: CodexWidgetStyle
    @Parameter(title: "Theme", default: .crimson) var theme: WidgetTheme
    @Parameter(title: "Period", default: .today) var period: UsagePeriod
    @Parameter(title: "Arrangement", default: .balanced) var arrangement: DashboardArrangement

    var displayConfiguration: WidgetDisplayConfiguration {
        .init(family: .dashboard, style: style, theme: theme, period: period, dashboardArrangement: arrangement)
    }
}

private struct CodexWidgetConfiguration<Intent: CodexWidgetIntent> {
    var kind: String
    var name: LocalizedStringKey
    var description: LocalizedStringKey
    var family: CodexWidgetFamily
    var intent: Intent.Type

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: intent,
            provider: CodexUsageProvider<Intent>(family: family)
        ) { entry in
            CodexUsageWidgetView(entry: entry)
        }
        .configurationDisplayName(name)
        .description(description)
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

struct UsagePulseWidget: Widget {
    var body: some WidgetConfiguration {
        CodexWidgetConfiguration(
            kind: "CodexUsageWidget",
            name: "Usage Pulse",
            description: "Tokens and activity for a selected period.",
            family: .usagePulse,
            intent: UsagePulseIntent.self
        ).body
    }
}

struct LimitsWidget: Widget {
    var body: some WidgetConfiguration {
        CodexWidgetConfiguration(
            kind: "CodexUsageWidget.limits",
            name: "Limits",
            description: "Remaining Codex allowance and reset pace.",
            family: .limits,
            intent: LimitsIntent.self
        ).body
    }
}

struct CostLensWidget: Widget {
    var body: some WidgetConfiguration {
        CodexWidgetConfiguration(
            kind: "CodexUsageWidget.costLens",
            name: "Cost Lens",
            description: "API-equivalent cost estimates from recorded usage.",
            family: .costLens,
            intent: CostLensIntent.self
        ).body
    }
}

struct ModelMixWidget: Widget {
    var body: some WidgetConfiguration {
        CodexWidgetConfiguration(
            kind: "CodexUsageWidget.modelMix",
            name: "Model Mix",
            description: "Model attribution for a selected period.",
            family: .modelMix,
            intent: ModelMixIntent.self
        ).body
    }
}

struct HeadroomImpactWidget: Widget {
    var body: some WidgetConfiguration {
        CodexWidgetConfiguration(
            kind: "CodexUsageWidget.headroomImpact",
            name: "Headroom Impact",
            description: "Local compression savings and avoided cost.",
            family: .headroomImpact,
            intent: HeadroomImpactIntent.self
        ).body
    }
}

struct SessionLiveWidget: Widget {
    var body: some WidgetConfiguration {
        CodexWidgetConfiguration(
            kind: "CodexUsageWidget.sessionLive",
            name: "Session Live",
            description: "Current session activity and freshness.",
            family: .sessionLive,
            intent: SessionLiveIntent.self
        ).body
    }
}

struct DashboardWidget: Widget {
    var body: some WidgetConfiguration {
        CodexWidgetConfiguration(
            kind: "CodexUsageWidget.dashboard",
            name: "Modular Dashboard",
            description: "A curated multi-metric Codex workspace.",
            family: .dashboard,
            intent: DashboardIntent.self
        ).body
    }
}

@main
struct CodexUsageWidgets: WidgetBundle {
    var body: some Widget {
        UsagePulseWidget()
        LimitsWidget()
        CostLensWidget()
        ModelMixWidget()
        HeadroomImpactWidget()
        SessionLiveWidget()
        DashboardWidget()
    }
}

extension CodexWidgetStyle: AppEnum {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Widget Style")
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .precisionInstrument: "Precision Instrument",
        .nativeGlass: "Native Glass",
        .signalGrid: "Signal Grid"
    ]
}

extension WidgetTheme: AppEnum {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Widget Theme")
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .crimson: "Summer",
        .darkGlass: "Dark Glass",
        .frostedWhite: "Frosted White",
        .monochrome: "Monochrome"
    ]
}

extension UsagePeriod: AppEnum {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Usage Period")
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .today: "Today",
        .sevenDays: "7 Days",
        .month: "This Month",
        .lifetime: "Lifetime"
    ]
}

extension DashboardArrangement: AppEnum {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Dashboard Arrangement")
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .balanced: "Balanced",
        .limitsFirst: "Limits First",
        .activityFirst: "Activity First"
    ]
}
