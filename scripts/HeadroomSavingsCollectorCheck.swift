import Foundation

@main
struct HeadroomSavingsCollectorCheck {
    static func main() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("headroom-savings-collector-check-\(UUID().uuidString)")
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        let executable = root.appendingPathComponent("headroom-fixture")
        let ledger = root.appendingPathComponent("savings_events.jsonl")
        try writeFixtureExecutable(at: executable)
        try writeFixtureLedger(at: ledger)

        var calendar = Calendar(identifier: .gregorian)
        guard let vancouver = TimeZone(identifier: "America/Vancouver") else {
            throw CheckFailure("America/Vancouver time zone is unavailable")
        }
        calendar.timeZone = vancouver

        let now = try date("2026-07-09T12:00:00.000Z")
        let firstCodexEvent = try date("2026-07-08T06:30:00.000Z")
        let lastCodexEvent = try date("2026-07-09T11:00:00.000Z")
        let collector = HeadroomSavingsCollector(
            executableURL: executable,
            ledgerURL: ledger,
            calendar: calendar,
            timeout: 2
        )
        let initialFingerprint = collector.sourceFingerprint()

        let activity = try require(collector.collect(now: now), "collector unexpectedly reported unavailable")
        let savings = activity.savings

        try expectEqual(savings.lifetimeTokensSaved, 100, "Codex lifetime tokens saved")
        try expectEqual(savings.todayTokensSaved, 50, "Codex tokens saved today")
        try expectEqual(savings.last7DaysTokensSaved, 100, "Codex tokens saved in the last seven days")
        try expectEqual(savings.inputTokensBeforeCompression, 600, "Codex tokens before compression")
        try expectEqual(savings.lifetimeRequests, 3, "Codex lifetime compression events")
        try expectEqual(savings.todayRequests, 1, "Codex compression events today")
        try expectNear(savings.costSavedUSD, 0.00030, tolerance: 0.000000001, "Codex lifetime cost avoided")
        try expectNear(savings.todayCostSavedUSD, 0.00015, tolerance: 0.000000001, "Codex cost avoided today")

        let exactPercent = 100 * Double(100) / Double(600)
        try expectNear(savings.savingsPercent, exactPercent, tolerance: 0.000000000001, "exact Codex savings percent")
        try expect(abs(savings.savingsPercent - 16.7) > 0.01, "collector reused a rounded report percentage")
        try expectEqual(savings.trackingStartedAt, Optional(firstCodexEvent), "Codex tracking start timestamp")
        try expectEqual(savings.lastUpdated, Optional(lastCodexEvent), "Codex last-updated timestamp")
        try expectEqual(savings.topModel, Optional("gpt-5.5"), "top Codex model")
        try expectEqual(savings.schemaVersion, Optional(1), "Headroom schema version")

        let firstDay = calendar.startOfDay(for: firstCodexEvent)
        let secondDay = calendar.startOfDay(for: try date("2026-07-08T07:30:00.000Z"))
        let thirdDay = calendar.startOfDay(for: lastCodexEvent)
        try expectEqual(activity.tokensSavedByDay.count, 3, "number of local Headroom activity days")
        try expectEqual(activity.tokensSavedByDay[firstDay], Optional(20), "first local day's Codex savings")
        try expectEqual(activity.tokensSavedByDay[secondDay], Optional(30), "second local day's Codex savings")
        try expectEqual(activity.tokensSavedByDay[thirdDay], Optional(50), "third local day's Codex savings")
        try expectEqual(activity.tokensSavedByDay.values.reduce(0, +), 100, "daily Codex-only savings total")

        let ledgerHandle = try FileHandle(forWritingTo: ledger)
        try ledgerHandle.seekToEnd()
        try ledgerHandle.write(contentsOf: Data("\n".utf8))
        try ledgerHandle.close()
        try expect(
            collector.sourceFingerprint() != initialFingerprint,
            "Headroom ledger changes should invalidate the refresh fingerprint"
        )

        let missingExecutable = root.appendingPathComponent("missing-headroom")
        let unavailableExecutableCollector = HeadroomSavingsCollector(
            executableURL: missingExecutable,
            ledgerURL: ledger,
            calendar: calendar,
            timeout: 2
        )
        try expect(
            unavailableExecutableCollector.collect(now: now) == nil,
            "collector should be unavailable when the Headroom executable is missing"
        )

