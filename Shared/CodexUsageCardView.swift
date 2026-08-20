import Foundation
import SwiftUI

enum CodexUsageCardSize: String, CaseIterable, Identifiable {
    case small
    case medium
    case large

    var id: String { rawValue }

    var widgetSettingsSize: CodexUsageWidgetSize {
        switch self {
        case .small: .small
        case .medium: .medium
        case .large: .large
        }
    }

    fileprivate var contentPadding: CGFloat {
        switch self {
        case .small, .medium, .large: 16
        }
    }
}

/// V1 compatibility preview. V2 widget families use semantic content and
/// `CodexWidgetStyledContainer`, while existing saved previews keep this path.
struct CodexUsageCardPreview: View {
    @Environment(\.colorScheme) private var colorScheme

    var snapshot: CodexUsageSnapshot
    var settings: CodexUsageWidgetSettings
    var size: CodexUsageCardSize

    var body: some View {
        ZStack {
            CodexUsageCardBackground(dark: dark, theme: settings.theme)
            CodexUsageCardView(
                snapshot: snapshot,
                settings: settings,
                size: size,
                monochrome: settings.theme == .monochrome,
                dark: dark
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(palette.separator, lineWidth: 1)
        }
    }

    private var dark: Bool {
        switch settings.theme {
        case .crimson, .classicRed, .darkGlass: true
        case .frostedWhite: false
        case .monochrome: colorScheme == .dark
        }
    }

    private var palette: CodexUsageCardPalette {
        CodexUsageCardPalette(dark: dark, monochrome: settings.theme == .monochrome, theme: settings.theme)
    }
}

struct CodexUsageCardBackground: View {
    var dark: Bool
    var theme: WidgetTheme

    var body: some View {
        if theme == .crimson || theme == .classicRed {
            LinearGradient(
                colors: theme == .classicRed
                    ? [Color(red: 0.065, green: 0.058, blue: 0.062), Color(red: 0.018, green: 0.018, blue: 0.022)]
                    : [Color(red: 0.025, green: 0.25, blue: 0.28), Color(red: 0.015, green: 0.08, blue: 0.13)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            dark
                ? Color(red: 0.075, green: 0.082, blue: 0.105)
                : Color(red: 0.965, green: 0.972, blue: 0.982)
        }
    }
}

struct CodexUsageCardView: View {
    var snapshot: CodexUsageSnapshot
    var settings: CodexUsageWidgetSettings
    var size: CodexUsageCardSize
    var monochrome: Bool
    var dark: Bool

    var body: some View {
        Group {
            switch size {
            case .small:
                CodexUsageSmallCard(snapshot: snapshot, settings: settings, palette: palette)
            case .medium:
                CodexUsageMediumCard(snapshot: snapshot, settings: settings, palette: palette)
            case .large:
                CodexUsageLargeCard(snapshot: snapshot, settings: settings, palette: palette)
            }
        }
        .padding(size.contentPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .foregroundStyle(palette.primary)
    }

    private var palette: CodexUsageCardPalette {
        CodexUsageCardPalette(dark: dark, monochrome: monochrome || settings.theme == .monochrome, theme: settings.theme)
    }
}

private struct CodexUsageCardPalette {
    var dark: Bool
    var monochrome: Bool
    var theme: WidgetTheme

    var primary: Color { dark ? .white : .black }
    var secondary: Color { primary.opacity(dark ? 0.72 : 0.66) }
    var tertiary: Color { primary.opacity(dark ? 0.52 : 0.48) }
    var accent: Color {
        if monochrome { return primary }
        if theme == .crimson { return Color(red: 0.12, green: 0.82, blue: 0.79) }
        if theme == .classicRed { return Color(red: 1, green: 0.18, blue: 0.23) }
        return Color.accentColor
    }
    var historicalBar: Color { primary.opacity(dark ? 0.30 : 0.22) }
    var track: Color { primary.opacity(dark ? 0.11 : 0.08) }
    var separator: Color { primary.opacity(dark ? 0.14 : 0.11) }
    var iconFill: Color { accent.opacity(dark ? 0.18 : 0.12) }
}

private struct CodexUsageSmallCard: View {
    var snapshot: CodexUsageSnapshot
    var settings: CodexUsageWidgetSettings
    var palette: CodexUsageCardPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CodexUsageCardHeader(snapshot: snapshot, size: .small, palette: palette)

            Spacer(minLength: 10)

            CodexUsageHeroMetric(
                value: settings.primaryMetric.displayValue(in: snapshot),
                label: settings.primaryMetric.shortLabel,
                valueSize: 34,
                labelSize: 11,
                palette: palette
            )

            Spacer(minLength: 8)

            CodexUsageSmallSecondaryCue(snapshot: snapshot, settings: settings, palette: palette)
        }
    }
}

private struct CodexUsageMediumCard: View {
    var snapshot: CodexUsageSnapshot
    var settings: CodexUsageWidgetSettings
    var palette: CodexUsageCardPalette

