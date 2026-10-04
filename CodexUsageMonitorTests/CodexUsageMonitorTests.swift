import Foundation
import Testing
@testable import CodexUsageMonitor

@Test("Streaming JSONL handles split UTF-8, large rows, CRLF, malformed rows and a final row", arguments: [1, 7, 65_536])
func streamingJSONLBoundaries(chunkSize: Int) throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: url) }
    let largeValue = String(repeating: "🚆", count: chunkSize == 1 ? 40 : 20_000)
    let rows: [[String: Any]] = [["id": 1, "text": "héllo 🚆"], ["id": 2, "text": largeValue], ["id": 3]]
    var bytes = Data([10])
    for row in rows.dropLast() {
        bytes.append(try JSONSerialization.data(withJSONObject: row))
        bytes.append(contentsOf: [13, 10])
    }
    bytes.append(Data("malformed\n{\"truncated\":\n".utf8))
    bytes.append(try JSONSerialization.data(withJSONObject: rows.last!))
    try bytes.write(to: url)
    var ids: [Int] = []
    try JSONLFileReader.forEachRow(at: url, chunkSize: chunkSize) { row in
        ids.append(row["id"] as! Int)
        if row["id"] as? Int == 2 { #expect(row["text"] as? String == largeValue) }
    }
    #expect(ids == [1, 2, 3])
}

@Test("Streaming JSONL propagates unreadable file errors")
func streamingJSONLReadFailure() {
    #expect(throws: (any Error).self) {
        try JSONLFileReader.forEachRow(at: URL(fileURLWithPath: "/nonexistent/\(UUID().uuidString).jsonl")) { _ in }
    }
}

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

@Test("Reader splits and prices a chat across active days", arguments: ["gpt-5.6-sol", "gpt-6.1-sol"])
func readerSplitsChatAcrossActiveDays(model: String) throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let log = """
    {"type":"session_meta","payload":{"id":"session-1","session_id":"session-1","timestamp":"2026-07-31T10:00:00Z"}}
    {"type":"turn_context","payload":{"model":"\(model)"}}
    {"timestamp":"2026-07-31T10:01:00Z","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":80,"cached_input_tokens":20,"output_tokens":20,"reasoning_output_tokens":0,"total_tokens":100},"last_token_usage":{"input_tokens":80,"cached_input_tokens":20,"output_tokens":20,"reasoning_output_tokens":0,"total_tokens":100}}}}
    {"timestamp":"2026-07-31T10:05:00Z","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":200,"cached_input_tokens":50,"output_tokens":50,"reasoning_output_tokens":0,"total_tokens":250},"last_token_usage":{"input_tokens":120,"cached_input_tokens":30,"output_tokens":30,"reasoning_output_tokens":0,"total_tokens":150}}}}
    {"timestamp":"2026-08-01T09:15:00Z","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":240,"cached_input_tokens":60,"output_tokens":60,"reasoning_output_tokens":0,"total_tokens":300},"last_token_usage":{"input_tokens":40,"cached_input_tokens":10,"output_tokens":10,"reasoning_output_tokens":0,"total_tokens":50}}}}
    """
    try Data(log.utf8).write(to: directory.appendingPathComponent("session-1.jsonl"))

    let now = try #require(ISO8601DateFormatter().date(from: "2026-08-01T12:00:00Z"))
    let reader = CodexUsageReader(sessionsDirectory: directory, cacheURL: directory.appendingPathComponent("reader-cache.plist"))
    let snapshot = reader.snapshot(now: now)
    let newest = try #require(snapshot.recentSessions.first)
    let previous = try #require(snapshot.recentSessions.last)

    #expect(snapshot.recentSessions.count == 2)
    #expect(newest.id.hasPrefix("session-1#"))
    #expect(newest.model == model)
    #expect(newest.turns == 1)
    #expect(newest.usage.total == 50)
    #expect(previous.turns == 2)
    #expect(previous.usage.total == 250)
    #expect(previous.estimatedCostUSD != nil)
    let pricing = try #require(ModelPricingCatalog.pricing(for: model))
    let cost = pricing.estimatedCost(for: snapshot.lifetime)
    #expect(abs(snapshot.estimatedCostUSD - cost) < 0.000_001)
    let modelEstimate = try #require(snapshot.modelUsage?.first).estimatedCostUSD
    #expect(abs(modelEstimate - cost) < 0.000_001)
    #expect(snapshot.unpricedTokens == 0)
    #expect(reader.snapshot(now: now).estimatedCostUSD == snapshot.estimatedCostUSD)
}

@Test("GPT-6.1 Sol uses its own cache rates and the 272K context boundary")
func sol61Pricing() throws {
    let pricing = try #require(ModelPricingCatalog.pricing(for: "gpt-6.1-sol"))
    #expect(ModelPricingCatalog.pricing(for: "gpt-6.1-sol-2026-10-01") == pricing)
    #expect(pricing.inputPerMillion == 2)
    #expect(pricing.cachedInputPerMillion == 0.1)
    #expect(pricing.outputPerMillion == 10)
    let short = TokenUsage(input: 272_000, cachedInput: 100_000, output: 10_000, reasoningOutput: 0, total: 282_000)
    let long = TokenUsage(input: 272_001, cachedInput: 100_000, output: 10_000, reasoningOutput: 0, total: 282_001)
    #expect(abs(pricing.estimatedCost(for: short) - 0.454) < 0.000_001)
    #expect(abs(pricing.estimatedCost(for: long) - 0.858004) < 0.000_001)
}
