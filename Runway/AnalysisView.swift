import Charts
import SwiftUI

struct AnalysisView: View {
    var snapshot: CodexUsageSnapshot
    var health: SnapshotHealth
    @Binding var selection: AnalysisSelection
    var section: AppSection = .analysis
    @State private var hoveredDate: Date?

    private var hoveredPoint: AnalysisChartPoint? {
        guard let hoveredDate else { return nil }
        return chartPoints.first { Calendar.current.isDate($0.date, equalTo: hoveredDate, toGranularity: chartPeriod == .lifetime ? .weekOfYear : .day) }
    }

    private var summary: PeriodUsageSummary {
        selection.usesCustomDates
            ? snapshot.summary(from: selection.startDate, through: selection.endDate)
            : snapshot.summary(for: selection.period)
    }

    private var periodLabel: String {
        selection.usesCustomDates
            ? "\(selection.startDate.formatted(.dateTime.month(.abbreviated).day())) – \(selection.endDate.formatted(.dateTime.month(.abbreviated).day().year()))"
            : selection.period.title
    }

    private var chartPeriod: UsagePeriod {
        selection.usesCustomDates ? (summary.days.count > 90 ? .lifetime : .month) : selection.period
    }

    private var periodBinding: Binding<UsagePeriod?> {
        Binding(get: { selection.usesCustomDates ? nil : selection.period }, set: {
            selection.usesCustomDates = $0 == nil
            if let period = $0 { selection.period = period }
        })
    }

    private var chartPoints: [AnalysisChartPoint] {
        if selection.measure == .tokens, let accountDays {
            return AnalysisChartData.points(from: accountDays, period: chartPeriod)
        }
        if accountLifetimeWithoutDays { return [] }
        return AnalysisChartData.points(
            from: summary.days,
            period: chartPeriod,
            measure: selection.measure
        )
    }

    private var accountDays: [AccountUsageDay]? {
        selection.usesCustomDates ? nil : snapshot.accountDays(for: selection.period)
    }

    private var accountLifetimeWithoutDays: Bool {
        selection.measure == .tokens && !selection.usesCustomDates && selection.period == .lifetime
            && snapshot.accountLifetimeTokens != nil && accountDays == nil
    }

    private var accountPeriodPending: Bool {
        !selection.usesCustomDates && snapshot.accountUsageIsPending(for: selection.period)
    }

    private var displayedChartValue: Double {
        if selection.measure == .tokens, let accountDays {
            return Double(accountDays.reduce(0) { $0 + $1.tokens })
        }
        if accountLifetimeWithoutDays, let total = snapshot.accountLifetimeTokens { return Double(total) }
        return summary.value(for: selection.measure)
    }

