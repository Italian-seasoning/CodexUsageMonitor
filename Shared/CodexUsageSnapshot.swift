import Darwin
import Foundation
import CryptoKit

enum JSONLFileReader {
    struct SourceIdentity: Codable, Equatable, Sendable {
        var device: UInt64
        var inode: UInt64
    }

    struct ReadProgress: Codable, Equatable, Sendable {
        var bytesRead: UInt64
        var prefixDigest: Data
        var endedWithNewline: Bool
        var identity: SourceIdentity
    }

    enum ReadError: Error, Equatable {
        case invalidOffset
        case sourceReplaced
        case prefixMismatch
        case sourceChanged
    }

    // Transcript size must not determine refresh memory. Only a partial row is
    // carried between fixed-size reads; JSON objects are released after each row.
    @discardableResult
    static func forEachRow(
        at url: URL,
        chunkSize: Int = 64 * 1024,
        offset: UInt64 = 0,
        expectedPrefixDigest: Data? = nil,
        expectedIdentity: SourceIdentity? = nil,
        _ visit: ([String: Any]) -> Void
    ) throws -> ReadProgress {
        precondition(chunkSize > 0)
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var initial = stat()
        try checkPOSIX(Darwin.fstat(handle.fileDescriptor, &initial))
        let identity = sourceIdentity(initial)
        guard expectedIdentity == nil || expectedIdentity == identity else {
            throw ReadError.sourceReplaced
        }
        guard initial.st_size >= 0, offset <= UInt64(initial.st_size) else {
            throw ReadError.invalidOffset
        }
        let initialSize = UInt64(initial.st_size)
        var cursor: UInt64 = 0
        var hasher = SHA256()
        var lastByte: UInt8?

        func read(through end: UInt64) throws -> Data {
            let count = Int(min(UInt64(chunkSize), end - cursor))
            guard let chunk = try autoreleasepool(invoking: { try handle.read(upToCount: count) }),
                  !chunk.isEmpty else { throw ReadError.sourceChanged }
            hasher.update(data: chunk)
            cursor += UInt64(chunk.count)
            lastByte = chunk.last
            return chunk
        }

        // Verify the entire cached prefix without decoding it. No parser state
        // may be advanced until both its bytes and source identity match.
        while cursor < offset { _ = try read(through: offset) }
        if let expectedPrefixDigest, Data(hasher.finalize()) != expectedPrefixDigest {
            throw ReadError.prefixMismatch
        }
        guard offset == 0 || lastByte == 10 else { throw ReadError.invalidOffset }
        var pending = Data()

        func consume(_ data: Data) {
            autoreleasepool {
                guard !data.isEmpty,
                      let row = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                else { return }
                visit(row)
            }
        }

        // Bound the suffix to the size observed on this same descriptor. An
        // append during a visit is rejected below instead of extending the read.
        while cursor < initialSize {
            let chunk = try read(through: initialSize)
            var start = chunk.startIndex
            while let newline = chunk[start...].firstIndex(of: 10) {
                if pending.isEmpty {
                    consume(chunk.subdata(in: start..<newline))
                } else {
                    pending.append(contentsOf: chunk[start..<newline])
                    consume(pending)
                    pending = Data()
                }
                start = chunk.index(after: newline)
            }
            if start < chunk.endIndex {
                pending.append(contentsOf: chunk[start...])
            }
        }
        // Codex may leave a valid final JSON row without a terminating newline.
        consume(pending)

        var final = stat()
        try checkPOSIX(Darwin.fstat(handle.fileDescriptor, &final))
        var path = stat()
        try checkPOSIX(url.withUnsafeFileSystemRepresentation { pointer in
            guard let pointer else { errno = EINVAL; return -1 }
            return Darwin.fstatat(AT_FDCWD, pointer, &path, 0)
        })
        guard unchanged(initial, final), unchanged(initial, path) else {
            throw ReadError.sourceChanged
        }
        return ReadProgress(bytesRead: cursor, prefixDigest: Data(hasher.finalize()),
            endedWithNewline: lastByte == nil || lastByte == 10, identity: identity)
    }

    private static func sourceIdentity(_ value: stat) -> SourceIdentity {
        SourceIdentity(device: UInt64(UInt32(bitPattern: value.st_dev)), inode: UInt64(value.st_ino))
    }

    private static func unchanged(_ lhs: stat, _ rhs: stat) -> Bool {
        sourceIdentity(lhs) == sourceIdentity(rhs)
            && lhs.st_size == rhs.st_size
            && lhs.st_mtimespec.tv_sec == rhs.st_mtimespec.tv_sec
            && lhs.st_mtimespec.tv_nsec == rhs.st_mtimespec.tv_nsec
            && lhs.st_ctimespec.tv_sec == rhs.st_ctimespec.tv_sec
            && lhs.st_ctimespec.tv_nsec == rhs.st_ctimespec.tv_nsec
    }

    private static func checkPOSIX(_ result: Int32) throws {
        guard result == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }
}

struct TokenUsage: Codable, Equatable, Hashable, Sendable {
    var input: Int
    var cachedInput: Int
    var output: Int
    var reasoningOutput: Int
    var total: Int

    static let zero = TokenUsage(input: 0, cachedInput: 0, output: 0, reasoningOutput: 0, total: 0)

    mutating func add(_ other: TokenUsage) {
        input += other.input
        cachedInput += other.cachedInput
        output += other.output
        reasoningOutput += other.reasoningOutput
        total += other.total
    }

    func delta(since previous: TokenUsage?) -> TokenUsage {
        guard let previous else { return self }
        guard input >= previous.input,
              cachedInput >= previous.cachedInput,
              output >= previous.output,
              reasoningOutput >= previous.reasoningOutput,
              total >= previous.total
        else {
            return self
        }
        return TokenUsage(
            input: input - previous.input,
            cachedInput: cachedInput - previous.cachedInput,
            output: output - previous.output,
            reasoningOutput: reasoningOutput - previous.reasoningOutput,
            total: total - previous.total
        )
    }

    var hasUsage: Bool {
        total > 0 || input > 0 || cachedInput > 0 || output > 0 || reasoningOutput > 0
    }
}

struct DailyUsage: Codable, Equatable, Identifiable, Sendable {
    var date: Date
    var usage: TokenUsage
    var sessions: Int
    var turns: Int? = nil
    var headroomSaved: Int? = nil
    var estimatedCostMicros: Int? = nil
    var legacyCoverageIncomplete: Bool? = nil

    var id: Date { date }
}

struct AccountUsageDay: Codable, Equatable, Sendable {
    var date: Date
    var tokens: Int
}

struct ModelUsage: Codable, Equatable, Identifiable, Sendable {
    var model: String
    var usage: TokenUsage
    var turns: Int
    var estimatedCostUSD: Double

    var id: String { model }

    var availableCostEstimateUSD: Double? {
        estimatedCostUSD > 0 || ModelPricingCatalog.pricing(for: model) != nil ? estimatedCostUSD : nil
    }
}

struct DailyModelUsage: Codable, Equatable, Identifiable, Sendable {
    var date: Date
    var models: [ModelUsage]

    var id: Date { date }
}

struct CodexSessionSummary: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var startedAt: Date
    var updatedAt: Date
    var usage: TokenUsage
    var turns: Int
    var model: String
    var estimatedCostUSD: Double?
    var title: String? = nil

    var sessionID: String { String(id.split(separator: "#", maxSplits: 1).first ?? Substring(id)) }
    var displayTitle: String { title ?? "Session \(sessionID.prefix(8))" }

    var sortableEstimatedCostUSD: Double { estimatedCostUSD ?? -1 }
}

struct ModelPricing: Equatable {
    var inputPerMillion: Double
    var cachedInputPerMillion: Double
    var outputPerMillion: Double
    var longInputPerMillion: Double?
    var longCachedInputPerMillion: Double?
    var longOutputPerMillion: Double?
    var longContextThreshold: Int?

    func estimatedCost(for usage: TokenUsage) -> Double {
        let usesLongContext = longContextThreshold.map { usage.input > $0 } == true
        let inputRate = usesLongContext ? (longInputPerMillion ?? inputPerMillion) : inputPerMillion
        let cachedRate = usesLongContext
            ? (longCachedInputPerMillion ?? longInputPerMillion ?? cachedInputPerMillion)
            : cachedInputPerMillion
        let outputRate = usesLongContext ? (longOutputPerMillion ?? outputPerMillion) : outputPerMillion
        let cached = min(usage.cachedInput, usage.input)
        let uncached = max(0, usage.input - cached)
        return Double(uncached) / 1_000_000 * inputRate
            + Double(cached) / 1_000_000 * cachedRate
            + Double(usage.output) / 1_000_000 * outputRate
    }
}

enum ModelPricingCatalog {
    static let version = "OpenAI Standard API · verified 2026-10-14"
    static let sourceURL = "https://developers.openai.com/api/docs/pricing"

    private static let prices: [String: ModelPricing] = [
        // Uses the monitor's existing 272K context boundary for API-equivalent estimates.
        "gpt-6.1-sol": ModelPricing(inputPerMillion: 2, cachedInputPerMillion: 0.1, outputPerMillion: 10, longInputPerMillion: 4, longCachedInputPerMillion: 0.2, longOutputPerMillion: 15, longContextThreshold: 272_000),
        "gpt-6-astra": ModelPricing(inputPerMillion: 10, cachedInputPerMillion: 1, outputPerMillion: 50, longInputPerMillion: 20, longCachedInputPerMillion: 2, longOutputPerMillion: 75, longContextThreshold: 272_000),
        "gpt-6-sol": ModelPricing(inputPerMillion: 2, cachedInputPerMillion: 0.2, outputPerMillion: 10, longInputPerMillion: 4, longCachedInputPerMillion: 0.4, longOutputPerMillion: 15, longContextThreshold: 272_000),
        "gpt-6-luna": ModelPricing(inputPerMillion: 0.1, cachedInputPerMillion: 0.01, outputPerMillion: 0.5, longInputPerMillion: 0.2, longCachedInputPerMillion: 0.02, longOutputPerMillion: 0.75, longContextThreshold: 272_000),
        "gpt-5.6-sol": ModelPricing(inputPerMillion: 4, cachedInputPerMillion: 0.4, outputPerMillion: 20, longInputPerMillion: 8, longCachedInputPerMillion: 0.8, longOutputPerMillion: 30, longContextThreshold: 272_000),
        "gpt-5.6-terra": ModelPricing(inputPerMillion: 2, cachedInputPerMillion: 0.2, outputPerMillion: 12, longInputPerMillion: 4, longCachedInputPerMillion: 0.4, longOutputPerMillion: 18, longContextThreshold: 272_000),
        "gpt-5.6-luna": ModelPricing(inputPerMillion: 0.2, cachedInputPerMillion: 0.02, outputPerMillion: 1.2, longInputPerMillion: 0.4, longCachedInputPerMillion: 0.04, longOutputPerMillion: 1.8, longContextThreshold: 272_000),
        "gpt-5.5": ModelPricing(inputPerMillion: 5, cachedInputPerMillion: 0.5, outputPerMillion: 30, longInputPerMillion: 10, longCachedInputPerMillion: 1, longOutputPerMillion: 45, longContextThreshold: 272_000),
        "gpt-5.5-pro": ModelPricing(inputPerMillion: 30, cachedInputPerMillion: 30, outputPerMillion: 180, longInputPerMillion: 60, longCachedInputPerMillion: 60, longOutputPerMillion: 270, longContextThreshold: 272_000),
        "gpt-5.4": ModelPricing(inputPerMillion: 2.5, cachedInputPerMillion: 0.25, outputPerMillion: 15, longInputPerMillion: 5, longCachedInputPerMillion: 0.5, longOutputPerMillion: 22.5, longContextThreshold: 272_000),
        "gpt-5.4-mini": ModelPricing(inputPerMillion: 0.75, cachedInputPerMillion: 0.075, outputPerMillion: 4.5, longInputPerMillion: nil, longCachedInputPerMillion: nil, longOutputPerMillion: nil, longContextThreshold: nil),
        "gpt-5.4-nano": ModelPricing(inputPerMillion: 0.2, cachedInputPerMillion: 0.02, outputPerMillion: 1.25, longInputPerMillion: nil, longCachedInputPerMillion: nil, longOutputPerMillion: nil, longContextThreshold: nil),
        "gpt-5.4-pro": ModelPricing(inputPerMillion: 30, cachedInputPerMillion: 30, outputPerMillion: 180, longInputPerMillion: 60, longCachedInputPerMillion: 60, longOutputPerMillion: 270, longContextThreshold: 272_000)
    ]

