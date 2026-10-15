import Foundation
import Testing
@testable import Runway

@Suite
struct IncrementalReaderTests {
    @Test("Append checkpoints preserve resets, model changes, lifecycle and tool IDs after cache reload")
    func parserStateAcrossAppends() throws {
        let fixture = try IncrementalFixture()
        let rows = try [
            fixture.metadata(),
            fixture.context("gpt-6.1-sol"),
            fixture.event("task_started", second: 1, extra: ["model_context_window": 100_000]),
            fixture.tokens(100, second: 2),
            fixture.tokens(0, second: 3),
            fixture.tokens(150, second: 4),
            fixture.context("gpt-5.6-terra"),
            fixture.tokens(180, second: 5, last: 30),
            fixture.tool("same-tool", second: 6),
            fixture.tool("same-tool", second: 7),
            fixture.event("task_complete", second: 8, extra: ["duration_ms": 7_000, "time_to_first_token_ms": 40]),
            fixture.event("turn_started", second: 9),
            fixture.tool("same-tool", second: 10),
            fixture.event("turn_aborted", second: 11)
        ]
        for row in rows {
            try fixture.append(row)
            fixture.expectParity()
        }
        let snapshot = fixture.snapshot()
        #expect(snapshot.lifetime.total == 280)
        #expect(snapshot.currentModel == "gpt-5.6-terra")
        #expect(snapshot.sessionActivity.first?.state == "interrupted")
        #expect(snapshot.sessionActivity.first?.toolCalls == 1)
        #expect(snapshot.sessionActivity.first?.toolFailures == 1)
        let progress = try fixture.progress()
        #expect(progress["bytesRead"] as? Int == (try Data(contentsOf: fixture.log)).count)
        #expect(progress["endedWithNewline"] as? Bool == true)
    }

    @Test("Late metadata and context before observation retain raw state rather than EOF fallbacks")
    func rawMetadataBeforeFinalization() throws {
        let fixture = try IncrementalFixture()
        for row in try [fixture.context("gpt-6.1-sol"), fixture.tokens(100, second: 5, kind: "legacy"),
                        fixture.context("gpt-5.6-luna")] {
            try fixture.append(row)
            fixture.expectParity()
        }
        try fixture.append(fixture.metadata(id: "canonical", extra: ["session_id": "canonical"]))
        try fixture.append(fixture.tokens(150, second: 6))
        fixture.expectParity()
        let snapshot = fixture.snapshot()
        #expect(snapshot.lifetime.total == 150)
        #expect(snapshot.currentModel == "gpt-5.6-luna")
        #expect(snapshot.sessionActivity.first?.id == "canonical")
        #expect(snapshot.sessionActivity.first?.provider == "openai")
        #expect(snapshot.sessionActivity.first?.reasoningEffort == "high")
        let entry = try fixture.entry()
        let parsed = try #require(entry["parsedFile"] as? [String: Any])
        #expect(parsed["lineageIDs"] as? [String] == ["canonical"])
        #expect(snapshot.currentSessionStartedAt == fixture.baseDate)
    }

    @Test("Tool observations before the first usage row retain unpublished activity across append")
    func toolActivityBeforeFirstUsage() throws {
        let fixture = try IncrementalFixture()
        try fixture.append(fixture.metadata() + fixture.context("gpt-6.1-sol") + fixture.tool("early-tool", second: 1))
        fixture.expectParity()
        try fixture.append(fixture.tokens(100, second: 2))
        fixture.expectParity()
        let activity = try #require(fixture.snapshot().sessionActivity.first)
        #expect(activity.provider == "openai")
        #expect(activity.project == "runway")
        #expect(activity.reasoningEffort == "high")
        #expect(activity.toolCalls == 1)
        #expect(activity.toolFailures == 1)
        #expect(activity.lastTool == "test")
        try fixture.append(fixture.tool("early-tool", second: 3))
        fixture.expectParity()
        #expect(fixture.snapshot().sessionActivity.first?.toolCalls == 1)
    }