    var body: some View {
        VStack(spacing: 0) {
            AppSectionHeader(section: section) {
                HStack(spacing: 8) {
                    Picker("Period", selection: periodBinding) {
                        ForEach(UsagePeriod.allCases) { period in
                            Text(period.title).tag(Optional(period))
                        }
                        Text("Custom dates…").tag(nil as UsagePeriod?)
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

            if selection.usesCustomDates {
                HStack(spacing: 12) {
                    DatePicker("From", selection: $selection.startDate, in: ...selection.endDate, displayedComponents: .date)
                    DatePicker("To", selection: $selection.endDate, in: selection.startDate...max(selection.startDate, Date()), displayedComponents: .date)
                }
                .datePickerStyle(.field)
                .font(.system(size: 11))
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
            }

            MagneticScrollView { height in
                activityChart(height: max(80, height - 116))
            } details: {
                    VStack(spacing: 10) {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 155), spacing: 10)], spacing: 10) {
                            modules
                        }

                        LimitSummaryStrip(snapshot: snapshot)

                        InspectorSection(title: "More detail") {
                            DisclosureGroup("Token breakdown") {
                                VStack(spacing: 8) {
                                    dataRow("Input", summary.usage.input.compactTokenString)
                                    dataRow("Cached input", summary.usage.cachedInput.compactTokenString)
                                    dataRow("Output", summary.usage.output.compactTokenString)
                                    dataRow("Unpriced lifetime tokens", (snapshot.unpricedTokens ?? 0).compactTokenString)
                                }.padding(.top, 8)
                            }
                            DisclosureGroup("Headroom savings") {
                                if let headroom = snapshot.headroom, headroom.isAvailable {
                                    VStack(spacing: 8) {
                                        dataRow("Today", headroom.todayTokensSaved.compactTokenString)
                                        dataRow("7 days", headroom.last7DaysTokensSaved.compactTokenString)
                                        dataRow(headroom.trackedPeriodLabel, headroom.lifetimeTokensSaved.compactTokenString)
                                        dataRow("Requests compressed", headroom.lifetimeRequests.formatted())
                                        dataRow("\(headroom.trackedPeriodLabel) API estimate avoided", headroom.costSavedUSD.compactCurrencyString)
                                    }.padding(.top, 8)
                                } else { Text("No Headroom data recorded").foregroundStyle(.secondary) }
                            }
                            DisclosureGroup("Statistics") {
                                VStack(spacing: 8) {
                                    dataRow("Current streak", "\(snapshot.currentStreak) days")
                                    dataRow("Longest streak", "\(snapshot.longestStreak) days")
                                    dataRow("Peak day", snapshot.peakDay?.usage.total.compactTokenString ?? "—")
                                    dataRow("Peak date", snapshot.peakDay?.date.formatted(date: .abbreviated, time: .omitted) ?? "—")
                                }.padding(.top, 8)
                            }
                            DisclosureGroup("Limit history") {
                                LimitHistoryChart(history: snapshot.rateLimits?.history ?? [], showsFiveHour: snapshot.rateLimits?.showsFiveHour == true)
                                    .frame(height: 125).padding(.top, 8)
                            }
                        }
                    }
            }
        }
    }

    private func activityChart(height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(hoveredPoint.map { chartPeriod == .lifetime ? "Week of \($0.date.formatted(date: .abbreviated, time: .omitted))" : $0.date.formatted(date: .abbreviated, time: .omitted) }
                    ?? "\(selection.measure == .tokens && (accountDays != nil || accountLifetimeWithoutDays) ? "Account" : "Local") \(periodLabel.lowercased())")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppPalette.muted)
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text(hoveredPoint.map { exactValue($0.value) } ?? formatted(displayedChartValue))
                        .font(.system(size: 30, weight: .semibold)).tracking(-0.7)
                        .monospacedDigit().minimumScaleFactor(0.65).lineLimit(1)
                    Text(selection.measure.title.lowercased())
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(AppPalette.muted)
                }
                if summary.hasPartialLegacyCoverage {
                    Label("Partial local history · Saved daily totals differ from surviving logs", systemImage: "circle.lefthalf.filled")
                        .font(.system(size: 11)).foregroundStyle(AppPalette.muted)
                }
                if selection.measure == .tokens, accountPeriodPending {
                    Label(accountDays == nil ? "Account reporting pending · Showing local logs" : "Account today is pending · Showing reported totals", systemImage: "clock")
                        .font(.system(size: 11)).foregroundStyle(AppPalette.muted)
                }
            }
            Chart(chartPoints) { point in
                BarMark(
                    x: .value("Period", point.date, unit: chartPeriod == .lifetime ? .weekOfYear : .day),
                    yStart: .value("Baseline", 0),
                    yEnd: .value(selection.measure.title, point.value),
                    width: chartPoints.count == 1 ? .fixed(48) : .ratio(0.68)
                )
                .foregroundStyle((hoveredPoint?.id == point.id || (hoveredPoint == nil && isHighlighted(point))) ? AppPalette.accent : AppPalette.chartMuted)
                .cornerRadius(6)
                .accessibilityLabel(point.date.formatted(date: .abbreviated, time: .omitted))
                .accessibilityValue(exactValue(point.value))
            }
            .chartXAxis {
                if chartPoints.count > 1 {
                    AxisMarks(values: xAxisDates) {
                        AxisValueLabel(format: xAxisFormat)
                            .foregroundStyle(AppPalette.muted)
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine().foregroundStyle(AppPalette.chartGrid)
                    AxisValueLabel {
                        if let value = value.as(Double.self) {
                            Text(axisLabel(value))
                                .foregroundStyle(AppPalette.muted)
                        }
                    }
                }
            }
            .chartPlotStyle { plot in
                plot.padding(.horizontal, 8)
            }
            .frame(height: height)
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let location):
                                guard let plotFrame = proxy.plotFrame else { hoveredDate = nil; return }
                                let frame = geometry[plotFrame]
                                hoveredDate = frame.contains(location) ? proxy.value(atX: location.x - frame.minX, as: Date.self) : nil
                            case .ended: hoveredDate = nil
                            }
                        }
                }
            }
            .overlay {
                if chartPoints.isEmpty {
                    ContentUnavailableView(
                        accountLifetimeWithoutDays ? "Account daily history unavailable" : "No usage in this period",
                        systemImage: "chart.bar.xaxis",
                        description: Text(accountLifetimeWithoutDays ? "The account lifetime total is available, but its daily chart is not." : health.detail)
                    )
                }
            }
            .accessibilityLabel("\(selection.measure.title) activity for \(periodLabel)")
            if chartPoints.count == 1, let point = chartPoints.first {
                Text(point.date, format: xAxisFormat)
                    .font(.system(size: AppTypeScale.caption))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 4)
        .onChange(of: selection.period) { hoveredDate = nil }
        .onChange(of: selection.measure) { hoveredDate = nil }
    }

    private func exactValue(_ value: Double) -> String {
        selection.measure == .apiEquivalentCost
            ? value.formatted(.currency(code: "USD"))
            : Int(value).formatted()
    }

    @ViewBuilder
    private var modules: some View {
        let accountTokens = accountDays.map { $0.reduce(0) { $0 + $1.tokens } }
            ?? (selection.usesCustomDates || selection.period != .lifetime ? nil : snapshot.accountLifetimeTokens)
        let tokenDetail = if accountTokens != nil {
            accountPeriodPending ? "Reported total; today pending" : "Codex account total"
        } else if summary.hasPartialLegacyCoverage {
            "Partial local history"
        } else {
            accountPeriodPending ? "Account reporting pending · Local sessions" : "Recorded local sessions"
        }
        MetricModule(
            eyebrow: selection.usesCustomDates ? "Local range tokens" : "\(accountTokens == nil ? "Local" : "Account") \(selection.period.title.lowercased())",
            value: (accountTokens ?? summary.usage.total).compactTokenString,
            detail: tokenDetail,
            symbol: "sum",
            state: health
        )
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
            detail: ["\(summary.requestCount.formatted()) requests", comparisonText].compactMap { $0 }.joined(separator: " · "),
            symbol: "rectangle.stack",
            state: health
        )
    }

    private var modelShareText: String {
        guard let model = summary.topModel, summary.usage.total > 0 else { return health.title }
        return "\((Double(model.usage.total) / Double(summary.usage.total)).formatted(.percent.precision(.fractionLength(0)))) of local usage"
    }

    private var headroomValue: String {
        if selection.usesCustomDates {
            let values = summary.days.compactMap(\.headroomSaved)
            return values.isEmpty ? "—" : values.reduce(0, +).compactTokenString
        }
        return snapshot.headroomTokensSaved(for: selection.period)?.compactTokenString ?? "—"
    }

    private var headroomDetail: String {
        guard let headroom = snapshot.headroom, headroom.isAvailable else {
            return "Headroom source unavailable"
        }
        return "\(headroom.savingsPercent.compactPercentString) \(headroom.trackedPeriodLabel.lowercased()) savings"
    }

    private func dataRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value).monospacedDigit()
        }.font(.system(size: 11))
    }

    private var comparisonText: String? {
        guard !selection.usesCustomDates, selection.period == .sevenDays, let delta = snapshot.last7DaysDeltaPercent else {
            return nil
        }
        return "\(delta >= 0 ? "+" : "")\(delta.formatted(.percent.precision(.fractionLength(0)))) vs prior"
    }

    private var xAxisDates: [Date] {
        let dates = chartPoints.map(\.date)
        if chartPeriod == .lifetime {
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
        switch chartPeriod {
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
        return grouped(points, period: period, calendar: calendar)
    }

    static func points(from days: [AccountUsageDay], period: UsagePeriod, calendar: Calendar = .current) -> [AnalysisChartPoint] {
        grouped(days.map { AnalysisChartPoint(date: $0.date, value: Double($0.tokens)) }, period: period, calendar: calendar)
    }

    private static func grouped(_ points: [AnalysisChartPoint], period: UsagePeriod, calendar: Calendar) -> [AnalysisChartPoint] {
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