    private static let modelIDsBySpecificity = prices.keys.sorted { $0.count > $1.count }

    static func pricing(for model: String?) -> ModelPricing? {
        guard let normalized = normalizedModelID(model) else { return nil }
        return prices[normalized]
    }

    static func displayName(for model: String?) -> String {
        guard let model, !model.isEmpty else { return "Unknown model" }
        return model
            .replacingOccurrences(of: "gpt-", with: "GPT ")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "codex", with: "Codex")
            .capitalized
            .replacingOccurrences(of: "Gpt", with: "GPT")
    }

    private static func normalizedModelID(_ model: String?) -> String? {
        guard let model = model?.lowercased() else { return nil }
        return modelIDsBySpecificity.first { model == $0 || model.hasPrefix($0 + "-") }
    }
}

struct HeadroomSavings: Codable, Equatable {
    var lifetimeTokensSaved: Int
    var todayTokensSaved: Int
    var last7DaysTokensSaved: Int
    var lifetimeRequests: Int
    var todayRequests: Int
    var inputTokensBeforeCompression: Int
    var savingsPercent: Double
    var costSavedUSD: Double
    var todayCostSavedUSD: Double
    var lastUpdated: Date?
    var trackingStartedAt: Date? = nil
    var topModel: String? = nil
    var schemaVersion: Int? = nil

    static let zero = HeadroomSavings(
        lifetimeTokensSaved: 0,
        todayTokensSaved: 0,
        last7DaysTokensSaved: 0,
        lifetimeRequests: 0,
        todayRequests: 0,
        inputTokensBeforeCompression: 0,
        savingsPercent: 0,
        costSavedUSD: 0,
        todayCostSavedUSD: 0,
        lastUpdated: nil
    )

    var isAvailable: Bool {
        lifetimeTokensSaved > 0 || lifetimeRequests > 0 || lastUpdated != nil
    }

    var trackedPeriodLabel: String { (schemaVersion ?? 1) >= 2 ? "Last 30 days" : "Tracked" }
}

struct HeadroomActivity: Equatable {
    var savings: HeadroomSavings
    var tokensSavedByDay: [Date: Int]
}

struct RateLimitWindow: Codable, Equatable {
    var usedPercent: Double
    var windowMinutes: Int
    var resetsAt: Date
    var observedAt: Date

    var remainingPercent: Double {
        min(100, max(0, 100 - usedPercent))
    }

    func isCurrent(at date: Date = .now) -> Bool {
        resetsAt > date && observedAt <= date.addingTimeInterval(60)
    }

    func pace(at date: Date = .now) -> LimitPace {
        let duration = TimeInterval(windowMinutes * 60)
        guard duration > 0 else { return .unknown }
        let startedAt = resetsAt.addingTimeInterval(-duration)
        let elapsedPercent = min(100, max(0, date.timeIntervalSince(startedAt) / duration * 100))
        let lead = usedPercent - elapsedPercent
        if usedPercent >= 90 || lead >= 25 { return .limitRisk }
        if usedPercent >= 70 || lead >= 10 { return .runningHigh }
        return .onPace
    }

    func resetText(at date: Date = .now) -> String {
        let seconds = max(0, resetsAt.timeIntervalSince(date))
        if seconds < 60 { return "Now" }
        if seconds < 3_600 { return "\(Int(ceil(seconds / 60)))m" }
        if seconds < 86_400 {
            let hours = Int(seconds / 3_600)
            let minutes = Int(seconds.truncatingRemainder(dividingBy: 3_600) / 60)
            return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h"
        }
        return resetsAt.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }
}

enum LimitPace: String, Codable, Equatable {
    case onPace
    case runningHigh
    case limitRisk
    case unknown

    var label: String {
        switch self {
        case .onPace: "On pace"
        case .runningHigh: "Running high"
        case .limitRisk: "Limit risk"
        case .unknown: "Unavailable"
        }
    }
}

struct RateLimitHistoryPoint: Codable, Equatable, Identifiable {
    var date: Date
    var fiveHourUsedPercent: Double?
    var weeklyUsedPercent: Double?

    var id: Date { date }
}

struct CodexRateLimits: Codable, Equatable {
    var fiveHour: RateLimitWindow?
    var weekly: RateLimitWindow?
    var history: [RateLimitHistoryPoint]
    // Actual observation timestamps and reset boundaries, independent of hourly charts.
    var consumptionSamples: [RateLimitWindow]? = nil
    var accountObservedAt: Date? = nil
    var planType: String? = nil

    var showsFiveHour: Bool {
        fiveHour != nil && !(planType?.lowercased().hasPrefix("pro") ?? false)
    }

    var preferredWindow: RateLimitWindow? { showsFiveHour ? fiveHour : weekly }

    var nearestReset: RateLimitWindow? {
        [showsFiveHour ? fiveHour : nil, weekly].compactMap { $0 }.min { $0.resetsAt < $1.resetsAt }
    }

    var pace: LimitPace { preferredWindow?.pace() ?? .unknown }
}

struct CodexTokenPoint: Codable, Equatable, Identifiable, Sendable {
    var date: Date
    var totalTokens: Int
    var id: Date { date }
}

/// Operational metadata only: never prompts, responses, commands or tool arguments.
struct CodexSessionActivity: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var project: String? = nil
    var title: String? = nil
    var model: String? = nil
    var provider: String? = nil
    var cliVersion: String? = nil
    var reasoningEffort: String? = nil
    var approvalPolicy: String? = nil
    var sandboxMode: String? = nil
    var state = "unknown"
    var observedAt: Date? = nil
    var turnStartedAt: Date? = nil
    var turnDurationSeconds: Double? = nil
    var firstTokenSeconds: Double? = nil
    var lastTool: String? = nil
    var toolCalls: Int? = nil
    var toolFailures: Int? = nil
    var usage: TokenUsage = .zero
    var requests: Int = 0
    var contextTokens: Int? = nil
    var contextWindow: Int? = nil
    var usageHistory: [CodexTokenPoint]? = nil

    var displayTitle: String { title ?? project ?? "Session \(id.prefix(8))" }

    func status(at now: Date = .now) -> String {
        if state == "running" {
            return observedAt.map { now.timeIntervalSince($0) <= 120 } == true
                ? "Working" : "Last seen working"
        }
        switch state {
        case "completed": return "Finished"
        case "interrupted": return "Interrupted"
        default: return "Last recorded"
        }
    }
}

/// Reads only saved chat names. Transcript contents are never used as a naming fallback.
enum CodexSessionNames {
    static func load(for sessionIDs: Set<String>, from url: URL) -> [String: String] {
        guard !sessionIDs.isEmpty, let file = try? FileHandle(forReadingFrom: url) else { return [:] }
        defer { try? file.close() }
        var names: [String: String] = [:]
        var line = Data()
        var oversized = false
        func consume() {
            defer { line.removeAll(keepingCapacity: true); oversized = false }
            guard !oversized,
                  let row = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  let id = row["id"] as? String, sessionIDs.contains(id),
                  let rawName = row["thread_name"] as? String else { return }
            let name = rawName.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
            if name.isEmpty { names.removeValue(forKey: id) }
            else { names[id] = String(name.prefix(240)) }
        }
        while let chunk = try? file.read(upToCount: 64 * 1024), !chunk.isEmpty {
            for byte in chunk {
                if byte == 10 { consume() }
                else if !oversized {
                    if line.count < 64 * 1024 { line.append(byte) }
                    else { oversized = true; line.removeAll(keepingCapacity: true) }
                }
            }
        }
        if !line.isEmpty || oversized { consume() }
        return names
    }

    static func applying(to snapshot: CodexUsageSnapshot, from url: URL) -> CodexUsageSnapshot {
        var result = snapshot
        let ids = Set(snapshot.sessionActivity.map(\.id) + snapshot.recentSessions.map(\.sessionID))
        let names = load(for: ids, from: url)
        for index in result.sessionActivity.indices {
            result.sessionActivity[index].title = names[result.sessionActivity[index].id]
        }
        for index in result.recentSessions.indices {
            result.recentSessions[index].title = names[result.recentSessions[index].sessionID]
        }
        return result
    }
}

struct CodexUsageSnapshot: Codable, Equatable {
    var currentSession: TokenUsage
    var lifetime: TokenUsage
    var today: TokenUsage
    var peakDay: DailyUsage?
    var currentStreak: Int
    var longestStreak: Int
    var lastUpdated: Date?
    var activityDays: [DailyUsage]
    var generatedAt: Date? = nil
    var sourceReadPending: Bool? = nil
    var sessionCount: Int? = nil
    var turnCount: Int? = nil
    var currentSessionTurns: Int? = nil
    var currentSessionStartedAt: Date? = nil
    var currentContextTokens: Int? = nil
    var contextWindow: Int? = nil
    var headroom: HeadroomSavings? = nil
    var modelUsage: [ModelUsage]? = nil
    var dailyModelUsage: [DailyModelUsage] = []
    var topModelToday: String? = nil
    var topModelLast7Days: String? = nil
    var topModelThisMonth: String? = nil
    var topModelLifetime: String? = nil
    var currentModel: String? = nil
    var unpricedTokens: Int? = nil
    var pricingVersion: String? = nil
    var rateLimits: CodexRateLimits? = nil
    var accountLifetimeTokens: Int? = nil
    var accountUsageDays: [AccountUsageDay]? = nil
    var accountUsageObservedAt: Date? = nil
    var recentSessions: [CodexSessionSummary] = []
    var sessionActivity: [CodexSessionActivity] = []
    var appearanceTheme: String? = nil

    static let empty = CodexUsageSnapshot(
        currentSession: .zero,
        lifetime: .zero,
        today: .zero,
        peakDay: nil,
        currentStreak: 0,
        longestStreak: 0,
        lastUpdated: nil,
        activityDays: [],
        generatedAt: nil,
        sessionCount: 0,
        turnCount: 0,
        currentSessionTurns: 0,
        currentSessionStartedAt: nil,
        currentContextTokens: nil,
        contextWindow: nil,
        headroom: nil,
        modelUsage: [],
        dailyModelUsage: [],
        topModelToday: nil,
        topModelLast7Days: nil,
        topModelThisMonth: nil,
        topModelLifetime: nil,
        currentModel: nil,
        unpricedTokens: 0,
        pricingVersion: ModelPricingCatalog.version,
        rateLimits: nil,
        recentSessions: []
    )
}

