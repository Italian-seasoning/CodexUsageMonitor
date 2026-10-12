import SwiftUI
import Charts

enum WidgetTypeScale {
    static let caption: CGFloat = 11
    static let label: CGFloat = 12
    static let body: CGFloat = 13
    static let value: CGFloat = 15
    static let heroCompact: CGFloat = 28
    static let hero: CGFloat = 38
}

struct WidgetLabeledValue: Equatable, Sendable {
    var label: String
    var value: String
}

struct WidgetChartPoint: Equatable, Identifiable, Sendable {
    var date: Date
    var value: Double
    var id: Date { date }
}

struct WidgetChartContent: Equatable, Sendable {
    var points: [WidgetChartPoint]
    var accessibilitySummary: String
}

enum WidgetFreshness: Equatable, Sendable {
    case fresh
    case partial
    case stale
    case unavailable
    case permissionBlocked
    case error

    var label: String {
        switch self {
        case .fresh: "Fresh"
        case .partial: "Partial"
        case .stale: "Cached"
        case .unavailable: "Unavailable"
        case .permissionBlocked: "Permission"
        case .error: "Error"
        }
    }

    var symbol: String {
        switch self {
        case .fresh: "checkmark.circle.fill"
        case .partial: "circle.lefthalf.filled"
        case .stale: "clock"
        case .unavailable: "slash.circle"
        case .permissionBlocked: "lock.fill"
        case .error: "exclamationmark.triangle.fill"
        }
    }
}

struct WidgetSemanticContent: Equatable, Sendable {
    var eyebrow: String
    var heroValue: String
    var heroLabel: String
    var secondaryValues: [WidgetLabeledValue]
    var chart: WidgetChartContent?
    var freshness: WidgetFreshness
    var fraction: Double? = nil
}

struct WidgetHero: View {
    var content: WidgetSemanticContent
    var palette: WidgetStylePalette
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 2 : 4) {
            Text(content.heroValue)
                .font(.system(
                    size: content.heroValue.count > 12 ? 20 : compact ? 30 : 40,
                    weight: .semibold,
                    design: .default
                ))
                .tracking(-0.8)
                .monospacedDigit()
                .foregroundStyle(palette.primary)
                .lineLimit(content.heroValue.count > 12 ? 2 : 1)
                .minimumScaleFactor(0.85)
            Text(content.heroLabel)
                .font(.system(size: compact ? WidgetTypeScale.label : WidgetTypeScale.body, weight: .medium))
                .foregroundStyle(palette.secondary)
                .lineLimit(compact ? 1 : 2)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(content.heroLabel), \(content.heroValue)")
    }
}

struct WidgetFreshnessLabel: View {
    var freshness: WidgetFreshness
    var palette: WidgetStylePalette
    var compact = false

    var body: some View {
        Group {
            if compact {
                Image(systemName: freshness.symbol)
                    .accessibilityLabel(freshness.label)
            } else {
                Label(freshness.label, systemImage: freshness.symbol)
                    .labelStyle(.titleAndIcon)
            }
        }
            .font(.system(size: WidgetTypeScale.caption, weight: .semibold))
            .foregroundStyle(freshness == .fresh ? palette.accent : palette.secondary)
            .help(freshness.label)
    }
}

struct WidgetMiniBars: View {
    var chart: WidgetChartContent
    var palette: WidgetStylePalette

    private var displayedPoints: [WidgetChartPoint] {
        guard chart.points.count > 14, let last = chart.points.last else { return chart.points }
        let step = Int(ceil(Double(chart.points.count - 1) / 13))
        return stride(from: 0, to: chart.points.count - 1, by: step).map { chart.points[$0] } + [last]
    }

