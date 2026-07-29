import AppKit
import Foundation
import SwiftUI
import Testing
@testable import CodexUsageMonitor

@Suite
struct WidgetConfigurationTests {
    @Test("Widget snapshots live outside protected app containers")
    func sharedSnapshotLocation() {
        let expected = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/CodexUsageMonitor/snapshot.json")
            .standardizedFileURL

        #expect(CodexUsageSnapshotStore.snapshotURL.standardizedFileURL == expected)
        #expect(!CodexUsageSnapshotStore.snapshotURL.path.contains("/Library/Containers/"))
        #expect(!CodexUsageSnapshotStore.snapshotURL.path.contains("/Library/Group Containers/"))
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
