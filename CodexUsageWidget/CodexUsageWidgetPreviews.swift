import SwiftUI

private struct WidgetStylePreviewMatrix: View {
    var style: CodexWidgetStyle

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: 18) {
                ForEach(CodexUsageCardSize.allCases) { size in
                    HStack(alignment: .top, spacing: 14) {
                        ForEach(CodexWidgetFamily.allCases) { family in
                            CodexWidgetFamilyView(
                                snapshot: .previewFixture,
                                configuration: WidgetDisplayConfiguration(
                                    family: family,
                                    style: style,
                                    theme: .crimson,
                                    period: .sevenDays,
                                    dashboardArrangement: .balanced
                                ),
                                size: size,
                                monochrome: false,
                                paintsBackground: true
                            )
                            .frame(width: frame(for: size).width, height: frame(for: size).height)
                        }
                    }
                }
            }
            .padding(20)
        }
    }

    private func frame(for size: CodexUsageCardSize) -> CGSize {
        switch size {
        case .small: CGSize(width: 170, height: 170)
        case .medium: CGSize(width: 340, height: 170)
        case .large: CGSize(width: 340, height: 340)
        }
    }
}

private extension CodexUsageSnapshot {
    static var previewFixture: CodexUsageSnapshot {
        let now = Date.now
        let usage = TokenUsage(input: 840_000, cachedInput: 510_000, output: 150_000, reasoningOutput: 40_000, total: 1_020_000)
        var snapshot = CodexUsageSnapshot.empty
        snapshot.today = usage
        snapshot.currentSession = TokenUsage(input: 124_000, cachedInput: 86_000, output: 22_000, reasoningOutput: 7_000, total: 153_000)
        snapshot.currentSessionTurns = 18
        snapshot.currentSessionStartedAt = now.addingTimeInterval(-2_700)
        snapshot.currentModel = "gpt-5.6-sol"
        snapshot.generatedAt = now
        snapshot.activityDays = (0..<7).map { offset in
            DailyUsage(
                date: Calendar.current.date(byAdding: .day, value: -offset, to: now) ?? now,
                usage: TokenUsage(input: 100_000 + offset * 12_000, cachedInput: 60_000, output: 20_000, reasoningOutput: 5_000, total: 125_000 + offset * 12_000),
                sessions: 2 + offset,
                turns: 8 + offset,
                headroomSaved: 22_000 + offset * 1_000,
                estimatedCostMicros: 1_300_000 + offset * 120_000
            )
        }
        snapshot.dailyModelUsage = [
            DailyModelUsage(
                date: now,
                models: [ModelUsage(model: "gpt-5.6-sol", usage: usage, turns: 18, estimatedCostUSD: 12.40)]
            )
        ]
        snapshot.rateLimits = CodexRateLimits(
            fiveHour: RateLimitWindow(usedPercent: 38, windowMinutes: 300, resetsAt: now.addingTimeInterval(4_200), observedAt: now),
            weekly: RateLimitWindow(usedPercent: 54, windowMinutes: 10_080, resetsAt: now.addingTimeInterval(220_000), observedAt: now),
            history: []
        )
        snapshot.headroom = HeadroomSavings(
            lifetimeTokensSaved: 620_000,
            todayTokensSaved: 72_000,
            last7DaysTokensSaved: 410_000,
            lifetimeRequests: 94,
            todayRequests: 12,
            inputTokensBeforeCompression: 2_200_000,
            savingsPercent: 0.28,
            costSavedUSD: 8.40,
            todayCostSavedUSD: 1.20,
            lastUpdated: now
        )
        return snapshot
    }
}

#Preview("Precision Instrument Matrix") {
    WidgetStylePreviewMatrix(style: .precisionInstrument)
}

#Preview("Native Glass Matrix") {
    WidgetStylePreviewMatrix(style: .nativeGlass)
}

#Preview("Signal Grid Matrix") {
    WidgetStylePreviewMatrix(style: .signalGrid)
}
