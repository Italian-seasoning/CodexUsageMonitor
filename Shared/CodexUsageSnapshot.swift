import Foundation

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

    var id: Date { date }
}

struct ModelUsage: Codable, Equatable, Identifiable, Sendable {
    var model: String
    var usage: TokenUsage
    var turns: Int
    var estimatedCostUSD: Double

    var id: String { model }
}

struct DailyModelUsage: Codable, Equatable, Identifiable, Sendable {
    var date: Date
    var models: [ModelUsage]

    var id: Date { date }
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
    static let version = "OpenAI Standard API · 2026-07-10"
    static let sourceURL = "https://developers.openai.com/api/docs/pricing"

    private static let prices: [String: ModelPricing] = [
        "gpt-5.6-sol": ModelPricing(inputPerMillion: 5, cachedInputPerMillion: 0.5, outputPerMillion: 30, longInputPerMillion: 10, longCachedInputPerMillion: 1, longOutputPerMillion: 45, longContextThreshold: 272_000),
        "gpt-5.6-terra": ModelPricing(inputPerMillion: 2.5, cachedInputPerMillion: 0.25, outputPerMillion: 15, longInputPerMillion: 5, longCachedInputPerMillion: 0.5, longOutputPerMillion: 22.5, longContextThreshold: 272_000),
        "gpt-5.6-luna": ModelPricing(inputPerMillion: 1, cachedInputPerMillion: 0.1, outputPerMillion: 6, longInputPerMillion: 2, longCachedInputPerMillion: 0.2, longOutputPerMillion: 9, longContextThreshold: 272_000),
        "gpt-5.5": ModelPricing(inputPerMillion: 5, cachedInputPerMillion: 0.5, outputPerMillion: 30, longInputPerMillion: 10, longCachedInputPerMillion: 1, longOutputPerMillion: 45, longContextThreshold: 272_000),
        "gpt-5.5-pro": ModelPricing(inputPerMillion: 30, cachedInputPerMillion: 30, outputPerMillion: 180, longInputPerMillion: 60, longCachedInputPerMillion: 60, longOutputPerMillion: 270, longContextThreshold: 272_000),
        "gpt-5.4": ModelPricing(inputPerMillion: 2.5, cachedInputPerMillion: 0.25, outputPerMillion: 15, longInputPerMillion: 5, longCachedInputPerMillion: 0.5, longOutputPerMillion: 22.5, longContextThreshold: 272_000),
        "gpt-5.4-mini": ModelPricing(inputPerMillion: 0.75, cachedInputPerMillion: 0.075, outputPerMillion: 4.5, longInputPerMillion: nil, longCachedInputPerMillion: nil, longOutputPerMillion: nil, longContextThreshold: nil),
        "gpt-5.4-nano": ModelPricing(inputPerMillion: 0.2, cachedInputPerMillion: 0.02, outputPerMillion: 1.25, longInputPerMillion: nil, longCachedInputPerMillion: nil, longOutputPerMillion: nil, longContextThreshold: nil),
        "gpt-5.4-pro": ModelPricing(inputPerMillion: 30, cachedInputPerMillion: 30, outputPerMillion: 180, longInputPerMillion: 60, longCachedInputPerMillion: 60, longOutputPerMillion: 270, longContextThreshold: 272_000)
    ]

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
        return prices.keys.sorted { $0.count > $1.count }.first { model == $0 || model.hasPrefix($0 + "-") }
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

    var preferredWindow: RateLimitWindow? { fiveHour ?? weekly }

    var nearestReset: RateLimitWindow? {
        [fiveHour, weekly].compactMap { $0 }.min { $0.resetsAt < $1.resetsAt }
    }

    var pace: LimitPace { preferredWindow?.pace() ?? .unknown }
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
        rateLimits: nil
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

enum WidgetTheme: String, Codable, CaseIterable, Identifiable {
    case crimson
    case darkGlass
    case frostedWhite
    case monochrome

    var id: String { rawValue }

