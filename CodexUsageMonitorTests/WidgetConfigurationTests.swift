import AppKit
import Foundation
import SwiftUI
import Testing
@testable import CodexUsageMonitor

@Suite
struct WidgetConfigurationTests {
    @Test("Lifetime activity chart groups daily usage into weekly bars")
    func lifetimeActivityChartAggregation() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        calendar.firstWeekday = 1
        let start = try #require(calendar.date(from: DateComponents(year: 2024, month: 1, day: 7)))
        let days = try (0..<14).map { offset in
            DailyUsage(
                date: try #require(calendar.date(byAdding: .day, value: offset, to: start)),
                usage: TokenUsage(input: 1, cachedInput: 0, output: 0, reasoningOutput: 0, total: 1),
                sessions: 1
            )
        }

        let lifetime = AnalysisChartData.points(
            from: days,
            period: .lifetime,
            measure: .tokens,
            calendar: calendar
        )

        #expect(lifetime.map(\.value) == [7, 7])
        #expect(AnalysisChartData.points(from: days, period: .month, measure: .tokens).count == 14)
    }

    @Test("Widget snapshots live outside protected app containers")
    func sharedSnapshotLocation() {
        let expected = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/CodexUsageMonitor/snapshot.json")
            .standardizedFileURL

        #expect(CodexUsageSnapshotStore.snapshotURL.standardizedFileURL == expected)
        #expect(!CodexUsageSnapshotStore.snapshotURL.path.contains("/Library/Containers/"))
        #expect(!CodexUsageSnapshotStore.snapshotURL.path.contains("/Library/Group Containers/"))
    }

    @Test("Debug builds cannot register as the production app or widget")
    func debugBundleIdentifiersAreIsolated() throws {
        #if DEBUG
        #expect(Bundle.main.bundleIdentifier == "com.codexusage.CodexUsageMonitor.debug")

        let plugInsURL = try #require(Bundle.main.builtInPlugInsURL)
        let widgetBundle = try #require(
            Bundle(url: plugInsURL.appendingPathComponent("CodexUsageWidget.appex"))
        )
        #expect(widgetBundle.bundleIdentifier == "com.codexusage.CodexUsageMonitor.debug.widget")
        #endif
    }

    @Test("Configuration preserves supported choices and scopes dashboard arrangements")
    func configurationNormalization() {
        for family in CodexWidgetFamily.allCases {
            for style in CodexWidgetStyle.allCases {
                for period in UsagePeriod.allCases {
                    for arrangement in DashboardArrangement.allCases {
                        let configuration = WidgetDisplayConfiguration(
                            family: family,
                            style: style,
                            theme: .darkGlass,
                            period: period,
                            dashboardArrangement: arrangement
                        )
                        let normalized = configuration.normalized()

                        #expect(normalized.family == family)
                        #expect(normalized.style == style)
                        #expect(normalized.theme == .darkGlass)
                        #expect(normalized.period == period)
                        #expect(normalized.dashboardArrangement == (family == .dashboard ? arrangement : .balanced))
                    }
                }
            }
        }
    }

    @Test("Desktop widget choices stay scoped to Small, Medium, and Large")
    func desktopWidgetConfigurationsAreIndependent() throws {
        var configurations = DesktopWidgetConfigurations.defaults(
            appearance: WidgetAppearanceSelection(style: .signalGrid, theme: .darkGlass)
        )

        #expect(configurations.small.family == .limits)
        #expect(configurations.medium.family == .usagePulse)
        #expect(configurations.large.family == .dashboard)
        #expect(configurations.small.style == .signalGrid)

        var medium = configurations.configuration(for: .medium)
        medium.family = .costLens
        medium.period = .month
        medium.dashboardArrangement = .activityFirst
        configurations.set(medium, for: .medium)

        #expect(configurations.small.family == .limits)
        #expect(configurations.medium.family == .costLens)
        #expect(configurations.medium.period == .month)
        #expect(configurations.medium.dashboardArrangement == .balanced)
        #expect(configurations.large.family == .dashboard)

        configurations.small.backgroundMode = .customImage
        #expect(configurations.small.backgroundMode == .customImage)
        #expect(WidgetBackgroundImageStore.url(for: .small) != WidgetBackgroundImageStore.url(for: .medium))

        let encoded = try JSONEncoder().encode(configurations)
        #expect(try JSONDecoder().decode(DesktopWidgetConfigurations.self, from: encoded) == configurations)
    }

    @Test("Version 2 widget identities remain registered during the 3.0 upgrade")
    func legacyWidgetKindsRemainStable() {
        #expect(CodexWidgetKind.primary == "CodexUsageWidget")
        #expect(CodexWidgetKind.limits == "CodexUsageWidget.limits")
        #expect(CodexWidgetKind.costLens == "CodexUsageWidget.costLens")
        #expect(CodexWidgetKind.modelMix == "CodexUsageWidget.modelMix")
        #expect(CodexWidgetKind.headroomImpact == "CodexUsageWidget.headroomImpact")
        #expect(CodexWidgetKind.sessionLive == "CodexUsageWidget.sessionLive")
        #expect(CodexWidgetKind.dashboard == "CodexUsageWidget.dashboard")
        #expect(CodexWidgetKind.all.count == 7)
        #expect(CodexWidgetKind.all.contains(CodexWidgetKind.primary))
        #expect(CodexWidgetKind.all.contains(CodexWidgetKind.dashboard))
    }

    @Test("App widget appearance overrides presentation without changing content choices")
    func appWidgetAppearanceOverride() {
        let configuration = WidgetDisplayConfiguration(
            family: .dashboard,
            style: .precisionInstrument,
            theme: .crimson,
            period: .month,
            dashboardArrangement: .activityFirst
        )
        let result = configuration.applying(
            WidgetAppearanceSelection(style: .signalGrid, theme: .frostedWhite)
        )

        #expect(result.style == .signalGrid)
        #expect(result.theme == .frostedWhite)
        #expect(result.family == .dashboard)
        #expect(result.period == .month)
        #expect(result.dashboardArrangement == .activityFirst)
    }

    @Test("Classic Red surfaces remain neutral and its gradient remains red")
    @MainActor
    func classicRedPanelTint() throws {
        let color = try #require(NSColor(AppTheme.classicRed.panelTint).usingColorSpace(.deviceRGB))
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)

        #expect(abs(red - green) < 0.04)
        #expect(abs(red - blue) < 0.04)

        let gradient = try #require(NSColor(AppTheme.classicRed.gradientLeading).usingColorSpace(.deviceRGB))
        gradient.getRed(&red, green: &green, blue: &blue, alpha: &alpha)

        #expect(red > green)
        #expect(red > blue)
    }

    @Test("Curated, saved, and custom presentation presets resolve predictably")
    func presentationPresets() {
        let saved = SavedWidgetPreset(
            id: UUID(),
            name: "My Coast",
            style: .signalGrid,
            theme: .frostedWhite
        )

        #expect(WidgetPresetMode.summer.presentation().style == .precisionInstrument)
        #expect(WidgetPresetMode.summer.presentation().theme == .crimson)
        #expect(WidgetPresetMode.classicRed.presentation().theme == .classicRed)
        #expect(WidgetPresetMode.saved.presentation(savedPreset: saved).style == .signalGrid)
        #expect(WidgetPresetMode.saved.presentation(savedPreset: saved).theme == .frostedWhite)
        #expect(
            WidgetPresetMode.custom.presentation(
                customStyle: .nativeGlass,
                customTheme: .monochrome
            ).theme == .monochrome
        )
    }

    @Test("Each widget family exposes its required hero metric")
    func familyHeroSemantics() {
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let snapshot = widgetFixture(now: now)

        func hero(_ family: CodexWidgetFamily) -> WidgetSemanticContent {
            WidgetFamilySemanticBuilder.content(
                snapshot: snapshot,
                configuration: WidgetDisplayConfiguration(
                    family: family,
                    style: .precisionInstrument,
                    theme: .crimson,
                    period: .today,
                    dashboardArrangement: .balanced
                ),
                now: now
            )
        }

        #expect(hero(.limits).heroValue == "75%")
        #expect(hero(.limits).heroLabel == "5-hour remaining")
        #expect(hero(.usagePulse).heroValue == 1_234.compactTokenString)
        #expect(hero(.costLens).heroValue == 2.5.compactCurrencyString)
        #expect(hero(.modelMix).heroValue == "GPT 5.6 Sol")
        #expect(hero(.headroomImpact).heroValue == 400.compactTokenString)
        #expect(hero(.sessionLive).heroValue == 321.compactTokenString)
        #expect(hero(.dashboard).heroValue == 1_234.compactTokenString)
    }

    @MainActor
    @Test("Widget foreground stays transparent for macOS vibrant rendering")
    func widgetForegroundLayerRemainsTransparent() throws {
        let renderer = ImageRenderer(
            content: CodexWidgetStyledContainer(
                style: .nativeGlass,
                theme: .darkGlass,
                monochrome: true
            ) {
                VStack {
                    HStack {
                        Color.red.frame(width: 8, height: 8)
                        Spacer()
                    }
                    Spacer()
                }
            }
            .frame(width: 170, height: 170)
        )
        renderer.scale = 1

        let image = try #require(renderer.cgImage)
        let center = NSBitmapImageRep(cgImage: image).colorAt(x: 85, y: 85)
        #expect(try #require(center).alphaComponent < 0.01)
    }

    @MainActor
    @Test("Every widget family renders in every size and style")
    func completeWidgetRenderMatrix() throws {
        let snapshot = widgetFixture(now: Date(timeIntervalSinceReferenceDate: 800_000_000))

        for family in CodexWidgetFamily.allCases {
            for style in CodexWidgetStyle.allCases {
                for size in CodexUsageCardSize.allCases {
                    let frame = switch size {
                    case .small: CGSize(width: 170, height: 170)
                    case .medium: CGSize(width: 340, height: 170)
                    case .large: CGSize(width: 340, height: 340)
                    }
                    let renderer = ImageRenderer(
                        content: CodexWidgetFamilyView(
                            snapshot: snapshot,
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
                        .frame(width: frame.width, height: frame.height)
                    )
                    renderer.scale = 1

                    #expect(try #require(renderer.cgImage).width == Int(frame.width))
                }
            }
        }
    }

    private func widgetFixture(now: Date) -> CodexUsageSnapshot {
        let usage = TokenUsage(input: 900, cachedInput: 100, output: 200, reasoningOutput: 34, total: 1_234)
        var snapshot = CodexUsageSnapshot.empty
        snapshot.today = usage
        snapshot.lifetime = usage
        snapshot.currentSession = TokenUsage(input: 200, cachedInput: 20, output: 90, reasoningOutput: 11, total: 321)
        snapshot.currentSessionTurns = 7
        snapshot.currentSessionStartedAt = now.addingTimeInterval(-900)
        snapshot.currentModel = "gpt-5.6-sol"
        snapshot.generatedAt = now
        snapshot.activityDays = [
            DailyUsage(
                date: now,
                usage: usage,
                sessions: 3,
                turns: 12,
                headroomSaved: 400,
                estimatedCostMicros: 2_500_000
            )
        ]
        snapshot.dailyModelUsage = [
            DailyModelUsage(
                date: now,
                models: [
                    ModelUsage(model: "gpt-5.6-sol", usage: usage, turns: 12, estimatedCostUSD: 2.5)
                ]
            )
        ]
        var headroom = HeadroomSavings.zero
        headroom.todayTokensSaved = 400
        headroom.last7DaysTokensSaved = 800
        headroom.lifetimeTokensSaved = 1_200
        headroom.lifetimeRequests = 20
        headroom.savingsPercent = 0.25
        headroom.costSavedUSD = 4.2
        headroom.lastUpdated = now
        snapshot.headroom = headroom
        snapshot.rateLimits = CodexRateLimits(
            fiveHour: RateLimitWindow(
                usedPercent: 25,
                windowMinutes: 300,
                resetsAt: now.addingTimeInterval(3_600),
                observedAt: now
            ),
            weekly: RateLimitWindow(
                usedPercent: 40,
                windowMinutes: 10_080,
                resetsAt: now.addingTimeInterval(86_400),
                observedAt: now
            ),
            history: []
        )
        return snapshot
    }
}
