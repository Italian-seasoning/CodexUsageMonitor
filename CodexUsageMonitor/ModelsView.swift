import Charts
import SwiftUI

struct ModelsView: View {
    var snapshot: CodexUsageSnapshot
    var health: SnapshotHealth

    @State private var period = UsagePeriod.sevenDays
    @State private var comparison = Comparison.tokens

    private enum Comparison: String, CaseIterable, Identifiable {
        case tokens = "Tokens"
        case apiCost = "API cost"

        var id: String { rawValue }
    }

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

    private var totalCost: Double {
        models.reduce(0) { $0 + $1.estimatedCostUSD }
    }

    private var comparedModels: [ModelUsage] {
        comparison == .tokens ? models : models.sorted { $0.estimatedCostUSD > $1.estimatedCostUSD }
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
                    InspectorSection(title: "Astra & Reserve", subtitle: "Local model usage · Standard API-equivalent estimates") {
                        Text("Reserve uses GPT-5.6 Luna. Luna tokens appear under their recorded model below; they do not measure your remaining Reserve allowance.")
                            .font(.system(size: AppTypeScale.caption))
                            .foregroundStyle(.secondary)
                        Text("Per 1M tokens · Astra: $10 input / $1 cached / $50 output. Long-context rates apply above 272K input tokens per request. API-equivalent estimates exclude cache-write and service-tier premiums.")
                            .font(.system(size: AppTypeScale.caption))
                            .foregroundStyle(.secondary)
                        Link("OpenAI pricing · checked September 26, 2026", destination: URL(string: ModelPricingCatalog.sourceURL)!)
                            .font(.system(size: AppTypeScale.caption))
                    }
                    InspectorSection(
                        title: "Model comparison",
                        subtitle: "\(period.title) attribution from local session logs"
                    ) {
                        Picker("Compare by", selection: $comparison) {
                            ForEach(Comparison.allCases) { option in
                                Text(option.rawValue).tag(option)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 220)
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
                                    Text(ModelPricingCatalog.displayName(for: comparedModels.first?.model))
                                        .font(.system(size: AppTypeScale.value, weight: .semibold, design: .rounded))
                                    Text("\(share(comparedModels[0])) of selected \(comparison == .tokens ? "tokens" : "API cost")")
                                        .font(.system(size: AppTypeScale.caption, weight: .medium))
                                        .foregroundStyle(AppPalette.muted)
                                }
                                Spacer()
                                modelValue(comparison == .tokens ? totalTokens.compactTokenString : totalCost.compactCurrencyString, label: comparison == .tokens ? "total tokens" : "API est.")
                            }

                            Chart(Array(comparedModels.prefix(6))) { model in
                                BarMark(
                                    x: .value("Scale", comparison == .tokens ? Double(totalTokens) : totalCost),
                                    y: .value("Model", ModelPricingCatalog.displayName(for: model.model)),
                                    height: .fixed(16),
                                    stacking: .unstacked
                                )
                                .foregroundStyle(AppPalette.chartTrack)
                                .cornerRadius(5)

                                BarMark(
                                    x: .value(comparison.rawValue, comparison == .tokens ? Double(model.usage.total) : model.estimatedCostUSD),
                                    y: .value("Model", ModelPricingCatalog.displayName(for: model.model)),
                                    height: .fixed(16),
                                    stacking: .unstacked
                                )
                                .foregroundStyle(model.id == comparedModels.first?.id ? AppPalette.accent : AppPalette.chartMuted)
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
                            .accessibilityLabel("Model \(comparison.rawValue.lowercased()) share for \(period.title)")
                        }
                    }

                    InspectorSection(
                        title: "Attributed models",
                        subtitle: "Tokens, share, requests, and recorded API-equivalent estimate"
                    ) {
                        ForEach(Array(comparedModels.enumerated()), id: \.element.id) { index, model in
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

                            if model.id != comparedModels.last?.id {
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
        if comparison == .apiCost {
            guard totalCost > 0 else { return "0%" }
            return (model.estimatedCostUSD / totalCost)
                .formatted(.percent.precision(.fractionLength(0)))
        }
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
