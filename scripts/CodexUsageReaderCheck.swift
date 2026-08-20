import Foundation

@main
struct CodexUsageReaderCheck {
    private struct CheckFailure: Error, CustomStringConvertible {
        let message: String

        var description: String { message }
    }

    static func main() throws {
        let arguments = Set(CommandLine.arguments.dropFirst())
        let unknownArguments = arguments.subtracting(["--live"])
        try expect(unknownArguments.isEmpty, "unknown arguments: \(unknownArguments.sorted().joined(separator: ", "))")

        try testCrossMidnightAttributionAndContext()
        try testUnchangedCumulativeSnapshotIsIgnored()
        try testCumulativeResetUsesLastTokenUsage()
        try testExactReplayCloneIsIgnored()
        try testPrefixContinuationCountsOnlyNewUsage()
        try testSubagentUsageIsExcludedFromProfileTotals()
        try testMalformedTrailingRowAndNullInfoAreIgnored()
        try testFutureDatedModelsDoNotAffectPeriodLeaders()
        try testModelAwarePricingAndUnpricedUsage()
        try testLegacySnapshotDecodesWithoutNewFields()

        print("CodexUsageReaderCheck passed (10 deterministic scenarios)")

        if arguments.contains("--live") {
            printLiveSnapshot()
        }
    }

    private static func testCrossMidnightAttributionAndContext() throws {
        try withFixture(named: "cross-midnight") { root in
            let first = usage(input: 80, cached: 40, output: 20, reasoning: 5, total: 100)
            let cumulative = usage(input: 130, cached: 60, output: 30, reasoning: 7, total: 160)
            let last = usage(input: 50, cached: 20, output: 10, reasoning: 2, total: 60)

            try writeRollout(
                root: root,
                path: "2026/07/03/rollout-cross-midnight.jsonl",
                rows: [
                    try sessionMeta("2026-07-03T23:50:00.000Z", id: "cross-midnight"),
                    try tokenRow("2026-07-03T23:55:00.000Z", cumulative: first, last: first, contextWindow: 200),
                    try tokenRow("2026-07-04T00:05:00.000Z", cumulative: cumulative, last: last, contextWindow: 256)
                ]
            )

            let snapshot = try makeSnapshot(root: root, now: "2026-07-04T12:00:00.000Z", activityDayCount: 2)
            try expectEqual(snapshot.lifetime, cumulative, "cross-midnight lifetime")
            try expectEqual(snapshot.today, last, "cross-midnight today")
            try expectEqual(snapshot.activityDays.map(\.usage.total), [100, 60], "cross-midnight daily totals")
            try expectEqual(snapshot.activityDays.map(\.sessions), [1, 1], "cross-midnight active sessions")
            try expectEqual(snapshot.activityDays.map { $0.turns ?? -1 }, [1, 1], "cross-midnight daily turns")
            try expectEqual(snapshot.turnCount, 2, "cross-midnight turn count")
            try expectEqual(snapshot.sessionCount, 1, "cross-midnight session count")
            try expectEqual(snapshot.currentSession.total, 160, "cross-midnight current session")
            try expectEqual(snapshot.currentContextTokens, 50, "latest context tokens")
            try expectEqual(snapshot.contextWindow, 256, "latest context window")
            try expectEqual(
                snapshot.currentSessionStartedAt,
                try date("2026-07-03T23:50:00.000Z"),
                "session start from metadata"
            )
        }
    }

    private static func testUnchangedCumulativeSnapshotIsIgnored() throws {
        try withFixture(named: "unchanged-cumulative") { root in
            let first = usage(input: 90, output: 10, total: 100)
            let cumulative = usage(input: 140, output: 20, total: 160)
            let last = usage(input: 50, output: 10, total: 60)

            try writeRollout(
                root: root,
                path: "2026/07/04/rollout-duplicate.jsonl",
                rows: [
                    try sessionMeta("2026-07-04T08:00:00.000Z", id: "duplicate"),
                    try tokenRow("2026-07-04T08:01:00.000Z", cumulative: first, last: first),
                    try tokenRow("2026-07-04T08:02:00.000Z", cumulative: first, last: first),
                    try tokenRow("2026-07-04T08:03:00.000Z", cumulative: cumulative, last: last)
                ]
            )

            let snapshot = try makeSnapshot(root: root, now: "2026-07-04T12:00:00.000Z")
            try expectEqual(snapshot.lifetime.total, 160, "unchanged cumulative lifetime")
            try expectEqual(snapshot.turnCount, 2, "unchanged cumulative turn count")
            try expectEqual(snapshot.currentSessionTurns, 2, "unchanged cumulative current-session turns")
            try expectEqual(snapshot.today.total, 160, "unchanged cumulative today")
        }
    }