    var body: some View {
        GeometryReader { geometry in
            let maxValue = max(chart.points.map(\.value).max() ?? 0, 1)
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(displayedPoints) { point in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(point.id == chart.points.last?.id ? palette.accent : palette.accent.opacity(0.32))
                        .frame(
                            maxWidth: chart.points.count == 1 ? 12 : .infinity,
                            minHeight: 3,
                            maxHeight: max(3, geometry.size.height * point.value / maxValue)
                        )
                }
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .accessibilityElement()
        .accessibilityLabel(chart.accessibilitySummary)
    }
}

struct WidgetSparkline: View {
    var chart: WidgetChartContent
    var palette: WidgetStylePalette
    var fixedDomain: ClosedRange<Double>?

    private var domain: ClosedRange<Double> {
        if let fixedDomain { return fixedDomain }
        let minimum = chart.points.map(\.value).min() ?? 0
        let maximum = chart.points.map(\.value).max() ?? 0
        let padding = max(1, (maximum - minimum) * 0.15)
        return max(0, minimum - padding)...max(1, maximum + padding)
    }

    var body: some View {
        Chart(chart.points.sorted { $0.date < $1.date }) { point in
            AreaMark(x: .value("Date", point.date), yStart: .value("Baseline", domain.lowerBound), yEnd: .value("Value", point.value))
                .interpolationMethod(.monotone)
                .foregroundStyle(LinearGradient(colors: [palette.accent.opacity(0.23), palette.accent.opacity(0.01)], startPoint: .top, endPoint: .bottom))
            LineMark(x: .value("Date", point.date), y: .value("Value", point.value))
                .interpolationMethod(.monotone)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .foregroundStyle(palette.accent)
            if chart.points.count == 1 {
                PointMark(x: .value("Date", point.date), y: .value("Value", point.value))
                    .foregroundStyle(palette.accent).symbolSize(16)
            }
        }
        .chartYScale(domain: domain)
        .chartXAxis(.hidden).chartYAxis(.hidden).chartLegend(.hidden)
        .accessibilityElement(children: .ignore).accessibilityLabel(chart.accessibilitySummary)
    }
}

struct WidgetGaugeRing: View {
    var progress: Double?
    var palette: WidgetStylePalette
    var caption = "left"

    private var value: Double? {
        progress.flatMap { $0.isFinite ? min(1, max(0, $0)) : nil }
    }