    @Test("Previously incomplete schema-seven checkpoints rebuild raw activity before reuse or append")
    func repairsMissingCheckpointActivity() throws {
        let fixture = try IncrementalFixture()
        try fixture.append(fixture.metadata() + fixture.context("gpt-6.1-sol") + fixture.tool("early-tool", second: 1))
        fixture.expectParity()
        func removeRawActivity(_ entry: inout [String: Any]) {
            var checkpoint = entry["checkpoint"] as! [String: Any]
            checkpoint.removeValue(forKey: "activity")
            entry["checkpoint"] = checkpoint
        }
        try fixture.mutateEntry(removeRawActivity)
        fixture.expectParity()
        let checkpoint = try #require(fixture.entry()["checkpoint"] as? [String: Any])
        let repaired = try #require(checkpoint["activity"] as? [String: Any])
        #expect(repaired["provider"] as? String == "openai")
        #expect(repaired["toolCalls"] as? Int == 1)
        try fixture.mutateEntry(removeRawActivity)
        try fixture.append(fixture.tokens(100, second: 2))
        fixture.expectParity()
        #expect(fixture.snapshot().sessionActivity.first?.provider == "openai")
        #expect(fixture.snapshot().sessionActivity.first?.toolCalls == 1)
    }

    @Test("Unterminated valid and partial rows reparse without retaining transcript tails")
    func incompleteRows() throws {
        let fixture = try IncrementalFixture()
        try fixture.append(fixture.metadata())
        try fixture.append(Data(fixture.tokens(100, second: 1).dropLast()))
        fixture.expectParity()
        #expect(fixture.snapshot().lifetime.total == 100)
        #expect(try fixture.progress()["endedWithNewline"] as? Bool == false)
        try fixture.append(Data("invalidates-the-previous-JSON-row\n".utf8))
        fixture.expectParity()
        #expect(fixture.snapshot().lifetime.total == 0)
        let token = try fixture.tokens(250, second: 2)
        let split = token.count / 2
        try fixture.append(Data(token.prefix(split)))
        fixture.expectParity()
        try fixture.append(Data(token.dropFirst(split)))
        fixture.expectParity()
        #expect(fixture.snapshot().lifetime.total == 250)
        let privateRow = try fixture.row("response_item", payload: ["text": "PRIVATE_TRANSCRIPT_SENTINEL 🚆"])
        let emoji = try #require(privateRow.range(of: Data("🚆".utf8)))
        let byteSplit = emoji.lowerBound + 1
        try fixture.append(Data(privateRow.prefix(byteSplit)))
        fixture.expectParity()
        try fixture.append(Data(privateRow.dropFirst(byteSplit)))
        fixture.expectParity()
        #expect(try Data(contentsOf: fixture.cache).range(of: Data("PRIVATE_TRANSCRIPT_SENTINEL".utf8)) == nil)
    }

