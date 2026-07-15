import Foundation

@main
struct RateLimitReaderCheck {
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let now = ISO8601DateFormatter.codex.date(from: "2026-07-15T18:00:00.000Z")!
        let fiveHourReset = now.addingTimeInterval(7_200)
        let weeklyReset = now.addingTimeInterval(3 * 86_400)
        let rows: [[String: Any]] = [
            [
                "timestamp": "2026-07-15T17:45:00.000Z",
                "type": "session_meta",
                "payload": ["id": "rate-limit-check", "timestamp": "2026-07-15T17:45:00.000Z"]
            ],
            tokenRow(
                timestamp: "2026-07-15T17:50:00.000Z",
                total: 100,
                fiveHour: 20,
                fiveHourReset: fiveHourReset,
                weekly: 55,
                weeklyReset: weeklyReset
            ),
            tokenRow(
                timestamp: "2026-07-15T17:55:00.000Z",
                total: 200,
                fiveHour: 42,
                fiveHourReset: fiveHourReset,
                weekly: 56,
                weeklyReset: weeklyReset
            )
        ]

        let data = try rows.map { try JSONSerialization.data(withJSONObject: $0) }
        let jsonl = data.map { String(decoding: $0, as: UTF8.self) }.joined(separator: "\n")
        try Data(jsonl.utf8).write(to: directory.appendingPathComponent("session.jsonl"))

        let snapshot = CodexUsageReader(sessionsDirectory: directory, cacheURL: nil).snapshot(now: now)
        precondition(snapshot.rateLimits?.fiveHour?.usedPercent == 42)
        precondition(snapshot.rateLimits?.weekly?.usedPercent == 56)
        precondition(snapshot.rateLimits?.history.count == 1)
        precondition(snapshot.rateLimits?.nearestReset?.windowMinutes == 300)
        print("RateLimitReaderCheck passed")
    }

    private static func tokenRow(
        timestamp: String,
        total: Int,
        fiveHour: Double,
        fiveHourReset: Date,
        weekly: Double,
        weeklyReset: Date
    ) -> [String: Any] {
        [
            "timestamp": timestamp,
            "type": "event_msg",
            "payload": [
                "type": "token_count",
                "info": [
                    "total_token_usage": ["input_tokens": total, "total_tokens": total],
                    "last_token_usage": ["input_tokens": 100, "total_tokens": 100]
                ],
                "rate_limits": [
                    "primary": [
                        "used_percent": fiveHour,
                        "window_minutes": 300,
                        "resets_at": Int(fiveHourReset.timeIntervalSince1970)
                    ],
                    "secondary": [
                        "used_percent": weekly,
                        "window_minutes": 10_080,
                        "resets_at": Int(weeklyReset.timeIntervalSince1970)
                    ]
                ]
            ]
        ]
    }
}