    var label: String {
        switch self {
        case .crimson: "Crimson"
        case .darkGlass: "Graphite"
        case .frostedWhite: "Paper"
        case .monochrome: "System mono"
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
        case .lifetime: snapshot.lifetime.total
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
        case .lifetime: return snapshot.lifetime.total.compactTokenString
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
        lifetime.hasUsage || headroom?.isAvailable == true
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
    var calendar: Calendar
    var activityDayCount: Int
    var cacheURL: URL?

    init(
        sessionsDirectory: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/sessions"),
        calendar: Calendar = .current,
        activityDayCount: Int = 84,
        cacheURL: URL? = nil
    ) {
        self.sessionsDirectory = sessionsDirectory
        self.calendar = calendar
        self.activityDayCount = activityDayCount
        let defaultSessionsDirectory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/sessions")
        self.cacheURL = cacheURL ?? (
            sessionsDirectory.standardizedFileURL == defaultSessionsDirectory.standardizedFileURL
                ? CodexUsageSnapshotStore.readerCacheURL
                : nil
        )
    }

    func sourceFingerprint() -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        let prime: UInt64 = 1_099_511_628_211
        for file in jsonlFiles().sorted(by: { $0.path < $1.path }) {
            let values = try? file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            let parts = [
                file.path,
                String(values?.fileSize ?? -1),
                String(values?.contentModificationDate?.timeIntervalSince1970.bitPattern ?? 0)
            ]
            for byte in parts.joined(separator: "|").utf8 {
                hash = (hash ^ UInt64(byte)) &* prime
            }
        }
        return String(hash, radix: 16)
    }

    func snapshot(now: Date = Date(), headroomActivity: HeadroomActivity? = nil) -> CodexUsageSnapshot {
        let parsedFiles = parsedFilesUsingCache()
        let files = deduplicatedFiles(parsedFiles.filter { !$0.samples.isEmpty })
        let rateLimits = rateLimitSnapshot(from: parsedFiles.flatMap(\.rateLimits), now: now)
        let sessions = groupedSessions(files)
        let startOfToday = calendar.startOfDay(for: now)
        let startOfLast7Days = calendar.date(byAdding: .day, value: -6, to: startOfToday) ?? startOfToday
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

                if day >= startOfToday { modelTokensToday[model, default: 0] += sample.usage.total }
                if day >= startOfLast7Days { modelTokensLast7Days[model, default: 0] += sample.usage.total }
                if day >= startOfMonth { modelTokensThisMonth[model, default: 0] += sample.usage.total }
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

        return CodexUsageSnapshot(
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
            rateLimits: rateLimits
        )
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
            history: hourly.values.sorted { $0.date < $1.date }
        )
        return result.fiveHour == nil && result.weekly == nil && result.history.isEmpty ? nil : result
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
        (0..<activityDayCount).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset - activityDayCount + 1, to: today) else {
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

    private func jsonlFiles() -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: sessionsDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return enumerator.compactMap { item in
            guard let url = item as? URL, url.pathExtension == "jsonl" else { return nil }
            return url
        }
    }

    private func parsedFilesUsingCache() -> [ParsedFile] {
        let existingCache = loadReaderCache()
        var nextEntries: [String: CachedFile] = [:]
        var parsedFiles: [ParsedFile] = []

        for file in jsonlFiles() {
            let path = file.path
            let values = try? file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            let fileSize = values?.fileSize ?? -1
            let modificationTime = values?.contentModificationDate?.timeIntervalSince1970 ?? -1

            let parsed: ParsedFile?
            if let cached = existingCache.entries[path],
               cached.fileSize == fileSize,
               cached.modificationTime == modificationTime {
                parsed = cached.parsedFile
            } else {
                parsed = parseSessionFile(file)
            }

            nextEntries[path] = CachedFile(
                fileSize: fileSize,
                modificationTime: modificationTime,
                parsedFile: parsed
            )
            if let parsed { parsedFiles.append(parsed) }
        }

        saveReaderCache(ReaderCache(schemaVersion: ReaderCache.currentSchemaVersion, entries: nextEntries))
        return parsedFiles
    }

    private func loadReaderCache() -> ReaderCache {
        guard let cacheURL else {
            return ReaderCache(schemaVersion: ReaderCache.currentSchemaVersion, entries: [:])
        }
        let candidates = cacheURL == CodexUsageSnapshotStore.readerCacheURL
            ? [cacheURL, CodexUsageSnapshotStore.legacyReaderCacheURL]
            : [cacheURL]
        for candidate in candidates {
            guard let data = try? Data(contentsOf: candidate) else { continue }
            if let cache = try? PropertyListDecoder().decode(ReaderCache.self, from: data),
               cache.schemaVersion == ReaderCache.currentSchemaVersion {
                return cache
            }
            if let cache = try? JSONDecoder().decode(ReaderCache.self, from: data),
               cache.schemaVersion == ReaderCache.currentSchemaVersion {
                return cache
            }
        }
        return ReaderCache(schemaVersion: ReaderCache.currentSchemaVersion, entries: [:])
    }