    private var showsStats: Bool {
        settings.showsStats
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CodexUsageCardHeader(snapshot: snapshot, size: .medium, palette: palette)

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    CodexUsageHeroMetric(
                        value: settings.primaryMetric.displayValue(in: snapshot),
                        label: settings.primaryMetric.shortLabel,
                        valueSize: 30,
                        labelSize: 11,
                        palette: palette
                    )
                    CodexUsageCostInline(snapshot: snapshot, palette: palette)
                }
                .frame(width: 116, alignment: .leading)

                CodexUsageDayBarChart(
                    days: snapshot.chartDays(count: 7, maxVisible: 7),
                    metric: settings.chartMetric,
                    periodDays: 7,
                    showsTitle: true,
                    palette: palette
                )
                .frame(maxWidth: .infinity)
                .frame(height: 58)
            }

            if showsStats {
                Divider().overlay(palette.separator)
                CodexUsageStatRow(
                    snapshot: snapshot,
                    settings: settings,
                    limit: 3,
                    palette: palette
                )
            }
        }
    }
}

private struct CodexUsageLargeCard: View {
    var snapshot: CodexUsageSnapshot
    var settings: CodexUsageWidgetSettings
    var palette: CodexUsageCardPalette

    private var showsStats: Bool {
        settings.showsStats
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            CodexUsageCardHeader(snapshot: snapshot, size: .large, palette: palette)

            HStack(alignment: .top, spacing: 16) {
                CodexUsageHeroMetric(
                value: settings.primaryMetric.displayValue(in: snapshot),
                    label: settings.primaryMetric.shortLabel,
                    valueSize: 42,
                    labelSize: 12,
                    palette: palette
                )

                Spacer(minLength: 0)

                CodexUsageCostSummary(snapshot: snapshot, settings: settings, palette: palette)
                    .frame(width: 112, alignment: .trailing)
            }

            CodexUsageDayBarChart(
                days: snapshot.chartDays(count: 14, maxVisible: 14),
                metric: settings.chartMetric,
                periodDays: 14,
                showsTitle: true,
                palette: palette
            )
            .frame(height: showsStats ? 108 : 138)

            if showsStats {
                Divider().overlay(palette.separator)
                CodexUsageStatGrid(snapshot: snapshot, settings: settings, palette: palette)
            }
        }
    }
}

private struct CodexUsageCardHeader: View {
    var snapshot: CodexUsageSnapshot
    var size: CodexUsageCardSize
    var palette: CodexUsageCardPalette

    private var updatedAt: Date? {
        snapshot.generatedAt ?? snapshot.lastUpdated ?? snapshot.headroom?.lastUpdated
    }

    private var isFresh: Bool {
        guard let updatedAt else { return false }
        return Date().timeIntervalSince(updatedAt) < 5 * 60
    }

