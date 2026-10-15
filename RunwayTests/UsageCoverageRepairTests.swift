import Foundation
import Testing
@testable import Runway

@Suite
struct UsageCoverageRepairTests {
    @Test("Missing current account buckets stay distinct from an explicit zero")
    func missingAccountPeriod() throws {
        let (snapshot, calendar, now) = try coverageFixture()
        #expect(snapshot.accountDays(for: .today, calendar: calendar, now: now) == nil)
        #expect(snapshot.accountDays(for: .lifetime, calendar: calendar, now: now)?.map(\.tokens) == [1_000])

        var reported = snapshot
        reported.accountUsageDays?.append(AccountUsageDay(date: calendar.startOfDay(for: now), tokens: 0))
        #expect(reported.accountDays(for: .today, calendar: calendar, now: now)?.map(\.tokens) == [0])
    }

    @Test("Widgets label positive local fallback when account reporting is delayed", arguments: [CodexWidgetFamily.usagePulse, .dashboard])
    func widgetLocalFallback(family: CodexWidgetFamily) throws {
        let (snapshot, calendar, now) = try coverageFixture()
        let widget = WidgetFamilySemanticBuilder.content(snapshot: snapshot,
            configuration: configuration(family: family, period: .today), now: now, calendar: calendar)
        #expect(widget.heroValue == 100.compactTokenString)
        #expect(widget.heroLabel == "Local today tokens")
        #expect(widget.chart?.points.map(\.value) == [100])
    }

    @Test("Explicit account zero stays authoritative over positive local usage", arguments: [CodexWidgetFamily.usagePulse, .dashboard])
    func widgetExplicitAccountZero(family: CodexWidgetFamily) throws {
        var (snapshot, calendar, now) = try coverageFixture()
        snapshot.accountUsageDays?.append(AccountUsageDay(date: calendar.startOfDay(for: now), tokens: 0))
        let widget = WidgetFamilySemanticBuilder.content(snapshot: snapshot,
            configuration: configuration(family: family, period: .today), now: now, calendar: calendar)
        #expect(widget.heroValue == "0")
        #expect(widget.heroLabel == "Account today tokens")
        #expect(widget.chart?.points.map(\.value) == [0])
        #expect(widget.freshness == .fresh)
    }

    @Test("Account period aggregation keeps reported rows and rejects mismatched totals")
    func accountPeriodAggregation() throws {
        var (snapshot, calendar, now) = try coverageFixture()
        snapshot.accountUsageDays?.append(AccountUsageDay(date: calendar.startOfDay(for: now), tokens: 500))
        snapshot.accountLifetimeTokens = 1_500
        #expect(snapshot.accountDays(for: .today, calendar: calendar, now: now)?.map(\.tokens) == [500])
        #expect(snapshot.accountDays(for: .sevenDays, calendar: calendar, now: now)?.reduce(0) { $0 + $1.tokens } == 1_500)
        #expect(snapshot.accountDays(for: .lifetime, calendar: calendar, now: now)?.reduce(0) { $0 + $1.tokens } == 1_500)
        snapshot.accountLifetimeTokens = 2_000
        #expect(snapshot.accountDays(for: .today, calendar: calendar, now: now) == nil)
        #expect(snapshot.accountDays(for: .lifetime, calendar: calendar, now: now) == nil)
    }

