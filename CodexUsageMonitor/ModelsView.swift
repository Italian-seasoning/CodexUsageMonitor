import Charts
import SwiftUI

struct ModelsView: View {
    var snapshot: CodexUsageSnapshot
    var health: SnapshotHealth
    @State private var period: UsagePeriod = .sevenDays

    private var models: [ModelUsage] {
        let dates = Set(snapshot.summary(for: period).days.map { Calendar.current.startOfDay(for: $0.date) })
        var result: [String: ModelUsage] = [:]
        for day in snapshot.dailyModelUsage where dates.contains(Calendar.current.startOfDay(for: day.date)) {
            for model in day.models {
                var item = result[model.model] ?? ModelUsage(model: model.model, usage: .zero, turns: 0, estimatedCostUSD: 0)
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
                    ForEach(UsagePeriod.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .frame(width: 130)
            }

            ScrollView {
                VStack(spacing: 10) {
                    InspectorSection(title: "Model share", subtitle: "\(period.title) attribution from local session logs") {
                        if models.isEmpty {
                            ContentUnavailableView(
                                "No model attribution",
                                systemImage: "square.stack.3d.up.slash",
                                description: Text(health.detail)
                            )
                            .frame(minHeight: 220)
                        } else {
                            HStack(alignment: .firstTextBaseline) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(ModelPricingCatalog.displayName(for: models.first?.model))
                                        .font(.system(size: AppTypeScale.value, weight: .semibold, design: .rounded))
                                    Text("\(share(models[0])) of attributed usage")
                                        .font(.system(size: AppTypeScale.caption, weight: .medium))
                                        .foregroundStyle(AppPalette.muted)
                                }
                                Spacer()
                                modelValue(totalTokens.compactTokenString, label: "total tokens")
                            }

                            Chart(Array(models.prefix(6))) { model in
                                BarMark(
                                    x: .value("Tokens", model.usage.total),
                                    y: .value("Model", ModelPricingCatalog.displayName(for: model.model))
                                )
                                .foregroundStyle(AppPalette.accent.gradient)
                                .cornerRadius(4)
                            }
                            .chartXAxis {
                                AxisMarks(position: .bottom) {
                                    AxisGridLine().foregroundStyle(Color.white.opacity(0.07))
                                    AxisValueLabel()
                                }
                            }
                            .frame(height: max(120, CGFloat(min(models.count, 6)) * 32))
                            .accessibilityLabel("Model token share for \(period.title)")
                        }
                    }

                    InspectorSection(title: "Attributed models", subtitle: "Tokens, share, requests, and recorded API-equivalent estimate") {
                        ForEach(Array(models.enumerated()), id: \.element.id) { index, model in
                            HStack(spacing: 12) {
                                Text("#\(index + 1)")
                                    .font(.system(size: AppTypeScale.caption, weight: .semibold, design: .rounded))
                                    .foregroundStyle(AppPalette.muted)
                                    .frame(width: 26, alignment: .leading)
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
                            if model.id != models.last?.id { Divider().overlay(AppPalette.divider) }
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
            Text(value).font(.system(size: AppTypeScale.body, weight: .semibold, design: .rounded)).monospacedDigit()
            Text(label).font(.system(size: AppTypeScale.caption)).foregroundStyle(.secondary)
        }
        .frame(width: 76, alignment: .trailing)
    }
}