    private static func testCumulativeResetUsesLastTokenUsage() throws {
        try withFixture(named: "cumulative-reset") { root in
            let first = usage(input: 90, output: 10, total: 100)
            let reset = usage(input: 55, output: 5, total: 60)
            let afterReset = usage(input: 80, output: 10, total: 90)
            let lastAfterReset = usage(input: 25, output: 5, total: 30)

            try writeRollout(
                root: root,
                path: "2026/07/04/rollout-reset.jsonl",
                rows: [
                    try sessionMeta("2026-07-04T09:00:00.000Z", id: "reset"),
                    try tokenRow("2026-07-04T09:01:00.000Z", cumulative: first, last: first),
                    try tokenRow("2026-07-04T09:02:00.000Z", cumulative: reset, last: reset),
                    try tokenRow("2026-07-04T09:03:00.000Z", cumulative: afterReset, last: lastAfterReset)
                ]
            )

            let snapshot = try makeSnapshot(root: root, now: "2026-07-04T12:00:00.000Z")
            try expectEqual(snapshot.lifetime.total, 190, "reset lifetime")
            try expectEqual(snapshot.lifetime.input, 170, "reset input")
            try expectEqual(snapshot.lifetime.output, 20, "reset output")
            try expectEqual(snapshot.turnCount, 3, "reset turn count")
            try expectEqual(snapshot.currentSession.total, 190, "reset current session")
        }
    }

    private static func testExactReplayCloneIsIgnored() throws {
        try withFixture(named: "exact-replay") { root in
            let first = usage(input: 90, output: 10, total: 100)
            let cumulative = usage(input: 140, output: 20, total: 160)
            let last = usage(input: 50, output: 10, total: 60)

            try writeRollout(
                root: root,
                path: "2026/07/03/rollout-ancestor.jsonl",
                rows: [
                    try sessionMeta("2026-07-03T10:00:00.000Z", id: "ancestor"),
                    try tokenRow("2026-07-03T10:01:00.000Z", cumulative: first, last: first),
                    try tokenRow("2026-07-03T10:02:00.000Z", cumulative: cumulative, last: last)
                ]
            )
            try writeRollout(
                root: root,
                path: "2026/07/04/rollout-replay.jsonl",
                rows: [
                    try sessionMeta("2026-07-04T10:00:00.000Z", id: "replay"),
                    try sessionMeta("2026-07-03T10:00:00.000Z", id: "ancestor"),
                    try tokenRow("2026-07-04T10:00:01.000Z", cumulative: first, last: first),
                    try tokenRow("2026-07-04T10:00:02.000Z", cumulative: cumulative, last: last)
                ]
            )

            let snapshot = try makeSnapshot(root: root, now: "2026-07-04T12:00:00.000Z", activityDayCount: 2)
            try expectEqual(snapshot.lifetime.total, 160, "exact replay lifetime")
            try expectEqual(snapshot.sessionCount, 1, "exact replay canonical sessions")
            try expectEqual(snapshot.turnCount, 2, "exact replay canonical turns")
            try expectEqual(snapshot.activityDays.map(\.usage.total), [160, 0], "exact replay daily totals")
            try expectEqual(snapshot.today.total, 0, "exact replay does not move usage to replay day")
        }
    }