    private func saveReaderCache(_ cache: ReaderCache) {
        guard let cacheURL else { return }
        do {
            try FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .binary
            let data = try encoder.encode(cache)
            try data.write(to: cacheURL, options: .atomic)
        } catch {
            // Cache failure only affects refresh speed; it must never block a valid snapshot.
        }
    }

    private func parseSessionFile(_ file: URL) -> ParsedFile? {
        guard let data = try? String(contentsOf: file, encoding: .utf8) else {
            return nil
        }

        var sessionID = file.deletingPathExtension().lastPathComponent
        var startedAt: Date?
        var primaryID: String?
        var lineageIDs: Set<String> = []
        var previousCumulative: TokenUsage?
        var samples: [UsageSample] = []
        var activeModel: String?
        var rateLimitSamples: [RateLimitSample] = []
        var lastRateLimitByWindow: [Int: RateLimitSample] = [:]

        for line in data.split(separator: "\n") {
            guard let row = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else {
                continue
            }

            if row["type"] as? String == "session_meta", let metadata = row["payload"] as? [String: Any] {
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
                }
                continue
            }

            if row["type"] as? String == "turn_context", let context = row["payload"] as? [String: Any] {
                activeModel = context["model"] as? String ?? activeModel
                continue
            }

            if let timestamp = parseDate(row["timestamp"] as? String),
               let payload = row["payload"] as? [String: Any],
               let limits = payload["rate_limits"] as? [String: Any] {
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
                let payload = row["payload"] as? [String: Any],
                payload["type"] as? String == "token_count",
                let timestamp = parseDate(row["timestamp"] as? String),
                let info = payload["info"] as? [String: Any],
                let totalValues = info["total_token_usage"] as? [String: Any]
            else {
                continue
            }

            let cumulative = tokenUsage(from: totalValues)
            if cumulative == previousCumulative {
                continue
            }

            let lastUsage = (info["last_token_usage"] as? [String: Any]).map(tokenUsage(from:))
            let usage = lastUsage?.hasUsage == true ? lastUsage! : cumulative.delta(since: previousCumulative)
            previousCumulative = cumulative
            guard usage.hasUsage else { continue }

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

        guard !samples.isEmpty || !rateLimitSamples.isEmpty else { return nil }
        if startedAt == nil { startedAt = samples.first?.timestamp }
        let resolvedPrimaryID = primaryID ?? sessionID
        lineageIDs.insert(resolvedPrimaryID)
        return ParsedFile(
            primaryID: resolvedPrimaryID,
            sessionID: sessionID,
            lineageIDs: lineageIDs,
            startedAt: startedAt,
            lineageSequence: samples.map(\.cumulative),
            samples: samples,
            rateLimits: rateLimitSamples
        )
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
                guard !file.samples.isEmpty else { continue }
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
    }

    private struct ReaderCache: Codable {
        static let currentSchemaVersion = 3

        var schemaVersion: Int
        var entries: [String: CachedFile]
    }
}

enum CodexUsageSnapshotStore {
    static let snapshotURL = containerBaseURL.appendingPathComponent("Library/Application Support/CodexUsageMonitor/snapshot.json")
    static let settingsURL = containerBaseURL.appendingPathComponent("Library/Application Support/CodexUsageMonitor/settings.json")
    static let readerCacheURL = containerBaseURL.appendingPathComponent("Library/Application Support/CodexUsageMonitor/reader-cache.plist")
    static let legacyReaderCacheURL = containerBaseURL.appendingPathComponent("Library/Application Support/CodexUsageMonitor/reader-cache.json")
    static let backgroundStatusURL = containerBaseURL.appendingPathComponent("Library/Application Support/CodexUsageMonitor/background-status.json")
    static let refreshLockURL = containerBaseURL.appendingPathComponent("Library/Application Support/CodexUsageMonitor/refresh.lock")

    private static let containerBaseURL: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let sandboxSuffix = "Library/Containers/com.nolankrahn.CodexUsageMonitor.widget/Data"
        return home.path.hasSuffix(sandboxSuffix)
            ? home
            : home.appendingPathComponent(sandboxSuffix)
    }()

    static func load() -> CodexUsageSnapshot? {
        guard let data = try? Data(contentsOf: snapshotURL) else { return nil }
        return try? JSONDecoder().decode(CodexUsageSnapshot.self, from: data)
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
        guard let data = try? Data(contentsOf: settingsURL),
              !data.isEmpty
        else {
            return .default
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

        return .default
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
