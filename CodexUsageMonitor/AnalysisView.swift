import Charts
import SwiftUI

struct AnalysisView: View {
    var snapshot: CodexUsageSnapshot
    var health: SnapshotHealth
    @Binding var selection: AnalysisSelection

    private var summary: PeriodUsageSummary {
        snapshot.summary(for: selection.period)
    }

    var body: some View {
        VStack(spacing: 0) {
            AppSectionHeader(section: .analysis) {
                HStack(spacing: 8) {
                    Picker("Period", selection: $selection.period) {
                        ForEach(UsagePeriod.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 130)

                    Picker("Measure", selection: $selection.measure) {
                        ForEach(UsageMeasure.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 135)
                }
            }

            ScrollView {
                GeometryReader { geometry in
                    VStack(spacing: 14) {
                        if geometry.size.width >= 1_050 {
                            wideMosaic
                        } else {
                            compactMosaic
                        }

                        LimitSummaryStrip(snapshot: snapshot)

                        InspectorSection(title: "Limit history", subtitle: "Remaining allowance over the last recorded week") {
                            LimitHistoryChart(history: snapshot.rateLimits?.history ?? [])
                                .frame(minHeight: 125)
                        }
                    }
                    .padding(20)
                }
                .frame(minHeight: 590)
            }
        }
    }

    private var wideMosaic: some View {
        HStack(alignment: .top, spacing: 14) {
            activityChart
                .frame(maxWidth: .infinity)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                modules
            }
            .frame(width: 390)
        }
    }

    private var compactMosaic: some View {
        VStack(spacing: 14) {
            activityChart
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                modules
            }
        }
    }

    private var activityChart: some View {
        InspectorSection(
            title: "\(selection.measure.title) activity",
            subtitle: "\(selection.period.title) · \(formatted(summary.value(for: selection.measure))) total"
        ) {
            Chart(summary.days) { day in
                BarMark(
                    x: .value("Day", day.date, unit: .day),
                    y: .value(selection.measure.title, day.value(for: selection.measure)),
                    width: .fixed(summary.days.count == 1 ? 68 : 14)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [AppPalette.accent, AppPalette.accent.opacity(0.28)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .cornerRadius(3)
            }
            .chartXAxis {
                AxisMarks(values: summary.days.map(\.date)) {
                    AxisGridLine().foregroundStyle(Color.white.opacity(0.06))
                    AxisValueLabel(format: selection.period == .today ? .dateTime.month(.abbreviated).day() : .dateTime.weekday(.narrow))
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) {
                    AxisGridLine().foregroundStyle(Color.white.opacity(0.07))
                    AxisValueLabel()
                }
            }
            .chartPlotStyle { plot in
                plot.padding(.top, 8).padding(.horizontal, 4)
            }
            .frame(minHeight: 230)
            .overlay {
                if summary.days.isEmpty {
                    ContentUnavailableView(
                        "No usage for this period",
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
            detail: "Recorded model rates, not subscription spend",
            symbol: "dollarsign.circle",
            state: health,
            accent: true
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
        guard let model = summary.topModel, summary.usage.total > 0 else { return "No model attribution" }
        let share = (Double(model.usage.total) / Double(summary.usage.total))
            .formatted(.percent.precision(.fractionLength(0)))
        return "\(share) of selected usage"
    }

    private var headroomValue: String {
        guard let headroom = snapshot.headroom, headroom.isAvailable else { return "—" }
        let value = selection.period == .today ? headroom.todayTokensSaved :
            selection.period == .sevenDays ? headroom.last7DaysTokensSaved : headroom.lifetimeTokensSaved
        return value.compactTokenString
    }

    private var headroomDetail: String {
        guard let headroom = snapshot.headroom, headroom.isAvailable else { return "Headroom source unavailable" }
        return "\(headroom.savingsPercent.compactPercentString) savings · \(headroom.costSavedUSD.compactCurrencyString) avoided"
    }

    private var comparisonText: String {
        guard selection.period == .sevenDays, let delta = snapshot.last7DaysDeltaPercent else {
            return health.title
        }
        return "\(delta >= 0 ? "+" : "")\(delta.formatted(.percent.precision(.fractionLength(0)))) vs prior"
    }

    private func formatted(_ value: Double) -> String {
        switch selection.measure {
        case .tokens: Int(value).compactTokenString
        case .apiEquivalentCost: value.compactCurrencyString
        case .sessions, .requests: Int(value).formatted()
        }
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