    private static func testPrefixContinuationCountsOnlyNewUsage() throws {
        try withFixture(named: "prefix-continuation") { root in
            let first = usage(input: 90, output: 10, total: 100)
            let second = usage(input: 140, output: 20, total: 160)
            let secondLast = usage(input: 50, output: 10, total: 60)
            let third = usage(input: 190, output: 30, total: 220)
            let thirdLast = usage(input: 50, output: 10, total: 60)

            try writeRollout(
                root: root,
                path: "2026/07/03/rollout-prefix-ancestor.jsonl",
                rows: [
                    try sessionMeta("2026-07-03T11:00:00.000Z", id: "prefix-ancestor"),
                    try tokenRow("2026-07-03T11:01:00.000Z", cumulative: first, last: first),
                    try tokenRow("2026-07-03T11:02:00.000Z", cumulative: second, last: secondLast)
                ]
            )
            try writeRollout(
                root: root,
                path: "2026/07/04/rollout-prefix-child.jsonl",
                rows: [
                    try sessionMeta("2026-07-04T11:00:00.000Z", id: "prefix-child"),
                    try sessionMeta("2026-07-03T11:00:00.000Z", id: "prefix-ancestor"),
                    try tokenRow("2026-07-04T11:00:01.000Z", cumulative: first, last: first),
                    try tokenRow("2026-07-04T11:00:02.000Z", cumulative: second, last: secondLast),
                    try tokenRow("2026-07-04T11:01:00.000Z", cumulative: third, last: thirdLast)
                ]
            )

            let snapshot = try makeSnapshot(root: root, now: "2026-07-04T12:00:00.000Z", activityDayCount: 2)
            try expectEqual(snapshot.lifetime.total, 220, "prefix continuation lifetime")
            try expectEqual(snapshot.sessionCount, 1, "prefix continuation grouped session")
            try expectEqual(snapshot.turnCount, 3, "prefix continuation turns")
            try expectEqual(snapshot.currentSession.total, 220, "prefix continuation current session")
            try expectEqual(snapshot.activityDays.map(\.usage.total), [160, 60], "prefix continuation daily totals")
            try expectEqual(snapshot.activityDays.map(\.sessions), [1, 1], "prefix continuation active sessions")
        }
    }

    private static func testSubagentUsageIsExcludedFromProfileTotals() throws {
        try withFixture(named: "subagent-session-id") { root in
            let parentUsage = usage(input: 90, output: 10, total: 100)
            let childUsage = usage(input: 35, output: 5, total: 40)
            let fallbackUsage = usage(input: 25, output: 5, total: 30)

            try writeRollout(
                root: root,
                path: "2026/07/04/rollout-parent.jsonl",
                rows: [
                    try sessionMeta(
                        "2026-07-04T13:00:00.000Z",
                        id: "parent-file",
                        sessionID: "shared-session"
                    ),
                    try tokenRow("2026-07-04T13:01:00.000Z", cumulative: parentUsage, last: parentUsage)
                ]
            )
            try writeRollout(
                root: root,
                path: "2026/07/04/rollout-child.jsonl",
                rows: [
                    try sessionMeta(
                        "2026-07-04T13:02:00.000Z",
                        id: "child-file",
                        sessionID: "shared-session",
                        threadSource: "subagent",
                        parentThreadID: "shared-session"
                    ),
                    try tokenRow("2026-07-04T13:03:00.000Z", cumulative: childUsage, last: childUsage)
                ]
            )
            try writeRollout(
                root: root,
                path: "2026/07/04/rollout-child-fallback.jsonl",
                rows: [
                    try sessionMeta(
                        "2026-07-04T13:04:00.000Z",
                        id: "child-fallback",
                        threadSource: "subagent",
                        parentThreadID: "shared-session"
                    ),
                    try tokenRow("2026-07-04T13:05:00.000Z", cumulative: fallbackUsage, last: fallbackUsage)
                ]
            )

            let snapshot = try makeSnapshot(root: root, now: "2026-07-04T14:00:00.000Z")
            try expectEqual(snapshot.lifetime.total, 100, "profile-compatible lifetime")
            try expectEqual(snapshot.sessionCount, 1, "primary session count")
            try expectEqual(snapshot.turnCount, 1, "primary turn count")
            try expectEqual(snapshot.todaySessionCount, 1, "primary daily session count")
            try expectEqual(snapshot.currentSession.total, 100, "primary current session")
        }
    }