    var body: some View {
        GeometryReader { geometry in
            let stroke = min(6, max(4, geometry.size.width / 10))
            ZStack {
                Circle().stroke(palette.track, style: StrokeStyle(lineWidth: stroke))
                Circle()
                    .trim(from: 0, to: value ?? 0)
                    .stroke(palette.accent, style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text(value.map { $0.formatted(.percent.precision(.fractionLength(0))) } ?? "—")
                        .font(.system(size: max(12, geometry.size.width * 0.27), weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(palette.primary)
                    if geometry.size.width >= 48 {
                        Text(caption).font(.system(size: 9)).foregroundStyle(palette.secondary)
                    }
                }
            }
            .padding(stroke / 2)
        }
        .accessibilityElement()
        .accessibilityLabel(value.map { "\($0.formatted(.percent.precision(.fractionLength(0)))) \(caption)" } ?? "Allowance unavailable")
    }
}

struct WidgetLimitDial: View {
    var title: String
    var window: RateLimitWindow?
    var palette: WidgetStylePalette
    var diameter: CGFloat = 48
    var now: Date = .now

    private var current: RateLimitWindow? {
        window.flatMap { $0.isCurrent(at: now) ? $0 : nil }
    }

    var body: some View {
        HStack(spacing: 8) {
            WidgetGaugeRing(progress: current.map { $0.remainingPercent / 100 }, palette: palette)
                .frame(width: diameter, height: diameter)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(palette.primary)
                Text(current.map { "Resets \($0.resetText(at: now))" } ?? "Awaiting data")
                    .font(.system(size: 10)).foregroundStyle(palette.secondary)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                    .help(current?.resetsAt.formatted(date: .abbreviated, time: .shortened) ?? "Awaiting current data")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) allowance")
        .accessibilityValue(current.map { "\($0.remainingPercent.compactPercentString) remaining, resets \($0.resetText(at: now))" } ?? "Awaiting current data")
    }
}

/// A quiet allowance summary shared by the workspace and glanceable widgets.
struct WidgetAllowanceMeter: View {
    var title: String
    var window: RateLimitWindow?
    var palette: WidgetStylePalette
    var compact = false
    var now: Date = .now
    var showsConsumption = false
    var consumptionRate: Double? = nil

    private var current: RateLimitWindow? {
        window.flatMap { $0.isCurrent(at: now) ? $0 : nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 5 : 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(palette.secondary)
                Spacer(minLength: 0)
                Text(current.map { "\(Int($0.remainingPercent.rounded()))%" } ?? "—")
                    .font(.system(size: compact ? 15 : 21, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(palette.primary)
            }
            GeometryReader { geometry in
                Capsule().fill(palette.track)
                    .overlay(alignment: .leading) {
                        Capsule().fill(palette.accent)
                            .frame(width: geometry.size.width * CGFloat(min(1, max(0, (current?.remainingPercent ?? 0) / 100))))
                    }
            }.frame(height: 4)
            if !compact {
                Text(current.map { now.timeIntervalSince($0.observedAt) > 180
                    ? "Last read \(Int(now.timeIntervalSince($0.observedAt) / 60))m ago"
                    : "Resets \($0.resetText(at: now))" } ?? "Not reported")
                    .font(.system(size: 10))
                    .foregroundStyle(palette.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if showsConsumption {
                    Text(consumptionRate.map { "≈\($0.formatted(.number.precision(.fractionLength(1))))% / 15 min" } ?? "Rate awaiting samples")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(palette.secondary)
                        .lineLimit(1)
                        .help("Estimated percentage points of allowance consumed per 15 minutes. Requires at least 10 minutes of recent observations within the same reset window.")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) allowance")
        .accessibilityValue((current.map { "\($0.remainingPercent.compactPercentString) remaining, resets \($0.resetText(at: now))" } ?? "Awaiting current data")
            + (showsConsumption ? consumptionRate.map { ", approximately \($0.formatted(.number.precision(.fractionLength(1)))) percentage points consumed per 15 minutes" } ?? ", rate awaiting samples" : ""))
    }
}

struct WidgetDotPlot: View {
    var chart: WidgetChartContent
    var palette: WidgetStylePalette

    var body: some View {
        Chart(chart.points) { point in
            PointMark(x: .value("Date", point.date), y: .value("Value", point.value))
                .foregroundStyle(point.id == chart.points.last?.id ? palette.accent : palette.accent.opacity(0.5))
                .symbolSize(28)
        }
        .chartYScale(domain: 0...max(1, (chart.points.map(\.value).max() ?? 0) * 1.15))
        .chartXAxis(.hidden).chartYAxis(.hidden).chartLegend(.hidden)
        .accessibilityElement(children: .ignore).accessibilityLabel(chart.accessibilitySummary)
    }
}

struct WidgetValueGrid: View {
    var values: [WidgetLabeledValue]
    var palette: WidgetStylePalette
    var columns = 2

    var body: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(minimum: 0), spacing: 12, alignment: .topLeading), count: columns),
            alignment: .leading,
            spacing: 8
        ) {
            ForEach(Array(values.enumerated()), id: \.offset) { _, item in
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.value)
                        .font(.system(size: WidgetTypeScale.value, weight: .semibold))
                        .monospacedDigit()
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                    Text(item.label)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(palette.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
            }
        }
    }
}

struct WidgetInlineValue: View {
    var item: WidgetLabeledValue
    var palette: WidgetStylePalette

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(item.label).font(.system(size: 11)).foregroundStyle(palette.secondary)
            Spacer(minLength: 0)
            Text(item.value).font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit().lineLimit(2).minimumScaleFactor(0.85)
                .multilineTextAlignment(.trailing).foregroundStyle(palette.primary)
        }
        .accessibilityElement(children: .combine)
    }
}