extension CodexUsageSnapshot {
    private enum CodingKeys: String, CodingKey {
        case currentSession
        case lifetime
        case today
        case peakDay
        case currentStreak
        case longestStreak
        case lastUpdated
        case activityDays
        case generatedAt
        case sourceReadPending
        case sessionCount
        case turnCount
        case currentSessionTurns
        case currentSessionStartedAt
        case currentContextTokens
        case contextWindow
        case headroom
        case modelUsage
        case dailyModelUsage
        case topModelToday
        case topModelLast7Days
        case topModelThisMonth
        case topModelLifetime
        case currentModel
        case unpricedTokens
        case pricingVersion
        case rateLimits
        case accountLifetimeTokens
        case accountUsageDays
        case accountUsageObservedAt
        case recentSessions
        case sessionActivity
        case appearanceTheme
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        currentSession = try values.decode(TokenUsage.self, forKey: .currentSession)
        lifetime = try values.decode(TokenUsage.self, forKey: .lifetime)
        today = try values.decode(TokenUsage.self, forKey: .today)
        peakDay = try values.decodeIfPresent(DailyUsage.self, forKey: .peakDay)
        currentStreak = try values.decode(Int.self, forKey: .currentStreak)
        longestStreak = try values.decode(Int.self, forKey: .longestStreak)
        lastUpdated = try values.decodeIfPresent(Date.self, forKey: .lastUpdated)
        activityDays = try values.decode([DailyUsage].self, forKey: .activityDays)
        generatedAt = try values.decodeIfPresent(Date.self, forKey: .generatedAt)
        sourceReadPending = try values.decodeIfPresent(Bool.self, forKey: .sourceReadPending)
        sessionCount = try values.decodeIfPresent(Int.self, forKey: .sessionCount)
        turnCount = try values.decodeIfPresent(Int.self, forKey: .turnCount)
        currentSessionTurns = try values.decodeIfPresent(Int.self, forKey: .currentSessionTurns)
        currentSessionStartedAt = try values.decodeIfPresent(Date.self, forKey: .currentSessionStartedAt)
        currentContextTokens = try values.decodeIfPresent(Int.self, forKey: .currentContextTokens)
        contextWindow = try values.decodeIfPresent(Int.self, forKey: .contextWindow)
        headroom = try values.decodeIfPresent(HeadroomSavings.self, forKey: .headroom)
        modelUsage = try values.decodeIfPresent([ModelUsage].self, forKey: .modelUsage)
        dailyModelUsage = try values.decodeIfPresent([DailyModelUsage].self, forKey: .dailyModelUsage) ?? []
        topModelToday = try values.decodeIfPresent(String.self, forKey: .topModelToday)
        topModelLast7Days = try values.decodeIfPresent(String.self, forKey: .topModelLast7Days)
        topModelThisMonth = try values.decodeIfPresent(String.self, forKey: .topModelThisMonth)
        topModelLifetime = try values.decodeIfPresent(String.self, forKey: .topModelLifetime)
        currentModel = try values.decodeIfPresent(String.self, forKey: .currentModel)
        unpricedTokens = try values.decodeIfPresent(Int.self, forKey: .unpricedTokens)
        pricingVersion = try values.decodeIfPresent(String.self, forKey: .pricingVersion)
        rateLimits = try values.decodeIfPresent(CodexRateLimits.self, forKey: .rateLimits)
        accountLifetimeTokens = try values.decodeIfPresent(Int.self, forKey: .accountLifetimeTokens)
        accountUsageDays = try values.decodeIfPresent([AccountUsageDay].self, forKey: .accountUsageDays)
        accountUsageObservedAt = try values.decodeIfPresent(Date.self, forKey: .accountUsageObservedAt)
        recentSessions = try values.decodeIfPresent([CodexSessionSummary].self, forKey: .recentSessions) ?? []
        sessionActivity = try values.decodeIfPresent([CodexSessionActivity].self, forKey: .sessionActivity) ?? []
        appearanceTheme = try values.decodeIfPresent(String.self, forKey: .appearanceTheme)
    }
}

extension CodexUsageSnapshot {
    func mergingLegacyHistory(
        _ legacySnapshots: [CodexUsageSnapshot],
        calendar: Calendar = .current
    ) -> CodexUsageSnapshot {
        guard !legacySnapshots.isEmpty else { return self }
        var result = self
        var days = Dictionary(uniqueKeysWithValues: result.activityDays.map {
            var day = $0
            day.legacyCoverageIncomplete = nil
            return (calendar.startOfDay(for: day.date), day)
        })
        var importedDates = Set<Date>()

        for snapshot in legacySnapshots {
            for var day in snapshot.activityDays {
                let date = calendar.startOfDay(for: day.date)
                let existing = days[date]
                if let existing, existing.usage.hasUsage, day.usage.total > existing.usage.total {
                    // Daily aggregates have no session provenance; retain totals and disclose the overlap.
                    days[date]?.legacyCoverageIncomplete = true
                }
                guard existing == nil || existing?.usage.hasUsage == false && day.usage.hasUsage else {
                    continue
                }
                day.date = date
                days[date] = day
                guard day.usage.hasUsage else { continue }
                importedDates.insert(date)
                result.lifetime.add(day.usage)
                result.sessionCount = (result.sessionCount ?? 0) + day.sessions
                result.turnCount = (result.turnCount ?? 0) + (day.turns ?? 0)
            }
        }

        result.activityDays = days.values.sorted { $0.date < $1.date }
        guard !importedDates.isEmpty else { return result }

        var dailyModels = Dictionary(uniqueKeysWithValues: result.dailyModelUsage.map {
            (calendar.startOfDay(for: $0.date), $0)
        })
        for snapshot in legacySnapshots {
            for var day in snapshot.dailyModelUsage {
                let date = calendar.startOfDay(for: day.date)
                guard importedDates.contains(date), dailyModels[date] == nil else { continue }
                day.date = date
                dailyModels[date] = day
            }
        }
        result.dailyModelUsage = dailyModels.values.sorted { $0.date < $1.date }

        var models = Dictionary(uniqueKeysWithValues: (result.modelUsage ?? []).map { ($0.model, $0) })
        for day in result.dailyModelUsage where importedDates.contains(calendar.startOfDay(for: day.date)) {
            for model in day.models {
                var aggregate = models[model.model]
                    ?? ModelUsage(model: model.model, usage: .zero, turns: 0, estimatedCostUSD: 0)
                aggregate.usage.add(model.usage)
                aggregate.turns += model.turns
                aggregate.estimatedCostUSD += model.estimatedCostUSD
                models[model.model] = aggregate
            }
        }
        result.modelUsage = models.values.sorted { $0.usage.total > $1.usage.total }
        result.topModelLifetime = result.modelUsage?.first?.model
        result.peakDay = result.activityDays.max { $0.usage.total < $1.usage.total }
        return result
    }
}

struct CodexUsageWidgetSettings: Codable, Equatable {
    var chartDayCount: Int
    var showsStats: Bool
    var primaryMetric: PrimaryMetric
    var chartMetric: ChartMetric
    var statSlots: [StatMetric]
    var theme: WidgetTheme
    var density: WidgetDensity

    static let `default` = CodexUsageWidgetSettings(
        chartDayCount: 7,
        showsStats: true,
        primaryMetric: .currentSession,
        chartMetric: .totalTokens,
        statSlots: [.today, .costToday, .headroomToday, .currentModel],
        theme: .crimson,
        density: .balanced
    )

    enum CodingKeys: String, CodingKey {
        case chartDayCount
        case showsStats
        case primaryMetric
        case chartMetric
        case statSlots
        case theme
        case density
    }

    init(
        chartDayCount: Int,
        showsStats: Bool,
        primaryMetric: PrimaryMetric,
        chartMetric: ChartMetric,
        statSlots: [StatMetric],
        theme: WidgetTheme,
        density: WidgetDensity
    ) {
        self.chartDayCount = chartDayCount
        self.showsStats = showsStats
        self.primaryMetric = primaryMetric
        self.chartMetric = chartMetric
        self.statSlots = statSlots
        self.theme = theme
        self.density = density
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.chartDayCount = try container.decodeIfPresent(Int.self, forKey: .chartDayCount) ?? Self.default.chartDayCount
        self.showsStats = try container.decodeIfPresent(Bool.self, forKey: .showsStats) ?? Self.default.showsStats
        self.primaryMetric = try container.decodeIfPresent(PrimaryMetric.self, forKey: .primaryMetric) ?? Self.default.primaryMetric
        self.chartMetric = try container.decodeIfPresent(ChartMetric.self, forKey: .chartMetric) ?? Self.default.chartMetric
        self.statSlots = try container.decodeIfPresent([StatMetric].self, forKey: .statSlots) ?? Self.default.statSlots
        self.theme = try container.decodeIfPresent(WidgetTheme.self, forKey: .theme) ?? Self.default.theme
        self.density = try container.decodeIfPresent(WidgetDensity.self, forKey: .density) ?? Self.default.density
    }
}

enum CodexUsageWidgetSize: String, Codable, CaseIterable, Identifiable {
    case small
    case medium
    case large

    var id: String { rawValue }
}

struct CodexUsageWidgetSettingsBySize: Codable, Equatable {
    var small: CodexUsageWidgetSettings
    var medium: CodexUsageWidgetSettings
    var large: CodexUsageWidgetSettings

    static let `default` = CodexUsageWidgetSettingsBySize(
        small: {
            var settings = CodexUsageWidgetSettings.default
            settings.chartDayCount = 7
            settings.statSlots = [.today, .costToday, .headroomToday, .currentModel]
            return settings
        }(),
        medium: .default,
        large: {
            var settings = CodexUsageWidgetSettings.default
            settings.chartDayCount = 14
            settings.density = .detailed
            settings.statSlots = [.today, .costTracked, .headroomSaved, .currentModel]
            return settings
        }()
    )

    init(small: CodexUsageWidgetSettings, medium: CodexUsageWidgetSettings, large: CodexUsageWidgetSettings) {
        self.small = small
        self.medium = medium
        self.large = large
    }

    init(all settings: CodexUsageWidgetSettings) {
        self.init(small: settings, medium: settings, large: settings)
    }

    func settings(for size: CodexUsageWidgetSize) -> CodexUsageWidgetSettings {
        switch size {
        case .small: small
        case .medium: medium
        case .large: large
        }
    }

    mutating func set(_ settings: CodexUsageWidgetSettings, for size: CodexUsageWidgetSize) {
        switch size {
        case .small: small = settings
        case .medium: medium = settings
        case .large: large = settings
        }
    }
}

enum WidgetTheme: String, Codable, CaseIterable, Identifiable, Sendable {
    case runway
    case crimson
    case classicRed
    case darkGlass
    case frostedWhite
    case monochrome
    case rain
    case autumn

    var id: String { rawValue }

    var label: String {
        switch self {
        case .crimson: "Summer"
        case .classicRed: "Classic Red"
        case .darkGlass: "Graphite"
        case .frostedWhite: "Paper"
        case .runway: "Runway Glass"
        case .monochrome: "System mono"
        case .rain: "Vancouver Rain"
        case .autumn: "Autumn"
        }
    }
}

enum WidgetDensity: String, Codable, CaseIterable, Identifiable {
    case minimal
    case balanced
    case detailed

    var id: String { rawValue }

    var label: String {
        switch self {
        case .minimal: "Minimal"
        case .balanced: "Balanced"
        case .detailed: "Detailed"
        }
    }
}

enum PrimaryMetric: String, Codable, CaseIterable, Identifiable {
    case currentSession
    case today
    case last7Days
    case lifetime
    case peakDay
    case headroomSaved
    case estimatedCost
    case fiveHourLimit
    case weeklyLimit

    var id: String { rawValue }

    var label: String {
        switch self {
        case .currentSession: "Session Tokens"
        case .today: "Today Tokens"
        case .last7Days: "Last 7 Days"
        case .lifetime: "Lifetime Tokens"
        case .peakDay: "Peak Day"
        case .headroomSaved: "Headroom Tokens Saved"
        case .estimatedCost: "Total API Estimate"
        case .fiveHourLimit: "5-Hour Remaining"
        case .weeklyLimit: "Weekly Remaining"
        }
    }

    func value(in snapshot: CodexUsageSnapshot) -> Int {
        switch self {
        case .currentSession: snapshot.currentSession.total
        case .today: snapshot.today.total
        case .last7Days: snapshot.last7DaysUsage.total
        case .lifetime: snapshot.accountLifetimeTokens ?? snapshot.lifetime.total
        case .peakDay: snapshot.peakDay?.usage.total ?? 0
        case .headroomSaved: snapshot.headroom?.lifetimeTokensSaved ?? 0
        case .estimatedCost: Int((snapshot.estimatedCostUSD * 1_000_000).rounded())
        case .fiveHourLimit: Int((snapshot.rateLimits?.fiveHour?.remainingPercent ?? 0).rounded())
        case .weeklyLimit: Int((snapshot.rateLimits?.weekly?.remainingPercent ?? 0).rounded())
        }
    }

