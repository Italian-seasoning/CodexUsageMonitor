import Charts
import SwiftUI

struct AnalysisView: View {
    var snapshot: CodexUsageSnapshot
    var health: SnapshotHealth
    @Binding var selection: AnalysisSelection

    private var summary: PeriodUsageSummary {
        snapshot.summary(for: selection.period)
    }

    private var chartPoints: [AnalysisChartPoint] {
        AnalysisChartData.points(
            from: summary.days,
            period: selection.period,
            measure: selection.measure
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            AppSectionHeader(section: .analysis) {
                HStack(spacing: 8) {
                    Picker("Period", selection: $selection.period) {
                        ForEach(UsagePeriod.allCases) { period in
                            Text(period.title).tag(period)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 130)

                    Picker("Measure", selection: $selection.measure) {
                        ForEach(UsageMeasure.allCases) { measure in
                            Text(measure.title).tag(measure)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 135)
                }
            }

            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: 10) {
                        activityChart

                        LazyVGrid(columns: metricColumns(for: geometry.size.width), spacing: 10) {
                            modules
                        }

                        LimitSummaryStrip(snapshot: snapshot)

                        InspectorSection(
                            title: "Limit history",
                            subtitle: "Remaining allowance over the last recorded week"
                        ) {
                            LimitHistoryChart(history: snapshot.rateLimits?.history ?? [])
                                .frame(minHeight: 125)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
            }
        }
    }

    private func metricColumns(for width: CGFloat) -> [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: 10),
            count: width >= 900 ? 4 : 2
        )
    }

    private var activityChart: some View {
        InspectorSection(
            title: "\(selection.measure.title) activity",
            subtitle: "\(selection.period.title) · \(formatted(summary.value(for: selection.measure))) total",
            subtitleInline: true
        ) {
            Chart(chartPoints) { point in
                BarMark(
                    x: .value("Period", point.date, unit: .day),
                    yStart: .value("Baseline", 0),
                    yEnd: .value(selection.measure.title, point.value),
                    width: barWidth
                )
                .foregroundStyle(isHighlighted(point) ? AppPalette.accent : AppPalette.chartMuted)
                .cornerRadius(6)
            }
            .chartXAxis {
                AxisMarks(values: xAxisDates.map(dayMidpoint)) {
                    AxisValueLabel(format: xAxisFormat)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine().foregroundStyle(AppPalette.chartGrid)
                    AxisValueLabel {
                        if let value = value.as(Double.self) {
                            Text(axisLabel(value))
                        }
                    }
                }
            }
            .chartPlotStyle { plot in
                plot.padding(.horizontal, 8)
            }
            .frame(height: 182)
            .overlay {
                if chartPoints.isEmpty {
                    ContentUnavailableView(
                        "No usage in this period",
                        systemImage: "chart.bar.xaxis",
                        description: Text(health.detail)
                    )
                }
            }
            .accessibilityLabel("\(selection.measure.title) activity for \(selection.period.title)")
        }
    }

    @ViewBuilder
    private var modules: some View {
        MetricModule(
            eyebrow: "Top model",
            value: ModelPricingCatalog.displayName(for: summary.topModel?.model),
            detail: modelShareText,
            symbol: "cpu",
            state: health
        )
        MetricModule(
            eyebrow: "API equivalent",
            value: summary.estimatedCostUSD.compactCurrencyString,
            detail: "Recorded rates, not subscription spend",
            symbol: "dollarsign.circle",
            state: health
        )
        MetricModule(
            eyebrow: "Headroom saved",
            value: headroomValue,
            detail: headroomDetail,
            symbol: "arrow.down.right.and.arrow.up.left",
            state: health
        )
        MetricModule(
            eyebrow: "Sessions",
            value: summary.sessionCount.formatted(),
            detail: "\(summary.requestCount.formatted()) requests · \(comparisonText)",
            symbol: "rectangle.stack",
            state: health
        )
    }

    private var modelShareText: String {
        guard let model = summary.topModel, summary.usage.total > 0 else { return health.title }
        return "\((Double(model.usage.total) / Double(summary.usage.total)).formatted(.percent.precision(.fractionLength(0)))) of selected usage"
    }

    private var headroomValue: String {
        guard let headroom = snapshot.headroom, headroom.isAvailable else { return "—" }
        let value = selection.period == .today
            ? headroom.todayTokensSaved
            : selection.period == .sevenDays
                ? headroom.last7DaysTokensSaved
                : headroom.lifetimeTokensSaved
        return value.compactTokenString
    }

