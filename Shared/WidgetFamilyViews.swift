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
        let accountDays = snapshot.accountDays(for: configuration.period, calendar: calendar, now: now)
        let accountLifetime = configuration.period == .lifetime ? snapshot.accountLifetimeTokens : nil
        let accountSource = accountDays != nil || accountLifetime != nil
        let accountPending = snapshot.accountUsageIsPending(for: configuration.period, calendar: calendar, now: now)
        let localHistoryLabel = summary.hasPartialLegacyCoverage ? " · Partial local history" : ""
        let localDataPartial = summary.hasPartialLegacyCoverage || snapshot.sourceReadPending == true
        let tokenTotal = accountDays.map { $0.reduce(0) { $0 + $1.tokens } } ?? accountLifetime ?? summary.usage.total
        let tokenChart: WidgetChartContent? = accountDays.map { days in
            WidgetChartContent(
                points: days.suffix(14).map { WidgetChartPoint(date: $0.date, value: Double($0.tokens)) },
                accessibilitySummary: "Codex account token history"
            )
        } ?? (accountLifetime == nil ? chart(summary.days) { Double($0.usage.total) } : nil)
        let tokenFreshness: WidgetFreshness = accountSource
            ? (snapshot.accountUsageObservedAt.map { now.timeIntervalSince($0) <= 180 } == true ? accountPending ? .partial : .fresh : .stale)
            : freshness(snapshot, hasData: tokenTotal > 0, now: now, partial: localDataPartial || accountPending)

        switch configuration.family {
        case .limits:
            return limits(snapshot: snapshot, now: now)
        case .usagePulse:
            return WidgetSemanticContent(
                eyebrow: "Usage Pulse",
                heroValue: tokenTotal.compactTokenString,
                heroLabel: "\(accountSource ? "Account" : "Local") \(configuration.period.widgetLabel.lowercased()) tokens\(accountSource ? accountPending ? " · Today pending" : "" : localHistoryLabel)",
                secondaryValues: [
                    .init(label: "Local sessions", value: summary.sessionCount.formatted()),
                    .init(label: "Local requests", value: summary.requestCount.formatted()),
                    .init(label: "Local API equivalent", value: summary.estimatedCostUSD.compactCurrencyString)
                ],
                chart: tokenChart,
                freshness: snapshot.sourceReadPending == true && tokenFreshness == .fresh ? .partial : tokenFreshness
            )
        case .costLens:
            return WidgetSemanticContent(
                eyebrow: "Cost Lens",
                heroValue: summary.estimatedCostUSD.compactCurrencyString,
                heroLabel: "\(configuration.period.widgetLabel) API estimate\(localHistoryLabel)",
                secondaryValues: [
                    .init(label: "Local tokens", value: summary.usage.total.compactTokenString),
                    .init(label: "Top model", value: ModelPricingCatalog.displayName(for: summary.topModel?.model)),
                    .init(label: "Unpriced lifetime", value: snapshot.unpricedTokens?.compactTokenString ?? "—")
                ],
                chart: chart(summary.days) { Double($0.estimatedCostMicros ?? 0) / 1_000_000 },
                freshness: freshness(snapshot, hasData: summary.usage.hasUsage, now: now, partial: localDataPartial)
            )
        case .modelMix:
            let share = summary.topModel.map {
                summary.usage.total > 0 ? Double($0.usage.total) / Double(summary.usage.total) : 0
            } ?? 0
            return WidgetSemanticContent(
                eyebrow: "Model Mix",
                heroValue: ModelPricingCatalog.displayName(for: summary.topModel?.model),
                heroLabel: "\(share.formatted(.percent.precision(.fractionLength(0)))) of \(configuration.period.widgetLabel.lowercased()) tokens\(localHistoryLabel)",
                secondaryValues: [
                    .init(label: "Attributed", value: (summary.topModel?.usage.total ?? 0).compactTokenString),
                    .init(label: "Total", value: summary.usage.total.compactTokenString),
                    .init(label: "API equivalent", value: summary.estimatedCostUSD.compactCurrencyString)
                ],
                chart: chart(summary.days) { Double($0.usage.total) },
                freshness: freshness(snapshot, hasData: summary.topModel != nil, now: now, partial: localDataPartial),
                fraction: share
            )
        case .headroomImpact:
            return headroom(snapshot: snapshot, summary: summary, period: configuration.period, now: now)
        case .sessionLive:
            return session(snapshot: snapshot, now: now)
        case .dashboard:
            return dashboard(snapshot: snapshot, summary: summary, configuration: configuration,
                tokenTotal: tokenTotal, tokenChart: tokenChart, accountSource: accountSource,
                accountPending: accountPending, tokenFreshness: tokenFreshness, now: now)
        }
    }

    private static func limits(snapshot: CodexUsageSnapshot, now: Date) -> WidgetSemanticContent {
        let fiveHour = snapshot.rateLimits?.showsFiveHour == true ? snapshot.rateLimits?.fiveHour.flatMap { $0.isCurrent(at: now) ? $0 : nil } : nil
        let weekly = snapshot.rateLimits?.weekly.flatMap { $0.isCurrent(at: now) ? $0 : nil }
        let preferred = fiveHour ?? weekly
        let remaining = preferred?.remainingPercent ?? 0
        let label = fiveHour != nil ? "5-hour remaining" : "Weekly remaining"
        let history = snapshot.rateLimits?.history ?? []
        return WidgetSemanticContent(
            eyebrow: "Limits",
            heroValue: preferred.map { "\(Int($0.remainingPercent.rounded()))%" } ?? "—",
            heroLabel: preferred == nil ? "No current limit window" : label,
            secondaryValues: [
                .init(label: "Weekly", value: weekly.map { "\(Int($0.remainingPercent.rounded()))%" } ?? "—"),
                .init(label: "Pace", value: preferred?.pace(at: now).label ?? "Unavailable"),
                .init(label: "Reset", value: [fiveHour, weekly].compactMap { $0 }.min { $0.resetsAt < $1.resetsAt }?.resetText(at: now) ?? "—")
            ],
            chart: WidgetChartContent(
                points: history.suffix(14).map {
                    WidgetChartPoint(date: $0.date, value: 100 - ((snapshot.rateLimits?.showsFiveHour == true ? $0.fiveHourUsedPercent : nil) ?? $0.weeklyUsedPercent ?? 100))
                },
                accessibilitySummary: "Remaining allowance history, latest \(Int(remaining.rounded())) percent"
            ),
            freshness: preferred.map { now.timeIntervalSince($0.observedAt) > 180 } == true
                ? .stale : freshness(snapshot, hasData: preferred != nil, now: now,
                    partial: snapshot.sourceReadPending == true
                        && snapshot.rateLimits?.accountObservedAt.map { now.timeIntervalSince($0) <= 180 } != true)
        )
    }

    private static func headroom(
        snapshot: CodexUsageSnapshot,
        summary: PeriodUsageSummary,
        period: UsagePeriod,
        now: Date
    ) -> WidgetSemanticContent {
        let saved = snapshot.headroomTokensSaved(for: period)
        let headroom = snapshot.headroom
        return WidgetSemanticContent(
            eyebrow: "Headroom Impact",
            heroValue: saved?.compactTokenString ?? "—",
            heroLabel: "\(period == .lifetime ? (headroom?.trackedPeriodLabel ?? "Tracked") : period.widgetLabel) tokens saved",
            secondaryValues: [
                .init(label: "\(headroom?.trackedPeriodLabel ?? "Tracked") savings", value: headroom?.savingsPercent.compactPercentString ?? "—"),
                .init(label: "\(headroom?.trackedPeriodLabel ?? "Tracked") API estimate", value: headroom?.costSavedUSD.compactCurrencyString ?? "—"),
                .init(label: "\(headroom?.trackedPeriodLabel ?? "Tracked") requests", value: headroom?.lifetimeRequests.formatted() ?? "—")
            ],
            chart: chart(summary.days) { Double($0.headroomSaved ?? 0) },
            freshness: freshness(snapshot, hasData: saved != nil, now: now,
                partial: period == .month && snapshot.sourceReadPending == true)
        )
    }

    private static func session(snapshot: CodexUsageSnapshot, now: Date) -> WidgetSemanticContent {
        let activity = snapshot.sessionActivity.first { $0.status(at: now) == "Working" } ?? snapshot.sessionActivity.first
        let age = (activity?.observedAt ?? snapshot.generatedAt).map { compactDuration(max(0, now.timeIntervalSince($0))) + " ago" } ?? "—"
        return WidgetSemanticContent(
            eyebrow: "Session Live",
            heroValue: (activity?.usage ?? snapshot.currentSession).total.compactTokenString,
            heroLabel: activity.map { "tokens · \($0.status(at: now))" } ?? "Current session tokens",
            secondaryValues: [
                .init(label: "Model", value: ModelPricingCatalog.displayName(for: activity?.model ?? snapshot.currentModel)),
                .init(label: "Requests", value: (activity?.requests ?? snapshot.currentSessionTurns ?? 0).formatted()),
                .init(label: "Updated", value: age)
            ],
            chart: activity?.usageHistory.map { points in
                WidgetChartContent(points: points.map { WidgetChartPoint(date: $0.date, value: Double($0.totalTokens)) },
                    accessibilitySummary: "Recorded session token history")
            },
            freshness: freshness(snapshot, hasData: (activity?.usage ?? snapshot.currentSession).hasUsage,
                now: now, partial: snapshot.sourceReadPending == true)
        )
    }

    private static func dashboard(
        snapshot: CodexUsageSnapshot,
        summary: PeriodUsageSummary,
        configuration: WidgetDisplayConfiguration,
        tokenTotal: Int,
        tokenChart: WidgetChartContent?,
        accountSource: Bool,
        accountPending: Bool,
        tokenFreshness: WidgetFreshness,
        now: Date
    ) -> WidgetSemanticContent {
        let weeklyWindow = snapshot.rateLimits?.weekly.flatMap { $0.isCurrent(at: now) ? $0 : nil }
        let weeklyRemaining = weeklyWindow?.remainingPercent
        let partialLocalHistory = !accountSource && summary.hasPartialLegacyCoverage
        let usage = WidgetLabeledValue(label: partialLocalHistory ? "Partial local history" : accountSource && accountPending ? "Account · Today pending" : "\(accountSource ? "Account" : "Local") tokens", value: tokenTotal.compactTokenString)
        let limits = WidgetLabeledValue(label: "Weekly left", value: weeklyRemaining.map { "\(Int($0.rounded()))%" } ?? "—")
        let cost = WidgetLabeledValue(label: "Local API equivalent", value: summary.estimatedCostUSD.compactCurrencyString)
        let model = WidgetLabeledValue(label: "Local top model", value: ModelPricingCatalog.displayName(for: summary.topModel?.model))
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
        let baseFreshness: WidgetFreshness = configuration.dashboardArrangement == .limitsFirst
            ? (weeklyWindow == nil ? .unavailable : now.timeIntervalSince(weeklyWindow!.observedAt) > 180 ? .stale : freshness(snapshot, hasData: true, now: now))
            : tokenFreshness
        return WidgetSemanticContent(
            eyebrow: "Dashboard",
            heroValue: hero.value,
            heroLabel: configuration.dashboardArrangement == .limitsFirst
                ? "Weekly remaining" : "\(accountSource ? "Account" : "Local") \(configuration.period.widgetLabel.lowercased()) tokens\(accountSource && accountPending ? " · Today pending" : partialLocalHistory ? " · Partial local history" : "")",
            secondaryValues: values,
            chart: tokenChart,
            freshness: (snapshot.sourceReadPending == true || accountPending) && baseFreshness == .fresh ? .partial : baseFreshness
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
        now: Date,
        partial: Bool = false
    ) -> WidgetFreshness {
        guard hasData else { return snapshot.hasUsage ? .partial : .unavailable }
        guard let generatedAt = snapshot.generatedAt else { return .stale }
        return now.timeIntervalSince(generatedAt) > 10 * 60 ? .stale : partial ? .partial : .fresh
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
                    LimitsFamilyView(snapshot: snapshot, content: content, size: size, palette: palette, now: now)
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
    var compact = false

    var body: some View {
        HStack(spacing: 5) {
            Text(content.eyebrow)
                .font(.system(size: WidgetTypeScale.label, weight: .semibold))
                .foregroundStyle(palette.secondary)
                .lineLimit(1)
            Spacer(minLength: 4)
            WidgetFreshnessLabel(freshness: content.freshness, palette: palette, compact: true)
        }
    }
}

private struct MetricFamilyLayout: View {
    var content: WidgetSemanticContent
    var size: CodexUsageCardSize
    var palette: WidgetStylePalette
    var usesDots = false

    var body: some View {
        VStack(alignment: .leading, spacing: size == .small ? 8 : 12) {
            WidgetFamilyHeader(content: content, palette: palette, compact: size == .small)
            if size == .medium {
                HStack(alignment: .bottom, spacing: 14) {
                    WidgetHero(content: content, palette: palette, compact: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let chart = content.chart {
                        trend(chart)
                            .frame(width: 108, height: 46)
                    }
                }
                Spacer(minLength: 4)
                WidgetValueGrid(values: Array(content.secondaryValues.prefix(3)), palette: palette, columns: 3)
            } else {
                WidgetHero(content: content, palette: palette, compact: size == .small)
                if size == .large, let chart = content.chart {
                    trend(chart)
                        .frame(maxHeight: .infinity)
                        .frame(minHeight: 72)
                }
                Spacer(minLength: 4)
                if size == .small {
                    if let chart = content.chart, !chart.points.isEmpty {
                        trend(chart).frame(height: 22)
                    }
                    if let item = content.secondaryValues.first {
                        WidgetInlineValue(item: item, palette: palette)
                    }
                } else {
                    Rectangle().fill(palette.separator).frame(height: 0.5)
                    WidgetValueGrid(values: Array(content.secondaryValues.prefix(3)), palette: palette, columns: 3)
                }
            }
        }
    }

    @ViewBuilder private func trend(_ chart: WidgetChartContent) -> some View {
        if usesDots { WidgetDotPlot(chart: chart, palette: palette) }
        else { WidgetMiniBars(chart: chart, palette: palette) }
    }
}

private struct LimitsFamilyView: View {
    var snapshot: CodexUsageSnapshot
    var content: WidgetSemanticContent
    var size: CodexUsageCardSize
    var palette: WidgetStylePalette
    var now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            WidgetFamilyHeader(content: content, palette: palette, compact: size == .small)
            if size == .small {
                if snapshot.rateLimits?.showsFiveHour == true {
                WidgetAllowanceMeter(title: "5-hour left", window: snapshot.rateLimits?.fiveHour, palette: palette, compact: true, now: now)
                }
                WidgetAllowanceMeter(title: "Weekly left", window: snapshot.rateLimits?.weekly, palette: palette, compact: true, now: now)
            } else {
                HStack(alignment: .top, spacing: 20) {
                    if snapshot.rateLimits?.showsFiveHour == true {
                    WidgetAllowanceMeter(title: "5-hour left", window: snapshot.rateLimits?.fiveHour, palette: palette, now: now,
                        showsConsumption: true, consumptionRate: snapshot.rateLimits?.consumptionPer15Minutes(for: snapshot.rateLimits?.fiveHour, now: now))
                    }
                    WidgetAllowanceMeter(title: "Weekly left", window: snapshot.rateLimits?.weekly, palette: palette, now: now,
                        showsConsumption: true, consumptionRate: snapshot.rateLimits?.consumptionPer15Minutes(for: snapshot.rateLimits?.weekly, now: now))
                }
            }
            if size == .large, let chart = content.chart {
                Text("Remaining allowance history").font(.system(size: 11)).foregroundStyle(palette.secondary)
                WidgetSparkline(chart: chart, palette: palette, fixedDomain: 0...100).frame(maxHeight: .infinity)
            }
            Spacer(minLength: 0)
            if size == .small, let reset = content.secondaryValues.first(where: { $0.label == "Reset" }) {
                Text(reset.value == "—" ? "Awaiting current data" : "Resets \(reset.value)")
                    .font(.system(size: 10))
                    .foregroundStyle(palette.secondary)
                    .lineLimit(2)
            }
            if size != .small, let pace = content.secondaryValues.first(where: { $0.label == "Pace" }) {
                WidgetInlineValue(item: pace, palette: palette)
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
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            WidgetFamilyHeader(content: content, palette: palette, compact: size == .small)
            HStack(spacing: 12) {
                WidgetHero(content: content, palette: palette, compact: size != .large)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if size != .small {
                    WidgetGaugeRing(progress: content.fraction, palette: palette, caption: "share")
                        .frame(width: size == .large ? 72 : 56, height: size == .large ? 72 : 56)
                }
            }
            if size == .small, let chart = content.chart {
                WidgetMiniBars(chart: chart, palette: palette).frame(height: 22)
            } else if size == .large, let chart = content.chart {
                Text("Daily tokens").font(.system(size: 11)).foregroundStyle(palette.secondary)
                WidgetMiniBars(chart: chart, palette: palette).frame(maxHeight: .infinity)
            }
            Spacer(minLength: 4)
            if size == .small, let item = content.secondaryValues.first {
                WidgetInlineValue(item: item, palette: palette)
            } else {
                WidgetValueGrid(values: content.secondaryValues, palette: palette, columns: 3)
            }
        }
    }
}

private struct HeadroomImpactFamilyView: View {
    var content: WidgetSemanticContent
    var size: CodexUsageCardSize
    var palette: WidgetStylePalette
    var body: some View { MetricFamilyLayout(content: content, size: size, palette: palette, usesDots: true) }
}

private struct SessionLiveFamilyView: View {
    var content: WidgetSemanticContent
    var size: CodexUsageCardSize
    var palette: WidgetStylePalette
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            WidgetFamilyHeader(content: content, palette: palette, compact: true)
            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(content.secondaryValues.first?.value ?? "Codex")
                        .font(.system(size: size == .small ? 13 : 15, weight: .semibold))
                        .lineLimit(1).minimumScaleFactor(0.7)
                    WidgetHero(content: content, palette: palette, compact: size != .large)
                }.frame(maxWidth: .infinity, alignment: .leading)
                if size == .medium, let chart = content.chart, !chart.points.isEmpty {
                    WidgetSparkline(chart: chart, palette: palette).frame(width: 108, height: 55)
                }
            }
            if size != .medium, let chart = content.chart, !chart.points.isEmpty {
                WidgetSparkline(chart: chart, palette: palette)
                    .frame(maxHeight: size == .small ? 22 : .infinity)
            }
            Spacer(minLength: 0)
            if size != .small {
                WidgetValueGrid(values: Array(content.secondaryValues.dropFirst()), palette: palette, columns: 2)
            }
        }
    }
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
