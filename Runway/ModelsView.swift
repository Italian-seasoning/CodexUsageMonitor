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
            return (snapshot.modelUsage ?? []).sorted { $0.usage.total > $1.usage.total }
        }
        return result.values.sorted { $0.usage.total > $1.usage.total }
    }

    private var totalTokens: Int {
        models.reduce(0) { $0 + $1.usage.total }
    }

    private var totalCost: Double {
        models.compactMap(\.availableCostEstimateUSD).reduce(0, +)
    }

    private var totalCostText: String {
        models.contains { $0.availableCostEstimateUSD != nil } ? totalCost.compactCurrencyString : "—"
    }

    private var comparedModels: [ModelUsage] {
        comparison == .tokens ? models : models.filter { $0.availableCostEstimateUSD != nil }
            .sorted { $0.estimatedCostUSD > $1.estimatedCostUSD }
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

            MagneticScrollView { height in
                    InspectorSection(
                        title: "Model comparison",
                        subtitle: "\(period.title) · \(comparison == .tokens ? totalTokens.compactTokenString + " tokens" : totalCostText + " API equivalent")"
                    ) {
                        Picker("Compare by", selection: $comparison) {
                            ForEach(Comparison.allCases) { option in
                                Text(option.rawValue).tag(option)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 220)
                        if comparedModels.isEmpty {
                            ContentUnavailableView(
                                comparison == .tokens ? "No attributed models" : "No priced models",
                                systemImage: "square.stack.3d.up.slash",
                                description: Text(health.detail)
                            )
                            .frame(height: max(80, height - 100))
                        } else {
                            VStack(spacing: 10) {
                                ForEach(Array(comparedModels.prefix(height < 350 ? 4 : 6))) { model in
                                    VStack(spacing: 5) {
                                        HStack(spacing: 8) {
                                            Text(ModelPricingCatalog.displayName(for: model.model))
                                                .lineLimit(1)
                                                .help(ModelPricingCatalog.displayName(for: model.model))
                                            Spacer(minLength: 0)
                                            Text(share(model)).monospacedDigit().fixedSize()
                                        }
                                        .font(.system(size: AppTypeScale.label, weight: model.id == comparedModels.first?.id ? .semibold : .medium))
                                        ProgressView(
                                            value: comparison == .tokens ? Double(model.usage.total) : model.estimatedCostUSD,
                                            total: comparison == .tokens ? Double(max(1, totalTokens)) : max(totalCost, Double.leastNonzeroMagnitude)
                                        )
                                        .tint(AppPalette.accent)
                                        .accessibilityHidden(true)
                                    }
                                    .frame(maxHeight: .infinity)
                                    .accessibilityElement(children: .combine)
                                    .accessibilityLabel("\(ModelPricingCatalog.displayName(for: model.model)), \(share(model)) of selected \(comparison == .tokens ? "tokens" : "API cost")")
                                }
                            }
                            .frame(height: max(100, height - 125))
                            .accessibilityElement(children: .contain)
                            .accessibilityLabel("Model \(comparison.rawValue.lowercased()) share for \(period.title)")
                        }
                    }
            } details: {
                VStack(spacing: 10) {
                    InspectorSection(
                        title: "Attributed models",
                        subtitle: "Tokens, share, requests, and recorded API-equivalent estimate"
                    ) {
                        if models.contains(where: { $0.availableCostEstimateUSD == nil }) {
                            Text("Unpriced models have no recorded rate and are excluded from API cost comparisons.")
                                .font(.system(size: AppTypeScale.caption)).foregroundStyle(.secondary)
                        }
                        ForEach(Array(comparedModels.enumerated()), id: \.element.id) { index, model in
                            VStack(spacing: 8) {
                                HStack {
                                    Text("\(index + 1). \(ModelPricingCatalog.displayName(for: model.model))")
                                        .font(.system(size: AppTypeScale.body, weight: .semibold)).lineLimit(1)
                                    Spacer(minLength: 6)
                                    Text(model.usage.total.compactTokenString).monospacedDigit()
                                }
                                HStack {
                                    modelValue(share(model), label: "share")
                                    Spacer(minLength: 0)
                                    modelValue(model.turns.formatted(), label: "requests")
                                    Spacer(minLength: 0)
                                    modelValue(model.availableCostEstimateUSD?.compactCurrencyString ?? "Unpriced", label: "API est.")
                                }
                            }
                            .padding(.vertical, 7)

                            if model.id != comparedModels.last?.id {
                                Divider().overlay(AppPalette.divider)
                            }
                        }
                    }
                    DisclosureGroup("Pricing and Reserve notes") {
                        Text("Reserve uses GPT-5.6 Luna. Luna tokens appear under their recorded model below; they do not measure your remaining Reserve allowance.")
                            .font(.system(size: AppTypeScale.caption))
                            .foregroundStyle(.secondary)
                        Text("Standard API rates per 1M tokens · GPT-6.1 Sol: $2 input / $0.10 cached / $10 output; above 272K input: $4 / $0.20 / $15. Astra: $10 input / $1 cached / $50 output. API-equivalent estimates exclude cache-write and service-tier premiums and do not represent subscription charges.")
                            .font(.system(size: AppTypeScale.caption))
                            .foregroundStyle(.secondary)
                        Link("OpenAI pricing", destination: URL(string: ModelPricingCatalog.sourceURL)!)
                            .font(.system(size: AppTypeScale.caption))
                    }
                }
            }
        }
    }

    private func share(_ model: ModelUsage) -> String {
        if comparison == .apiCost {
            guard let estimate = model.availableCostEstimateUSD else { return "—" }
            guard totalCost > 0 else { return "0%" }
            return (estimate / totalCost)
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