    private var headroomDetail: String {
        guard let headroom = snapshot.headroom, headroom.isAvailable else {
            return "Headroom source unavailable"
        }
        return "\(headroom.savingsPercent.compactPercentString) savings · \(headroom.costSavedUSD.compactCurrencyString) avoided"
    }

    private var comparisonText: String {
        guard selection.period == .sevenDays, let delta = snapshot.last7DaysDeltaPercent else {
            return health.title
        }
        return "\(delta >= 0 ? "+" : "")\(delta.formatted(.percent.precision(.fractionLength(0)))) vs prior"
    }

    private var barWidth: MarkDimension {
        switch chartPoints.count {
        case 0...1: .fixed(68)
        case 2...7: .fixed(42)
        case 8...18: .fixed(24)
        default: .fixed(12)
        }
    }

    private var xAxisDates: [Date] {
        let dates = chartPoints.map(\.date)
        if selection.period == .lifetime {
            var months: [Date] = []
            for date in dates where months.last.map({
                !Calendar.current.isDate($0, equalTo: date, toGranularity: .month)
            }) ?? true {
                months.append(date)
            }
            return months
        }
        guard dates.count > 7 else { return dates }
        let interval = max(1, Int(ceil(Double(dates.count) / 6)))
        return dates.enumerated().compactMap { index, date in
            index.isMultiple(of: interval) ? date : nil
        }
    }

    private var xAxisFormat: Date.FormatStyle {
        switch selection.period {
        case .today, .month:
            .dateTime.month(.abbreviated).day()
        case .sevenDays:
            .dateTime.weekday(.abbreviated)
        case .lifetime:
            .dateTime.month(.abbreviated).year()
        }
    }

    private func isHighlighted(_ point: AnalysisChartPoint) -> Bool {
        point.id == chartPoints.last(where: { $0.value > 0 })?.id
    }

    private func formatted(_ value: Double) -> String {
        switch selection.measure {
        case .tokens: Int(value).compactTokenString
        case .apiEquivalentCost: value.compactCurrencyString
        case .sessions, .requests: Int(value).formatted()
        }
    }

    private func axisLabel(_ value: Double) -> String {
        switch selection.measure {
        case .tokens: Int(value).compactTokenString
        case .apiEquivalentCost: value.compactCurrencyString
        case .sessions, .requests:
            Int(value).formatted(.number.notation(.compactName))
        }
    }

    private func dayMidpoint(_ date: Date) -> Date {
        Calendar.current.date(byAdding: .hour, value: 12, to: date) ?? date
    }
}

struct AnalysisChartPoint: Identifiable, Equatable {
    var date: Date
    var value: Double

    var id: Date { date }
}

enum AnalysisChartData {
    static func points(
        from days: [DailyUsage],
        period: UsagePeriod,
        measure: UsageMeasure,
        calendar: Calendar = .current
    ) -> [AnalysisChartPoint] {
        let points = days.map {
            AnalysisChartPoint(date: $0.date, value: $0.value(for: measure))
        }
        guard period == .lifetime else { return points }

        return Dictionary(grouping: points) {
            calendar.dateInterval(of: .weekOfYear, for: $0.date)?.start
                ?? calendar.startOfDay(for: $0.date)
        }
        .map { date, points in
            AnalysisChartPoint(
                date: date,
                value: points.reduce(0) { $0 + $1.value }
            )
        }
        .sorted { $0.date < $1.date }
    }
}

private extension DailyUsage {
    func value(for measure: UsageMeasure) -> Double {
        switch measure {
        case .tokens: Double(usage.total)
        case .apiEquivalentCost: Double(estimatedCostMicros ?? 0) / 1_000_000
        case .sessions: Double(sessions)
        case .requests: Double(turns ?? 0)
        }
    }
}

extension UsagePeriod {
    var title: String {
        switch self {
        case .today: "Today"
        case .sevenDays: "7 Days"
        case .month: "This Month"
        case .lifetime: "Lifetime"
        }
    }
}

extension UsageMeasure {
    var title: String {
        switch self {
        case .tokens: "Tokens"
        case .apiEquivalentCost: "API Cost"
        case .sessions: "Sessions"
        case .requests: "Requests"
        }
    }
}
