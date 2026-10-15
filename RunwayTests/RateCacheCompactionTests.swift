import Foundation
import Testing
@testable import Runway

@Suite
struct RateCacheCompactionTests {
    @Test("Unchanged files retain their fingerprint until injected calendar context changes",
        arguments: ["timeZone", "calendar", "locale", "firstWeekday", "minimumDaysInFirstWeek"])
    func calendarContextFingerprint(component: String) throws {
        let fixture = try RateFixture()
        defer { fixture.remove() }
        try fixture.write("main", rows: [RateInput(fixture.now.addingTimeInterval(-60), used: 20)])
        let before = fixture.reader().sourceFingerprint(now: fixture.now)
        #expect(before == fixture.reader().sourceFingerprint(now: fixture.now.addingTimeInterval(75)))
        #expect(SnapshotRefresh.canReuseSnapshot(previousFingerprint: before,
            currentFingerprint: before, hasSnapshot: true, force: false))
        var changed = fixture.calendar
        switch component {
        case "timeZone": changed.timeZone = try #require(TimeZone(secondsFromGMT: 1_800))
        case "calendar":
            changed = Calendar(identifier: .buddhist)
            changed.timeZone = fixture.calendar.timeZone
        case "locale": changed.locale = Locale(identifier: "en_GB")
        case "firstWeekday": changed.firstWeekday = changed.firstWeekday % 7 + 1
        default: changed.minimumDaysInFirstWeek = changed.minimumDaysInFirstWeek % 7 + 1
        }
        let after = fixture.reader(calendar: changed).sourceFingerprint(now: fixture.now)
        #expect(after != before)
        #expect(!SnapshotRefresh.canReuseSnapshot(previousFingerprint: before,
            currentFingerprint: after, hasSnapshot: true, force: false))
    }

    @Test("A daylight-saving offset transition invalidates snapshot reuse with unchanged files")
    func daylightSavingFingerprint() throws {
        let anchor = try #require(ISO8601DateFormatter().date(from: "2026-11-01T08:59:30Z"))
        let fixture = try RateFixture(now: anchor)
        defer { fixture.remove() }
        try fixture.write("main", rows: [RateInput(anchor.addingTimeInterval(-60), used: 20)])
        var calendar = fixture.calendar
        calendar.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        #expect(calendar.timeZone.secondsFromGMT(for: anchor)
            != calendar.timeZone.secondsFromGMT(for: anchor.addingTimeInterval(60)))
        let reader = fixture.reader(calendar: calendar)
        let before = reader.sourceFingerprint(now: anchor)
        let after = reader.sourceFingerprint(now: anchor.addingTimeInterval(60))
        #expect(after != before)
        #expect(!SnapshotRefresh.canReuseSnapshot(previousFingerprint: before,
            currentFingerprint: after, hasSnapshot: true, force: false))
    }

    @Test("Restored mtime cannot hide same-length rewrites or atomic replacement", arguments: [false, true])
    func rewrittenSourceFingerprint(atomicReplacement: Bool) throws {
        let fixture = try RateFixture()
        defer { fixture.remove() }
        try fixture.write("main", rows: [RateInput(fixture.now.addingTimeInterval(-60), used: 20)])
        let file = fixture.sessions.appendingPathComponent("main.jsonl")
        let restored = Date(timeIntervalSince1970: fixture.now.timeIntervalSince1970.rounded(.down))
        try FileManager.default.setAttributes([.modificationDate: restored], ofItemAtPath: file.path)
        let original = try Data(contentsOf: file)
        let originalInode = try #require(FileManager.default.attributesOfItem(atPath: file.path)[.systemFileNumber] as? NSNumber)
        let before = fixture.reader().sourceFingerprint(now: fixture.now)
        let text = String(decoding: original, as: UTF8.self)
        let rewritten = Data(text.replacingOccurrences(of: "\"used_percent\":20", with: "\"used_percent\":21").utf8)
        #expect(rewritten != original)
        #expect(rewritten.count == original.count)
        if atomicReplacement {
            try rewritten.write(to: file, options: .atomic)
        } else {
            let handle = try FileHandle(forWritingTo: file)
            try handle.write(contentsOf: rewritten)
            try handle.close()
        }
        try FileManager.default.setAttributes([.modificationDate: restored], ofItemAtPath: file.path)
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        #expect(attributes[.modificationDate] as? Date == restored)
        let rewrittenInode = try #require(attributes[.systemFileNumber] as? NSNumber)
        #expect(atomicReplacement ? rewrittenInode != originalInode : rewrittenInode == originalInode)
        let after = fixture.reader().sourceFingerprint(now: fixture.now)
        #expect(after != before)
        #expect(!SnapshotRefresh.canReuseSnapshot(previousFingerprint: before,
            currentFingerprint: after, hasSnapshot: true, force: false))
    }

    @Test("System calendar cache context survives a process-independent Codable roundtrip")
    func systemCalendarContextRoundtrip() throws {
        let fixture = try RateFixture()
        defer { fixture.remove() }
        let calendar = Calendar.current
        try fixture.write("main", rows: [RateInput(fixture.now.addingTimeInterval(-60), used: 20)])
        _ = fixture.reader(calendar: calendar).snapshot(now: fixture.now)
        let context = try PropertyListDecoder().decode(CacheContext.self, from: Data(contentsOf: fixture.cache))
        #expect(context.calendar == calendar)
        #expect(fixture.reader(calendar: calendar).snapshot(now: fixture.now)
            == fixture.reader(cached: false, calendar: calendar).snapshot(now: fixture.now))
    }

    @Test("Rate cache compacts repeated observations while preserving complete fresh and warm snapshots")
    func compactedSnapshotReplay() throws {
        let fixture = try RateFixture()
        defer { fixture.remove() }
        let rows = (0..<3_000).map { index in
            RateInput(fixture.now.addingTimeInterval(Double(index - 3_000) * 15), used: Double(index % 80))
        }
        try fixture.write("main", rows: rows)
        let fresh = fixture.reader().snapshot(now: fixture.now)
        #expect(fresh == fixture.reader(cached: false).snapshot(now: fixture.now))
        let context = try PropertyListDecoder().decode(CacheContext.self, from: Data(contentsOf: fixture.cache))
        #expect(context.schemaVersion == 7)
        #expect(context.calendar == fixture.calendar)
        #expect(context.pruningAnchor == fixture.now)
        #expect(try fixture.cachedRateCount() < 100)
        let later = fixture.now.addingTimeInterval(75)
        #expect(fixture.reader().snapshot(now: later) == fixture.reader(cached: false).snapshot(now: later))
    }

    @Test("Cache calendar context invalidates for non-whole-hour time zones and calendar changes", arguments: [false, true])
    func changedCalendar(useDifferentIdentifier: Bool) throws {
        let fixture = try RateFixture()
        defer { fixture.remove() }
        let hour = fixture.calendar.dateInterval(of: .hour, for: fixture.now)!.start.addingTimeInterval(-7_200)
        try fixture.write("main", rows: [RateInput(hour.addingTimeInterval(300), used: 10),
            RateInput(hour.addingTimeInterval(2_400), used: 20)])
        _ = fixture.reader().snapshot(now: fixture.now)
        // A poisoned retained value makes reuse observable even when two calendars share hour boundaries.
        try fixture.editCache { cache in
            var entries = cache["entries"] as! [String: [String: Any]]
            for path in Array(entries.keys) {
                var entry = entries[path]!
                var parsed = entry["parsedFile"] as! [String: Any]
                var rates = parsed["rateLimits"] as! [[String: Any]]
                for index in rates.indices { rates[index]["usedPercent"] = 99.0 }
                parsed["rateLimits"] = rates
                entry["parsedFile"] = parsed
                entries[path] = entry
            }
            cache["entries"] = entries
        }
        var changed = useDifferentIdentifier ? Calendar(identifier: .buddhist) : fixture.calendar
        changed.timeZone = try #require(TimeZone(secondsFromGMT: useDifferentIdentifier ? 0 : 1_800))
        #expect(fixture.reader(calendar: changed).snapshot(now: fixture.now)
            == fixture.reader(cached: false, calendar: changed).snapshot(now: fixture.now))
    }

    @Test("Clock rollback rebuilds observations needed before the pruning anchor")
    func clockRollback() throws {
        let fixture = try RateFixture()
        defer { fixture.remove() }
        let hour = fixture.calendar.dateInterval(of: .hour, for: fixture.now)!.start.addingTimeInterval(-7_200)
        try fixture.write("main", rows: [RateInput(hour.addingTimeInterval(300), used: 10),
            RateInput(hour.addingTimeInterval(2_400), used: 20)])
        _ = fixture.reader().snapshot(now: fixture.now)
        let earlier = hour.addingTimeInterval(1_200)
        let cached = fixture.reader().snapshot(now: earlier)
        #expect(cached == fixture.reader(cached: false).snapshot(now: earlier))
        #expect(cached.rateLimits?.consumptionSamples?.map(\.usedPercent) == [10])
    }

    @Test("A backward calendar cutoff at a daylight-saving fold rebuilds re-entering history")
    func daylightSavingCutoffRollback() throws {
        let formatter = ISO8601DateFormatter()
        let anchor = try #require(formatter.date(from: "2026-11-01T08:59:30Z"))
        let later = anchor.addingTimeInterval(60)
        let fixture = try RateFixture(now: anchor)
        defer { fixture.remove() }
        var calendar = fixture.calendar
        calendar.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        #expect(calendar.timeZone.secondsFromGMT(for: anchor) != calendar.timeZone.secondsFromGMT(for: later))
        let beforeCutoff = try #require(calendar.date(byAdding: .day, value: -7, to: anchor))
        let afterCutoff = try #require(calendar.date(byAdding: .day, value: -7, to: later))
        #expect(afterCutoff < beforeCutoff)
        try fixture.write("main", rows: [RateInput(afterCutoff.addingTimeInterval(300), used: 10),
            RateInput(afterCutoff.addingTimeInterval(2_400), used: 20),
            RateInput(anchor.addingTimeInterval(-60), used: 40)])
        _ = fixture.reader(calendar: calendar).snapshot(now: anchor)
        let snapshot = fixture.reader(calendar: calendar).snapshot(now: later)
        #expect(snapshot == fixture.reader(cached: false, calendar: calendar).snapshot(now: later))
        #expect(snapshot.rateLimits?.history.count == 2)
    }

    @Test("Future rows enter minute consumption without being lost to hour compaction")
    func futureRowsAndResetChanges() throws {
        let fixture = try RateFixture()
        defer { fixture.remove() }
        let future = [RateInput(fixture.now.addingTimeInterval(20), used: 10),
            RateInput(fixture.now.addingTimeInterval(40), used: 20, reset: fixture.now.addingTimeInterval(604_900))]
        try fixture.write("main", rows: future)
        #expect(fixture.reader().snapshot(now: fixture.now) == fixture.reader(cached: false).snapshot(now: fixture.now))
        #expect(try fixture.cachedRateCount() == 2)
        for offset in [25.0, 45.0] {
            let later = fixture.now.addingTimeInterval(offset)
            let snapshot = fixture.reader().snapshot(now: later)
            #expect(snapshot == fixture.reader(cached: false).snapshot(now: later))
            #expect(snapshot.rateLimits?.consumptionSamples?.last?.usedPercent == (offset == 25 ? 10 : 20))
        }
    }

    @Test("Unknown durations retain nil history witnesses without inventing current windows")
    func unknownDurationsAndMissingWindows() throws {
        let fixture = try RateFixture()
        defer { fixture.remove() }
        try fixture.write("main", rows: [RateInput(fixture.now.addingTimeInterval(-7_000), used: 10, window: -5),
            RateInput(fixture.now.addingTimeInterval(-6_900), used: 20, window: 60),
            RateInput(fixture.now.addingTimeInterval(-3_000), used: 30, window: 0)])
        _ = fixture.reader().snapshot(now: fixture.now)
        let snapshot = fixture.reader().snapshot(now: fixture.now)
        #expect(snapshot == fixture.reader(cached: false).snapshot(now: fixture.now))
        #expect(snapshot.rateLimits?.fiveHour == nil)
        #expect(snapshot.rateLimits?.weekly == nil)
        #expect(snapshot.rateLimits?.history.isEmpty == false)
        #expect(snapshot.rateLimits?.history.allSatisfy { $0.fiveHourUsedPercent == nil && $0.weeklyUsedPercent == nil } == true)
        #expect(snapshot.rateLimits?.consumptionSamples?.isEmpty == true)
    }

    @Test("Per-file winners preserve equal timestamps, different resets, and deletion fallback")
    func crossFileTiesAndDeletion() throws {
        let fixture = try RateFixture()
        defer { fixture.remove() }
        let tie = fixture.now.addingTimeInterval(-100)
        try fixture.write("first", rows: [RateInput(tie, used: 10),
            RateInput(tie, used: 20, reset: fixture.now.addingTimeInterval(604_900))])
        try fixture.write("second", rows: [RateInput(tie, used: 30),
            RateInput(tie, used: 40, reset: fixture.now.addingTimeInterval(605_000))])
        _ = fixture.reader().snapshot(now: fixture.now)
        #expect(fixture.reader().snapshot(now: fixture.now) == fixture.reader(cached: false).snapshot(now: fixture.now))
        try FileManager.default.removeItem(at: fixture.sessions.appendingPathComponent("second.jsonl"))
        let remaining = fixture.reader().snapshot(now: fixture.now)
        #expect(remaining == fixture.reader(cached: false).snapshot(now: fixture.now))
        #expect(remaining.rateLimits?.weekly?.usedPercent == 20)
        #expect(remaining.rateLimits?.weekly?.resetsAt == fixture.now.addingTimeInterval(604_900))
    }

    @Test("Schema six migrates as unpruned data; schema seven requires complete context", arguments: ["schema6", "calendar", "pruningAnchor"])
    func cacheMigrationAndMissingContext(mode: String) throws {
        let fixture = try RateFixture()
        defer { fixture.remove() }
        try fixture.write("main", rows: [RateInput(fixture.now.addingTimeInterval(-60), used: 20)])
        _ = fixture.reader().snapshot(now: fixture.now)
        try fixture.editCache { cache in
            if mode == "schema6" {
                cache["schemaVersion"] = 6
                cache.removeValue(forKey: "calendar")
                cache.removeValue(forKey: "pruningAnchor")
            } else {
                cache.removeValue(forKey: mode)
                var entries = cache["entries"] as! [String: [String: Any]]
                for path in Array(entries.keys) {
                    var entry = entries[path]!
                    var parsed = entry["parsedFile"] as! [String: Any]
                    var rates = parsed["rateLimits"] as! [[String: Any]]
                    rates[0]["usedPercent"] = 99.0
                    parsed["rateLimits"] = rates
                    entry["parsedFile"] = parsed
                    entries[path] = entry
                }
                cache["entries"] = entries
            }
        }
        #expect(fixture.reader().snapshot(now: fixture.now) == fixture.reader(cached: false).snapshot(now: fixture.now))
        let context = try PropertyListDecoder().decode(CacheContext.self, from: Data(contentsOf: fixture.cache))
        #expect(context.schemaVersion == 7)
        #expect(context.calendar == fixture.calendar)
        #expect(context.pruningAnchor == fixture.now)
    }
}

