import Foundation
import Testing
@testable import CodexUsageMonitor

@Test("Empty snapshot starts at zero")
func emptySnapshotStartsAtZero() {
    #expect(CodexUsageSnapshot.empty.today.total == 0)
    #expect(CodexUsageSnapshot.empty.lifetime.total == 0)
}

@Test("Background refresh runs once per minute")
func backgroundRefreshRunsOncePerMinute() {
    #expect(BackgroundRefreshAgent.interval == 60)
}

@Test("Menu bar label formats both limit rows")
func menuBarLabelFormatsBothLimitRows() {
    let window = RateLimitWindow(
        usedPercent: 24.6,
        windowMinutes: 300,
        resetsAt: .now.addingTimeInterval(3_600),
        observedAt: .now
    )

    #expect(CodexMenuBarLabel.labelText(prefix: "5H", window: window, mode: .percentage) == "5H 75%")
    #expect(CodexMenuBarLabel.labelText(prefix: "W", window: window, mode: .percentage) == "W 75%")
    #expect(CodexMenuBarLabel.labelText(prefix: "W", window: nil, mode: .percentage) == "W —")
}

@Test("Phone reset request is sent only after a confirmed five-hour reset")
func phoneResetRequestRequiresConfirmedReset() throws {
    let now = try #require(ISO8601DateFormatter().date(from: "2026-08-30T12:00:00Z"))
    let window = RateLimitWindow(
        usedPercent: 1,
        windowMinutes: 300,
        resetsAt: now.addingTimeInterval(5 * 3_600),
        observedAt: now
    )

    let request = try #require(PhoneResetNotificationManager.confirmedResetRequest(
        topic: "codex-private-topic",
        window: window,
        previousReset: now.addingTimeInterval(-1).timeIntervalSince1970,
        now: now
    ))

    #expect(request.url?.absoluteString == "https://ntfy.sh/codex-private-topic")
    #expect(request.httpMethod == "POST")
    #expect(request.value(forHTTPHeaderField: "At") == nil)
}

@Test("Reset notification state ignores timestamp jitter and older windows")
func resetNotificationStateRejectsDuplicateWindows() throws {
    let reset = try #require(ISO8601DateFormatter().date(from: "2026-08-30T13:00:00Z"))
    let stored = reset.timeIntervalSince1970

    #expect(LimitNotificationManager.isNewReset(reset, after: 0))
    #expect(!LimitNotificationManager.isNewReset(reset.addingTimeInterval(1), after: stored))
    #expect(!LimitNotificationManager.isNewReset(reset.addingTimeInterval(-3_600), after: stored))
    #expect(LimitNotificationManager.isNewReset(reset.addingTimeInterval(5 * 3_600), after: stored))
}

@Test("Legacy reset alert state migrates without sending again")
func legacyResetNotificationStateIsRecognized() throws {
    let suiteName = "CodexUsageMonitorTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    defaults.set(true, forKey: "CodexUsageMonitor.notified.300.1788226971.80")

    #expect(LimitNotificationManager.previousNotifiedReset(
        defaults: defaults,
        windowMinutes: 300,
        threshold: 80
    ) == 1_788_226_971)
    #expect(LimitNotificationManager.previousNotifiedReset(
        defaults: defaults,
        windowMinutes: 300,
        threshold: 95
    ) == 0)
}

@Test("Reset notifications require an observed window transition")
func resetNotificationsRequireObservedTransition() throws {
    let now = try #require(ISO8601DateFormatter().date(from: "2026-08-30T12:00:00Z"))
    let fiveHour = RateLimitWindow(
        usedPercent: 1,
        windowMinutes: 300,
        resetsAt: now.addingTimeInterval(5 * 3_600),
        observedAt: now
    )
    let weekly = RateLimitWindow(
        usedPercent: 77,
        windowMinutes: 10_080,
        resetsAt: now.addingTimeInterval(6 * 86_400),
        observedAt: now
    )

    #expect(LimitNotificationManager.isConfirmedReset(
        previousReset: now.addingTimeInterval(-1).timeIntervalSince1970,
        window: fiveHour,
        now: now
    ))
    #expect(!LimitNotificationManager.isConfirmedReset(
        previousReset: weekly.resetsAt.timeIntervalSince1970,
        window: weekly,
        now: now
    ))
    #expect(PhoneResetNotificationManager.confirmedResetRequest(
        topic: "codex-private-topic",
        window: fiveHour,
        previousReset: fiveHour.resetsAt.timeIntervalSince1970,
        now: now
    ) == nil)
}

@Test("Reader splits a chat across active days")
func readerSplitsChatAcrossActiveDays() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let log = """
    {"type":"session_meta","payload":{"id":"session-1","session_id":"session-1","timestamp":"2026-07-31T10:00:00Z"}}
    {"type":"turn_context","payload":{"model":"gpt-5.6-sol"}}
    {"timestamp":"2026-07-31T10:01:00Z","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":80,"cached_input_tokens":20,"output_tokens":20,"reasoning_output_tokens":0,"total_tokens":100},"last_token_usage":{"input_tokens":80,"cached_input_tokens":20,"output_tokens":20,"reasoning_output_tokens":0,"total_tokens":100}}}}
    {"timestamp":"2026-07-31T10:05:00Z","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":200,"cached_input_tokens":50,"output_tokens":50,"reasoning_output_tokens":0,"total_tokens":250},"last_token_usage":{"input_tokens":120,"cached_input_tokens":30,"output_tokens":30,"reasoning_output_tokens":0,"total_tokens":150}}}}
    {"timestamp":"2026-08-01T09:15:00Z","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":240,"cached_input_tokens":60,"output_tokens":60,"reasoning_output_tokens":0,"total_tokens":300},"last_token_usage":{"input_tokens":40,"cached_input_tokens":10,"output_tokens":10,"reasoning_output_tokens":0,"total_tokens":50}}}}
    """
    try Data(log.utf8).write(to: directory.appendingPathComponent("session-1.jsonl"))

    let now = try #require(ISO8601DateFormatter().date(from: "2026-08-01T12:00:00Z"))
    let snapshot = CodexUsageReader(sessionsDirectory: directory).snapshot(now: now)
    let newest = try #require(snapshot.recentSessions.first)
    let previous = try #require(snapshot.recentSessions.last)

    #expect(snapshot.recentSessions.count == 2)
    #expect(newest.id.hasPrefix("session-1#"))
    #expect(newest.model == "gpt-5.6-sol")
    #expect(newest.turns == 1)
    #expect(newest.usage.total == 50)
    #expect(previous.turns == 2)
    #expect(previous.usage.total == 250)
    #expect(previous.estimatedCostUSD != nil)
}
