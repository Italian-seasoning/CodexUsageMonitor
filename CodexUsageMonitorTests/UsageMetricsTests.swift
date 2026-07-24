import Foundation
import Testing
@testable import CodexUsageMonitor

@Suite
struct UsageMetricsTests {
    @Test("Period summaries use deterministic calendar boundaries")
    func periodSummariesUseDeterministicCalendarBoundaries() {
        let fixture = usageMetricsFixture()

        #expect(fixture.snapshot.summary(for: .today, calendar: fixture.calendar, now: fixture.now).usage.total == 100)
        #expect(fixture.snapshot.summary(for: .sevenDays, calendar: fixture.calendar, now: fixture.now).usage.total == 700)
        #expect(fixture.snapshot.summary(for: .month, calendar: fixture.calendar, now: fixture.now).usage.total == 3_000)
        #expect(fixture.snapshot.summary(for: .lifetime, calendar: fixture.calendar, now: fixture.now).usage == fixture.snapshot.lifetime)
        #expect(fixture.snapshot.summary(for: .today, calendar: fixture.calendar).usage.total == 100)
        #expect(fixture.snapshot.summary(for: .today, calendar: fixture.calendar, now: fixture.now).topModel?.model == "gpt-5.6-sol")
    }

    @Test("Token measure stays numeric across periods")
    func tokenMeasureStaysNumericAcrossPeriods() {
        let fixture = usageMetricsFixture()

        let tokenValues: [Int] = UsagePeriod.allCases.map {
            fixture.snapshot.summary(for: $0, calendar: fixture.calendar, now: fixture.now).usage.total
        }

        #expect(tokenValues == [100, 700, 3_000, 5_000])
        #expect(UsageMeasure.tokens.rawValue == "tokens")
    }

    @Test("Today token selection does not fall back to the current model")
    func todayTokenSelectionUsesTodayUsage() {
        let fixture = usageMetricsFixture()
        var snapshot = fixture.snapshot
        snapshot.currentModel = "gpt-5.6-sol"

        let presented = snapshot
            .summary(for: .today, calendar: fixture.calendar, now: fixture.now)
            .value(for: .tokens)

        #expect(presented == 100)
    }

    @Test("Period summaries exclude future rows and preserve recorded model cost")
    func periodSummariesExcludeFutureRowsAndPreserveRecordedModelCost() {
        let fixture = usageMetricsFixture()
        let today = fixture.snapshot.summary(for: .today, calendar: fixture.calendar, now: fixture.now)
        let lifetime = fixture.snapshot.summary(for: .lifetime, calendar: fixture.calendar, now: fixture.now)

        #expect(today.sessionCount == 1)
        #expect(today.requestCount == 10)
        #expect(abs(today.estimatedCostUSD - 0.62) < 0.000_001)
        #expect(lifetime.days.allSatisfy { $0.date <= fixture.now })
        #expect(lifetime.topModel?.model != "future-model")
        #expect(abs(lifetime.estimatedCostUSD - 2.32) < 0.000_001)
    }

    @Test("Period cost does not reprice an aggregate across the long-context threshold")
    func periodCostDoesNotRepriceAggregateAcrossLongContextThreshold() throws {
        let fixture = usageMetricsFixture()
        let aggregate = TokenUsage(
            input: 400_000,
            cachedInput: 0,
            output: 0,
            reasoningOutput: 0,
            total: 400_000
        )
        var snapshot = fixture.snapshot
        snapshot.dailyModelUsage = [
            DailyModelUsage(
                date: fixture.calendar.startOfDay(for: fixture.now),
                models: [
                    ModelUsage(
                        model: "gpt-5.6-sol",
                        usage: aggregate,
                        turns: 2,
                        estimatedCostUSD: 2
                    )
                ]
            )
        ]

        let pricing = try #require(ModelPricingCatalog.pricing(for: "gpt-5.6-sol"))
        #expect(abs(pricing.estimatedCost(for: aggregate) - 4) < 0.000_001)
        #expect(abs(snapshot.summary(for: .today, calendar: fixture.calendar, now: fixture.now).estimatedCostUSD - 2) < 0.000_001)
    }

