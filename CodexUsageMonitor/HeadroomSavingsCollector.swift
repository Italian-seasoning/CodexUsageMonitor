import Foundation

struct HeadroomSavingsCollector {
    var executableURL: URL
    var ledgerURL: URL
    var calendar: Calendar
    var timeout: TimeInterval

    init(
        executableURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/bin/headroom"),
        ledgerURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".headroom/savings_events.jsonl"),
        calendar: Calendar = .current,
        timeout: TimeInterval = 3
    ) {
        self.executableURL = executableURL
        self.ledgerURL = ledgerURL
        self.calendar = calendar
        self.timeout = timeout
    }

    func collect(now: Date = Date()) -> HeadroomActivity? {
        guard FileManager.default.isExecutableFile(atPath: executableURL.path),
              FileManager.default.isReadableFile(atPath: ledgerURL.path),
              let report = loadReport(),
              report.schemaVersion >= 1
        else {
            return nil
        }

        let events = loadCodexEvents()
        guard !events.isEmpty else { return nil }

        let onlyCodexClients = report.byClient
            .filter { $0.tokensSaved > 0 || $0.calls > 0 }
            .allSatisfy { $0.client.lowercased() == "codex" }
        let tracked = aggregate(events: events)
        let todayStart = calendar.startOfDay(for: now)
        let todayEvents = events.filter { calendar.startOfDay(for: $0.timestamp) == todayStart }
        let last7Start = now.addingTimeInterval(-7 * 24 * 60 * 60)
        let last7Events = events.filter { $0.timestamp >= last7Start && $0.timestamp <= now }

        let lifetimeBucket = onlyCodexClients ? report.lifetime : tracked
        let todayBucket = onlyCodexClients ? report.windows.today : aggregate(events: todayEvents)
        let last7Bucket = onlyCodexClients ? report.windows.last7Days : aggregate(events: last7Events)
        let exactPercent = lifetimeBucket.tokensBefore > 0
            ? 100 * Double(lifetimeBucket.tokensSaved) / Double(lifetimeBucket.tokensBefore)
            : 0

        var byDay: [Date: Int] = [:]
        var modelSavings: [String: Int] = [:]
        for event in events {
            let day = calendar.startOfDay(for: event.timestamp)
            byDay[day, default: 0] += event.saved
            modelSavings[event.model, default: 0] += event.saved
        }

        let savings = HeadroomSavings(
            lifetimeTokensSaved: lifetimeBucket.tokensSaved,
            todayTokensSaved: todayBucket.tokensSaved,
            last7DaysTokensSaved: last7Bucket.tokensSaved,
            lifetimeRequests: lifetimeBucket.calls,
            todayRequests: todayBucket.calls,
            inputTokensBeforeCompression: lifetimeBucket.tokensBefore,
            savingsPercent: exactPercent,
            costSavedUSD: lifetimeBucket.costUSD,
            todayCostSavedUSD: todayBucket.costUSD,
            lastUpdated: events.map(\.timestamp).max(),
            trackingStartedAt: events.map(\.timestamp).min(),
            topModel: modelSavings.max { $0.value < $1.value }?.key ?? report.topModel,
            schemaVersion: report.schemaVersion
        )
        return HeadroomActivity(savings: savings, tokensSavedByDay: byDay)
    }

    private func loadReport() -> SavingsReport? {
        let process = Process()
        let output = Pipe()
        let errors = Pipe()
        let completion = DispatchSemaphore(value: 0)

        process.executableURL = executableURL
        process.arguments = ["savings", "--json"]
        process.standardOutput = output
        process.standardError = errors
        process.terminationHandler = { _ in completion.signal() }

        do {
            try process.run()
        } catch {
            return nil
        }

        if completion.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        return try? JSONDecoder().decode(SavingsReport.self, from: data)
    }

    private func loadCodexEvents() -> [SavingsEvent] {
        guard let contents = try? String(contentsOf: ledgerURL, encoding: .utf8) else { return [] }
        return contents.split(separator: "\n").compactMap { line in
            guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  (object["client"] as? String)?.lowercased() == "codex",
                  let timestamp = parseDate(object["ts"] as? String),
                  let before = object["before"] as? Int,
                  let after = object["after"] as? Int,
                  let saved = object["saved"] as? Int,
                  before >= 0, after >= 0, saved > 0,
                  saved == max(before - after, 0)
            else {
                return nil
            }

            let cost = max(0, object["cost_usd"] as? Double ?? 0)
            return SavingsEvent(
                timestamp: timestamp,
                before: before,
                saved: saved,
                costUSD: cost,
                model: object["model"] as? String ?? "Unknown"
            )
        }
    }

    private func aggregate(events: [SavingsEvent]) -> SavingsBucket {
        SavingsBucket(
            tokensSaved: events.reduce(0) { $0 + $1.saved },
            tokensBefore: events.reduce(0) { $0 + $1.before },
            costUSD: events.reduce(0) { $0 + $1.costUSD },
            calls: events.count,
            savingsPercent: 0
        )
    }

    private func parseDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        return ISO8601DateFormatter.codex.date(from: value)
            ?? ISO8601DateFormatter.codexNoFractions.date(from: value)
    }
}

private struct SavingsEvent {
    var timestamp: Date
    var before: Int
    var saved: Int
    var costUSD: Double
    var model: String
}

private struct SavingsReport: Decodable {
    var schemaVersion: Int
    var topModel: String
    var lifetime: SavingsBucket
    var windows: SavingsWindows
    var byClient: [ClientSavings]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case topModel = "top_model"
        case lifetime
        case windows
        case byClient = "by_client"
    }
}

private struct SavingsWindows: Decodable {
    var today: SavingsBucket
    var last7Days: SavingsBucket
    var allTime: SavingsBucket

    enum CodingKeys: String, CodingKey {
        case today
        case last7Days = "last_7_days"
        case allTime = "all_time"
    }
}

private struct SavingsBucket: Decodable {
    var tokensSaved: Int
    var tokensBefore: Int
    var costUSD: Double
    var calls: Int
    var savingsPercent: Double

    enum CodingKeys: String, CodingKey {
        case tokensSaved = "tokens_saved"
        case tokensBefore = "tokens_before"
        case costUSD = "cost_usd"
        case calls
        case savingsPercent = "savings_percent"
    }

    init(tokensSaved: Int, tokensBefore: Int, costUSD: Double, calls: Int, savingsPercent: Double) {
        self.tokensSaved = tokensSaved
        self.tokensBefore = tokensBefore
        self.costUSD = costUSD
        self.calls = calls
        self.savingsPercent = savingsPercent
    }
}

private struct ClientSavings: Decodable {
    var client: String
    var tokensSaved: Int
    var calls: Int

    enum CodingKeys: String, CodingKey {
        case client
        case tokensSaved = "tokens_saved"
        case calls
    }
}