    var body: some View {
        HStack(spacing: 6) {
            Text("Codex")
                .font(.system(size: size == .large ? 12 : 11, weight: .semibold))
                .foregroundStyle(palette.primary)

            Spacer(minLength: 0)

            if size == .small {
                Circle()
                    .fill(isFresh ? palette.accent : palette.tertiary)
                    .frame(width: 6, height: 6)
                    .accessibilityLabel(Text(isFresh ? "Usage data is current" : "Usage data may be stale"))
            } else if let updatedAt {
                Text(freshnessText(for: updatedAt))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(palette.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .accessibilityLabel(Text("Updated"))
                    .accessibilityValue(Text(updatedAt.formatted(date: .abbreviated, time: .shortened)))
            } else {
                Text("Local")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(palette.secondary)
            }
        }
        .frame(height: size == .large ? 20 : 18)
    }

    private func freshnessText(for date: Date) -> String {
        let seconds = max(0, Date().timeIntervalSince(date))
        if seconds < 60 { return "Now" }
        if seconds < 60 * 60 { return "\(Int(seconds / 60))m" }
        if seconds < 24 * 60 * 60 { return "\(Int(seconds / 3600))h" }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
}

private struct CodexUsageHeroMetric: View {
    var value: String
    var label: String
    var valueSize: CGFloat
    var labelSize: CGFloat
    var palette: CodexUsageCardPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: valueSize, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.48)
            Text(label)
                .font(.system(size: labelSize, weight: .semibold))
                .foregroundStyle(palette.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text(value))
    }
}

private struct CodexUsageSmallSecondaryCue: View {
    var snapshot: CodexUsageSnapshot
    var settings: CodexUsageWidgetSettings
    var palette: CodexUsageCardPalette

    private var label: String {
        if settings.primaryMetric != .estimatedCost, snapshot.estimatedCostUSD > 0 {
            return "\(ModelPricingCatalog.displayName(for: snapshot.currentModel)) · \(snapshot.estimatedCostUSD.compactCurrencyString) est."
        }

        if let headroom = snapshot.headroom, headroom.isAvailable {
            return "Headroom: \(headroom.lifetimeTokensSaved.compactTokenString) tokens saved"
        }

        let total = snapshot.last7DaysUsage.total.compactTokenString
        if let delta = snapshot.last7DaysDeltaPercent {
            return "7d \(total) · \(delta.compactSignedPercent)"
        }
        return "7d \(total)"
    }

    var body: some View {
        Text(label)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(palette.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.66)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Secondary usage summary"))
        .accessibilityValue(Text(label))
    }
}

private struct CodexUsageCostInline: View {
    var snapshot: CodexUsageSnapshot
    var palette: CodexUsageCardPalette

    private var text: String {
        let model = ModelPricingCatalog.displayName(for: snapshot.currentModel)
        return "\(model) · \(snapshot.estimatedCostUSD.compactCurrencyString) est."
    }

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(palette.accent)
                .frame(width: 5, height: 5)
                .accessibilityHidden(true)
            Text(text)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(palette.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Model and API-equivalent estimate"))
        .accessibilityValue(Text(text))
    }
}

private struct CodexUsageCostSummary: View {
    var snapshot: CodexUsageSnapshot
    var settings: CodexUsageWidgetSettings
    var palette: CodexUsageCardPalette

    private var value: String {
        settings.primaryMetric == .estimatedCost
            ? snapshot.todayEstimatedCostUSD.compactCurrencyString
            : snapshot.estimatedCostUSD.compactCurrencyString
    }

    private var label: String {
        settings.primaryMetric == .estimatedCost ? "Today estimate" : "Estimated API cost"
    }

    private var detail: String {
        ModelPricingCatalog.displayName(for: snapshot.currentModel)
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.68)
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(palette.secondary)
                .lineLimit(1)
            Text(detail)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(palette.accent)
                .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text("\(value), \(detail)"))
    }
}

private struct CodexUsageDayBarChart: View {
    var days: [DailyUsage]
    var metric: ChartMetric
    var periodDays: Int
    var showsTitle: Bool
    var palette: CodexUsageCardPalette

    private var maxValue: Int {
        max(days.map(metric.value).max() ?? 0, 1)
    }

    private var latestDayID: Date? {
        days.last?.id
    }

