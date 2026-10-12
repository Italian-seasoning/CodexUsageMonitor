import Foundation
import Testing
@testable import CodexUsageMonitor

@Suite
struct UsageMetricsTests {
    @Test("Archiving a session preserves its usage and range totals")
    func archivePreservesUsage() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let active = root.appendingPathComponent("sessions")
        let archived = root.appendingPathComponent("archived_sessions")
        try FileManager.default.createDirectory(at: active, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: archived, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let log = """
        {"type":"session_meta","payload":{"id":"archive-test","timestamp":"2026-07-01T10:00:00Z"}}
        {"timestamp":"2026-07-01T10:01:00Z","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":80,"output_tokens":20,"total_tokens":100},"last_token_usage":{"input_tokens":80,"output_tokens":20,"total_tokens":100}}}}
        """
        let file = active.appendingPathComponent("session.jsonl")
        try Data(log.utf8).write(to: file)
        let reader = CodexUsageReader(sessionsDirectory: active, cacheURL: root.appendingPathComponent("cache.plist"), archivedSessionsDirectory: archived)
        let before = reader.snapshot()
        try FileManager.default.moveItem(at: file, to: archived.appendingPathComponent("session.jsonl"))
        let after = reader.snapshot()
        #expect(before.lifetime.total == 100)
        #expect(after.lifetime == before.lifetime)
        #expect(after.activityDays == before.activityDays)
    }