    private static func testMalformedTrailingRowAndNullInfoAreIgnored() throws {
        try withFixture(named: "malformed-null") { root in
            let valid = usage(input: 45, output: 5, total: 50)

            try writeRollout(
                root: root,
                path: "2026/07/04/rollout-malformed.jsonl",
                rows: [
                    try sessionMeta("2026-07-04T15:00:00.000Z", id: "malformed"),
                    try tokenRow("2026-07-04T15:01:00.000Z", cumulative: valid, last: valid),
                    try nullInfoRow("2026-07-04T15:02:00.000Z")
                ],
                trailingRow: "{\"timestamp\":\"2026-07-04T15:03:00.000Z\",\"type\":\"event_msg\""
            )

            let snapshot = try makeSnapshot(root: root, now: "2026-07-04T16:00:00.000Z")
            try expectEqual(snapshot.lifetime.total, 50, "malformed/null lifetime")
            try expectEqual(snapshot.turnCount, 1, "malformed/null turns")
            try expectEqual(snapshot.sessionCount, 1, "malformed/null sessions")
            try expectEqual(snapshot.lastUpdated, try date("2026-07-04T15:01:00.000Z"), "malformed/null last update")
        }
    }

    private static func testFutureDatedModelsDoNotAffectPeriodLeaders() throws {
        try withFixture(named: "future-model") { root in
            let sample = usage(input: 200_000, total: 200_000)
            var current = sample
            current.add(sample)
            let future = usage(input: 1_000_000, total: 1_000_000)
            var cumulative = current
            cumulative.add(future)

            try writeRollout(
                root: root,
                path: "2026/07/04/rollout-future-model.jsonl",
                rows: [
                    try sessionMeta("2026-07-04T09:00:00.000Z", id: "future-model"),
                    try turnContext("2026-07-04T09:00:01.000Z", model: "gpt-5.6-sol"),
                    try tokenRow("2026-07-04T09:01:00.000Z", cumulative: sample, last: sample),
                    try tokenRow("2026-07-04T10:01:00.000Z", cumulative: current, last: sample),
                    try turnContext("2026-07-05T09:00:01.000Z", model: "future-model"),
                    try tokenRow("2026-07-05T09:01:00.000Z", cumulative: cumulative, last: future)
                ]
            )

            let snapshot = try makeSnapshot(root: root, now: "2026-07-04T12:00:00.000Z")
            try expectEqual(snapshot.topModelToday, Optional("gpt-5.6-sol"), "future-safe today model")
            try expectEqual(snapshot.topModelLast7Days, Optional("gpt-5.6-sol"), "future-safe seven-day model")
            try expectEqual(snapshot.topModelThisMonth, Optional("gpt-5.6-sol"), "future-safe month model")

            let today = try date("2026-07-04T00:00:00.000Z")
            guard let dailyModel = snapshot.dailyModelUsage
                .first(where: { $0.date == today })?
                .models.first(where: { $0.model == "gpt-5.6-sol" }),
                let pricing = ModelPricingCatalog.pricing(for: dailyModel.model)
            else {
                throw CheckFailure(message: "missing current daily model pricing fixture")
            }
            try expectNear(dailyModel.estimatedCostUSD, 2, tolerance: 0.000_001, "per-sample daily model cost")
            try expectNear(pricing.estimatedCost(for: dailyModel.usage), 4, tolerance: 0.000_001, "aggregate repricing")
        }
    }