    private var accessibilitySummary: String {
        guard !days.isEmpty else { return "No activity" }
        return days.map { day in
            let date = day.date.formatted(.dateTime.weekday(.abbreviated))
            return "\(date) \(metric.value(in: day).formatted())"
        }.joined(separator: ", ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: showsTitle ? 7 : 0) {
            if showsTitle {
                HStack(spacing: 8) {
                    Text("\(periodDays) days")
                    Spacer(minLength: 0)
                    Text("Peak \(peakLabel)")
                }
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(palette.secondary)
                .lineLimit(1)
            }

            GeometryReader { proxy in
                HStack(alignment: .bottom, spacing: days.count > 7 ? 4 : 7) {
                    ForEach(days) { day in
                        VStack(spacing: 4) {
                            GeometryReader { barProxy in
                                ZStack(alignment: .bottom) {
                                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                                        .fill(palette.track)
                                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                                        .fill(day.id == latestDayID ? palette.accent : palette.historicalBar)
                                        .frame(height: barHeight(for: metric.value(in: day), available: barProxy.size.height))
                                }
                            }
                            Text(day.singleCharacterWeekday)
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(day.id == latestDayID ? palette.primary : palette.tertiary)
                                .frame(height: 9)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Last \(periodDays) days, \(metric.shortLabel)"))
        .accessibilityValue(Text(accessibilitySummary))
    }

    private func barHeight(for value: Int, available: CGFloat) -> CGFloat {
        guard value > 0 else { return 0 }
        return max(3, available * CGFloat(value) / CGFloat(maxValue))
    }

    private var peakLabel: String {
        switch metric {
        case .estimatedCost:
            return (Double(maxValue) / 1_000_000).compactCurrencyString
        case .sessions, .turns:
            return maxValue.formatted()
        default:
            return maxValue.compactTokenString
        }
    }
}

private struct CodexUsageStatRow: View {
    var snapshot: CodexUsageSnapshot
    var settings: CodexUsageWidgetSettings
    var limit: Int
    var palette: CodexUsageCardPalette

    var body: some View {
        let metrics = settings.visibleStatSlots(excluding: settings.primaryMetric, limit: limit)
        HStack(spacing: 0) {
            ForEach(Array(metrics.enumerated()), id: \.offset) { index, metric in
                if index > 0 {
                    Divider().overlay(palette.separator)
                }
                CodexUsageStatCell(
                    metric: metric,
                    snapshot: snapshot,
                    settings: settings,
                    valueSize: 13,
                    labelSize: 10,
                    palette: palette
                )
                .padding(.horizontal, index == 0 ? 0 : 8)
            }
        }
    }
}

private struct CodexUsageStatGrid: View {
    var snapshot: CodexUsageSnapshot
    var settings: CodexUsageWidgetSettings
    var palette: CodexUsageCardPalette

    var body: some View {
        let metrics = settings.visibleStatSlots(excluding: settings.primaryMetric, limit: 4)
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                gridCell(metrics[0])
                Divider().overlay(palette.separator)
                gridCell(metrics[1])
            }
            Divider().overlay(palette.separator)
            HStack(spacing: 0) {
                gridCell(metrics[2])
                Divider().overlay(palette.separator)
                gridCell(metrics[3])
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func gridCell(_ metric: StatMetric) -> some View {
        CodexUsageStatCell(
            metric: metric,
            snapshot: snapshot,
            settings: settings,
            valueSize: 14,
            labelSize: 10,
            palette: palette
        )
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }
}

private struct CodexUsageStatCell: View {
    var metric: StatMetric
    var snapshot: CodexUsageSnapshot
    var settings: CodexUsageWidgetSettings
    var valueSize: CGFloat
    var labelSize: CGFloat
    var palette: CodexUsageCardPalette

    private var value: String {
        metric.value(in: snapshot, settings: settings)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.system(size: valueSize, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.58)
            Text(metric.label)
                .font(.system(size: labelSize, weight: .semibold))
                .foregroundStyle(palette.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.64)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(metric.label))
        .accessibilityValue(Text(value))
    }
}

private extension DailyUsage {
    var singleCharacterWeekday: String {
        let calendar = Calendar.current
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let index = calendar.component(.weekday, from: date) - 1
        guard symbols.indices.contains(index), let character = symbols[index].first else { return "" }
        return String(character).uppercased(with: Locale.current)
    }
}

private extension Double {
    var compactSignedPercent: String {
        let percent = self * 100
        let sign = percent >= 0 ? "+" : ""
        return "\(sign)\(Int(percent.rounded()))%"
    }
}