    func displayValue(in snapshot: CodexUsageSnapshot) -> String {
        switch self {
        case .estimatedCost: snapshot.estimatedCostUSD.compactCurrencyString
        case .fiveHourLimit:
            snapshot.rateLimits?.fiveHour.map { "\(Int($0.remainingPercent.rounded()))%" } ?? "—"
        case .weeklyLimit:
            snapshot.rateLimits?.weekly.map { "\(Int($0.remainingPercent.rounded()))%" } ?? "—"
        default: value(in: snapshot).compactTokenString
        }
    }
}

enum ChartMetric: String, Codable, CaseIterable, Identifiable {
    case totalTokens
    case inputTokens
    case cachedTokens
    case outputTokens
    case reasoningTokens
    case sessions
    case turns
    case headroomSavings
    case estimatedCost

    var id: String { rawValue }

    var label: String {
        switch self {
        case .totalTokens: "Total Tokens"
        case .inputTokens: "Input"
        case .cachedTokens: "Cached Input"
        case .outputTokens: "Output"
        case .reasoningTokens: "Reasoning"
        case .sessions: "Sessions"
        case .turns: "Requests"
        case .headroomSavings: "Headroom Tokens Saved"
        case .estimatedCost: "Estimated API Cost"
        }
    }

    func value(in day: DailyUsage) -> Int {
        switch self {
        case .totalTokens: day.usage.total
        case .inputTokens: day.usage.input
        case .cachedTokens: day.usage.cachedInput
        case .outputTokens: day.usage.output
        case .reasoningTokens: day.usage.reasoningOutput
        case .sessions: day.sessions
        case .turns: day.turns ?? 0
        case .headroomSavings: day.headroomSaved ?? 0
        case .estimatedCost: day.estimatedCostMicros ?? 0
        }
    }

    func displayValue(_ value: Int) -> String {
        self == .estimatedCost ? (Double(value) / 1_000_000).compactCurrencyString : value.compactTokenString
    }
}

enum StatMetric: String, Codable, CaseIterable, Identifiable {
    case currentSession
    case today
    case last7Days
    case lifetime
    case peakDay
    case sessionsToday
    case totalSessions
    case turnsToday
    case averageSession
    case cachedToday
    case currentStreak
    case longestStreak
    case contextUsed
    case headroomToday
    case headroomSaved
    case headroomRate
    case headroomCost
    case weeklyGoal
    case costToday
    case costTracked
    case currentModel
    case topModelToday
    case topModelLast7Days
    case topModelThisMonth
    case topModelLifetime
    case unpricedTokens
    case fiveHourLimit
    case weeklyLimit
    case limitPace
    case nextReset

    var id: String { rawValue }

    var label: String {
        switch self {
        case .currentSession: "Session"
        case .today: "Today"
        case .last7Days: "7 Days"
        case .lifetime: "Lifetime"
        case .peakDay: "Peak"
        case .sessionsToday: "Sessions Today"
        case .totalSessions: "All Sessions"
        case .turnsToday: "Requests Today"
        case .averageSession: "Avg / Session"
        case .cachedToday: "Cached Today"
        case .currentStreak: "Streak"
        case .longestStreak: "Longest"
        case .contextUsed: "Context"
        case .headroomToday: "Tokens Saved Today"
        case .headroomSaved: "Headroom Tokens"
        case .headroomRate: "Savings Rate"
        case .headroomCost: "Cost Avoided"
        case .weeklyGoal: "Goal (legacy)"
        case .costToday: "API Est. Today"
        case .costTracked: "Total API Estimate"
        case .currentModel: "Current Model"
        case .topModelToday: "Top Model Today"
        case .topModelLast7Days: "Top Model · 7 Days"
        case .topModelThisMonth: "Top Model · Month"
        case .topModelLifetime: "Top Model · Lifetime"
        case .unpricedTokens: "Unpriced"
        case .fiveHourLimit: "5-Hour Remaining"
        case .weeklyLimit: "Weekly Remaining"
        case .limitPace: "Limit Pace"
        case .nextReset: "Next Reset"
        }
    }

    func value(in snapshot: CodexUsageSnapshot, settings: CodexUsageWidgetSettings? = nil) -> String {
        switch self {
        case .currentSession: return snapshot.currentSession.total.compactTokenString
        case .today: return snapshot.today.total.compactTokenString
        case .last7Days: return snapshot.last7DaysUsage.total.compactTokenString
        case .lifetime: return (snapshot.accountLifetimeTokens ?? snapshot.lifetime.total).compactTokenString
        case .peakDay: return (snapshot.peakDay?.usage.total ?? 0).compactTokenString
        case .sessionsToday: return snapshot.todaySessionCount.formatted()
        case .totalSessions: return (snapshot.sessionCount ?? 0).formatted()
        case .turnsToday: return snapshot.todayTurnCount.formatted()
        case .averageSession: return snapshot.averageSessionTokens.compactTokenString
        case .cachedToday: return snapshot.today.cachedInput.compactTokenString
        case .currentStreak: return "\(snapshot.currentStreak)d"
        case .longestStreak: return "\(snapshot.longestStreak)d"
        case .contextUsed:
            guard let percent = snapshot.contextUsedPercent else { return "—" }
            return "\(Int((percent * 100).rounded()))%"
        case .headroomToday:
            guard let headroom = snapshot.headroom, headroom.isAvailable else { return "—" }
            return headroom.todayTokensSaved.compactTokenString
        case .headroomSaved:
            guard let headroom = snapshot.headroom, headroom.isAvailable else { return "—" }
            return headroom.lifetimeTokensSaved.compactTokenString
        case .headroomRate:
            guard let headroom = snapshot.headroom, headroom.isAvailable else { return "—" }
            return headroom.savingsPercent.compactPercentString
        case .headroomCost:
            guard let headroom = snapshot.headroom, headroom.isAvailable else { return "—" }
            return headroom.costSavedUSD.compactCurrencyString
        case .weeklyGoal: return "Off"
        case .costToday: return snapshot.todayEstimatedCostUSD.compactCurrencyString
        case .costTracked: return snapshot.estimatedCostUSD.compactCurrencyString
        case .currentModel: return ModelPricingCatalog.displayName(for: snapshot.currentModel)
        case .topModelToday: return ModelPricingCatalog.displayName(for: snapshot.topModelToday)
        case .topModelLast7Days: return ModelPricingCatalog.displayName(for: snapshot.topModelLast7Days)
        case .topModelThisMonth: return ModelPricingCatalog.displayName(for: snapshot.topModelThisMonth)
        case .topModelLifetime: return ModelPricingCatalog.displayName(for: snapshot.topModelLifetime)
        case .unpricedTokens: return (snapshot.unpricedTokens ?? 0).compactTokenString
        case .fiveHourLimit:
            return snapshot.rateLimits?.fiveHour.map { "\(Int($0.remainingPercent.rounded()))%" } ?? "—"
        case .weeklyLimit:
            return snapshot.rateLimits?.weekly.map { "\(Int($0.remainingPercent.rounded()))%" } ?? "—"
        case .limitPace: return snapshot.rateLimits?.pace.label ?? "Unavailable"
        case .nextReset: return snapshot.rateLimits?.nearestReset?.resetText() ?? "—"
        }
    }

    static var selectableCases: [StatMetric] {
        allCases.filter { $0 != .weeklyGoal }
    }
}

extension CodexUsageWidgetSettings {
    var normalizedStatSlots: [StatMetric] {
        let defaults = CodexUsageWidgetSettings.default.statSlots
        var result: [StatMetric] = []
        for metric in statSlots + defaults + StatMetric.selectableCases where metric != .weeklyGoal && !result.contains(metric) {
            result.append(metric)
            if result.count == 4 { break }
        }
        return result
    }

    func visibleStatSlots(excluding primary: PrimaryMetric, limit: Int) -> [StatMetric] {
        var result: [StatMetric] = []
        for metric in normalizedStatSlots + StatMetric.selectableCases where !metric.matches(primary) && !result.contains(metric) {
            result.append(metric)
            if result.count == limit { break }
        }
        return result
    }
}

extension CodexUsageSnapshot {
    func chartDays(count: Int, maxVisible: Int) -> [DailyUsage] {
        Array(activityDays.suffix(max(1, min(count, maxVisible))))
    }

    var last7DaysUsage: TokenUsage {
        activityDays.suffix(7).reduce(into: .zero) { $0.add($1.usage) }
    }

    var previous7DaysUsage: TokenUsage {
        activityDays.dropLast(7).suffix(7).reduce(into: .zero) { $0.add($1.usage) }
    }

    var last7DaysDeltaPercent: Double? {
        guard previous7DaysUsage.total > 0 else { return nil }
        return Double(last7DaysUsage.total - previous7DaysUsage.total) / Double(previous7DaysUsage.total)
    }

    var todaySessionCount: Int {
        activityDays.last?.sessions ?? 0
    }

    var todayTurnCount: Int {
        activityDays.last?.turns ?? 0
    }

    var estimatedCostUSD: Double {
        modelUsage?.reduce(0) { $0 + $1.estimatedCostUSD } ?? 0
    }

    var todayEstimatedCostUSD: Double {
        Double(activityDays.last?.estimatedCostMicros ?? 0) / 1_000_000
    }

    var last7DaysEstimatedCostUSD: Double {
        Double(activityDays.suffix(7).reduce(0) { $0 + ($1.estimatedCostMicros ?? 0) }) / 1_000_000
    }

    var averageSessionTokens: Int {
        guard let sessionCount, sessionCount > 0 else { return 0 }
        return lifetime.total / sessionCount
    }

    var contextUsedPercent: Double? {
        guard let currentContextTokens, let contextWindow, contextWindow > 0 else { return nil }
        return min(1, Double(currentContextTokens) / Double(contextWindow))
    }

    var hasUsage: Bool {
        lifetime.hasUsage || accountLifetimeTokens != nil || headroom?.isAvailable == true
    }

    var cachedHeadroomActivity: HeadroomActivity? {
        guard let headroom, headroom.isAvailable else { return nil }
        let pairs: [(Date, Int)] = activityDays.compactMap { day in
            guard let saved = day.headroomSaved else { return nil }
            return (day.date, saved)
        }
        let byDay = Dictionary(uniqueKeysWithValues: pairs)
        return HeadroomActivity(savings: headroom, tokensSavedByDay: byDay)
    }
}

extension PrimaryMetric {
    var shortLabel: String {
        switch self {
        case .currentSession: "Session"
        case .today: "Today"
        case .last7Days: "Last 7 Days"
        case .lifetime: "Lifetime"
        case .peakDay: "Peak Day"
        case .headroomSaved: "Headroom Tokens"
        case .estimatedCost: "Total API Estimate"
        case .fiveHourLimit: "5-Hour Left"
        case .weeklyLimit: "Weekly Left"
        }
    }
}

extension ChartMetric {
    var shortLabel: String {
        switch self {
        case .totalTokens: "Tokens"
        case .inputTokens: "Input"
        case .cachedTokens: "Cached"
        case .outputTokens: "Output"
        case .reasoningTokens: "Reasoning"
        case .sessions: "Sessions"
        case .turns: "Requests"
        case .headroomSavings: "Saved"
        case .estimatedCost: "Est. Cost"
        }
    }
}

extension StatMetric {
    func matches(_ primary: PrimaryMetric) -> Bool {
        switch (self, primary) {
        case (.currentSession, .currentSession),
             (.today, .today),
             (.last7Days, .last7Days),
             (.lifetime, .lifetime),
             (.peakDay, .peakDay),
             (.headroomSaved, .headroomSaved),
             (.costTracked, .estimatedCost),
             (.fiveHourLimit, .fiveHourLimit),
             (.weeklyLimit, .weeklyLimit):
            return true
        default:
            return false
        }
    }
}