    @Test("Rewrites, replacement, truncation and rewrite-plus-append match full parsing",
          arguments: ["middle-and-append", "same-size", "replacement", "truncate"])
    func sourceMutation(mode: String) throws {
        let fixture = try IncrementalFixture()
        let noise = try fixture.row("response_item", payload: ["text": String(repeating: "n", count: 70_000)])
        let prefix = try fixture.metadata() + noise + fixture.tokens(100, second: 1) + noise + fixture.tokens(200, second: 2)
        try fixture.append(prefix)
        fixture.expectParity()
        let changed = try fixture.metadata() + noise + fixture.tokens(900, second: 1) + noise + fixture.tokens(200, second: 2)
        #expect(changed.count == prefix.count)
        let oldDate = try #require(fixture.log.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
        if mode == "replacement" {
            try changed.write(to: fixture.log, options: .atomic)
        } else {
            let handle = try FileHandle(forUpdating: fixture.log)
            defer { try? handle.close() }
            try handle.seek(toOffset: 0)
            if mode == "truncate" {
                let short = try fixture.metadata() + fixture.tokens(50, second: 1)
                try handle.write(contentsOf: short)
                try handle.truncate(atOffset: UInt64(short.count))
            } else {
                try handle.write(contentsOf: changed)
            }
        }
        if mode == "same-size" || mode == "replacement" {
            try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: fixture.log.path)
        }
        if mode == "middle-and-append" { try fixture.append(fixture.tokens(250, second: 3)) }
        fixture.expectParity()
        #expect(fixture.snapshot().lifetime.total == (mode == "truncate" ? 50 : mode == "middle-and-append" ? 1_150 : 1_100))
    }

    @Test("Failed reads keep previous usage and checkpoint metadata and recover on retry")
    func failedReadDoesNotAdvance() throws {
        let fixture = try IncrementalFixture()
        try fixture.append(fixture.metadata() + fixture.tokens(200, second: 1))
        let before = fixture.snapshot()
        let progress = try fixture.progress()
        let held = fixture.directory.appendingPathComponent("held.bin")
        try FileManager.default.moveItem(at: fixture.log, to: held)
        try FileManager.default.createDirectory(at: fixture.log, withIntermediateDirectories: true)
        let failed = CodexUsageReader(sessionsDirectory: fixture.logs, calendar: fixture.calendar, cacheURL: fixture.cache)
            .snapshotResult(now: fixture.baseDate.addingTimeInterval(60))
        #expect(failed.snapshot == before)
        #expect(failed.sourceReadPending)
        #expect(try fixture.progress()["prefixDigest"] as? Data == progress["prefixDigest"] as? Data)
        #expect(try fixture.progress()["bytesRead"] as? Int == progress["bytesRead"] as? Int)
        try FileManager.default.removeItem(at: fixture.log)
        try FileManager.default.moveItem(at: held, to: fixture.log)
        try fixture.append(fixture.tokens(250, second: 2))
        fixture.expectParity()
        #expect(fixture.snapshot().lifetime.total == 250)
    }

    @Test("Unreadable enumeration retains known files, then recovery and actual deletion clear pending state")
    func enumerationFailureAndDeletion() throws {
        let fixture = try IncrementalFixture()
        try fixture.append(fixture.metadata() + fixture.tokens(200, second: 1))
        let before = fixture.snapshot()
        let manager = FileManager.default
        try manager.setAttributes([.posixPermissions: 0], ofItemAtPath: fixture.logs.path)
        defer { try? manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fixture.logs.path) }
        let reader = CodexUsageReader(sessionsDirectory: fixture.logs, calendar: fixture.calendar, cacheURL: fixture.cache)
        let failed = reader.snapshotResult(now: fixture.baseDate.addingTimeInterval(60))
        #expect(failed.sourceReadPending)
        #expect(failed.snapshot == before)
        try manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fixture.logs.path)
        let recovered = reader.snapshotResult(now: fixture.baseDate.addingTimeInterval(60))
        #expect(!recovered.sourceReadPending)
        #expect(recovered.snapshot == before)
        try manager.removeItem(at: fixture.log)
        let deleted = reader.snapshotResult(now: fixture.baseDate.addingTimeInterval(60))
        #expect(!deleted.sourceReadPending)
        #expect(deleted.snapshot.lifetime.total == 0)
    }

    @Test("An unreadable empty tree changes its fingerprint and cannot reuse an account-only snapshot")
    func emptyTreePermissionFingerprint() throws {
        let fixture = try IncrementalFixture()
        let reader = CodexUsageReader(sessionsDirectory: fixture.logs, calendar: fixture.calendar, cacheURL: fixture.cache)
        let now = fixture.baseDate.addingTimeInterval(60)
        let readable = reader.sourceFingerprint(now: now)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: fixture.logs.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fixture.logs.path) }
        let unreadable = reader.sourceFingerprint(now: now)
        #expect(unreadable != readable)
        #expect(unreadable == reader.sourceFingerprint(now: now))
        #expect(!SnapshotRefresh.canReuseSnapshot(previousFingerprint: readable, currentFingerprint: unreadable,
            hasSnapshot: true, force: false))
        #expect(reader.snapshotResult(now: now).sourceReadPending)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fixture.logs.path)
        #expect(reader.sourceFingerprint(now: now) == readable)
    }

    @Test("Old checkpoints, corrupt caches and wrong prefix digests fall back to full parsing")
    func cacheRecovery() throws {
        let fixture = try IncrementalFixture()
        try fixture.append(fixture.metadata() + fixture.tokens(100, second: 1))
        fixture.expectParity()
        try fixture.mutateEntry { $0.removeValue(forKey: "checkpoint") }
        try fixture.append(fixture.tokens(150, second: 2))
        fixture.expectParity()
        try fixture.mutateEntry { entry in
            var checkpoint = entry["checkpoint"] as! [String: Any]
            var progress = checkpoint["progress"] as! [String: Any]
            progress["prefixDigest"] = Data(repeating: 0, count: 32)
            checkpoint["progress"] = progress
            entry["checkpoint"] = checkpoint
        }
        try fixture.append(fixture.tokens(200, second: 3))
        fixture.expectParity()
        try Data("broken cache".utf8).write(to: fixture.cache)
        try fixture.append(fixture.tokens(250, second: 4))
        fixture.expectParity()
    }

    @Test("Schema-six migration adds identity and ctime before later restored-mtime changes",
          arguments: [false, true])
    func migratedCacheInvalidation(replacement: Bool) throws {
        let fixture = try IncrementalFixture()
        let original = try fixture.metadata() + fixture.tokens(100, second: 1)
        try fixture.append(original)
        fixture.expectParity()
        try fixture.mutateEntry(schemaVersion: 6) { entry in
            for key in ["checkpoint", "changeTimeSeconds", "changeTimeNanoseconds", "sourceIdentity"] {
                entry.removeValue(forKey: key)
            }
        }
        fixture.expectParity()
        let migrated = try fixture.entry()
        #expect(migrated["checkpoint"] == nil)
        #expect(migrated["changeTimeSeconds"] != nil)
        #expect(migrated["changeTimeNanoseconds"] != nil)
        #expect(migrated["sourceIdentity"] != nil)
        let oldDate = try #require(fixture.log.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
        let changed = try fixture.metadata() + fixture.tokens(900, second: 1)
        #expect(changed.count == original.count)
        if replacement {
            try changed.write(to: fixture.log, options: .atomic)
        } else {
            let handle = try FileHandle(forWritingTo: fixture.log)
            defer { try? handle.close() }
            try handle.write(contentsOf: changed)
        }
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: fixture.log.path)
        fixture.expectParity()
        #expect(fixture.snapshot().lifetime.total == 900)
    }

    @Test("Resumed lineage and subagent classification survive append checkpoints")
    func resumedParentAndSubagent() throws {
        let fixture = try IncrementalFixture()
        try fixture.append(fixture.metadata(id: "parent") + fixture.tokens(100, second: 1))
        let resumed = fixture.logs.appendingPathComponent("resume.jsonl")
        try fixture.append(fixture.metadata(id: "resumed", second: 2, extra: ["session_id": "parent"])
            + fixture.tokens(100, second: 1), to: resumed)
        fixture.expectParity()
        try fixture.append(fixture.tokens(150, second: 3), to: resumed)
        fixture.expectParity()
        #expect(fixture.snapshot().lifetime.total == 150)
        let child = fixture.logs.appendingPathComponent("child.jsonl")
        try fixture.append(fixture.metadata(id: "child", extra: ["thread_source": "subagent", "parent_thread_id": "parent"]), to: child)
        fixture.expectParity()
        try fixture.append(fixture.tokens(1_000, second: 4), to: child)
        fixture.expectParity()
        #expect(fixture.snapshot().lifetime.total == 150)
    }
}

