import SwiftUI

enum WidgetFamilySemanticBuilder {
    static func content(
        snapshot: CodexUsageSnapshot,
        configuration: WidgetDisplayConfiguration,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> WidgetSemanticContent {
        let configuration = configuration.normalized()
        let summary = snapshot.summary(for: configuration.period, calendar: calendar, now: now)

        switch configuration.family {
        case .limits:
            return limits(snapshot: snapshot, now: now)
        case .usagePulse:
            return WidgetSemanticContent(
                eyebrow: "Usage Pulse",
                heroValue: summary.usage.total.compactTokenString,
                heroLabel: "\(configuration.period.widgetLabel) tokens",
                secondaryValues: [
                    .init(label: "Sessions", value: summary.sessionCount.formatted()),
                    .init(label: "Requests", value: summary.requestCount.formatted()),
                    .init(label: "API equivalent", value: summary.estimatedCostUSD.compactCurrencyString)
                ],
                chart: chart(summary.days) { Double($0.usage.total) },
                freshness: freshness(snapshot, hasData: summary.usage.hasUsage, now: now)
            )
        case .costLens:
            return WidgetSemanticContent(
                eyebrow: "Cost Lens",
                heroValue: summary.estimatedCostUSD.compactCurrencyString,
                heroLabel: "\(configuration.period.widgetLabel) API-equivalent estimate",
                secondaryValues: [
                    .init(label: "Tokens", value: summary.usage.total.compactTokenString),
                    .init(label: "Top model", value: ModelPricingCatalog.displayName(for: summary.topModel?.model)),
                    .init(label: "Unpriced", value: (snapshot.unpricedTokens ?? 0).compactTokenString)
                ],
                chart: chart(summary.days) { Double($0.estimatedCostMicros ?? 0) / 1_000_000 },
                freshness: freshness(snapshot, hasData: summary.usage.hasUsage, now: now)
            )
        case .modelMix:
            let share = summary.topModel.map {
                summary.usage.total > 0 ? Double($0.usage.total) / Double(summary.usage.total) : 0
            } ?? 0
            return WidgetSemanticContent(
                eyebrow: "Model Mix",
                heroValue: ModelPricingCatalog.displayName(for: summary.topModel?.model),
                heroLabel: "\(share.formatted(.percent.precision(.fractionLength(0)))) of \(configuration.period.widgetLabel.lowercased()) tokens",
                secondaryValues: [
                    .init(label: "Attributed", value: (summary.topModel?.usage.total ?? 0).compactTokenString),
                    .init(label: "Total", value: summary.usage.total.compactTokenString),
                    .init(label: "API equivalent", value: summary.estimatedCostUSD.compactCurrencyString)
                ],
                chart: chart(summary.days) { Double($0.usage.total) },
                freshness: freshness(snapshot, hasData: summary.topModel != nil, now: now)
            )
        case .headroomImpact:
            return headroom(snapshot: snapshot, summary: summary, period: configuration.period, now: now)
        case .sessionLive:
            return session(snapshot: snapshot, now: now)
        case .dashboard:
            return dashboard(snapshot: snapshot, summary: summary, configuration: configuration, now: now)
        }
    }

    private static func limits(snapshot: CodexUsageSnapshot, now: Date) -> WidgetSemanticContent {
        let preferred = snapshot.rateLimits?.fiveHour ?? snapshot.rateLimits?.weekly
        let remaining = preferred?.remainingPercent ?? 0
        let label = snapshot.rateLimits?.fiveHour != nil ? "5-hour remaining" : "Weekly remaining"
        let history = snapshot.rateLimits?.history ?? []
        return WidgetSemanticContent(
            eyebrow: "Limits",
            heroValue: preferred.map { "\(Int($0.remainingPercent.rounded()))%" } ?? "—",
            heroLabel: preferred == nil ? "No current limit window" : label,
            secondaryValues: [
                .init(label: "Weekly", value: snapshot.rateLimits?.weekly.map { "\(Int($0.remainingPercent.rounded()))%" } ?? "—"),
                .init(label: "Pace", value: snapshot.rateLimits?.pace.label ?? "Unavailable"),
                .init(label: "Reset", value: snapshot.rateLimits?.nearestReset?.resetText(at: now) ?? "—")
            ],
            chart: WidgetChartContent(
                points: history.suffix(14).map {
                    WidgetChartPoint(date: $0.date, value: 100 - ($0.fiveHourUsedPercent ?? $0.weeklyUsedPercent ?? 100))
                },
                accessibilitySummary: "Remaining allowance history, latest \(Int(remaining.rounded())) percent"
            ),
            freshness: freshness(snapshot, hasData: preferred != nil, now: now)
        )
    }

    private static func headroom(
        snapshot: CodexUsageSnapshot,
        summary: PeriodUsageSummary,
        period: UsagePeriod,
        now: Date
    ) -> WidgetSemanticContent {
        let saved: Int
        switch period {
        case .today:
            saved = snapshot.headroom?.todayTokensSaved ?? 0
        case .sevenDays:
            saved = snapshot.headroom?.last7DaysTokensSaved ?? 0
        case .month:
            saved = summary.days.reduce(0) { $0 + ($1.headroomSaved ?? 0) }
        case .lifetime:
            saved = snapshot.headroom?.lifetimeTokensSaved ?? 0
        }
        let headroom = snapshot.headroom
        return WidgetSemanticContent(
            eyebrow: "Headroom Impact",
            heroValue: saved.compactTokenString,
            heroLabel: "\(period.widgetLabel) tokens saved",
            secondaryValues: [
                .init(label: "Savings rate", value: headroom?.savingsPercent.compactPercentString ?? "—"),
                .init(label: "Cost avoided", value: headroom?.costSavedUSD.compactCurrencyString ?? "—"),
                .init(label: "Requests", value: (headroom?.lifetimeRequests ?? 0).formatted())
            ],
            chart: chart(summary.days) { Double($0.headroomSaved ?? 0) },
            freshness: freshness(snapshot, hasData: headroom?.isAvailable == true, now: now)
        )
    }

    private static func session(snapshot: CodexUsageSnapshot, now: Date) -> WidgetSemanticContent {
        let age = snapshot.currentSessionStartedAt.map { compactDuration(now.timeIntervalSince($0)) } ?? "—"
        return WidgetSemanticContent(
            eyebrow: "Session Live",
            heroValue: snapshot.currentSession.total.compactTokenString,
            heroLabel: "Current session tokens",
            secondaryValues: [
                .init(label: "Age", value: age),
                .init(label: "Model", value: ModelPricingCatalog.displayName(for: snapshot.currentModel)),
                .init(label: "Requests", value: (snapshot.currentSessionTurns ?? 0).formatted())
            ],
            chart: nil,
            freshness: freshness(snapshot, hasData: snapshot.currentSession.hasUsage, now: now)
        )
    }

    private static func dashboard(
        snapshot: CodexUsageSnapshot,
        summary: PeriodUsageSummary,
        configuration: WidgetDisplayConfiguration,
        now: Date
    ) -> WidgetSemanticContent {
        let weeklyRemaining = snapshot.rateLimits?.weekly?.remainingPercent
        let usage = WidgetLabeledValue(label: "Tokens", value: summary.usage.total.compactTokenString)
        let limits = WidgetLabeledValue(label: "Weekly left", value: weeklyRemaining.map { "\(Int($0.rounded()))%" } ?? "—")
        let cost = WidgetLabeledValue(label: "API equivalent", value: summary.estimatedCostUSD.compactCurrencyString)
        let model = WidgetLabeledValue(label: "Top model", value: ModelPricingCatalog.displayName(for: summary.topModel?.model))
        let values: [WidgetLabeledValue]
        let hero: WidgetLabeledValue
        switch configuration.dashboardArrangement {
        case .balanced:
            hero = usage
            values = [limits, cost, model]
        case .limitsFirst:
            hero = limits
            values = [usage, cost, model]
        case .activityFirst:
            hero = usage
            values = [model, cost, limits]
        }
        return WidgetSemanticContent(
            eyebrow: "Modular Dashboard",
            heroValue: hero.value,
            heroLabel: "\(configuration.period.widgetLabel) \(hero.label.lowercased())",
            secondaryValues: values,
            chart: chart(summary.days) { Double($0.usage.total) },
            freshness: freshness(snapshot, hasData: summary.usage.hasUsage, now: now)
        )
    }

    private static func chart(
        _ days: [DailyUsage],
        value: (DailyUsage) -> Double
    ) -> WidgetChartContent {
        let points = days.suffix(14).map { WidgetChartPoint(date: $0.date, value: value($0)) }
        let latest = points.last?.value ?? 0
        let peak = points.map(\.value).max() ?? 0
        return WidgetChartContent(
            points: points,
            accessibilitySummary: "Activity trend with \(points.count) points, latest \(Int(latest)), peak \(Int(peak))"
        )
    }

    private static func freshness(
        _ snapshot: CodexUsageSnapshot,
        hasData: Bool,
        now: Date
    ) -> WidgetFreshness {
        guard hasData else { return snapshot.hasUsage ? .partial : .unavailable }
        guard let generatedAt = snapshot.generatedAt else { return .stale }
        return now.timeIntervalSince(generatedAt) > 10 * 60 ? .stale : .fresh
    }

    private static func compactDuration(_ seconds: TimeInterval) -> String {
        let seconds = max(0, seconds)
        if seconds < 60 { return "\(Int(seconds))s" }
        if seconds < 3_600 { return "\(Int(seconds / 60))m" }
        return "\(Int(seconds / 3_600))h \(Int(seconds.truncatingRemainder(dividingBy: 3_600) / 60))m"
    }
}

struct CodexWidgetFamilyView: View {
    @Environment(\.colorScheme) private var colorScheme
    var snapshot: CodexUsageSnapshot
    var configuration: WidgetDisplayConfiguration
    var size: CodexUsageCardSize
    var monochrome: Bool
    var paintsBackground = false
    var now: Date = .now

