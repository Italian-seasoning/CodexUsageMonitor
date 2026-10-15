import Foundation

struct HeadroomSavingsCollector {
    var executableURL: URL
    var ledgerURL: URL
    var calendar: Calendar
    var timeout: TimeInterval
    var cacheURL: URL?

    init(
        executableURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/bin/headroom"),
        ledgerURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".headroom/savings_events.jsonl"),
        calendar: Calendar = .current,
        timeout: TimeInterval = 10,
        cacheURL: URL? = nil
    ) {
        self.executableURL = executableURL
        self.ledgerURL = ledgerURL
        self.calendar = calendar
        self.timeout = timeout
        self.cacheURL = cacheURL
    }

    func sourceFingerprint() -> String {
        [executableURL, ledgerURL]
            .map(fileFingerprint)
            .joined(separator: "|")
    }

    func collect(now: Date = Date()) -> HeadroomActivity? {
        guard FileManager.default.isExecutableFile(atPath: executableURL.path),
              FileManager.default.isReadableFile(atPath: ledgerURL.path)
        else {
            return nil
        }

        let fingerprint = sourceFingerprint()
        let cached = cacheURL.flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? PropertyListDecoder().decode(SavingsCache.self, from: $0) }
            .flatMap { $0.fingerprint == fingerprint && $0.report.schemaVersion >= 1 ? $0 : nil }
        let report: SavingsReport
        let events: [SavingsEvent]
        if let cached {
            report = cached.report
            events = cached.events
        } else {
            guard let fresh = loadReport(), fresh.schemaVersion >= 1 else { return nil }
            report = fresh
            events = loadCodexEvents()
            if let cacheURL {
                let encoder = PropertyListEncoder()
                encoder.outputFormat = .binary
                if let data = try? encoder.encode(SavingsCache(fingerprint: fingerprint, report: report, events: events)) {
                    try? FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try? data.write(to: cacheURL, options: .atomic)
                }
            }
        }
        guard !events.isEmpty else { return nil }

        let onlyCodexClients = report.byClient
            .filter { $0.tokensSaved > 0 || $0.calls > 0 }
            .allSatisfy { $0.client.lowercased() == "codex" }
        let retainedEvents = report.schemaVersion >= 2
            ? events.filter { $0.timestamp >= now.addingTimeInterval(-30 * 24 * 60 * 60) && $0.timestamp <= now }
            : events
        let tracked = aggregate(events: retainedEvents)
        let todayStart = calendar.startOfDay(for: now)
        let todayEvents = events.filter { calendar.startOfDay(for: $0.timestamp) == todayStart }
        let last7Start = now.addingTimeInterval(-7 * 24 * 60 * 60)
        let last7Events = events.filter { $0.timestamp >= last7Start && $0.timestamp <= now }

        let lifetimeBucket = onlyCodexClients && cached == nil ? report.lifetime : tracked
        let todayBucket = onlyCodexClients && cached == nil ? report.windows.today : aggregate(events: todayEvents)
        let last7Bucket = onlyCodexClients && cached == nil ? report.windows.last7Days : aggregate(events: last7Events)
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
        let completion = DispatchSemaphore(value: 0)
        let drained = DispatchSemaphore(value: 0)
        let lock = NSLock()
        var reportData: Data?

        process.executableURL = executableURL
        process.arguments = ["savings", "--json"]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { _ in completion.signal() }

        do {
            try process.run()
        } catch {
            return nil
        }

        DispatchQueue.global(qos: .utility).async {
            var data = Data()
            defer { drained.signal() }
            do {
                while let chunk = try output.fileHandleForReading.read(upToCount: 65_536), !chunk.isEmpty {
                    guard data.count + chunk.count <= 16 * 1_024 * 1_024 else {
                        if process.isRunning { process.terminate() }
                        return
                    }
                    data.append(chunk)
                }
                lock.lock()
                reportData = data
                lock.unlock()
            } catch { }
        }

        if completion.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            return nil
        }
        guard process.terminationStatus == 0, drained.wait(timeout: .now() + 1) == .success else { return nil }
        lock.lock()
        let data = reportData
        lock.unlock()
        guard let data else { return nil }
        return try? JSONDecoder().decode(SavingsReport.self, from: data)
    }

    private func fileFingerprint(_ url: URL) -> String {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else {
            return "missing:\(url.path)"
        }
        let size = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
        let modified = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        return "\(url.path):\(size):\(modified)"
    }

    private func loadCodexEvents() -> [SavingsEvent] {
        var events: [SavingsEvent] = []
        do {
            try JSONLFileReader.forEachRow(at: ledgerURL) { object in
                guard
                      (object["client"] as? String)?.lowercased() == "codex",
                      let timestamp = parseDate(object["ts"] as? String),
                      let before = object["before"] as? Int,
                      let after = object["after"] as? Int,
                      let saved = object["saved"] as? Int,
                      before >= 0, after >= 0, saved >= 0,
                      saved == max(before - after, 0)
                else {
                    return
                }

                let cost = max(0, object["cost_usd"] as? Double ?? 0)
                events.append(SavingsEvent(
                    timestamp: timestamp,
                    before: before,
                    saved: saved,
                    costUSD: cost,
                    model: object["model"] as? String ?? "Unknown"
                ))
            }
        } catch {
            return []
        }
        return events
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

private struct SavingsCache: Codable {
    var fingerprint: String
    var report: SavingsReport
    var events: [SavingsEvent]
}

private struct SavingsEvent: Codable {
    var timestamp: Date
    var before: Int
    var saved: Int
    var costUSD: Double
    var model: String
}

private struct SavingsReport: Codable {
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

private struct SavingsWindows: Codable {
    var today: SavingsBucket
    var last7Days: SavingsBucket

    enum CodingKeys: String, CodingKey {
        case today
        case last7Days = "last_7_days"
    }
}

private struct SavingsBucket: Codable {
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

private struct ClientSavings: Codable {
    var client: String
    var tokensSaved: Int
    var calls: Int

    enum CodingKeys: String, CodingKey {
        case client
        case tokensSaved = "tokens_saved"
        case calls
    }
}
