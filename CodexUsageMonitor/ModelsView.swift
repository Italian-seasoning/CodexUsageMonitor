import Charts
import SwiftUI

struct ModelsView: View {
    var snapshot: CodexUsageSnapshot
    var health: SnapshotHealth

    @State private var period = UsagePeriod.sevenDays

    private var models: [ModelUsage] {
        let dates = Set(
            snapshot.summary(for: period).days.map {
                Calendar.current.startOfDay(for: $0.date)
            }
        )
        var result: [String: ModelUsage] = [:]
        for day in snapshot.dailyModelUsage where dates.contains(Calendar.current.startOfDay(for: day.date)) {
            for model in day.models {
                var item = result[model.model]
                    ?? ModelUsage(model: model.model, usage: .zero, turns: 0, estimatedCostUSD: 0)
                item.usage.add(model.usage)
                item.turns += model.turns
                item.estimatedCostUSD += model.estimatedCostUSD
                result[model.model] = item
            }
        }
        if period == .lifetime && result.isEmpty {
            return snapshot.modelUsage ?? []
        }
        return result.values.sorted { $0.usage.total > $1.usage.total }
    }

    private var totalTokens: Int {
        models.reduce(0) { $0 + $1.usage.total }
    }

    var body: some View {
        VStack(spacing: 0) {
            AppSectionHeader(section: .models) {
                Picker("Period", selection: $period) {
                    ForEach(UsagePeriod.allCases) { period in
                        Text(period.title).tag(period)
                    }
                }
                .labelsHidden()
                .frame(width: 130)
            }

            ScrollView {
                VStack(spacing: 10) {
                    InspectorSection(
                        title: "Model share",
                        subtitle: "\(period.title) attribution from local session logs"
                    ) {
                        if models.isEmpty {
                            ContentUnavailableView(
                                "No attributed models",
                                systemImage: "square.stack.3d.up.slash",
                                description: Text(health.detail)
                            )
                            .frame(height: 220)
                        } else {
                            HStack(alignment: .firstTextBaseline) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(ModelPricingCatalog.displayName(for: models.first?.model))
                                        .font(.system(size: AppTypeScale.value, weight: .semibold, design: .rounded))
                                    Text("\(share(models[0])) of selected usage")
                                        .font(.system(size: AppTypeScale.caption, weight: .medium))
                                        .foregroundStyle(AppPalette.muted)
                                }
                                Spacer()
                                modelValue(totalTokens.compactTokenString, label: "total tokens")
                            }

                            Chart(Array(models.prefix(6))) { model in
                                BarMark(
                                    x: .value("Scale", totalTokens),
                                    y: .value("Model", ModelPricingCatalog.displayName(for: model.model)),
                                    height: .fixed(16),
                                    stacking: .unstacked
                                )
                                .foregroundStyle(AppPalette.chartTrack)
                                .cornerRadius(5)

                                BarMark(
                                    x: .value("Tokens", model.usage.total),
                                    y: .value("Model", ModelPricingCatalog.displayName(for: model.model)),
                                    height: .fixed(16),
                                    stacking: .unstacked
                                )
                                .foregroundStyle(model.id == models.first?.id ? AppPalette.accent : AppPalette.chartMuted)
                                .cornerRadius(5)
                                .annotation(position: .trailing, spacing: 8) {
                                    Text(share(model))
                                        .font(.system(size: AppTypeScale.caption, weight: .semibold))
                                        .foregroundStyle(AppPalette.muted)
                                }
                            }
                            .chartXAxis(.hidden)
                            .chartYAxis {
                                AxisMarks(position: .leading) {
                                    AxisValueLabel()
                                        .foregroundStyle(AppPalette.muted)
                                }
                            }
                            .chartPlotStyle { plot in
                                plot.padding(.trailing, 42)
                            }
                            .frame(height: max(132, CGFloat(min(models.count, 6)) * 38))
                            .accessibilityLabel("Model token share for \(period.title)")
                        }
                    }

                    InspectorSection(
                        title: "Attributed models",
                        subtitle: "Tokens, share, requests, and recorded API-equivalent estimate"
                    ) {
                        ForEach(Array(models.enumerated()), id: \.element.id) { index, model in
                            HStack(spacing: 12) {
                                Text("\(index + 1)")
                                    .font(.system(size: AppTypeScale.caption, weight: .semibold))
                                    .foregroundStyle(AppPalette.muted)
                                    .frame(width: 26)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(ModelPricingCatalog.displayName(for: model.model))
                                        .font(.system(size: AppTypeScale.body, weight: .semibold))
                                    Text(model.model)
                                        .font(.system(size: AppTypeScale.caption))
                                        .foregroundStyle(.tertiary)
                                }

                                Spacer()
                                modelValue(model.usage.total.compactTokenString, label: "tokens")
                                modelValue(share(model), label: "share")
                                modelValue(model.turns.formatted(), label: "requests")
                                modelValue(model.estimatedCostUSD.compactCurrencyString, label: "API est.")
                            }
                            .padding(.vertical, 7)

                            if model.id != models.last?.id {
                                Divider().overlay(AppPalette.divider)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
        }
    }

    private func share(_ model: ModelUsage) -> String {
        guard totalTokens > 0 else { return "0%" }
        return (Double(model.usage.total) / Double(totalTokens))
            .formatted(.percent.precision(.fractionLength(0)))
    }

    private func modelValue(_ value: String, label: String) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(value)
                .font(.system(size: AppTypeScale.body, weight: .semibold, design: .rounded))
                .monospacedDigit()
            Text(label)
                .font(.system(size: AppTypeScale.caption))
                .foregroundStyle(.secondary)
        }
        .frame(width: 76, alignment: .trailing)
    }
}