    @Test("Reader retains actual minute observations alongside hourly history")
    func readerConsumptionSamples() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let formatter = ISO8601DateFormatter()
        let lines = try (0...3).map { index -> String in
            let row: [String: Any] = ["timestamp": formatter.string(from: now.addingTimeInterval(Double(index - 3) * 300)),
                "type": "event_msg", "payload": ["type": "token_count", "rate_limits": [
                    "primary": ["window_minutes": 300, "used_percent": 20 + index * 2, "resets_at": now.addingTimeInterval(3_600).timeIntervalSince1970]]]]
            return String(decoding: try JSONSerialization.data(withJSONObject: row), as: UTF8.self)
        }.joined(separator: "\n")
        try Data((lines + "\n").utf8).write(to: directory.appendingPathComponent("sample.jsonl"))
        let reader = CodexUsageReader(sessionsDirectory: directory, cacheURL: directory.appendingPathComponent("cache.plist"))
        let snapshot = reader.snapshot(now: now)
        let limits = try #require(snapshot.rateLimits)
        #expect(limits.consumptionSamples?.count == 4)
        #expect(limits.consumptionPer15Minutes(for: limits.fiveHour, now: now) == 6)
        let decoded = try JSONDecoder().decode(CodexUsageSnapshot.self, from: JSONEncoder().encode(snapshot))
        #expect(decoded.rateLimits?.consumptionSamples == limits.consumptionSamples)
    }

    @Test("Custom dates include both endpoints and never substitute lifetime totals")
    func customDateRange() {
        let fixture = usageMetricsFixture()
        let today = fixture.calendar.startOfDay(for: fixture.now)
        let yesterday = fixture.calendar.date(byAdding: .day, value: -1, to: today)!
        let range = fixture.snapshot.summary(from: yesterday, through: today, calendar: fixture.calendar, now: fixture.now)
        #expect(range.usage.total == 200)
        #expect(range.requestCount == 20)
        #expect(range.sessionCount == 2)
        #expect(abs(range.estimatedCostUSD - 0.72) < 0.000_001)
        #expect(range.days.count == 2)
        #expect(fixture.snapshot.summary(from: today, through: today, calendar: fixture.calendar, now: fixture.now).usage.total == 100)
        #expect(fixture.snapshot.summary(from: today, through: yesterday, calendar: fixture.calendar, now: fixture.now).usage.total == 0)
        let future = fixture.calendar.date(byAdding: .day, value: 2, to: today)!
        let empty = fixture.snapshot.summary(from: future, through: future, calendar: fixture.calendar, now: fixture.now)
        #expect(empty.usage.total == 0)
        #expect(empty.topModel == nil)
        var legacy = fixture.snapshot
        legacy.dailyModelUsage = []
        #expect(legacy.summary(from: today, through: today, calendar: fixture.calendar, now: fixture.now).topModel == nil)
    }

    @Test("Date ranges use calendar midnights across daylight saving")
    func customDatesAcrossDST() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Vancouver")!
        let start = calendar.date(from: DateComponents(year: 2026, month: 3, day: 8))!
        let next = calendar.date(byAdding: .day, value: 1, to: start)!
        var snapshot = CodexUsageSnapshot.empty
        snapshot.activityDays = [start, next].map {
            DailyUsage(date: $0, usage: TokenUsage(input: 10, cachedInput: 0, output: 0, reasoningOutput: 0, total: 10), sessions: 1)
        }
        #expect(next.timeIntervalSince(start) == 23 * 3_600)
        #expect(snapshot.summary(from: start, through: start, calendar: calendar, now: next).usage.total == 10)
    }

    @Test("15-minute consumption uses recent same-window samples and rejects resets and gaps")
    func consumptionRate() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let reset = now.addingTimeInterval(3_600)
        let samples = (0...3).map { index in
            RateLimitWindow(usedPercent: Double(20 + index * 2), windowMinutes: 300,
                resetsAt: reset, observedAt: now.addingTimeInterval(Double(index - 3) * 300))
        }
        var limits = CodexRateLimits(fiveHour: samples.last, weekly: nil, history: [], consumptionSamples: samples)
        #expect(limits.consumptionPer15Minutes(for: limits.fiveHour, now: now) == 6)
        #expect(limits.consumptionPer15Minutes(for: limits.weekly, now: now) == nil)
        #expect(limits.consumptionPer15Minutes(for: limits.fiveHour, now: now.addingTimeInterval(301)) == nil)
        limits.consumptionSamples = [samples[2], samples[3]]
        #expect(limits.consumptionPer15Minutes(for: limits.fiveHour, now: now) == nil)
        limits.consumptionSamples = [samples[0], samples[3]]
        #expect(limits.consumptionPer15Minutes(for: limits.fiveHour, now: now) == nil)
        limits.consumptionSamples = samples.map { var point = $0; point.resetsAt = reset.addingTimeInterval(-3_600); return point }
        #expect(limits.consumptionPer15Minutes(for: limits.fiveHour, now: now) == nil)
        limits.consumptionSamples = samples
        limits.consumptionSamples?[1].usedPercent = 5
        #expect(limits.consumptionPer15Minutes(for: limits.fiveHour, now: now) == nil)
        limits.consumptionSamples = samples.map { var point = $0; point.usedPercent = 26; return point }
        #expect(limits.consumptionPer15Minutes(for: limits.fiveHour, now: now) == 0)
        let legacy = try JSONDecoder().decode(CodexRateLimits.self, from: Data("{\"history\":[]}".utf8))
        #expect(legacy.consumptionSamples == nil)
    }

    @Test("Account lifetime takes priority in the lifetime widget")
    func accountLifetimeTakesPriority() throws {
        var snapshot = usageMetricsFixture().snapshot
        snapshot.accountLifetimeTokens = 7_500
        let saved = try JSONEncoder().encode(snapshot)
        let restored = try JSONDecoder().decode(CodexUsageSnapshot.self, from: saved)

        #expect(PrimaryMetric.lifetime.value(in: restored) == 7_500)
        #expect(restored.lifetime.total == 5_000)
    }

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
        #expect(abs(pricing.estimatedCost(for: aggregate) - 3.2) < 0.000_001)
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

    @Test("Legacy history fills missing days without double-counting overlap")
    func legacyHistoryMergeIsDateSafe() {
        let fixture = usageMetricsFixture()
        let today = fixture.calendar.startOfDay(for: fixture.now)
        let yesterday = fixture.calendar.date(byAdding: .day, value: -1, to: today)!
        let usage: (Int) -> TokenUsage = {
            TokenUsage(input: $0, cachedInput: 0, output: 0, reasoningOutput: 0, total: $0)
        }

        var current = CodexUsageSnapshot.empty
        current.lifetime = usage(100)
        current.activityDays = [
            DailyUsage(date: today, usage: usage(100), sessions: 1, turns: 10)
        ]
        current.sessionCount = 1
        current.turnCount = 10

        var legacy = CodexUsageSnapshot.empty
        legacy.activityDays = [
            DailyUsage(date: yesterday, usage: usage(50), sessions: 2, turns: 5),
            DailyUsage(date: today, usage: usage(999), sessions: 9, turns: 99)
        ]
        legacy.dailyModelUsage = [
            DailyModelUsage(
                date: yesterday,
                models: [ModelUsage(model: "gpt-5.6-terra", usage: usage(50), turns: 5, estimatedCostUSD: 0.5)]
            )
        ]

        let merged = current.mergingLegacyHistory([legacy], calendar: fixture.calendar)

        #expect(merged.lifetime.total == 150)
        #expect(merged.sessionCount == 3)
        #expect(merged.turnCount == 15)
        #expect(merged.activityDays.count == 2)
        #expect(merged.activityDays.last?.usage.total == 100)
        #expect(merged.modelUsage?.first?.usage.total == 50)
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