    @Test("Reported aggregate account totals disclose missing active-day coverage", arguments: [UsagePeriod.sevenDays, .month])
    func pendingAggregateAccountCoverage(period: UsagePeriod) throws {
        let (snapshot, calendar, now) = try coverageFixture()
        #expect(snapshot.accountUsageIsPending(for: period, calendar: calendar, now: now))
        #expect(!snapshot.accountUsageIsPending(for: .lifetime, calendar: calendar, now: now))
        for family in [CodexWidgetFamily.usagePulse, .dashboard] {
            let pending = WidgetFamilySemanticBuilder.content(snapshot: snapshot,
                configuration: configuration(family: family, period: period), now: now, calendar: calendar)
            #expect(pending.heroValue == 1_000.compactTokenString)
            #expect(pending.heroLabel.contains("Today pending"))
            #expect(pending.freshness == .partial)

            var zero = snapshot
            zero.accountUsageDays?.append(AccountUsageDay(date: calendar.startOfDay(for: now), tokens: 0))
            #expect(!zero.accountUsageIsPending(for: period, calendar: calendar, now: now))
            let confirmedZero = WidgetFamilySemanticBuilder.content(snapshot: zero,
                configuration: configuration(family: family, period: period), now: now, calendar: calendar)
            #expect(confirmedZero.heroValue == 1_000.compactTokenString)
            #expect(confirmedZero.freshness == .fresh)
            #expect(!confirmedZero.heroLabel.contains("pending"))

            var reported = snapshot
            reported.accountUsageDays?.append(AccountUsageDay(date: calendar.startOfDay(for: now), tokens: 500))
            reported.accountLifetimeTokens = 1_500
            #expect(!reported.accountUsageIsPending(for: period, calendar: calendar, now: now))
            let complete = WidgetFamilySemanticBuilder.content(snapshot: reported,
                configuration: configuration(family: family, period: period), now: now, calendar: calendar)
            #expect(complete.heroValue == 1_500.compactTokenString)
            #expect(complete.freshness == .fresh)
        }
        var quiet = snapshot
        quiet.activityDays[0].usage = .zero
        #expect(!quiet.accountUsageIsPending(for: period, calendar: calendar, now: now))
    }

    @Test("Larger legacy overlap is disclosed without inflating local tokens, sessions, or requests")
    func legacyOverlapDisclosure() throws {
        let (current, calendar, now) = try coverageFixture()
        var saved = current
        saved.activityDays[0].usage = usage(1_000)
        saved.activityDays[0].sessions = 10
        saved.activityDays[0].turns = 10
        let backup = saved
        let merged = current.mergingLegacyHistory([saved, saved], calendar: calendar)
        #expect(merged.lifetime == current.lifetime)
        #expect(merged.sessionCount == current.sessionCount)
        #expect(merged.turnCount == current.turnCount)
        #expect(merged.activityDays[0].usage.total == 100)
        #expect(merged.activityDays[0].legacyCoverageIncomplete == true)
        #expect(merged.summary(for: .today, calendar: calendar, now: now).hasPartialLegacyCoverage)
        #expect(saved == backup)

        let restored = try JSONDecoder().decode(CodexUsageSnapshot.self, from: JSONEncoder().encode(merged))
        #expect(restored.activityDays[0].legacyCoverageIncomplete == true)
        #expect(restored.summary(for: .today, calendar: calendar, now: now).hasPartialLegacyCoverage)

        let widget = WidgetFamilySemanticBuilder.content(snapshot: merged,
            configuration: configuration(family: .usagePulse, period: .today), now: now, calendar: calendar)
        #expect(widget.heroValue == 100.compactTokenString)
        #expect(widget.heroLabel.contains("Partial local history"))
        #expect(widget.freshness == .partial)

        var reported = merged
        reported.accountUsageDays?.append(AccountUsageDay(date: calendar.startOfDay(for: now), tokens: 0))
        let accountWidget = WidgetFamilySemanticBuilder.content(snapshot: reported,
            configuration: configuration(family: .usagePulse, period: .today), now: now, calendar: calendar)
        #expect(accountWidget.heroValue == "0")
        #expect(accountWidget.heroLabel == "Account today tokens")
        #expect(accountWidget.freshness == .fresh)
    }

