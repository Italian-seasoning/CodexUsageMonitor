import Foundation

// Decode only the monitor's public snapshot. This process never reads Codex logs.
struct MonitorSnapshot: Decodable, Sendable {
    var generatedAt: Date?
    var currentModel: String?
    var currentSession: Usage
    var currentSessionTurns: Int?
    var rateLimits: Limits?
    var sessionActivity: [Activity]?
    var appearanceTheme: String?

    struct Point: Decodable, Sendable {
        var date: Date
        var totalTokens: Int
    }

    struct Usage: Decodable, Sendable {
        var input: Int
        var cachedInput: Int
        var output: Int
        var total: Int
        var compact: String {
            total.formatted(.number.notation(.compactName).precision(.fractionLength(0...1)))
        }
    }

    struct Activity: Decodable, Sendable {
        var id: String
        var project: String?
        var model: String?
        var state: String
        var observedAt: Date?
        var toolCalls: Int?
        var toolFailures: Int?
        var usage: Usage
        var requests: Int
        var usageHistory: [Point]?

        func isWorking(at now: Date) -> Bool {
            state == "running" && observedAt.map { now.timeIntervalSince($0) <= 120 } == true
        }

        func status(at now: Date) -> String {
            switch state {
            case "running": isWorking(at: now) ? "Working" : "Last seen working"
            case "completed": "Finished"
            case "interrupted": "Interrupted"
            default: "Last recorded"
            }
        }
    }

    struct Limits: Decodable, Sendable {
        var fiveHour: Window?
        var weekly: Window?
    }

    struct Window: Decodable, Sendable {
        var usedPercent: Double
        var resetsAt: Date

        func remaining(at now: Date) -> String {
            guard resetsAt > now, usedPercent.isFinite else { return "—" }
            return "\(Int(max(0, min(100, 100 - usedPercent)).rounded()))%"
        }
    }

    var latest: Activity? {
        sessionActivity?.first { $0.isWorking(at: .now) } ?? sessionActivity?.first
    }

    func isFresh(at now: Date) -> Bool {
        // Runway refreshes only while Codex is open, so allow ten quiet minutes.
        generatedAt.map { now.timeIntervalSince($0) <= 600 } == true
    }
}
