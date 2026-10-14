import Foundation
import Testing
@testable import CodexUsageMonitor

@Suite
struct RefreshCoordinatorTests {
    @Test("Account daily buckets must cover the account lifetime exactly")
    func accountUsageBuckets() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let result: [String: Any] = [
            "summary": ["lifetimeTokens": 10_200],
            "dailyUsageBuckets": [
                ["startDate": "2026-10-12", "tokens": 5_400],
                ["startDate": "2026-10-13", "tokens": 4_800]
            ]
        ]
        let days = try #require(CodexAccountReader.decodeUsageDays(result, calendar: calendar))
        #expect(days.map(\.tokens) == [5_400, 4_800])
        var incomplete = result
        incomplete["summary"] = ["lifetimeTokens": 10_201]
        #expect(CodexAccountReader.decodeUsageDays(incomplete, calendar: calendar) == nil)
    }

    @Test("Pro plans hide five-hour windows without discarding the account record")
    func proPresentation() throws {
        let now = Date()
        let hourly: [String: Any] = ["usedPercent": 20.0, "windowDurationMins": 300,
            "resetsAt": now.addingTimeInterval(3600).timeIntervalSince1970]
        for plan in ["pro", "prolite", "Pro"] {
            let account = try #require(CodexAccountReader.decodeRateLimits(["rateLimits": ["planType": plan, "primary": hourly]], now: now))
            #expect(account.fiveHour != nil)
            #expect(!account.showsFiveHour)
            let merged = SnapshotRefresh.mergedLimits(local: nil, previous: nil, account: account, now: now)
            let cached = SnapshotRefresh.mergedLimits(local: account, previous: merged, account: nil, now: now)
            #expect(cached?.planType == plan)
            #expect(cached?.showsFiveHour == false)
        }
        let plus = try #require(CodexAccountReader.decodeRateLimits(["rateLimits": ["planType": "plus", "primary": hourly]], now: now))
        #expect(plus.showsFiveHour)
        #expect(CodexRateLimits(fiveHour: nil, weekly: nil, history: []).showsFiveHour == false)
    }

    @Test("Account primary weekly window is never mislabeled five-hour")
    func accountWindowMapping() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let weekly: [String: Any] = ["usedPercent": 65.0, "windowDurationMins": 10_080,
            "resetsAt": now.addingTimeInterval(86_400).timeIntervalSince1970]
        let hourly: [String: Any] = ["usedPercent": 10.0, "windowDurationMins": 300,
            "resetsAt": now.addingTimeInterval(3_600).timeIntervalSince1970]
        let data: [String: Any] = ["rateLimits": ["primary": hourly],
            "rateLimitsByLimitId": ["codex": ["primary": weekly, "secondary": NSNull()]]]
        let account = try #require(CodexAccountReader.decodeRateLimits(data, now: now))
        #expect(account.fiveHour == nil)
        #expect(account.weekly?.remainingPercent == 35)
        let local = CodexRateLimits(fiveHour: RateLimitWindow(usedPercent: 10, windowMinutes: 300,
            resetsAt: now.addingTimeInterval(3_600), observedAt: now.addingTimeInterval(-10)), weekly: nil, history: [])
        let merged = try #require(SnapshotRefresh.mergedLimits(local: local, previous: nil, account: account, now: now))
        #expect(merged.fiveHour == nil)
        #expect(merged.weekly?.remainingPercent == 35)
        let cached = SnapshotRefresh.mergedLimits(local: local, previous: merged, account: nil, now: now.addingTimeInterval(15))
        #expect(cached?.fiveHour == nil)
        #expect(cached?.weekly?.remainingPercent == 35)
        let reversed = try #require(CodexAccountReader.decodeRateLimits(["rateLimits": ["primary": weekly, "secondary": hourly]], now: now))
        #expect(reversed.fiveHour?.remainingPercent == 90)
        #expect(reversed.weekly?.remainingPercent == 35)
    }

    @Test("Frequent source changes do not relaunch account polling every time")
    func accountPollingBudget() {
        let now = Date()
        #expect(!SnapshotRefresh.shouldReadAccount(lastAttempt: now.addingTimeInterval(-15), trigger: .sourceChange, now: now))
        #expect(SnapshotRefresh.shouldReadAccount(lastAttempt: now.addingTimeInterval(-60), trigger: .fallbackTimer, now: now))
        #expect(SnapshotRefresh.shouldReadAccount(lastAttempt: now, trigger: .manual, now: now))
        #expect(SnapshotRefresh.shouldReadAccount(lastAttempt: now, trigger: .wake, now: now))
    }

    @Test("Missing local logs keep cached account usage only between account reads")
    func missingLocalAccountFallback() {
        #expect(SnapshotRefresh.accountAvailableWhenLocalMissing(fetched: 10_200, cached: nil, attempted: true))
        #expect(SnapshotRefresh.accountAvailableWhenLocalMissing(fetched: nil, cached: 10_200, attempted: false))
        #expect(!SnapshotRefresh.accountAvailableWhenLocalMissing(fetched: nil, cached: 10_200, attempted: true))
        #expect(!SnapshotRefresh.accountAvailableWhenLocalMissing(fetched: nil, cached: nil, attempted: false))
    }

    @Test("Simultaneous refresh requests share one engine pass")
    func coalescesSimultaneousRequests() async {
        let calls = CallRecorder()
        let coordinator = RefreshCoordinator { trigger, force in
            await calls.record(trigger: trigger, force: force)
            try? await Task.sleep(for: .milliseconds(50))
            return RefreshResult(outcome: .updated, snapshot: nil, message: "updated")
        }

        await withTaskGroup(of: RefreshResult.self) { group in
            for _ in 0..<10 {
                group.addTask {
                    await coordinator.refresh(trigger: .sourceChange)
                }
            }
            for await result in group {
                #expect(result.outcome == .updated)
            }
        }

        #expect(await calls.count == 1)
    }

    @Test("Manual refresh always reaches the engine as forced")
    func manualRefreshIsForced() async {
        let calls = CallRecorder()
        let coordinator = RefreshCoordinator { trigger, force in
            await calls.record(trigger: trigger, force: force)
            return RefreshResult(outcome: .updated, snapshot: nil, message: "updated")
        }

        _ = await coordinator.refresh(trigger: .manual)

        #expect(await calls.values == [RecordedCall(trigger: .manual, force: true)])
    }

    @Test("A forced request behind an unforced pass queues one follow-up")
    func queuesOneForcedFollowUp() async {
        let calls = CallRecorder()
        let coordinator = RefreshCoordinator { trigger, force in
            await calls.record(trigger: trigger, force: force)
            try? await Task.sleep(for: .milliseconds(40))
            return RefreshResult(outcome: .updated, snapshot: nil, message: "updated")
        }

        async let background = coordinator.refresh(trigger: .backgroundAgent)
        while await calls.count == 0 {
            await Task.yield()
        }
        async let firstManual = coordinator.refresh(trigger: .manual)
        async let secondManual = coordinator.refresh(trigger: .manual)
        _ = await [background, firstManual, secondManual]

        #expect(await calls.count == 2)
        #expect(await calls.values.last?.force == true)
    }

    @Test("Matching fingerprints make an unforced background pass unchanged")
    func matchingFingerprintIsUnchanged() async {
        let coordinator = RefreshCoordinator { trigger, force in
            let unchanged = SnapshotRefresh.canReuseSnapshot(
                previousFingerprint: "same",
                currentFingerprint: "same",
                hasSnapshot: true,
                force: force
            )
            return RefreshResult(
                outcome: trigger == .backgroundAgent && unchanged ? .unchanged : .updated,
                snapshot: nil,
                message: "complete"
            )
        }

        let result = await coordinator.refresh(trigger: .backgroundAgent)

        #expect(result.outcome == .unchanged)
    }

    @Test("Widget sync retries after failure and refreshes on launch")
    func widgetSyncRetry() {
        #expect(SnapshotRefresh.shouldReloadWidget(outcome: .unchanged, trigger: .backgroundAgent, syncPending: true))
        #expect(SnapshotRefresh.shouldReloadWidget(outcome: .unchanged, trigger: .launch, syncPending: false))
        #expect(SnapshotRefresh.shouldReloadWidget(outcome: .unchanged, trigger: .manual, syncPending: false))
        #expect(!SnapshotRefresh.shouldReloadWidget(outcome: .unchanged, trigger: .backgroundAgent, syncPending: false))
        let now = Date()
        #expect(!SnapshotRefresh.shouldReloadWidget(outcome: .updated, trigger: .sourceChange, syncPending: false, lastRequested: now, now: now))
        #expect(SnapshotRefresh.shouldReloadWidget(outcome: .updated, trigger: .sourceChange, syncPending: false, lastRequested: now.addingTimeInterval(-60), now: now))
        #expect(!SnapshotRefresh.shouldReloadWidget(outcome: .unchanged, trigger: .backgroundAgent, syncPending: false,
            reloadPending: true, lastRequested: now, now: now))
        #expect(SnapshotRefresh.shouldReloadWidget(outcome: .unchanged, trigger: .backgroundAgent, syncPending: false,
            reloadPending: true, lastRequested: now, now: now.addingTimeInterval(60)))
    }
}

private struct RecordedCall: Equatable {
    var trigger: RefreshTrigger
    var force: Bool
}

private actor CallRecorder {
    private(set) var values: [RecordedCall] = []
    var count: Int { values.count }

    func record(trigger: RefreshTrigger, force: Bool) {
        values.append(RecordedCall(trigger: trigger, force: force))
    }
}