    @Test("Partial local coverage is limited to affected periods and clears when logs recover")
    func legacyCoveragePeriodsAndRecovery() throws {
        var (current, calendar, now) = try coverageFixture()
        current.accountLifetimeTokens = nil
        current.accountUsageDays = nil
        let yesterday = try #require(calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now)))
        current.activityDays.append(DailyUsage(date: yesterday, usage: usage(50), sessions: 1, turns: 1))
        current.lifetime = usage(150)
        var saved = CodexUsageSnapshot.empty
        saved.activityDays = [DailyUsage(date: yesterday, usage: usage(500), sessions: 5, turns: 5)]
        let merged = current.mergingLegacyHistory([saved], calendar: calendar)
        #expect(!merged.summary(for: .today, calendar: calendar, now: now).hasPartialLegacyCoverage)
        #expect(merged.summary(for: .sevenDays, calendar: calendar, now: now).hasPartialLegacyCoverage)
        #expect(!merged.summary(from: now, through: now, calendar: calendar, now: now).hasPartialLegacyCoverage)
        #expect(merged.summary(from: yesterday, through: yesterday, calendar: calendar, now: now).hasPartialLegacyCoverage)
        let unaffectedWidget = WidgetFamilySemanticBuilder.content(snapshot: merged,
            configuration: configuration(family: .dashboard, period: .today), now: now, calendar: calendar)
        #expect(unaffectedWidget.heroLabel == "Local today tokens")
        #expect(unaffectedWidget.freshness == .fresh)

        var recovered = merged
        let index = try #require(recovered.activityDays.firstIndex { $0.date == yesterday })
        recovered.activityDays[index].usage = usage(500)
        recovered.lifetime = usage(600)
        let complete = recovered.mergingLegacyHistory([saved], calendar: calendar)
        #expect(complete.activityDays[index].legacyCoverageIncomplete == nil)
        #expect(!complete.summary(for: .lifetime, calendar: calendar, now: now).hasPartialLegacyCoverage)
        #expect(complete.lifetime.total == 600)
    }

    @Test("Old daily snapshots remain compatible without the optional coverage marker")
    func legacyCoverageBackwardCompatibility() throws {
        let (snapshot, _, _) = try coverageFixture()
        let data = try JSONEncoder().encode(snapshot.activityDays[0])
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "legacyCoverageIncomplete")
        let restored = try JSONDecoder().decode(DailyUsage.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(restored.usage.total == 100)
        #expect(restored.legacyCoverageIncomplete == nil)
    }

