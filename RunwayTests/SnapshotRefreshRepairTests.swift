import Darwin
import Foundation
import Testing
@testable import Runway

@Suite
struct SnapshotRefreshRepairTests {
    @Test("An account child closing stdin after initialization cannot kill Runway")
    func accountChildClosesStdin() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "read request; exec 0<&-; printf '%s\\n' '{\"id\":0,\"result\":{}}'"]
        #expect(CodexAccountReader.read(process: process) == nil)
        let input = try #require(process.standardInput as? Pipe)
        #expect(fcntl(input.fileHandleForWriting.fileDescriptor, F_GETNOSIGPIPE) == 1)
        process.waitUntilExit()
        #expect(throws: (any Error).self) {
            try input.fileHandleForWriting.write(contentsOf: Data([10]))
        }
    }

    @Test("Account-only polling records bounded hourly allowance history")
    func accountOnlyHistory() throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let reset = start.addingTimeInterval(86_400)
        var limits: CodexRateLimits?
        var hours = Set<Date>()
        for minute in 0...20 {
            let now = start.addingTimeInterval(Double(minute * 60))
            let weekly = RateLimitWindow(usedPercent: Double(10 + minute), windowMinutes: 10_080,
                resetsAt: reset, observedAt: now)
            let account = CodexRateLimits(fiveHour: nil, weekly: weekly, history: [])
            limits = SnapshotRefresh.mergedLimits(local: nil, previous: limits, account: account, now: now)
            hours.insert(Calendar.current.dateInterval(of: .hour, for: now)!.start)
        }
        let recorded = try #require(limits)
        #expect(recorded.history.count == hours.count)
        #expect(recorded.history.last?.weeklyUsedPercent == 30)
        #expect(recorded.history.allSatisfy { $0.fiveHourUsedPercent == nil })
        #expect(recorded.consumptionSamples?.count == 21)
        let cached = SnapshotRefresh.mergedLimits(local: nil, previous: recorded, account: nil,
            now: start.addingTimeInterval(3_600))
        #expect(cached?.history == recorded.history)
        let staleLocal = CodexRateLimits(fiveHour: nil,
            weekly: RateLimitWindow(usedPercent: 1, windowMinutes: 10_080,
                resetsAt: reset, observedAt: start.addingTimeInterval(-60)),
            history: [RateLimitHistoryPoint(date: recorded.history.last!.date,
                fiveHourUsedPercent: 80, weeklyUsedPercent: 1)])
        let preserved = SnapshotRefresh.mergedLimits(local: staleLocal, previous: recorded, account: nil,
            now: start.addingTimeInterval(3_600))
        #expect(preserved?.history == recorded.history)
    }

    @Test("Account history retains local windows and expires observations after seven days")
    func historyMergesAndExpires() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let hour = try #require(Calendar.current.dateInterval(of: .hour, for: now)?.start)
        let prior = hour.addingTimeInterval(-3_600)
        let previous = CodexRateLimits(fiveHour: nil, weekly: nil, history: [
            RateLimitHistoryPoint(date: hour.addingTimeInterval(-8 * 86_400), fiveHourUsedPercent: 5, weeklyUsedPercent: 20),
            RateLimitHistoryPoint(date: prior, fiveHourUsedPercent: 10, weeklyUsedPercent: 30),
            RateLimitHistoryPoint(date: hour, fiveHourUsedPercent: 15, weeklyUsedPercent: 35)
        ])
        let local = CodexRateLimits(fiveHour: nil, weekly: nil, history: [
            RateLimitHistoryPoint(date: prior, fiveHourUsedPercent: 12, weeklyUsedPercent: nil)
        ])
        let account = CodexRateLimits(fiveHour: nil, weekly: RateLimitWindow(usedPercent: 40,
            windowMinutes: 10_080, resetsAt: now.addingTimeInterval(86_400), observedAt: now), history: [])
        let merged = try #require(SnapshotRefresh.mergedLimits(local: local, previous: previous, account: account, now: now))
        #expect(merged.history == [
            RateLimitHistoryPoint(date: prior, fiveHourUsedPercent: 12, weeklyUsedPercent: 30),
            RateLimitHistoryPoint(date: hour, fiveHourUsedPercent: nil, weeklyUsedPercent: 40)
        ])
    }

    @Test("Forced refresh lock acquisition waits and has a bounded timeout")
    func waitsForProcessLock() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("refresh.lock")
        let holder = try #require(RefreshLock.acquire(at: url))
        #expect(RefreshLock.acquire(at: url) == nil)
        let timeoutStart = ProcessInfo.processInfo.systemUptime
        #expect(RefreshLock.acquire(at: url, timeout: 0.15) == nil)
        #expect(ProcessInfo.processInfo.systemUptime - timeoutStart >= 0.14)
        // Waiting must not depend on a shared queue saturated by parallel blocking tests.
        Thread.detachNewThread {
            Thread.sleep(forTimeInterval: 0.15)
            holder.release()
        }
        let waiting = try #require(RefreshLock.acquire(at: url, timeout: 2))
        waiting.release()
    }

    @Test("A failed refresh persists the account attempt and throttles the next offline poll")
    func failedAccountAttemptBudget() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let previous = BackgroundRefreshRecord(lastAttempt: now.addingTimeInterval(-120),
            lastSuccess: now.addingTimeInterval(-180), outcome: .updated,
            durationSeconds: 1, error: nil, lastAccountAttempt: now.addingTimeInterval(-120))
        var saved: BackgroundRefreshRecord?
        SnapshotRefresh.saveRecord(startedAt: now, outcome: .failed, message: "Offline",
            fingerprint: nil, widgetReloadRequestedAt: nil, lastAccountAttempt: now,
            previousRecord: previous, persist: { saved = $0 })
        let record = try #require(saved)
        let reloaded = try JSONDecoder().decode(BackgroundRefreshRecord.self, from: JSONEncoder().encode(record))
        #expect(reloaded.outcome == .failed)
        #expect(reloaded.lastSuccess == previous.lastSuccess)
        #expect(reloaded.lastAccountAttempt == now)
        #expect(!SnapshotRefresh.shouldReadAccount(lastAttempt: reloaded.lastAccountAttempt,
            trigger: .fallbackTimer, now: now.addingTimeInterval(15)))
        #expect(SnapshotRefresh.shouldReadAccount(lastAttempt: reloaded.lastAccountAttempt,
            trigger: .fallbackTimer, now: now.addingTimeInterval(60)))
    }

    @Test("Legacy background migration stops the old label and removes only its registration")
    func removesLegacyBackgroundAgent() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let legacy = directory.appendingPathComponent("\(BackgroundRefreshAgent.legacyIdentifier).plist")
        let current = directory.appendingPathComponent("\(BackgroundRefreshAgent.identifier).plist")
        let registration = Data("registration".utf8)
        try registration.write(to: legacy)
        try registration.write(to: current)
        let service = "gui/123/\(BackgroundRefreshAgent.legacyIdentifier)"
        var loaded = true
        var calls: [[String]] = []
        let removed = BackgroundRefreshAgent.removeAgent(identifier: BackgroundRefreshAgent.legacyIdentifier,
            directory: directory, domain: "gui/123", allowed: true) { arguments in
            calls.append(arguments)
            if arguments == ["bootout", service] {
                loaded = false
                return 0
            }
            return loaded ? 0 : 113
        }
        #expect(removed)
        #expect(calls == [["print", service], ["bootout", service], ["print", service]])
        #expect(!FileManager.default.fileExists(atPath: legacy.path))
        #expect(try Data(contentsOf: current) == registration)

        // A loaded launchd job remains addressable after its old plist has disappeared.
        loaded = true
        calls = []
        #expect(BackgroundRefreshAgent.removeAgent(identifier: BackgroundRefreshAgent.legacyIdentifier,
            directory: directory, domain: "gui/123", allowed: true) { arguments in
            calls.append(arguments)
            if arguments.first == "bootout" { loaded = false; return 0 }
            return loaded ? 0 : 113
        })
        #expect(calls.contains(["bootout", service]))
    }

    @Test("A disabled or unloaded legacy registration is removed without re-enabling its job")
    func removesUnloadedLegacyBackgroundAgent() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let legacy = directory.appendingPathComponent("\(BackgroundRefreshAgent.legacyIdentifier).plist")
        try Data("disabled registration".utf8).write(to: legacy)
        var calls: [[String]] = []
        #expect(BackgroundRefreshAgent.removeAgent(identifier: BackgroundRefreshAgent.legacyIdentifier,
            directory: directory, domain: "gui/123", allowed: true) { arguments in
            calls.append(arguments)
            return 113
        })
        #expect(calls == [["print", "gui/123/\(BackgroundRefreshAgent.legacyIdentifier)"]])
        #expect(!FileManager.default.fileExists(atPath: legacy.path))
    }

    @Test("Failed legacy job removal preserves its plist and reports failure")
    func legacyBackgroundAgentRemovalFailure() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let legacy = directory.appendingPathComponent("\(BackgroundRefreshAgent.legacyIdentifier).plist")
        let registration = Data("registration".utf8)
        try registration.write(to: legacy)
        for failure in [Int32(-1), 1, 5] {
            #expect(!BackgroundRefreshAgent.removeAgent(identifier: BackgroundRefreshAgent.legacyIdentifier,
                directory: directory, domain: "gui/123", allowed: true) { _ in failure })
            #expect(try Data(contentsOf: legacy) == registration)
        }
        #expect(!BackgroundRefreshAgent.removeAgent(identifier: BackgroundRefreshAgent.legacyIdentifier,
            directory: directory, domain: "gui/123", allowed: true) { arguments in
            arguments.first == "bootout" ? 5 : 0
        })
        #expect(try Data(contentsOf: legacy) == registration)
        // Even a successful bootout cannot remove the file while the job still appears loaded.
        #expect(!BackgroundRefreshAgent.removeAgent(identifier: BackgroundRefreshAgent.legacyIdentifier,
            directory: directory, domain: "gui/123", allowed: true) { _ in 0 })
        #expect(try Data(contentsOf: legacy) == registration)
    }

    @Test("Debug and temporary app builds cannot modify production launch agents")
    func backgroundAgentDebugIsolation() throws {
        #expect(BackgroundRefreshAgent.canManageAgents(
            bundleIdentifier: "com.codexusage.CodexUsageMonitor", isStableInstall: true))
        #expect(!BackgroundRefreshAgent.canManageAgents(
            bundleIdentifier: "com.codexusage.CodexUsageMonitor.debug", isStableInstall: true))
        #expect(!BackgroundRefreshAgent.canManageAgents(
            bundleIdentifier: "com.codexusage.CodexUsageMonitor", isStableInstall: false))
        #expect(!BackgroundRefreshAgent.canManageAgents(bundleIdentifier: nil, isStableInstall: true))
        var called = false
        #expect(!BackgroundRefreshAgent.removeAgent(identifier: BackgroundRefreshAgent.legacyIdentifier,
            directory: URL(fileURLWithPath: "/unused"), domain: "gui/123", allowed: false) { _ in
            called = true
            return 0
        })
        #expect(!called)
    }
}
