import Foundation

enum UsagePeriod: String, Codable, CaseIterable, Identifiable, Sendable {
    case today
    case sevenDays
    case month
    case lifetime

    var id: Self { self }
}

enum UsageMeasure: String, Codable, CaseIterable, Identifiable, Sendable {
    case tokens
    case apiEquivalentCost
    case sessions
    case requests

    var id: Self { self }
}

struct PeriodUsageSummary: Equatable, Sendable {
    let usage: TokenUsage
    let sessionCount: Int
    let requestCount: Int
    let estimatedCostUSD: Double
    let topModel: ModelUsage?
    let days: [DailyUsage]
}

extension CodexUsageSnapshot {
    func summary(
        for period: UsagePeriod,
        calendar: Calendar = .current,
        now: Date? = nil
    ) -> PeriodUsageSummary {
        let anchor = now ?? generatedAt ?? Date()
        let start: Date? = switch period {
        case .today:
            calendar.startOfDay(for: anchor)
        case .sevenDays:
            calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: anchor))
        case .month:
            calendar.date(from: calendar.dateComponents([.year, .month], from: anchor))
        case .lifetime:
            nil
        }
        let includes: (Date) -> Bool = { date in
            date <= anchor && start.map { date >= $0 } != false
        }
        let days = activityDays.filter { includes($0.date) }.sorted { $0.date < $1.date }
        let usage = period == .lifetime
            ? lifetime
            : days.reduce(into: .zero) { $0.add($1.usage) }
        let sessionCount = period == .lifetime
            ? self.sessionCount ?? days.reduce(0) { $0 + $1.sessions }
            : days.reduce(0) { $0 + $1.sessions }
        let requestCount = period == .lifetime
            ? turnCount ?? days.reduce(0) { $0 + ($1.turns ?? 0) }
            : days.reduce(0) { $0 + ($1.turns ?? 0) }

        var models: [String: ModelUsage] = [:]
        for daily in dailyModelUsage where includes(daily.date) {
            for model in daily.models {
                var aggregate = models[model.model]
                    ?? ModelUsage(model: model.model, usage: .zero, turns: 0, estimatedCostUSD: 0)
                aggregate.usage.add(model.usage)
                aggregate.turns += model.turns
                aggregate.estimatedCostUSD += model.estimatedCostUSD
                models[model.model] = aggregate
            }
        }
        let datedModels = Array(models.values)
        let legacyLifetimeModels = period == .lifetime && dailyModelUsage.isEmpty ? modelUsage ?? [] : []
        let summaryModels = legacyLifetimeModels.isEmpty ? datedModels : legacyLifetimeModels
        let topModel = summaryModels.sorted {
            $0.usage.total == $1.usage.total
                ? $0.model < $1.model
                : $0.usage.total > $1.usage.total
        }.first
        let estimatedCostUSD = if !summaryModels.isEmpty {
            summaryModels.reduce(0) { $0 + $1.estimatedCostUSD }
        } else {
            Double(days.reduce(0) { $0 + ($1.estimatedCostMicros ?? 0) }) / 1_000_000
        }

        return PeriodUsageSummary(
            usage: usage,
            sessionCount: sessionCount,
            requestCount: requestCount,
            estimatedCostUSD: estimatedCostUSD,
            topModel: topModel,
            days: days
        )
    }
}