    private static func testModelAwarePricingAndUnpricedUsage() throws {
        try withFixture(named: "model-pricing") { root in
            let sol = usage(input: 100_000, cached: 40_000, output: 10_000, reasoning: 3_000, total: 110_000)
            let terra = usage(input: 300_000, cached: 100_000, output: 20_000, reasoning: 7_000, total: 320_000)
            let unpriced = usage(input: 10_000, output: 1_000, total: 11_000)
            var cumulative = TokenUsage.zero
            cumulative.add(sol)
            let afterSol = cumulative
            cumulative.add(terra)
            let afterTerra = cumulative
            cumulative.add(unpriced)

            try writeRollout(
                root: root,
                path: "2026/07/04/rollout-model-pricing.jsonl",
                rows: [
                    try sessionMeta("2026-07-04T17:00:00.000Z", id: "model-pricing"),
                    try turnContext("2026-07-04T17:00:01.000Z", model: "gpt-5.6-sol"),
                    try tokenRow("2026-07-04T17:01:00.000Z", cumulative: afterSol, last: sol),
                    try turnContext("2026-07-04T17:01:01.000Z", model: "gpt-5.6-terra"),
                    try tokenRow("2026-07-04T17:02:00.000Z", cumulative: afterTerra, last: terra),
                    try turnContext("2026-07-04T17:02:01.000Z", model: "gpt-5.3-codex"),
                    try tokenRow("2026-07-04T17:03:00.000Z", cumulative: cumulative, last: unpriced)
                ]
            )

            let snapshot = try makeSnapshot(root: root, now: "2026-07-04T18:00:00.000Z")
            try expectEqual(snapshot.currentModel, Optional("gpt-5.3-codex"), "latest model")
            try expectEqual(snapshot.unpricedTokens, Optional(11_000), "unpriced model tokens")
            try expectEqual(snapshot.modelUsage?.count, Optional(3), "model aggregate count")
            try expectEqual(snapshot.modelUsage?.first { $0.model == "gpt-5.6-sol" }?.turns, Optional(1), "Sol turns")
            try expectEqual(snapshot.modelUsage?.first { $0.model == "gpt-5.6-terra" }?.usage, Optional(terra), "Terra usage")

            // Sol short context: 60k uncached × $5 + 40k cached × $0.50 + 10k output × $30 = $0.62.
            // Terra long context: 200k uncached × $5 + 100k cached × $0.50 + 20k output × $22.50 = $1.50.
            // Reasoning is already included in output and must not be added a second time.
            try expectNear(snapshot.estimatedCostUSD, 2.12, tolerance: 0.000_000_1, "model-aware estimated cost")
            try expectNear(snapshot.todayEstimatedCostUSD, 2.12, tolerance: 0.000_000_1, "daily estimated cost")
            try expectEqual(snapshot.activityDays.last?.estimatedCostMicros, Optional(2_120_000), "daily cost micros")
            try expectEqual(snapshot.pricingVersion, Optional(ModelPricingCatalog.version), "pricing provenance")
        }
    }

    private static func testLegacySnapshotDecodesWithoutNewFields() throws {
        let timestamp = try date("2026-07-04T16:00:00.000Z")
        let legacyUsage: [String: Any] = [
            "input": 10,
            "cachedInput": 4,
            "output": 2,
            "reasoningOutput": 1,
            "total": 12
        ]
        let legacySnapshot: [String: Any] = [
            "currentSession": legacyUsage,
            "lifetime": legacyUsage,
            "today": legacyUsage,
            "peakDay": [
                "date": timestamp.timeIntervalSinceReferenceDate,
                "usage": legacyUsage,
                "sessions": 1
            ],
            "currentStreak": 1,
            "longestStreak": 2,
            "lastUpdated": timestamp.timeIntervalSinceReferenceDate,
            "activityDays": [[
                "date": timestamp.timeIntervalSinceReferenceDate,
                "usage": legacyUsage,
                "sessions": 1
            ]]
        ]

        let data = try JSONSerialization.data(withJSONObject: legacySnapshot, options: [.sortedKeys])
        let decoded = try JSONDecoder().decode(CodexUsageSnapshot.self, from: data)
        try expectEqual(decoded.lifetime.total, 12, "legacy lifetime")
        try expectEqual(decoded.activityDays.first?.turns, nil, "legacy daily turns default")
        try expectEqual(decoded.activityDays.first?.headroomSaved, nil, "legacy daily Headroom default")
        try expectEqual(decoded.generatedAt, nil, "legacy generatedAt default")
        try expectEqual(decoded.sessionCount, nil, "legacy sessionCount default")
        try expectEqual(decoded.turnCount, nil, "legacy turnCount default")
        try expectEqual(decoded.currentSessionTurns, nil, "legacy currentSessionTurns default")
        try expectEqual(decoded.currentContextTokens, nil, "legacy context tokens default")
        try expectEqual(decoded.contextWindow, nil, "legacy context window default")
        try expectEqual(decoded.headroom, nil, "legacy Headroom default")
        try expectEqual(decoded.modelUsage, nil, "legacy model usage default")
        try expectEqual(decoded.currentModel, nil, "legacy current model default")
        try expectEqual(decoded.unpricedTokens, nil, "legacy unpriced tokens default")
        try expectEqual(decoded.pricingVersion, nil, "legacy pricing version default")
    }

    private static func printLiveSnapshot() {
        let snapshot = CodexUsageReader().snapshot()
        let updated = snapshot.lastUpdated.map { ISO8601DateFormatter.codex.string(from: $0) } ?? "none"
        print(
            "live lifetime=\(snapshot.lifetime.total) "
                + "today=\(snapshot.today.total) "
                + "canonicalSessions=\(snapshot.sessionCount ?? 0) "
                + "turns=\(snapshot.turnCount ?? 0) "
                + "current=\(snapshot.currentSession.total) "
                + "currentTurns=\(snapshot.currentSessionTurns ?? 0) "
                + "lastUpdated=\(updated)"
        )
    }