private struct CacheContext: Decodable {
    var schemaVersion: Int
    var calendar: Calendar?
    var pruningAnchor: Date?
}

private struct RateInput {
    var date: Date
    var used: Double
    var window: Int
    var reset: Date?

    init(_ date: Date, used: Double, window: Int = 10_080, reset: Date? = nil) {
        self.date = date
        self.used = used
        self.window = window
        self.reset = reset
    }
}

private struct RateFixture {
    let directory: URL
    let sessions: URL
    let archived: URL
    let cache: URL
    let calendar: Calendar
    let now: Date

    init(now: Date = Date(timeIntervalSince1970: 1_800_001_800)) throws {
        self.now = now
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        sessions = directory.appendingPathComponent("sessions")
        archived = directory.appendingPathComponent("archived")
        cache = directory.appendingPathComponent("reader-cache.plist")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        self.calendar = calendar
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: archived, withIntermediateDirectories: true)
    }

    func remove() { try? FileManager.default.removeItem(at: directory) }

    func reader(cached: Bool = true, calendar: Calendar? = nil) -> CodexUsageReader {
        CodexUsageReader(sessionsDirectory: sessions, calendar: calendar ?? self.calendar,
            cacheURL: cached ? cache : nil, archivedSessionsDirectory: archived)
    }

    func write(_ name: String, rows: [RateInput]) throws {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let started = now.addingTimeInterval(-7_200 + Double(name.utf8.reduce(0) { $0 + Int($1) }))
        let usage = ["input_tokens": 100, "cached_input_tokens": 0, "output_tokens": 0, "reasoning_output_tokens": 0, "total_tokens": 100]
        var objects: [[String: Any]] = [
            ["type": "session_meta", "payload": ["id": name, "timestamp": formatter.string(from: started)]],
            ["type": "turn_context", "timestamp": formatter.string(from: started), "payload": ["model": "gpt-6.1-sol"]],
            ["type": "event_msg", "timestamp": formatter.string(from: started), "payload": ["type": "token_count", "info": ["total_token_usage": usage, "last_token_usage": usage]]]
        ]
        objects += rows.map { row in
            ["type": "event_msg", "timestamp": formatter.string(from: row.date), "payload": [
                "type": "token_count", "rate_limits": ["primary": ["window_minutes": row.window,
                    "used_percent": row.used, "resets_at": (row.reset ?? now.addingTimeInterval(604_800)).timeIntervalSince1970]]]]
        }
        let lines = try objects.map { String(decoding: try JSONSerialization.data(withJSONObject: $0, options: [.sortedKeys]), as: UTF8.self) }
        try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: sessions.appendingPathComponent(name + ".jsonl"))
    }

    func cachedRateCount() throws -> Int {
        let object = try PropertyListSerialization.propertyList(from: Data(contentsOf: cache), format: nil) as! [String: Any]
        let entries = object["entries"] as! [String: [String: Any]]
        return entries.values.reduce(0) { total, entry in
            total + ((entry["parsedFile"] as? [String: Any])?["rateLimits"] as? [[String: Any]] ?? []).count
        }
    }

    func editCache(_ edit: (inout [String: Any]) -> Void) throws {
        var object = try PropertyListSerialization.propertyList(from: Data(contentsOf: cache), format: nil) as! [String: Any]
        edit(&object)
        try PropertyListSerialization.data(fromPropertyList: object, format: .binary, options: 0).write(to: cache)
    }
}