struct CodexUsageReader {
    var sessionsDirectory: URL
    var archivedSessionsDirectory: URL?
    var calendar: Calendar
    var activityDayCount: Int
    var cacheURL: URL?

    init(
        sessionsDirectory: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/sessions"),
        calendar: Calendar = .current,
        activityDayCount: Int = 0,
        cacheURL: URL? = nil,
        archivedSessionsDirectory: URL? = nil
    ) {
        self.sessionsDirectory = sessionsDirectory
        self.calendar = calendar
        self.activityDayCount = activityDayCount
        let defaultSessionsDirectory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/sessions")
        self.archivedSessionsDirectory = archivedSessionsDirectory ?? (
            sessionsDirectory.standardizedFileURL == defaultSessionsDirectory.standardizedFileURL
                ? defaultSessionsDirectory.deletingLastPathComponent().appendingPathComponent("archived_sessions") : nil)
        self.cacheURL = cacheURL ?? (
            sessionsDirectory.standardizedFileURL == defaultSessionsDirectory.standardizedFileURL
                ? CodexUsageSnapshotStore.readerCacheURL
                : nil
        )
    }

    func sourceFingerprint(now: Date = Date()) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        let prime: UInt64 = 1_099_511_628_211
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let calendarData = (try? encoder.encode(calendar)) ?? Data()
        for byte in calendarData + Data("|\(calendar.timeZone.secondsFromGMT(for: now))".utf8) {
            hash = (hash ^ UInt64(byte)) &* prime
        }
        var failedSubtrees = Set<String>()
        let files = jsonlFiles { failed in _ = failedSubtrees.insert(canonicalSourcePath(failed)) }
        for file in files.sorted(by: { $0.path < $1.path }) {
            var metadata = stat()
            let status = file.withUnsafeFileSystemRepresentation { pointer in
                guard let pointer else { errno = EINVAL; return Int32(-1) }
                return Darwin.fstatat(AT_FDCWD, pointer, &metadata, 0)
            }
            let parts = [
                file.path,
                String(status), String(metadata.st_dev), String(metadata.st_ino), String(metadata.st_size),
                String(metadata.st_mtimespec.tv_sec), String(metadata.st_mtimespec.tv_nsec),
                String(metadata.st_ctimespec.tv_sec), String(metadata.st_ctimespec.tv_nsec)
            ]
            for byte in parts.joined(separator: "|").utf8 {
                hash = (hash ^ UInt64(byte)) &* prime
            }
        }
        for failed in failedSubtrees.sorted() {
            for byte in ("|unreadable-subtree|" + failed).utf8 {
                hash = (hash ^ UInt64(byte)) &* prime
            }
        }
        return "session-activity-v7|" + String(hash, radix: 16)
    }

    func snapshot(now: Date = Date(), headroomActivity: HeadroomActivity? = nil) -> CodexUsageSnapshot {
        snapshotResult(now: now, headroomActivity: headroomActivity).snapshot
    }

    func snapshotResult(now: Date = Date(), headroomActivity: HeadroomActivity? = nil)
        -> (snapshot: CodexUsageSnapshot, sourceReadPending: Bool) {
        // Detached tasks do not provide a per-refresh Foundation autorelease pool.
        // Keep only the returned value alive after parsing and cache serialization.
        autoreleasepool { makeSnapshot(now: now, headroomActivity: headroomActivity) }
    }

    private func makeSnapshot(now: Date, headroomActivity: HeadroomActivity?)
        -> (snapshot: CodexUsageSnapshot, sourceReadPending: Bool) {
        let read = parsedFilesUsingCache(now: now)
        let parsedFiles = read.files
        let observedFiles = deduplicatedFiles(parsedFiles.filter { !$0.isSubagent })
        let files = observedFiles.filter { !$0.samples.isEmpty }
        let rateLimits = rateLimitSnapshot(from: parsedFiles.flatMap(\.rateLimits), now: now)
        let sessions = groupedSessions(files)
        let startOfToday = calendar.startOfDay(for: now)
        let startOfLast7Days = calendar.date(byAdding: .day, value: -6, to: startOfToday) ?? startOfToday
        let startOfLast30Days = calendar.date(byAdding: .day, value: -29, to: startOfToday) ?? startOfToday
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? startOfToday
        var lifetime = TokenUsage.zero
        var byDay: [Date: DayAggregate] = [:]
        var totalTurns = 0
        var modelAggregates: [String: (usage: TokenUsage, turns: Int, cost: Double)] = [:]
        var dailyModelAggregates: [Date: [String: (usage: TokenUsage, turns: Int, cost: Double)]] = [:]
        var modelTokensToday: [String: Int] = [:]
        var modelTokensLast7Days: [String: Int] = [:]
        var modelTokensThisMonth: [String: Int] = [:]
        var unpricedTokens = 0

        for session in sessions {
            lifetime.add(session.total)
            totalTurns += session.samples.count
            for sample in session.samples {
                let model = sample.model ?? "Unknown"
                let pricing = ModelPricingCatalog.pricing(for: sample.model)
                let estimatedCost = pricing?.estimatedCost(for: sample.usage) ?? 0
                var aggregate = modelAggregates[model] ?? (.zero, 0, 0)
                aggregate.usage.add(sample.usage)
                aggregate.turns += 1
                aggregate.cost += estimatedCost
                if pricing == nil {
                    unpricedTokens += sample.usage.total
                }
                modelAggregates[model] = aggregate

                let day = calendar.startOfDay(for: sample.timestamp)
                var dailyModels = dailyModelAggregates[day] ?? [:]
                var dailyModel = dailyModels[model] ?? (.zero, 0, 0)
                dailyModel.usage.add(sample.usage)
                dailyModel.turns += 1
                dailyModel.cost += estimatedCost
                dailyModels[model] = dailyModel
                dailyModelAggregates[day] = dailyModels

                if day == startOfToday { modelTokensToday[model, default: 0] += sample.usage.total }
                if day >= startOfLast7Days, day <= startOfToday {
                    modelTokensLast7Days[model, default: 0] += sample.usage.total
                }
                if day >= startOfMonth, day <= startOfToday {
                    modelTokensThisMonth[model, default: 0] += sample.usage.total
                }
            }
            let groupedByDay = Dictionary(grouping: session.samples) { calendar.startOfDay(for: $0.timestamp) }
            for (day, samples) in groupedByDay {
                var daily = byDay[day] ?? DayAggregate()
                for sample in samples {
                    daily.usage.add(sample.usage)
                    daily.estimatedCostUSD += ModelPricingCatalog.pricing(for: sample.model)?.estimatedCost(for: sample.usage) ?? 0
                }
                daily.sessions += 1
                daily.turns += samples.count
                byDay[day] = daily
            }
        }

        let newest = sessions.max { lhs, rhs in
            (lhs.latestSample?.timestamp ?? .distantPast) < (rhs.latestSample?.timestamp ?? .distantPast)
        }
        let headroomByDay = headroomActivity?.tokensSavedByDay ?? [:]
        let activityDays = recentDays(endingAt: startOfToday, byDay: byDay, headroomByDay: headroomByDay)
        let peakDay = byDay
            .map {
                DailyUsage(
                    date: $0.key,
                    usage: $0.value.usage,
                    sessions: $0.value.sessions,
                    turns: $0.value.turns,
                    estimatedCostMicros: Int(($0.value.estimatedCostUSD * 1_000_000).rounded())
                )
            }
            .max { $0.usage.total < $1.usage.total }
        let modelUsage = modelAggregates.map { model, aggregate in
            ModelUsage(
                model: model,
                usage: aggregate.usage,
                turns: aggregate.turns,
                estimatedCostUSD: aggregate.cost
            )
        }.sorted { $0.usage.total > $1.usage.total }
        let dailyModelUsage = dailyModelAggregates.map { date, aggregates in
            DailyModelUsage(
                date: date,
                models: aggregates.map { model, aggregate in
                    ModelUsage(
                        model: model,
                        usage: aggregate.usage,
                        turns: aggregate.turns,
                        estimatedCostUSD: aggregate.cost
                    )
                }.sorted { $0.usage.total > $1.usage.total }
            )
        }.sorted { $0.date < $1.date }
        let recentSessions = recentSessionSummaries(
            from: sessions,
            since: startOfLast30Days,
            through: now
        )
        let sessionByID = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0) })
        let latestActivity = Dictionary(grouping: observedFiles, by: \.sessionID).compactMap { id, files in
            guard var activity = files.compactMap(\.activity).max(by: {
                ($0.observedAt ?? .distantPast) < ($1.observedAt ?? .distantPast)
            }), let observedAt = activity.observedAt, observedAt <= now,
                  observedAt >= startOfLast30Days else { return nil as CodexSessionActivity? }
            activity.id = id
            let session = sessionByID[id]
            activity.usage = session?.total ?? .zero
            activity.requests = session?.samples.count ?? 0
            activity.contextTokens = session?.latestSample?.contextTokens
            activity.contextWindow = activity.contextWindow ?? session?.latestSample?.contextWindow
            var total = 0
            let points = (session?.samples ?? []).sorted { $0.timestamp < $1.timestamp }.map { sample in
                total += sample.usage.total
                return CodexTokenPoint(date: sample.timestamp, totalTokens: total)
            }
            activity.usageHistory = Dictionary(grouping: points, by: \.date).compactMap { $0.value.last }
                .sorted { $0.date < $1.date }.suffix(120).map { $0 }
            return activity
        }.sorted { ($0.observedAt ?? .distantPast) > ($1.observedAt ?? .distantPast) }

        return (CodexUsageSnapshot(
            currentSession: newest?.total ?? .zero,
            lifetime: lifetime,
            today: byDay[startOfToday]?.usage ?? .zero,
            peakDay: peakDay,
            currentStreak: currentStreak(endingAt: startOfToday, byDay: byDay),
            longestStreak: longestStreak(byDay: byDay),
            lastUpdated: newest?.latestSample?.timestamp,
            activityDays: activityDays,
            generatedAt: now,
            sessionCount: sessions.count,
            turnCount: totalTurns,
            currentSessionTurns: newest?.samples.count ?? 0,
            currentSessionStartedAt: newest?.startedAt,
            currentContextTokens: newest?.latestSample?.contextTokens,
            contextWindow: newest?.latestSample?.contextWindow,
            headroom: headroomActivity?.savings.isAvailable == true ? headroomActivity?.savings : nil,
            modelUsage: modelUsage,
            dailyModelUsage: dailyModelUsage,
            topModelToday: topModel(in: modelTokensToday),
            topModelLast7Days: topModel(in: modelTokensLast7Days),
            topModelThisMonth: topModel(in: modelTokensThisMonth),
            topModelLifetime: modelUsage.first?.model,
            currentModel: newest?.latestSample?.model,
            unpricedTokens: unpricedTokens,
            pricingVersion: ModelPricingCatalog.version,
            rateLimits: rateLimits,
            recentSessions: recentSessions,
            sessionActivity: Array(latestActivity.prefix(12))
        ), read.sourceReadPending)
    }

    private func recentSessionSummaries(
        from sessions: [SessionUsage],
        since startDate: Date,
        through endDate: Date
    ) -> [CodexSessionSummary] {
        sessions.flatMap { session in
            let samplesByDay = Dictionary(grouping: session.samples.filter {
                $0.timestamp >= startDate && $0.timestamp <= endDate
            }) {
                calendar.startOfDay(for: $0.timestamp)
            }

            return samplesByDay.compactMap { (day, samples) -> CodexSessionSummary? in
                let samples = samples.sorted { $0.timestamp < $1.timestamp }
                guard let first = samples.first, let last = samples.last else { return nil }

                var usage = TokenUsage.zero
                var tokensByModel: [String: Int] = [:]
                var estimatedCostUSD = 0.0
                var hasPricedUsage = false
                for sample in samples {
                    usage.add(sample.usage)
                    let model = sample.model ?? "Unknown"
                    tokensByModel[model, default: 0] += sample.usage.total
                    if let pricing = ModelPricingCatalog.pricing(for: sample.model) {
                        estimatedCostUSD += pricing.estimatedCost(for: sample.usage)
                        hasPricedUsage = true
                    }
                }

                let primaryModel = tokensByModel.sorted {
                    $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value
                }.first?.key ?? "Unknown"
                let startedAt = session.startedAt.map {
                    calendar.isDate($0, inSameDayAs: day) ? $0 : first.timestamp
                } ?? first.timestamp

                return CodexSessionSummary(
                    id: "\(session.id)#\(Int(day.timeIntervalSinceReferenceDate))",
                    startedAt: startedAt,
                    updatedAt: last.timestamp,
                    usage: usage,
                    turns: samples.count,
                    model: primaryModel,
                    estimatedCostUSD: hasPricedUsage ? estimatedCostUSD : nil
                )
            }
        }
        .sorted { $0.updatedAt > $1.updatedAt }
    }

    private func rateLimitSnapshot(from samples: [RateLimitSample], now: Date) -> CodexRateLimits? {
        guard !samples.isEmpty else { return nil }
        let sorted = samples.sorted { $0.observedAt < $1.observedAt }

        func currentWindow(minutes: Int) -> RateLimitWindow? {
            sorted.last { $0.windowMinutes == minutes }.map {
                RateLimitWindow(
                    usedPercent: $0.usedPercent,
                    windowMinutes: $0.windowMinutes,
                    resetsAt: $0.resetsAt,
                    observedAt: $0.observedAt
                )
            }.flatMap { $0.isCurrent(at: now) ? $0 : nil }
        }

        let cutoff = calendar.date(byAdding: .day, value: -7, to: now) ?? now.addingTimeInterval(-604_800)
        var hourly: [Date: RateLimitHistoryPoint] = [:]
        for sample in sorted where sample.observedAt >= cutoff {
            let hour = calendar.dateInterval(of: .hour, for: sample.observedAt)?.start ?? sample.observedAt
            var point = hourly[hour] ?? RateLimitHistoryPoint(
                date: hour,
                fiveHourUsedPercent: nil,
                weeklyUsedPercent: nil
            )
            if sample.windowMinutes == 300 {
                point.fiveHourUsedPercent = sample.usedPercent
            } else if sample.windowMinutes == 10_080 {
                point.weeklyUsedPercent = sample.usedPercent
            }
            hourly[hour] = point
        }

        let result = CodexRateLimits(
            fiveHour: currentWindow(minutes: 300),
            weekly: currentWindow(minutes: 10_080),
            history: hourly.values.sorted { $0.date < $1.date },
            consumptionSamples: Self.consumptionSamples(from: sorted.map {
                RateLimitWindow(usedPercent: $0.usedPercent, windowMinutes: $0.windowMinutes,
                    resetsAt: $0.resetsAt, observedAt: $0.observedAt)
            }, now: now)
        )
        return result.fiveHour == nil && result.weekly == nil && result.history.isEmpty ? nil : result
    }

    private static func consumptionSamples(from samples: [RateLimitWindow], now: Date) -> [RateLimitWindow] {
        // Bound snapshot size to at most one observation per minute per allowance.
        var minutes: [String: RateLimitWindow] = [:]
        for sample in samples where sample.observedAt >= now.addingTimeInterval(-3_600)
            && sample.observedAt <= now && [300, 10_080].contains(sample.windowMinutes) {
            let key = "\(sample.windowMinutes):\(Int(sample.observedAt.timeIntervalSince1970 / 60))"
            if minutes[key].map({ $0.observedAt <= sample.observedAt }) ?? true { minutes[key] = sample }
        }
        return minutes.values.sorted { $0.observedAt < $1.observedAt }
    }

    private func topModel(in totals: [String: Int]) -> String? {
        totals.max { lhs, rhs in
            lhs.value == rhs.value ? lhs.key > rhs.key : lhs.value < rhs.value
        }?.key
    }

    private func recentDays(
        endingAt today: Date,
        byDay: [Date: DayAggregate],
        headroomByDay: [Date: Int]
    ) -> [DailyUsage] {
        let earliestRecordedDay = (Array(byDay.keys) + Array(headroomByDay.keys))
            .map { calendar.startOfDay(for: $0) }
            .min() ?? today
        let earliestDay = activityDayCount > 0
            ? max(
                earliestRecordedDay,
                calendar.date(byAdding: .day, value: 1 - activityDayCount, to: today) ?? earliestRecordedDay
            )
            : earliestRecordedDay
        let dayCount = max(1, (calendar.dateComponents([.day], from: earliestDay, to: today).day ?? 0) + 1)

        return (0..<dayCount).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: earliestDay) else {
                return nil
            }
            let entry = byDay[day] ?? DayAggregate()
            return DailyUsage(
                date: day,
                usage: entry.usage,
                sessions: entry.sessions,
                turns: entry.turns,
                headroomSaved: headroomByDay[day],
                estimatedCostMicros: Int((entry.estimatedCostUSD * 1_000_000).rounded())
            )
        }
    }

    private func currentStreak(endingAt today: Date, byDay: [Date: DayAggregate]) -> Int {
        var streak = 0
        var day = today
        while (byDay[day]?.usage.total ?? 0) > 0 {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return streak
    }

    private func longestStreak(byDay: [Date: DayAggregate]) -> Int {
        let activeDays = byDay
            .filter { $0.value.usage.total > 0 }
            .map(\.key)
            .sorted()

        var best = 0
        var current = 0
        var previous: Date?

        for day in activeDays {
            if let previous, calendar.dateComponents([.day], from: previous, to: day).day == 1 {
                current += 1
            } else {
                current = 1
            }
            best = max(best, current)
            previous = day
        }

        return best
    }

    private func jsonlFiles(onEnumerationError: ((URL) -> Void)? = nil) -> [URL] {
        [sessionsDirectory, archivedSessionsDirectory].compactMap { $0 }.flatMap { directory -> [URL] in
            guard let enumerator = FileManager.default.enumerator(
                at: directory, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles], errorHandler: { url, error in
                    if !isMissingSource(error) { onEnumerationError?(url) }
                    return true
                }) else {
                var metadata = stat()
                let status = directory.withUnsafeFileSystemRepresentation { pointer in
                    guard let pointer else { errno = EINVAL; return Int32(-1) }
                    return Darwin.fstatat(AT_FDCWD, pointer, &metadata, 0)
                }
                if status == 0 || (errno != ENOENT && errno != ENOTDIR) { onEnumerationError?(directory) }
                return []
            }
            return enumerator.compactMap { item in
                guard let url = item as? URL, url.pathExtension == "jsonl" else { return nil }
                return url
            }
        }
    }

    private func parsedFilesUsingCache(now: Date) -> (files: [ParsedFile], sourceReadPending: Bool) {
        let existingCache = autoreleasepool { loadReaderCache(now: now) }
        var nextEntries: [String: CachedFile] = [:]
        var parsedFiles: [ParsedFile] = []
        var sourceReadPending = false
        var failedSubtrees: [String] = []
        let files = jsonlFiles { failed in
            failedSubtrees.append(canonicalSourcePath(failed))
            sourceReadPending = true
        }

        for file in files {
            let path = file.path
            let values = try? file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            let fileSize = values?.fileSize ?? -1
            let modificationTime = values?.contentModificationDate?.timeIntervalSince1970 ?? -1
            var metadata = stat()
            let hasMetadata = file.withUnsafeFileSystemRepresentation { pointer in
                guard let pointer else { return false }
                return Darwin.fstatat(AT_FDCWD, pointer, &metadata, 0) == 0
            }

            let cached = existingCache.entries[path]
            let invalidCheckpoint = cached?.checkpoint != nil && cached?.parsedFile == nil
                && cached?.checkpoint?.activity == nil
            var unchanged = cached?.fileSize == fileSize && cached?.modificationTime == modificationTime
                && fileSize >= 0 && values?.contentModificationDate != nil && hasMetadata
                && !invalidCheckpoint
            let identity = hasMetadata ? JSONLFileReader.SourceIdentity(
                device: UInt64(UInt32(bitPattern: metadata.st_dev)), inode: UInt64(metadata.st_ino)) : nil
            if let expectedIdentity = cached?.checkpoint?.progress.identity ?? cached?.sourceIdentity {
                unchanged = unchanged && expectedIdentity == identity
            }
            if let changeTime = cached?.changeTimeSeconds {
                unchanged = unchanged && changeTime == Int64(metadata.st_ctimespec.tv_sec)
                    && cached?.changeTimeNanoseconds == Int64(metadata.st_ctimespec.tv_nsec)
            }

            let entry: CachedFile?
            if unchanged {
                var trusted = cached
                trusted?.changeTimeSeconds = Int64(metadata.st_ctimespec.tv_sec)
                trusted?.changeTimeNanoseconds = Int64(metadata.st_ctimespec.tv_nsec)
                let fallbackIdentity = trusted?.checkpoint == nil ? identity : nil
                trusted?.sourceIdentity = fallbackIdentity
                entry = trusted
            } else {
                do {
                    let read: (parsed: ParsedFile?, checkpoint: ParserCheckpoint)
                    if !invalidCheckpoint, let cached, let checkpoint = cached.checkpoint,
                       checkpoint.progress.endedWithNewline,
                       cached.fileSize >= 0, UInt64(cached.fileSize) == checkpoint.progress.bytesRead,
                       fileSize > cached.fileSize {
                        do {
                            read = try parseSessionFile(file, resuming: cached)
                        } catch let error as JSONLFileReader.ReadError {
                            switch error {
                            case .invalidOffset, .sourceReplaced, .prefixMismatch:
                                read = try parseSessionFile(file)
                            case .sourceChanged:
                                throw error
                            }
                        }
                    } else {
                        read = try parseSessionFile(file)
                    }
                    entry = CachedFile(fileSize: Int(read.checkpoint.progress.bytesRead),
                        modificationTime: modificationTime, parsedFile: read.parsed, checkpoint: read.checkpoint,
                        changeTimeSeconds: hasMetadata ? Int64(metadata.st_ctimespec.tv_sec) : nil,
                        changeTimeNanoseconds: hasMetadata ? Int64(metadata.st_ctimespec.tv_nsec) : nil)
                } catch {
                    // A failed read must retain known usage and remain eligible for retry.
                    if isMissingSource(error) {
                        entry = nil
                    } else {
                        sourceReadPending = true
                        entry = cached
                    }
                }
            }
            if let entry {
                nextEntries[path] = entry
                if let parsed = entry.parsedFile { parsedFiles.append(parsed) }
            }
        }
        for (path, entry) in existingCache.entries where nextEntries[path] == nil {
            let normalized = canonicalSourcePath(URL(fileURLWithPath: path))
            if failedSubtrees.contains(where: { normalized == $0 || normalized.hasPrefix($0 + "/") }) {
                nextEntries[path] = entry
                if let parsed = entry.parsedFile { parsedFiles.append(parsed) }
            }
        }

        autoreleasepool {
            saveReaderCache(ReaderCache(schemaVersion: ReaderCache.currentSchemaVersion, entries: nextEntries), now: now)
        }
        return (parsedFiles, sourceReadPending)
    }

    private func canonicalSourcePath(_ url: URL) -> String {
        var ancestor = url.standardizedFileURL
        var suffix: [String] = []
        while true {
            if let resolved = ancestor.path.withCString({ Darwin.realpath($0, nil) }) {
                let prefix = String(cString: resolved)
                free(resolved)
                guard !suffix.isEmpty else { return prefix }
                return prefix + (prefix.hasSuffix("/") ? "" : "/") + suffix.reversed().joined(separator: "/")
            }
            guard ancestor.path != "/" else { return url.standardizedFileURL.path }
            suffix.append(ancestor.lastPathComponent)
            ancestor.deleteLastPathComponent()
        }
    }

    private func isMissingSource(_ error: Error) -> Bool {
        let error = error as NSError
        return error.domain == NSPOSIXErrorDomain && [Int(ENOENT), Int(ENOTDIR)].contains(error.code)
            || error.domain == NSCocoaErrorDomain
                && [CocoaError.fileNoSuchFile.rawValue, CocoaError.fileReadNoSuchFile.rawValue].contains(error.code)
    }

    private func loadReaderCache(now: Date) -> ReaderCache {
        guard let cacheURL else {
            return ReaderCache(schemaVersion: ReaderCache.currentSchemaVersion, entries: [:])
        }
        let candidates = cacheURL == CodexUsageSnapshotStore.readerCacheURL
            ? [cacheURL, CodexUsageSnapshotStore.legacyReaderCacheURL]
            : [cacheURL]
        func isUsable(_ cache: ReaderCache) -> Bool {
            if cache.schemaVersion == 6 { return true }
            guard cache.schemaVersion == ReaderCache.currentSchemaVersion else { return false }
            if cache.entries.isEmpty { return true }
            guard cache.calendar == calendar, let anchor = cache.pruningAnchor, anchor <= now else { return false }
            let previousCutoff = calendar.date(byAdding: .day, value: -7, to: anchor) ?? anchor.addingTimeInterval(-604_800)
            let currentCutoff = calendar.date(byAdding: .day, value: -7, to: now) ?? now.addingTimeInterval(-604_800)
            // A daylight-saving fold can move the calendar cutoff backward while time advances.
            return previousCutoff <= currentCutoff
        }
        for candidate in candidates {
            guard let data = try? Data(contentsOf: candidate) else { continue }
            if let cache = try? PropertyListDecoder().decode(ReaderCache.self, from: data),
               isUsable(cache) {
                return cache
            }
            if let cache = try? JSONDecoder().decode(ReaderCache.self, from: data),
               isUsable(cache) {
                return cache
            }
        }
        return ReaderCache(schemaVersion: ReaderCache.currentSchemaVersion, entries: [:])
    }

    private func saveReaderCache(_ cache: ReaderCache, now: Date) {
        guard let cacheURL else { return }
        do {
            var compacted = cache
            compacted.schemaVersion = ReaderCache.currentSchemaVersion
            compacted.calendar = calendar
            compacted.pruningAnchor = now
            for (path, var entry) in cache.entries {
                guard var parsed = entry.parsedFile else { continue }
                parsed.rateLimits = compactedRateLimits(parsed.rateLimits, now: now)
                entry.parsedFile = parsed
                compacted.entries[path] = entry
            }
            try FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .binary
            let data = try encoder.encode(compacted)
            try data.write(to: cacheURL, options: .atomic)
        } catch {
            // Cache failure only affects refresh speed; it must never block a valid snapshot.
        }
    }

    private func compactedRateLimits(_ samples: [RateLimitSample], now: Date) -> [RateLimitSample] {
        guard samples.allSatisfy({ $0.observedAt.timeIntervalSinceReferenceDate.isFinite }) else { return samples }
        let cutoff = calendar.date(byAdding: .day, value: -7, to: now) ?? now.addingTimeInterval(-604_800)
        let minuteCutoff = now.addingTimeInterval(-3_600)
        var latest: [Int: Int] = [:]
        var hours: [Date: [Int: Int]] = [:]
        var minutes: [String: Int] = [:]
        var retained = Set<Int>()

        func newer(_ previous: Int?, than index: Int) -> Int {
            guard let previous else { return index }
            return samples[previous].observedAt <= samples[index].observedAt ? index : previous
        }

        for (index, sample) in samples.enumerated() {
            let knownWindow = [300, 10_080].contains(sample.windowMinutes)
            // Future rows must remain available as the clock advances into their minute.
            if sample.observedAt > now { retained.insert(index) }
            if knownWindow { latest[sample.windowMinutes] = newer(latest[sample.windowMinutes], than: index) }
            if sample.observedAt >= cutoff {
                let hour = calendar.dateInterval(of: .hour, for: sample.observedAt)?.start ?? sample.observedAt
                let kind = knownWindow ? sample.windowMinutes : 0
                hours[hour, default: [:]][kind] = newer(hours[hour]?[kind], than: index)
            }
            if knownWindow, sample.observedAt >= minuteCutoff, sample.observedAt <= now {
                let key = "\(sample.windowMinutes):\(Int(sample.observedAt.timeIntervalSince1970 / 60))"
                minutes[key] = newer(minutes[key], than: index)
            }
        }
        retained.formUnion(latest.values)
        for hour in hours.values { retained.formUnion(hour.values) }
        retained.formUnion(minutes.values)
        return samples.enumerated().compactMap { retained.contains($0.offset) ? $0.element : nil }
    }

    private func parseSessionFile(_ file: URL, resuming cached: CachedFile? = nil) throws
        -> (parsed: ParsedFile?, checkpoint: ParserCheckpoint) {
        let resume = cached?.checkpoint
        var sessionID = resume?.sessionID ?? file.deletingPathExtension().lastPathComponent
        var startedAt = resume?.startedAt
        var primaryID = resume?.primaryID
        var lineageIDs = resume?.lineageIDs ?? []
        var previousCumulative = resume?.previousCumulative
        var samples = resume == nil ? [] : cached?.parsedFile?.samples ?? []
        var activeModel = resume?.activeModel
        var rateLimitSamples = resume == nil ? [] : cached?.parsedFile?.rateLimits ?? []
        var lastRateLimitByWindow = resume?.lastRateLimitByWindow ?? [:]
        var isSubagent = resume?.isSubagent ?? false
        var activity = resume?.activity ?? cached?.parsedFile?.activity ?? CodexSessionActivity(id: sessionID)
        var hasLifecycle = resume?.hasLifecycle ?? false
        var completedToolIDs = resume?.completedToolIDs ?? []

        let progress = try JSONLFileReader.forEachRow(at: file, offset: resume?.progress.bytesRead ?? 0,
            expectedPrefixDigest: resume?.progress.prefixDigest, expectedIdentity: resume?.progress.identity) { row in
                if row["type"] as? String == "session_meta", let metadata = row["payload"] as? [String: Any] {
                    if metadata["thread_source"] as? String == "subagent" { isSubagent = true }
                    if let id = metadata["id"] as? String { lineageIDs.insert(id) }
                    if let id = metadata["session_id"] as? String { lineageIDs.insert(id) }
                    if primaryID == nil {
                        let threadSource = metadata["thread_source"] as? String
                        primaryID = metadata["id"] as? String ?? sessionID
                        sessionID = metadata["session_id"] as? String
                            ?? (threadSource == "subagent" ? metadata["parent_thread_id"] as? String : nil)
                            ?? metadata["id"] as? String
                            ?? sessionID
                        startedAt = parseDate(metadata["timestamp"] as? String)
                        activity.id = sessionID
                        activity.project = (metadata["cwd"] as? String).map { URL(fileURLWithPath: $0).lastPathComponent }
                        activity.provider = metadata["model_provider"] as? String
                        activity.cliVersion = metadata["cli_version"] as? String
                    }
                    return
                }

            if row["type"] as? String == "turn_context", let context = row["payload"] as? [String: Any] {
                activeModel = context["model"] as? String ?? activeModel
                activity.model = activeModel
                activity.reasoningEffort = context["effort"] as? String
                activity.approvalPolicy = context["approval_policy"] as? String
                activity.sandboxMode = (context["sandbox_policy"] as? [String: Any])?["type"] as? String
                activity.project = (context["cwd"] as? String).map { URL(fileURLWithPath: $0).lastPathComponent } ?? activity.project
                return
            }

            guard let payload = row["payload"] as? [String: Any] else { return }
            let payloadType = payload["type"] as? String
            let eventType = row["type"] as? String == "event_msg" ? payloadType : nil
            let limits = payload["rate_limits"] as? [String: Any]
            guard ["task_started", "turn_started", "task_complete", "turn_complete",
                   "task_aborted", "turn_aborted", "item_completed", "token_count"].contains(eventType ?? "")
                    || limits != nil || payloadType == "token_count",
                  let timestamp = parseDate(row["timestamp"] as? String)
            else { return }

                switch eventType {
                case "task_started", "turn_started":
                    hasLifecycle = true
                    activity.state = "running"
                    activity.turnStartedAt = timestamp
                    activity.turnDurationSeconds = nil
                    activity.firstTokenSeconds = nil
                    activity.lastTool = nil
                    activity.toolCalls = 0
                    activity.toolFailures = 0
                    completedToolIDs.removeAll()
                    activity.contextWindow = payload["model_context_window"] as? Int ?? activity.contextWindow
                    activity.observedAt = timestamp
                case "task_complete", "turn_complete":
                    hasLifecycle = true
                    activity.state = "completed"
                    activity.turnDurationSeconds = (payload["duration_ms"] as? Double).map { $0 / 1000 }
                    activity.firstTokenSeconds = (payload["time_to_first_token_ms"] as? Double).map { $0 / 1000 }
                    activity.observedAt = timestamp
                case "task_aborted", "turn_aborted":
                    hasLifecycle = true
                    activity.state = "interrupted"
                    activity.observedAt = timestamp
                case "item_completed":
                    activity.observedAt = timestamp
                    if let item = payload["item"] as? [String: Any],
                       let type = item["type"] as? String,
                       ["CommandExecution", "McpToolCall", "WebSearch", "FileChange"].contains(type),
                       let id = item["id"] as? String, completedToolIDs.insert(id).inserted {
                        activity.toolCalls = (activity.toolCalls ?? 0) + 1
                        activity.lastTool = type == "McpToolCall" ? String((item["tool"] as? String ?? type).prefix(80)) : type
                        let failed = item["status"] as? String == "failed"
                            || (item["exit_code"] as? Int).map { $0 != 0 } == true
                        activity.toolFailures = (activity.toolFailures ?? 0) + (failed ? 1 : 0)
                    }
                case "token_count":
                    activity.observedAt = timestamp
                    activity.model = activeModel
                default: break
                }
            if let limits {
                for key in ["primary", "secondary"] {
                    guard let values = limits[key] as? [String: Any],
                          let windowMinutes = (values["window_minutes"] as? NSNumber)?.intValue,
                          let usedPercent = (values["used_percent"] as? NSNumber)?.doubleValue,
                          let resetsAt = (values["resets_at"] as? NSNumber)?.doubleValue
                    else { continue }

                        let sample = RateLimitSample(
                            observedAt: timestamp,
                            usedPercent: usedPercent,
                            windowMinutes: windowMinutes,
                            resetsAt: Date(timeIntervalSince1970: resetsAt)
                        )
                        if lastRateLimitByWindow[windowMinutes] != sample {
                            rateLimitSamples.append(sample)
                            lastRateLimitByWindow[windowMinutes] = sample
                        }
                    }
                }

                guard
                    payloadType == "token_count",
                    let info = payload["info"] as? [String: Any],
                    let totalValues = info["total_token_usage"] as? [String: Any]
                else {
                    return
                }

                let cumulative = tokenUsage(from: totalValues)
                if cumulative == previousCumulative {
                    return
                }

                let lastUsage = (info["last_token_usage"] as? [String: Any]).map(tokenUsage(from:))
                let usage = lastUsage?.hasUsage == true ? lastUsage! : cumulative.delta(since: previousCumulative)
                previousCumulative = cumulative
                guard usage.hasUsage else { return }

                let contextTokens = (info["last_token_usage"] as? [String: Any])?["input_tokens"] as? Int
                let contextWindow = info["model_context_window"] as? Int
                samples.append(UsageSample(
                    timestamp: timestamp,
                    cumulative: cumulative,
                    usage: usage,
                    contextTokens: contextTokens,
                    contextWindow: contextWindow,
                    model: activeModel
                ))
        }
        let hasParsedFile = !samples.isEmpty || !rateLimitSamples.isEmpty || hasLifecycle
        let checkpoint = ParserCheckpoint(progress: progress, sessionID: sessionID, startedAt: startedAt,
            primaryID: primaryID, lineageIDs: lineageIDs, previousCumulative: previousCumulative,
            activeModel: activeModel, lastRateLimitByWindow: lastRateLimitByWindow,
            isSubagent: isSubagent, activity: !hasParsedFile || activity.observedAt == nil ? activity : nil,
            hasLifecycle: hasLifecycle, completedToolIDs: completedToolIDs)
        guard hasParsedFile else { return (nil, checkpoint) }
        let resolvedPrimaryID = primaryID ?? sessionID
        lineageIDs.insert(resolvedPrimaryID)
        return (ParsedFile(
            primaryID: resolvedPrimaryID,
            sessionID: sessionID,
            lineageIDs: lineageIDs,
            startedAt: startedAt ?? samples.first?.timestamp,
            lineageSequence: samples.map(\.cumulative),
            samples: samples,
            rateLimits: rateLimitSamples,
            isSubagent: isSubagent,
            activity: activity.observedAt == nil ? nil : activity
        ), checkpoint)
    }

    private func deduplicatedFiles(_ files: [ParsedFile]) -> [ParsedFile] {
        let sortedFiles = files.sorted {
            ($0.startedAt ?? $0.samples.first?.timestamp ?? .distantFuture)
                < ($1.startedAt ?? $1.samples.first?.timestamp ?? .distantFuture)
        }
        var canonical: [ParsedFile] = []

        for original in sortedFiles {
            var file = original
            let ancestor = canonical
                .filter { candidate in
                    file.lineageIDs.contains(candidate.primaryID)
                        && candidate.lineageSequence.count <= file.lineageSequence.count
                        && zip(candidate.lineageSequence, file.lineageSequence).allSatisfy { $0.0 == $0.1 }
                }
                .max { $0.lineageSequence.count < $1.lineageSequence.count }

            if let ancestor {
                let replayedCount = ancestor.lineageSequence.count
                file.samples = Array(file.samples.dropFirst(replayedCount))
                file.sessionID = ancestor.sessionID
                // A resumed turn can be working before its first new token event.
                guard !file.samples.isEmpty
                    || (file.activity?.turnStartedAt ?? .distantPast) > (ancestor.activity?.observedAt ?? .distantPast)
                else { continue }
            }
            canonical.append(file)
        }

        return canonical
    }

    private func groupedSessions(_ files: [ParsedFile]) -> [SessionUsage] {
        var byID: [String: SessionUsage] = [:]
        for file in files {
            var session = byID[file.sessionID] ?? SessionUsage(id: file.sessionID)
            session.startedAt = minDate(session.startedAt, file.startedAt)
            session.samples.append(contentsOf: file.samples)
            byID[file.sessionID] = session
        }
        return byID.values.map { session in
            var sorted = session
            sorted.samples.sort { $0.timestamp < $1.timestamp }
            return sorted
        }
    }

    private func tokenUsage(from values: [String: Any]) -> TokenUsage {
        TokenUsage(
            input: values["input_tokens"] as? Int ?? 0,
            cachedInput: values["cached_input_tokens"] as? Int ?? 0,
            output: values["output_tokens"] as? Int ?? 0,
            reasoningOutput: values["reasoning_output_tokens"] as? Int ?? 0,
            total: values["total_tokens"] as? Int ?? 0
        )
    }

    private func minDate(_ lhs: Date?, _ rhs: Date?) -> Date? {
        switch (lhs, rhs) {
        case let (lhs?, rhs?): min(lhs, rhs)
        case let (lhs?, nil): lhs
        case let (nil, rhs?): rhs
        case (nil, nil): nil
        }
    }

    private func parseDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        // Match legacy millisecond precision and reject its unsupported time components.
        if (20...24).contains(value.utf8.count), value.hasSuffix("Z"),
           let month = Int(value.dropFirst(5).prefix(2)), (1...12).contains(month),
           let day = Int(value.dropFirst(8).prefix(2)), (1...31).contains(day),
           let hour = Int(value.dropFirst(11).prefix(2)), (0..<24).contains(hour),
           let minute = Int(value.dropFirst(14).prefix(2)), (0..<60).contains(minute),
           let second = Int(value.dropFirst(17).prefix(2)), (0..<60).contains(second),
           let date = try? Date.ISO8601FormatStyle(includingFractionalSeconds: value.contains(".")).parse(value) {
            return Date(timeIntervalSince1970: (date.timeIntervalSince1970 * 1_000).rounded() / 1_000)
        }
        return ISO8601DateFormatter.codex.date(from: value) ?? ISO8601DateFormatter.codexNoFractions.date(from: value)
    }

    private struct DayAggregate {
        var usage = TokenUsage.zero
        var sessions = 0
        var turns = 0
        var estimatedCostUSD = 0.0
    }

    private struct UsageSample: Codable {
        var timestamp: Date
        var cumulative: TokenUsage
        var usage: TokenUsage
        var contextTokens: Int?
        var contextWindow: Int?
        var model: String?
    }

    private struct ParsedFile: Codable {
        var primaryID: String
        var sessionID: String
        var lineageIDs: Set<String>
        var startedAt: Date?
        var lineageSequence: [TokenUsage]
        var samples: [UsageSample]
        var rateLimits: [RateLimitSample]
        var isSubagent: Bool
        var activity: CodexSessionActivity?
    }

    private struct RateLimitSample: Codable, Equatable {
        var observedAt: Date
        var usedPercent: Double
        var windowMinutes: Int
        var resetsAt: Date
    }

    private struct SessionUsage {
        var id: String
        var startedAt: Date?
        var samples: [UsageSample] = []

        var total: TokenUsage {
            samples.reduce(into: .zero) { $0.add($1.usage) }
        }

        var latestSample: UsageSample? {
            samples.max { $0.timestamp < $1.timestamp }
        }
    }

    private struct CachedFile: Codable {
        var fileSize: Int
        var modificationTime: TimeInterval
        var parsedFile: ParsedFile?
        var checkpoint: ParserCheckpoint? = nil
        var changeTimeSeconds: Int64? = nil
        var changeTimeNanoseconds: Int64? = nil
        var sourceIdentity: JSONLFileReader.SourceIdentity? = nil
    }

    private struct ParserCheckpoint: Codable {
        var progress: JSONLFileReader.ReadProgress
        var sessionID: String
        var startedAt: Date?
        var primaryID: String?
        var lineageIDs: Set<String>
        var previousCumulative: TokenUsage?
        var activeModel: String?
        var lastRateLimitByWindow: [Int: RateLimitSample]
        var isSubagent: Bool
        var activity: CodexSessionActivity?
        var hasLifecycle: Bool
        var completedToolIDs: Set<String>
    }

    private struct ReaderCache: Codable {
        static let currentSchemaVersion = 7

        var schemaVersion: Int
        var entries: [String: CachedFile]
        var calendar: Calendar? = nil
        var pruningAnchor: Date? = nil
    }
}