private final class IncrementalFixture {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let logs: URL
    let log: URL
    let cache: URL
    let baseDate = ISO8601DateFormatter().date(from: "2026-10-14T12:00:00Z")!
    var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }

    init() throws {
        logs = directory.appendingPathComponent("sessions")
        log = logs.appendingPathComponent("fallback-filename.jsonl")
        cache = directory.appendingPathComponent("cache.plist")
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: directory) }

    func snapshot(cached: Bool = true) -> CodexUsageSnapshot {
        CodexUsageReader(sessionsDirectory: logs, calendar: calendar, cacheURL: cached ? cache : nil)
            .snapshot(now: baseDate.addingTimeInterval(60))
    }

    func expectParity() { #expect(snapshot() == snapshot(cached: false)) }

    func append(_ bytes: Data, to url: URL? = nil) throws {
        let target = url ?? log
        if !FileManager.default.fileExists(atPath: target.path) { try Data().write(to: target) }
        let handle = try FileHandle(forWritingTo: target)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: bytes)
    }

    func row(_ kind: String, second: Int = 0, payload: [String: Any]) throws -> Data {
        let timestamp = ISO8601DateFormatter().string(from: baseDate.addingTimeInterval(Double(second)))
        return try JSONSerialization.data(withJSONObject: ["type": kind, "timestamp": timestamp, "payload": payload],
            options: [.sortedKeys]) + Data([10])
    }

    func metadata(id: String = "session", second: Int = 0, extra: [String: Any] = [:]) throws -> Data {
        var payload: [String: Any] = ["id": id, "timestamp": ISO8601DateFormatter().string(from: baseDate.addingTimeInterval(Double(second))),
            "cwd": "/projects/runway", "model_provider": "openai", "cli_version": "test"]
        payload.merge(extra) { _, new in new }
        return try row("session_meta", second: second, payload: payload)
    }

    func context(_ model: String) throws -> Data {
        try row("turn_context", payload: ["model": model, "effort": "high", "approval_policy": "never",
            "sandbox_policy": ["type": "workspace-write"], "cwd": "/projects/runway"])
    }

    func tokens(_ total: Int, second: Int, last: Int? = nil, kind: String = "event_msg") throws -> Data {
        func usage(_ count: Int) -> [String: Int] { ["input_tokens": count, "total_tokens": count] }
        var info: [String: Any] = ["total_token_usage": usage(total), "model_context_window": 100_000]
        if let last { info["last_token_usage"] = usage(last) }
        return try row(kind, second: second, payload: ["type": "token_count", "info": info])
    }

    func event(_ type: String, second: Int, extra: [String: Any] = [:]) throws -> Data {
        var payload: [String: Any] = ["type": type]
        payload.merge(extra) { _, new in new }
        return try row("event_msg", second: second, payload: payload)
    }

    func tool(_ id: String, second: Int) throws -> Data {
        try event("item_completed", second: second, extra: ["item": ["id": id, "type": "McpToolCall", "tool": "test", "status": "failed"]])
    }

    func entry() throws -> [String: Any] {
        let root = try #require(PropertyListSerialization.propertyList(from: Data(contentsOf: cache), format: nil) as? [String: Any])
        let entries = try #require(root["entries"] as? [String: Any])
        return try #require(entries[entryKey(entries)] as? [String: Any])
    }

    func progress() throws -> [String: Any] {
        let checkpoint = try #require(entry()["checkpoint"] as? [String: Any])
        return try #require(checkpoint["progress"] as? [String: Any])
    }

    func mutateEntry(schemaVersion: Int? = nil, _ change: (inout [String: Any]) -> Void) throws {
        var root = try #require(PropertyListSerialization.propertyList(from: Data(contentsOf: cache), format: nil) as? [String: Any])
        var entries = try #require(root["entries"] as? [String: Any])
        let key = try entryKey(entries)
        var entry = try #require(entries[key] as? [String: Any])
        change(&entry)
        entries[key] = entry
        root["entries"] = entries
        if let schemaVersion {
            root["schemaVersion"] = schemaVersion
            root.removeValue(forKey: "calendar")
            root.removeValue(forKey: "pruningAnchor")
        }
        try PropertyListSerialization.data(fromPropertyList: root, format: .binary, options: 0).write(to: cache)
    }

    func entryKey(_ entries: [String: Any]) throws -> String {
        try #require(entries.keys.first {
            URL(fileURLWithPath: $0).standardizedFileURL.pathComponents == log.standardizedFileURL.pathComponents
        })
    }
}
