import SwiftUI

enum WidgetTypeScale {
    static let caption: CGFloat = 11
    static let label: CGFloat = 12
    static let body: CGFloat = 13
    static let value: CGFloat = 15
    static let heroCompact: CGFloat = 32
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
}

struct WidgetHero: View {
    var content: WidgetSemanticContent
    var palette: WidgetStylePalette
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 2 : 4) {
            Text(content.heroValue)
                .font(.system(
                    size: compact ? WidgetTypeScale.heroCompact : WidgetTypeScale.hero,
                    weight: .semibold,
                    design: .rounded
                ))
                .monospacedDigit()
                .foregroundStyle(palette.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(content.heroLabel)
                .font(.system(size: compact ? WidgetTypeScale.label : WidgetTypeScale.body, weight: .medium))
                .foregroundStyle(palette.secondary)
                .lineLimit(2)
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
    }
}

struct WidgetMiniBars: View {
    var chart: WidgetChartContent
    var palette: WidgetStylePalette

    var body: some View {
        GeometryReader { geometry in
            let maxValue = max(chart.points.map(\.value).max() ?? 0, 1)
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(chart.points) { point in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(point.id == chart.points.last?.id ? palette.accent : palette.track)
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

struct WidgetGaugeRing: View {
    var progress: Double
    var palette: WidgetStylePalette

    var body: some View {
        ZStack {
            Circle()
                .stroke(palette.track, style: StrokeStyle(lineWidth: 7, lineCap: .round))
            Circle()
                .trim(from: 0, to: min(1, max(0, progress)))
                .stroke(palette.accent, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(progress, format: .percent.precision(.fractionLength(0)))
                .font(.system(size: WidgetTypeScale.value, weight: .bold, design: .rounded))
                .monospacedDigit()
        }
        .accessibilityElement()
        .accessibilityLabel("\(progress.formatted(.percent.precision(.fractionLength(0)))) remaining")
    }
}

struct WidgetValueGrid: View {
    var values: [WidgetLabeledValue]
    var palette: WidgetStylePalette
    var columns = 2

    var body: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: columns),
            alignment: .leading,
            spacing: 8
        ) {
            ForEach(Array(values.enumerated()), id: \.offset) { _, item in
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.value)
                        .font(.system(size: WidgetTypeScale.value, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Text(item.label)
                        .font(.system(size: WidgetTypeScale.caption, weight: .medium))
                        .foregroundStyle(palette.secondary)
                        .lineLimit(1)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}