        let missingLedger = root.appendingPathComponent("missing-savings-events.jsonl")
        let unavailableLedgerCollector = HeadroomSavingsCollector(
            executableURL: executable,
            ledgerURL: missingLedger,
            calendar: calendar,
            timeout: 2
        )
        try expect(
            unavailableLedgerCollector.collect(now: now) == nil,
            "collector should be unavailable when the Headroom ledger is missing"
        )

        print("HeadroomSavingsCollectorCheck passed")
    }

    private static func writeFixtureExecutable(at url: URL) throws {
        let report = """
        {
          "schema_version": 1,
          "path": "/tmp/headroom-fixture/savings_events.jsonl",
          "top_model": "other-model",
          "lifetime": {
            "tokens_saved": 1000,
            "tokens_before": 1600,
            "cost_usd": 0.003,
            "calls": 4,
            "savings_percent": 62.5
          },
          "windows": {
            "today": {
              "tokens_saved": 950,
              "tokens_before": 1300,
              "cost_usd": 0.00285,
              "calls": 2,
              "savings_percent": 73.1
            },
            "last_7_days": {
              "tokens_saved": 1000,
              "tokens_before": 1600,
              "cost_usd": 0.003,
              "calls": 4,
              "savings_percent": 62.5
            },
            "all_time": {
              "tokens_saved": 1000,
              "tokens_before": 1600,
              "cost_usd": 0.003,
              "calls": 4,
              "savings_percent": 62.5
            }
          },
          "by_model": [
            {
              "model": "other-model",
              "tokens_saved": 900,
              "tokens_before": 1000,
              "cost_usd": 0.0027,
              "calls": 1,
              "savings_percent": 90.0
            },
            {
              "model": "gpt-5.5",
              "tokens_saved": 80,
              "tokens_before": 500,
              "cost_usd": 0.00024,
              "calls": 2,
              "savings_percent": 16.0
            }
          ],
          "by_client": [
            {
              "client": "codex",
              "tokens_saved": 100,
              "tokens_before": 600,
              "cost_usd": 0.0003,
              "calls": 3,
              "savings_percent": 16.7
            },
            {
              "client": "other-client",
              "tokens_saved": 900,
              "tokens_before": 1000,
              "cost_usd": 0.0027,
              "calls": 1,
              "savings_percent": 90.0
            }
          ]
        }
        """
        let script = """
        #!/bin/sh
        if [ "$1" != "savings" ] || [ "$2" != "--json" ]; then
          exit 64
        fi
        /bin/cat <<'HEADROOM_JSON'
        \(report)
        HEADROOM_JSON
        """
        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    private static func writeFixtureLedger(at url: URL) throws {
        let rows = [
            #"{"v":1,"ts":"2026-07-08T06:30:00.000Z","before":100,"after":80,"saved":20,"cost_usd":0.00006,"model":"gpt-5.4","client":"Codex","source":"proxy","pid":101}"#,
            #"{"v":1,"ts":"2026-07-08T07:30:00.000Z","before":200,"after":170,"saved":30,"cost_usd":0.00009,"model":"gpt-5.5","client":"CODEX","source":"proxy","pid":101}"#,
            #"{"v":1,"ts":"2026-07-09T11:00:00.000Z","before":300,"after":250,"saved":50,"cost_usd":0.00015,"model":"gpt-5.5","client":"codex","source":"proxy","pid":101}"#,
            #"{"v":1,"ts":"2026-07-09T11:30:00.000Z","before":1000,"after":100,"saved":900,"cost_usd":0.0027,"model":"other-model","client":"other-client","source":"proxy","pid":202}"#,
            "{\"v\":1,\"ts\":\""
        ]
        try rows.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    private static func date(_ value: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return try require(formatter.date(from: value), "invalid fixture date: \(value)")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw CheckFailure(message) }
    }

    private static func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ label: String) throws {
        guard actual == expected else {
            throw CheckFailure("\(label): expected \(expected), got \(actual)")
        }
    }

    private static func expectNear(_ actual: Double, _ expected: Double, tolerance: Double, _ label: String) throws {
        guard abs(actual - expected) <= tolerance else {
            throw CheckFailure("\(label): expected \(expected), got \(actual)")
        }
    }

    private static func require<T>(_ value: T?, _ message: String) throws -> T {
        guard let value else { throw CheckFailure(message) }
        return value
    }
}

private struct CheckFailure: Error, CustomStringConvertible {
    var message: String

    init(_ message: String) {
        self.message = message
    }

    var description: String { message }
}