enum CodexUsageSnapshotStore {
    static let snapshotURL = dataDirectoryURL.appendingPathComponent("snapshot.json")
    static let settingsURL = dataDirectoryURL.appendingPathComponent("settings.json")
    static let settingsV2URL = dataDirectoryURL.appendingPathComponent("settings-v2.json")
    static let readerCacheURL = dataDirectoryURL.appendingPathComponent("reader-cache.plist")
    static let legacyReaderCacheURL = dataDirectoryURL.appendingPathComponent("reader-cache.json")
    static let backgroundStatusURL = dataDirectoryURL.appendingPathComponent("background-status.json")
    static let refreshLockURL = dataDirectoryURL.appendingPathComponent("refresh.lock")
    static let legacyHistoryURL = dataDirectoryURL.appendingPathComponent("legacy-history.json")

    private static let dataDirectoryURL = WidgetDataBridge.currentDirectoryURL

    static func load() -> CodexUsageSnapshot? {
        guard let data = try? Data(contentsOf: snapshotURL) else { return nil }
        return try? JSONDecoder().decode(CodexUsageSnapshot.self, from: data)
    }

    static func loadLegacyHistory() -> [CodexUsageSnapshot] {
        if let data = try? Data(contentsOf: legacyHistoryURL),
           let snapshots = try? JSONDecoder().decode([CodexUsageSnapshot].self, from: data) {
            return snapshots
        }

        return []
    }

