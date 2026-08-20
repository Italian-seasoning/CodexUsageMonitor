import Foundation
import Testing
@testable import CodexUsageMonitor

@Test("Empty snapshot starts at zero")
func emptySnapshotStartsAtZero() {
    #expect(CodexUsageSnapshot.empty.today.total == 0)
    #expect(CodexUsageSnapshot.empty.lifetime.total == 0)
}

@Test("Reader exposes recent sessions without a second log parser")
func readerExposesRecentSessions() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let log = """
    {"type":"session_meta","payload":{"id":"session-1","session_id":"session-1","timestamp":"2026-07-31T10:00:00Z"}}
    {"type":"turn_context","payload":{"model":"gpt-5.6-sol"}}
    {"timestamp":"2026-07-31T10:01:00Z","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":80,"cached_input_tokens":20,"output_tokens":20,"reasoning_output_tokens":0,"total_tokens":100},"last_token_usage":{"input_tokens":80,"cached_input_tokens":20,"output_tokens":20,"reasoning_output_tokens":0,"total_tokens":100}}}}
    {"timestamp":"2026-07-31T10:05:00Z","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":200,"cached_input_tokens":50,"output_tokens":50,"reasoning_output_tokens":0,"total_tokens":250},"last_token_usage":{"input_tokens":120,"cached_input_tokens":30,"output_tokens":30,"reasoning_output_tokens":0,"total_tokens":150}}}}
    """
    try Data(log.utf8).write(to: directory.appendingPathComponent("session-1.jsonl"))

    let now = try #require(ISO8601DateFormatter().date(from: "2026-07-31T12:00:00Z"))
    let snapshot = CodexUsageReader(sessionsDirectory: directory).snapshot(now: now)
    let session = try #require(snapshot.recentSessions.first)

    #expect(snapshot.recentSessions.count == 1)
    #expect(session.id == "session-1")
    #expect(session.model == "gpt-5.6-sol")
    #expect(session.turns == 2)
    #expect(session.usage.total == 250)
    #expect(session.estimatedCostUSD != nil)
}