    @Test("Legacy snapshots decode without dated model usage")
    func legacySnapshotsDecodeWithoutDatedModelUsage() throws {
        let fixture = usageMetricsFixture()
        let encoded = try JSONEncoder().encode(fixture.snapshot)
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "dailyModelUsage")

        let decoded = try JSONDecoder().decode(
            CodexUsageSnapshot.self,
            from: JSONSerialization.data(withJSONObject: object)
        )
        let today = decoded.summary(for: .today, calendar: fixture.calendar, now: fixture.now)
        let lifetime = decoded.summary(for: .lifetime, calendar: fixture.calendar, now: fixture.now)

        #expect(decoded.dailyModelUsage.isEmpty)
        #expect(today.usage.total == 100)
        #expect(today.sessionCount == 1)
        #expect(today.requestCount == 10)
        #expect(abs(today.estimatedCostUSD - 0.62) < 0.000_001)
        #expect(today.topModel == nil)
        #expect(lifetime.topModel?.model == "gpt-5.6-terra")
        #expect(abs(lifetime.estimatedCostUSD - 2.32) < 0.000_001)
    }
}

private func usageMetricsFixture() -> (snapshot: CodexUsageSnapshot, calendar: Calendar, now: Date) {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let now = calendar.date(from: DateComponents(year: 2026, month: 7, day: 24, hour: 12))!
    let day: (Int, Int, Int) -> Date = { year, month, day in
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }
    let usage: (Int) -> TokenUsage = {
        TokenUsage(input: $0, cachedInput: 0, output: 0, reasoningOutput: 0, total: $0)
    }

    var activityDays = [
        DailyUsage(date: day(2026, 6, 30), usage: usage(400), sessions: 4, turns: 40, estimatedCostMicros: 400_000),
        DailyUsage(date: day(2026, 7, 1), usage: usage(700), sessions: 7, turns: 70, estimatedCostMicros: 700_000)
    ]
    activityDays += (2...24).map {
        let cost = $0 == 24 ? 620_000 : ($0 >= 18 ? 100_000 : nil)
        return DailyUsage(
            date: day(2026, 7, $0),
            usage: usage(100),
            sessions: 1,
            turns: 10,
            estimatedCostMicros: cost
        )
    }
    activityDays.append(DailyUsage(date: day(2026, 7, 25), usage: usage(900), sessions: 9, turns: 90))

    var snapshot = CodexUsageSnapshot(
        currentSession: .zero,
        lifetime: usage(5_000),
        today: usage(100),
        peakDay: nil,
        currentStreak: 0,
        longestStreak: 0,
        lastUpdated: now,
        activityDays: activityDays,
        generatedAt: now,
        sessionCount: 50,
        turnCount: 500,
        modelUsage: [
            ModelUsage(model: "gpt-5.6-terra", usage: usage(1_700), turns: 170, estimatedCostUSD: 1.7),
            ModelUsage(model: "gpt-5.6-sol", usage: usage(100), turns: 10, estimatedCostUSD: 0.62)
        ]
    )
    snapshot.dailyModelUsage = [
        DailyModelUsage(
            date: day(2026, 6, 30),
            models: [ModelUsage(model: "gpt-5.6-terra", usage: usage(400), turns: 40, estimatedCostUSD: 0.4)]
        ),
        DailyModelUsage(
            date: day(2026, 7, 1),
            models: [ModelUsage(model: "gpt-5.6-terra", usage: usage(700), turns: 70, estimatedCostUSD: 0.7)]
        )
    ]
    snapshot.dailyModelUsage += (18...23).map {
        DailyModelUsage(
            date: day(2026, 7, $0),
            models: [ModelUsage(model: "gpt-5.6-terra", usage: usage(100), turns: 10, estimatedCostUSD: 0.1)]
        )
    }
    snapshot.dailyModelUsage += [
        DailyModelUsage(
            date: day(2026, 7, 24),
            models: [ModelUsage(model: "gpt-5.6-sol", usage: usage(100), turns: 10, estimatedCostUSD: 0.62)]
        ),
        DailyModelUsage(
            date: day(2026, 7, 25),
            models: [ModelUsage(model: "future-model", usage: usage(10_000), turns: 100, estimatedCostUSD: 999)]
        )
    ]
    return (snapshot, calendar, now)
}