    private var content: WidgetSemanticContent {
        WidgetFamilySemanticBuilder.content(snapshot: snapshot, configuration: configuration, now: now)
    }

    private var palette: WidgetStylePalette {
        WidgetStylePalette.make(
            style: configuration.style,
            theme: configuration.theme,
            monochrome: monochrome,
            colorScheme: colorScheme
        )
    }

    var body: some View {
        CodexWidgetStyledContainer(
            style: configuration.style,
            theme: configuration.theme,
            monochrome: monochrome,
            paintsBackground: paintsBackground
        ) {
            Group {
                switch configuration.family {
                case .limits:
                    LimitsFamilyView(content: content, size: size, palette: palette)
                case .usagePulse:
                    UsagePulseFamilyView(content: content, size: size, palette: palette)
                case .costLens:
                    CostLensFamilyView(content: content, size: size, palette: palette)
                case .modelMix:
                    ModelMixFamilyView(content: content, size: size, palette: palette)
                case .headroomImpact:
                    HeadroomImpactFamilyView(content: content, size: size, palette: palette)
                case .sessionLive:
                    SessionLiveFamilyView(content: content, size: size, palette: palette)
                case .dashboard:
                    DashboardFamilyView(content: content, size: size, palette: palette)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

private struct WidgetFamilyHeader: View {
    var content: WidgetSemanticContent
    var palette: WidgetStylePalette

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "sun.horizon.fill")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(palette.accent)
                .accessibilityHidden(true)
            Text(content.eyebrow.uppercased())
                .font(.system(size: 9, weight: .bold))
                .tracking(0.5)
                .foregroundStyle(palette.secondary)
                .lineLimit(1)
            Spacer(minLength: 4)
            WidgetFreshnessLabel(freshness: content.freshness, palette: palette)
        }
    }
}

private struct MetricFamilyLayout: View {
    var content: WidgetSemanticContent
    var size: CodexUsageCardSize
    var palette: WidgetStylePalette

    var body: some View {
        VStack(alignment: .leading, spacing: size == .small ? 7 : 9) {
            WidgetFamilyHeader(content: content, palette: palette)
            if size == .medium {
                HStack(alignment: .bottom, spacing: 14) {
                    WidgetHero(content: content, palette: palette, compact: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let chart = content.chart {
                        WidgetMiniBars(chart: chart, palette: palette)
                            .frame(width: 108, height: 46)
                    }
                }
                WidgetValueGrid(values: Array(content.secondaryValues.prefix(3)), palette: palette, columns: 3)
            } else {
                WidgetHero(content: content, palette: palette, compact: size == .small)
                if size == .large, let chart = content.chart {
                    WidgetMiniBars(chart: chart, palette: palette)
                        .frame(height: 104)
                }
                Spacer(minLength: 1)
                WidgetValueGrid(
                    values: Array(content.secondaryValues.prefix(size == .small ? 1 : 4)),
                    palette: palette,
                    columns: size == .small ? 1 : 2
                )
            }
        }
    }
}

private struct LimitsFamilyView: View {
    var content: WidgetSemanticContent
    var size: CodexUsageCardSize
    var palette: WidgetStylePalette
    private var progress: Double { Double(content.heroValue.dropLast()) ?? 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            WidgetFamilyHeader(content: content, palette: palette)
            HStack(spacing: 12) {
                WidgetGaugeRing(progress: progress / 100, palette: palette)
                    .frame(width: size == .small ? 66 : 82, height: size == .small ? 66 : 82)
                if size != .small {
                    WidgetHero(content: content, palette: palette, compact: true)
                }
            }
            Spacer(minLength: 1)
            WidgetValueGrid(
                values: Array(content.secondaryValues.prefix(size == .small ? 1 : 3)),
                palette: palette,
                columns: size == .small ? 1 : 3
            )
            if size == .large, let chart = content.chart {
                WidgetMiniBars(chart: chart, palette: palette).frame(height: 82)
            }
        }
    }
}

private struct UsagePulseFamilyView: View {
    var content: WidgetSemanticContent
    var size: CodexUsageCardSize
    var palette: WidgetStylePalette
    var body: some View { MetricFamilyLayout(content: content, size: size, palette: palette) }
}

private struct CostLensFamilyView: View {
    var content: WidgetSemanticContent
    var size: CodexUsageCardSize
    var palette: WidgetStylePalette
    var body: some View { MetricFamilyLayout(content: content, size: size, palette: palette) }
}

private struct ModelMixFamilyView: View {
    var content: WidgetSemanticContent
    var size: CodexUsageCardSize
    var palette: WidgetStylePalette
    var body: some View { MetricFamilyLayout(content: content, size: size, palette: palette) }
}

private struct HeadroomImpactFamilyView: View {
    var content: WidgetSemanticContent
    var size: CodexUsageCardSize
    var palette: WidgetStylePalette
    var body: some View { MetricFamilyLayout(content: content, size: size, palette: palette) }
}

private struct SessionLiveFamilyView: View {
    var content: WidgetSemanticContent
    var size: CodexUsageCardSize
    var palette: WidgetStylePalette
    var body: some View { MetricFamilyLayout(content: content, size: size, palette: palette) }
}

private struct DashboardFamilyView: View {
    var content: WidgetSemanticContent
    var size: CodexUsageCardSize
    var palette: WidgetStylePalette
    var body: some View { MetricFamilyLayout(content: content, size: size, palette: palette) }
}

extension UsagePeriod {
    var widgetLabel: String {
        switch self {
        case .today: "Today"
        case .sevenDays: "7-day"
        case .month: "Month"
        case .lifetime: "Lifetime"
        }
    }
}