    private static func withFixture(named name: String, _ body: (URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-usage-reader-check-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(root)
    }

    private static func makeSnapshot(
        root: URL,
        now: String,
        activityDayCount: Int = 1
    ) throws -> CodexUsageSnapshot {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return CodexUsageReader(
            sessionsDirectory: root,
            calendar: calendar,
            activityDayCount: activityDayCount
        ).snapshot(now: try date(now))
    }

    private static func writeRollout(
        root: URL,
        path: String,
        rows: [String],
        trailingRow: String? = nil
    ) throws {
        let file = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        var contents = rows.joined(separator: "\n")
        if let trailingRow {
            contents += "\n\(trailingRow)"
        }
        try contents.write(to: file, atomically: true, encoding: .utf8)
    }

    private static func sessionMeta(
        _ timestamp: String,
        id: String,
        sessionID: String? = nil,
        threadSource: String? = nil,
        parentThreadID: String? = nil
    ) throws -> String {
        var payload: [String: Any] = [
            "id": id,
            "timestamp": timestamp
        ]
        if let sessionID { payload["session_id"] = sessionID }
        if let threadSource { payload["thread_source"] = threadSource }
        if let parentThreadID { payload["parent_thread_id"] = parentThreadID }
        return try jsonRow(timestamp: timestamp, type: "session_meta", payload: payload)
    }

    private static func tokenRow(
        _ timestamp: String,
        cumulative: TokenUsage,
        last: TokenUsage? = nil,
        contextWindow: Int? = nil
    ) throws -> String {
        var info: [String: Any] = ["total_token_usage": logDictionary(cumulative)]
        if let last { info["last_token_usage"] = logDictionary(last) }
        if let contextWindow { info["model_context_window"] = contextWindow }
        return try jsonRow(
            timestamp: timestamp,
            type: "event_msg",
            payload: ["type": "token_count", "info": info]
        )
    }

    private static func turnContext(_ timestamp: String, model: String) throws -> String {
        try jsonRow(
            timestamp: timestamp,
            type: "turn_context",
            payload: ["model": model]
        )
    }

    private static func nullInfoRow(_ timestamp: String) throws -> String {
        try jsonRow(
            timestamp: timestamp,
            type: "event_msg",
            payload: ["type": "token_count", "info": NSNull()]
        )
    }

    private static func jsonRow(
        timestamp: String,
        type: String,
        payload: [String: Any]
    ) throws -> String {
        let object: [String: Any] = [
            "timestamp": timestamp,
            "type": type,
            "payload": payload
        ]
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        guard let row = String(data: data, encoding: .utf8) else {
            throw CheckFailure(message: "could not encode fixture row")
        }
        return row
    }

    private static func logDictionary(_ usage: TokenUsage) -> [String: Any] {
        [
            "input_tokens": usage.input,
            "cached_input_tokens": usage.cachedInput,
            "output_tokens": usage.output,
            "reasoning_output_tokens": usage.reasoningOutput,
            "total_tokens": usage.total
        ]
    }

    private static func usage(
        input: Int,
        cached: Int = 0,
        output: Int = 0,
        reasoning: Int = 0,
        total: Int
    ) -> TokenUsage {
        TokenUsage(
            input: input,
            cachedInput: cached,
            output: output,
            reasoningOutput: reasoning,
            total: total
        )
    }

    private static func date(_ value: String) throws -> Date {
        guard let parsed = ISO8601DateFormatter.codex.date(from: value) else {
            throw CheckFailure(message: "invalid fixture date: \(value)")
        }
        return parsed
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw CheckFailure(message: message) }
    }

    private static func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ label: String) throws {
        guard actual == expected else {
            throw CheckFailure(
                message: "\(label): expected \(String(describing: expected)), got \(String(describing: actual))"
            )
        }
    }

    private static func expectNear(_ actual: Double, _ expected: Double, tolerance: Double, _ label: String) throws {
        guard abs(actual - expected) <= tolerance else {
            throw CheckFailure(message: "\(label): expected \(expected), got \(actual)")
        }
    }
}