    @discardableResult
    static func save(_ snapshot: CodexUsageSnapshot) -> Bool {
        do {
            try FileManager.default.createDirectory(at: snapshotURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: snapshotURL, options: .atomic)
            return load()?.generatedAt == snapshot.generatedAt
        } catch {
            return false
        }
    }

    static func loadSettings() -> CodexUsageWidgetSettings {
        loadAllSettings().small
    }

    static func loadAllSettings() -> CodexUsageWidgetSettingsBySize {
        loadAllSettingsIfPresent() ?? .default
    }

    static func loadAllSettingsIfPresent() -> CodexUsageWidgetSettingsBySize? {
        guard let data = try? Data(contentsOf: settingsURL),
              !data.isEmpty
        else {
            return nil
        }

        if let settings = try? JSONDecoder().decode(CodexUsageWidgetSettingsBySize.self, from: data) {
            return CodexUsageWidgetSettingsBySize(
                small: normalized(settings.small, for: .small),
                medium: normalized(settings.medium, for: .medium),
                large: normalized(settings.large, for: .large)
            )
        }

        if let settings = try? JSONDecoder().decode(CodexUsageWidgetSettings.self, from: data) {
            return CodexUsageWidgetSettingsBySize(
                small: normalized(settings, for: .small),
                medium: normalized(settings, for: .medium),
                large: normalized(settings, for: .large)
            )
        }

        return nil
    }