    @Test("Pending source reads survive snapshots while older snapshots stay compatible")
    func pendingReadSnapshotCompatibility() throws {
        var snapshot = pendingReadFixture(now: Date())
        let data = try JSONEncoder().encode(snapshot)
        let restored = try JSONDecoder().decode(CodexUsageSnapshot.self, from: data)
        #expect(restored == snapshot)
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "sourceReadPending")
        let legacy = try JSONDecoder().decode(CodexUsageSnapshot.self,
            from: JSONSerialization.data(withJSONObject: object))
        snapshot.sourceReadPending = nil
        #expect(legacy == snapshot)
    }

    @Test("Pending local reads report partial health even with fresh account sources")
    func pendingReadHealth() {
        let now = Date()
        var snapshot = pendingReadFixture(now: now)
        let pending = SnapshotHealth(snapshot: snapshot, record: nil, isRefreshing: false)
        #expect(pending.kind == .freshPartial)
        #expect(pending.detail == "Local usage may be incomplete; retrying")
        snapshot.sourceReadPending = nil
        #expect(SnapshotHealth(snapshot: snapshot, record: nil, isRefreshing: false).kind == .freshComplete)
        let oldRecord = BackgroundRefreshRecord(lastAttempt: now, lastSuccess: now, outcome: .updated,
            durationSeconds: 0, error: nil, sourceFingerprint: "same|pending-source-read")
        #expect(SnapshotHealth(snapshot: snapshot, record: oldRecord, isRefreshing: false).kind == .freshPartial)
        snapshot.sourceReadPending = true
        snapshot.generatedAt = now.addingTimeInterval(-601)
        #expect(SnapshotHealth(snapshot: snapshot, record: nil, isRefreshing: false).kind == .staleCached)
    }

    @Test("App health discloses delayed current account buckets without changing totals")
    func pendingAccountHealth() throws {
        let now = Date()
        var snapshot = pendingReadFixture(now: now)
        snapshot.sourceReadPending = nil
        let today = Calendar.current.startOfDay(for: now)
        let yesterday = try #require(Calendar.current.date(byAdding: .day, value: -1, to: today))
        snapshot.accountUsageDays = [AccountUsageDay(date: yesterday, tokens: 1_000)]
        let pending = SnapshotHealth(snapshot: snapshot, record: nil, isRefreshing: false)
        #expect(pending.kind == .freshPartial)
        #expect(pending.detail == "Account usage for today is pending")
        #expect(snapshot.accountLifetimeTokens == 1_000)
        snapshot.accountUsageDays?.append(AccountUsageDay(date: today, tokens: 0))
        #expect(SnapshotHealth(snapshot: snapshot, record: nil, isRefreshing: false).kind == .freshComplete)
        #expect(WidgetFamilySemanticBuilder.content(snapshot: snapshot,
            configuration: configuration(family: .limits, period: .today), now: now).freshness == .fresh)
    }

    @Test("Widgets with local data remain partial until a source read succeeds",
        arguments: [CodexWidgetFamily.usagePulse, .dashboard, .costLens, .modelMix, .sessionLive])
    func pendingLocalWidgets(family: CodexWidgetFamily) {
        let now = Date()
        var snapshot = pendingReadFixture(now: now)
        let pending = WidgetFamilySemanticBuilder.content(snapshot: snapshot,
            configuration: configuration(family: family, period: .today), now: now)
        #expect(pending.freshness == .partial)
        snapshot.sourceReadPending = nil
        let complete = WidgetFamilySemanticBuilder.content(snapshot: snapshot,
            configuration: configuration(family: family, period: .today), now: now)
        #expect(complete.heroValue == pending.heroValue)
        #expect(complete.freshness == .fresh)
    }

    @Test("Verified account limits remain fresh while unverified local limits remain partial")
    func pendingReadLimitSources() {
        let now = Date()
        var snapshot = pendingReadFixture(now: now)
        let display = configuration(family: .limits, period: .today)
        #expect(WidgetFamilySemanticBuilder.content(snapshot: snapshot,
            configuration: display, now: now).freshness == .fresh)
        snapshot.rateLimits?.accountObservedAt = nil
        #expect(WidgetFamilySemanticBuilder.content(snapshot: snapshot,
            configuration: display, now: now).freshness == .partial)
    }

    private func configuration(family: CodexWidgetFamily, period: UsagePeriod) -> WidgetDisplayConfiguration {
        WidgetDisplayConfiguration(family: family, style: .precisionInstrument,
            theme: .crimson, period: period, dashboardArrangement: .balanced)
    }

    private func coverageFixture() throws -> (CodexUsageSnapshot, Calendar, Date) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 14, hour: 12)))
        let today = calendar.startOfDay(for: now)
        let yesterday = try #require(calendar.date(byAdding: .day, value: -1, to: today))
        let local = usage(100)
        var snapshot = CodexUsageSnapshot.empty
        snapshot.generatedAt = now
        snapshot.lifetime = local
        snapshot.today = local
        snapshot.activityDays = [DailyUsage(date: today, usage: local, sessions: 1, turns: 1)]
        snapshot.accountLifetimeTokens = 1_000
        snapshot.accountUsageObservedAt = now
        snapshot.accountUsageDays = [AccountUsageDay(date: yesterday, tokens: 1_000)]
        return (snapshot, calendar, now)
    }

    private func usage(_ total: Int) -> TokenUsage {
        TokenUsage(input: total, cachedInput: 0, output: 0, reasoningOutput: 0, total: total)
    }

    private func pendingReadFixture(now: Date) -> CodexUsageSnapshot {
        let day = Calendar.current.startOfDay(for: now)
        let local = usage(100)
        let model = ModelUsage(model: "gpt-6.1-sol", usage: local, turns: 1, estimatedCostUSD: 0.001)
        var snapshot = CodexUsageSnapshot.empty
        snapshot.generatedAt = now
        snapshot.sourceReadPending = true
        snapshot.currentSession = local
        snapshot.lifetime = local
        snapshot.today = local
        snapshot.activityDays = [DailyUsage(date: day, usage: local, sessions: 1, turns: 1)]
        snapshot.modelUsage = [model]
        snapshot.dailyModelUsage = [DailyModelUsage(date: day, models: [model])]
        snapshot.accountLifetimeTokens = 1_000
        snapshot.accountUsageDays = [AccountUsageDay(date: day, tokens: 1_000)]
        snapshot.accountUsageObservedAt = now
        snapshot.rateLimits = CodexRateLimits(fiveHour: nil,
            weekly: RateLimitWindow(usedPercent: 20, windowMinutes: 10_080,
                resetsAt: now.addingTimeInterval(604_800), observedAt: now),
            history: [], accountObservedAt: now)
        return snapshot
    }
}