    static func saveSettings(_ settings: CodexUsageWidgetSettings) {
        saveAllSettings(CodexUsageWidgetSettingsBySize(all: settings))
    }

    @discardableResult
    static func saveAllSettings(_ settings: CodexUsageWidgetSettingsBySize) -> Bool {
        do {
            try FileManager.default.createDirectory(at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(settings)
            try data.write(to: settingsURL, options: .atomic)
            return loadAllSettings() == settings
        } catch {
            return false
        }
    }

    private static func normalized(_ settings: CodexUsageWidgetSettings, for size: CodexUsageWidgetSize) -> CodexUsageWidgetSettings {
        var normalized = settings
        normalized.chartDayCount = size == .large ? 14 : 7
        if normalized.density == .minimal {
            normalized.density = size == .large ? .detailed : .balanced
            normalized.showsStats = true
        }
        let legacyDefaults: [[StatMetric]] = [
            [.lifetime, .peakDay, .currentStreak, .costToday],
            [.lifetime, .peakDay, .currentStreak, .longestStreak]
        ]
        if normalized.statSlots.isEmpty || legacyDefaults.contains(normalized.statSlots) {
            normalized.statSlots = CodexUsageWidgetSettingsBySize.default.settings(for: size).statSlots
        }
        normalized.statSlots = normalized.normalizedStatSlots
        return normalized
    }
}

extension ISO8601DateFormatter {
    static let codex: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static let codexNoFractions: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

extension Int {
    var compactTokenString: String {
        let value = Double(self)
        if self >= 1_000_000_000 { return String(format: "%.1fB", value / 1_000_000_000).trimmedZeroDecimal }
        if self >= 1_000_000 { return String(format: "%.1fM", value / 1_000_000).trimmedZeroDecimal }
        if self >= 1_000 { return String(format: "%.1fK", value / 1_000).trimmedZeroDecimal }
        return formatted()
    }
}

extension String {
    var trimmedZeroDecimal: String {
        replacingOccurrences(of: ".0", with: "")
    }
}

extension Double {
    var compactPercentString: String {
        if self >= 10 { return String(format: "%.0f%%", self) }
        return String(format: "%.1f%%", self)
    }

    var compactCurrencyString: String {
        if self >= 100 { return "$\(Int(rounded()).formatted())" }
        if self >= 10 { return String(format: "$%.1f", self) }
        return String(format: "$%.2f", self)
    }
}
