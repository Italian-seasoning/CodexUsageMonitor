# Codex Usage Monitor V2 Implementation Plan

> Execution requirement: implement task-by-task, run the named check after every task, and review each commit before continuing.

**Goal:** Ship Codex Usage Monitor 2.0 as a reliable, analysis-first native macOS app with seven curated widget families, three widget styles, upgrade-safe settings, deterministic onboarding, and one low-resource refresh path.

**Architecture:** Keep the existing local Codex reader, Headroom collector, shared JSON snapshot, LaunchAgent, SwiftUI, WidgetKit, App Intents, Swift Charts, and Sparkle. Add typed period/metric selection and a versioned settings store around the current data model; route every refresh trigger through one coordinator; split the two oversized UI files only where V2 adds distinct responsibilities. The widget extension remains a pure snapshot reader.

**Tech Stack:** Swift 5, SwiftUI, Swift Charts, WidgetKit, App Intents, AppKit, Foundation, OSLog, Swift Testing/XCTest, Xcode 26, Sparkle 2.9.4.

## Global Constraints

- Minimum deployment target remains macOS 14.0.
- Do not add a UI framework, chart package, database, cross-platform runtime, or generic widget engine.
- Preserve local-only collection and the existing app-group snapshot boundary.
- Keep app theme and per-widget theme independent.
- API values must say “API-equivalent estimate”; never imply ChatGPT subscription spending.
- Background work must never request permission or create a Dock/menu-bar process.
- The shared snapshot should be checked at least every three minutes during an active login session; WidgetKit redraw timing is not guaranteed.
- Preserve the existing `CodexUsageWidget` kind as the Usage Pulse family so installed V1 widgets have a migration path.
- Use Xcode automatic signing with Personal Team `Y9F67Z9663`; do not claim Developer ID signing or notarization.
- Public source and release copy must contain no agent metadata, generated-work folders, or build-number copy.
- Commit after every task only when its checks pass.

## File Map

### Shared data and configuration

- Create `Shared/UsageMetrics.swift`: typed periods, metric selection, period summaries, and freshness semantics.
- Create `Shared/WidgetConfiguration.swift`: normalized widget family/style/theme/period/dashboard choices used by App Intents and renderers.
- Modify `Shared/CodexUsageSnapshot.swift`: keep collection/storage types; expose only the additional history needed by period summaries and migration.
- Create `Shared/CodexUsageSettings.swift`: versioned app settings payload, field-by-field decoder, legacy import, diagnostics, and atomic persistence.

### Refresh and setup

- Modify `CodexUsageMonitor/SnapshotRefresh.swift`: pure refresh engine, result type, structured status, file lock, and reload-all request.
- Create `CodexUsageMonitor/RefreshCoordinator.swift`: in-process coalescing and trigger handling.
- Create `CodexUsageMonitor/SourceChangeMonitor.swift`: native FSEvents monitoring with debounce.
- Modify `CodexUsageMonitor/BackgroundRefreshAgent.swift`: settings-backed enablement and richer diagnostic record.
- Modify `CodexUsageMonitor/CodexUsageMonitorApp.swift`: coordinator lifecycle, foreground/sleep recovery, background-only execution, and settings injection.
- Delete `scripts/RefreshSnapshot.swift`: it has no production caller and duplicates the refresh engine.

### Onboarding

- Modify `CodexUsageMonitor/OnboardingStateStore.swift`: schema migration and completed-setup requirements.
- Rewrite `CodexUsageMonitor/OnboardingView.swift`: centered native sheet, deterministic access states, stable pages, skip warning, and compact update checklist.

### Main app

- Modify `CodexUsageMonitor/ContentView.swift`: compact icon-rail shell only.
- Create `CodexUsageMonitor/AnalysisView.swift`: Adaptive Mosaic, period control, activity chart, and analysis modules.
- Create `CodexUsageMonitor/ModelsView.swift`: model share, volume, and API-equivalent cost analysis.
- Create `CodexUsageMonitor/WidgetsView.swift`: curated family/style preview browser.
- Create `CodexUsageMonitor/SettingsView.swift`: app appearance, widget defaults, menu/Dock/background, notification, update, and onboarding controls.
- Create `CodexUsageMonitor/DataHealthView.swift`: semantic health icon/popover and authoritative manual refresh.
- Create `CodexUsageMonitor/AppChrome.swift`: red/black glass palette, module surface, compact rail, and reusable layout constants.
- Modify `CodexUsageMonitor/LimitViews.swift` and `CodexUsageMonitor/MenuBarView.swift`: consume typed settings and shared period semantics.

### Widget extension

- Modify `CodexUsageWidget/CodexUsageWidget.swift`: `WidgetBundle`, seven configurations, normalized App Intent entries, and three-minute timeline request.
- Refactor `Shared/CodexUsageCardView.swift`: keep the compatibility entry point and move generic semantic pieces out.
- Create `Shared/WidgetComponents.swift`: hero values, gauges, compact charts, grids, freshness labels, palettes, and accessibility.
- Create `Shared/WidgetFamilyViews.swift`: seven family renderers with small/medium/large progressive disclosure.
- Create `Shared/WidgetStyleViews.swift`: Precision Instrument, Native Glass, and Signal Grid shells.
- Create `CodexUsageWidget/CodexUsageWidgetPreviews.swift`: representative Xcode preview matrix.

### Tests

- Create `CodexUsageMonitorTests/UsageMetricsTests.swift`.
- Create `CodexUsageMonitorTests/SettingsMigrationTests.swift`.
- Create `CodexUsageMonitorTests/RefreshCoordinatorTests.swift`.
- Create `CodexUsageMonitorTests/OnboardingStateTests.swift`.
- Create `CodexUsageMonitorTests/WidgetConfigurationTests.swift`.
- Keep the existing collector and launch checks under `scripts/`.

---

### Task 1: Add the Native Test Target and Lock the V1 Baseline

**Files:**

- Modify: `CodexUsageMonitor.xcodeproj/project.pbxproj`
- Create: `CodexUsageMonitorTests/CodexUsageMonitorTests.swift`

**Produces:** A macOS unit-test target named `CodexUsageMonitorTests` with `@testable import CodexUsageMonitor`.

- [ ] **Step 1: Record the baseline build**

Run:

```bash
rtk xcodebuild -project CodexUsageMonitor.xcodeproj -scheme CodexUsageMonitor -configuration Debug -destination 'platform=macOS' -derivedDataPath build/V2Baseline build
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 2: Add the test target in Xcode**

Use Xcode’s macOS Unit Testing Bundle template, name it `CodexUsageMonitorTests`, set the host application to `CodexUsageMonitor`, use team `Y9F67Z9663`, and add it to the shared scheme’s Test action.

- [ ] **Step 3: Add a real smoke test**

```swift
import Testing
@testable import CodexUsageMonitor

@Test("Empty snapshot starts at zero")
func emptySnapshotStartsAtZero() {
    #expect(CodexUsageSnapshot.empty.today.total == 0)
    #expect(CodexUsageSnapshot.empty.lifetime.total == 0)
}
```

- [ ] **Step 4: Run the test target**

Run:

```bash
rtk xcodebuild test -project CodexUsageMonitor.xcodeproj -scheme CodexUsageMonitor -destination 'platform=macOS' -derivedDataPath build/V2Tests
```

Expected: one passing test and `TEST SUCCEEDED`.

- [ ] **Step 5: Commit**

```bash
rtk git add CodexUsageMonitor.xcodeproj CodexUsageMonitorTests
rtk git commit -m "test: add native V2 test target"
```

### Task 2: Add Typed Period and Metric Semantics

**Files:**

- Create: `Shared/UsageMetrics.swift`
- Modify: `Shared/CodexUsageSnapshot.swift`
- Create: `CodexUsageMonitorTests/UsageMetricsTests.swift`
- Modify: `CodexUsageMonitor.xcodeproj/project.pbxproj`

**Interfaces:**

- Produces:

```swift
enum UsagePeriod: String, Codable, CaseIterable, Identifiable, Sendable {
    case today, sevenDays, month, lifetime
}

enum UsageMeasure: String, Codable, CaseIterable, Identifiable, Sendable {
    case tokens, apiEquivalentCost, sessions, requests
}

struct PeriodUsageSummary: Equatable, Sendable {
    let usage: TokenUsage
    let sessionCount: Int
    let requestCount: Int
    let estimatedCostUSD: Double
    let topModel: ModelUsage?
    let days: [DailyUsage]
}

extension CodexUsageSnapshot {
    func summary(
        for period: UsagePeriod,
        calendar: Calendar = .current,
        now: Date? = nil
    ) -> PeriodUsageSummary
}
```

- [ ] **Step 1: Write failing period tests**

Create fixtures with distinct today, seven-day, month, and lifetime totals. Assert:

```swift
#expect(snapshot.summary(for: .today).usage.total == 100)
#expect(snapshot.summary(for: .sevenDays).usage.total == 700)
#expect(snapshot.summary(for: .month).usage.total == 3_000)
#expect(snapshot.summary(for: .lifetime).usage == snapshot.lifetime)
#expect(snapshot.summary(for: .today).topModel?.model == "gpt-5.6-sol")
```

Also assert that changing `UsagePeriod` never returns a model name through the `.tokens` measure.

- [ ] **Step 2: Verify the tests fail**

Run:

```bash
rtk xcodebuild test -project CodexUsageMonitor.xcodeproj -scheme CodexUsageMonitor -destination 'platform=macOS' -only-testing:CodexUsageMonitorTests/UsageMetricsTests
```

Expected: compile failure because `UsagePeriod` and `summary(for:)` do not exist.

- [ ] **Step 3: Implement period summaries**

Use `activityDays` for Today/7D/Month, `lifetime` for Lifetime, and filter dated model records from the calendar boundary through the injected `now ?? generatedAt ?? Date()`. Extend snapshot collection with:

```swift
struct DailyModelUsage: Codable, Equatable, Identifiable {
    var date: Date
    var models: [ModelUsage]
    var id: Date { date }
}
```

Build each daily `ModelUsage.estimatedCostUSD` by summing the existing per-sample pricing result; do not recompute cost from a daily aggregate because long-context pricing is sample-sensitive. Decode the new snapshot field with `decodeIfPresent(...) ?? []` so V1 snapshots remain valid. Exclude future-dated rows. For a legacy snapshot without dated model history, keep token/session/request summaries valid and return no period-specific model breakdown rather than inventing one.

- [ ] **Step 4: Run focused and full tests**

Run:

```bash
rtk xcodebuild test -project CodexUsageMonitor.xcodeproj -scheme CodexUsageMonitor -destination 'platform=macOS' -only-testing:CodexUsageMonitorTests/UsageMetricsTests
rtk xcodebuild test -project CodexUsageMonitor.xcodeproj -scheme CodexUsageMonitor -destination 'platform=macOS'
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
rtk git add Shared/UsageMetrics.swift Shared/CodexUsageSnapshot.swift CodexUsageMonitorTests/UsageMetricsTests.swift CodexUsageMonitor.xcodeproj
rtk git commit -m "feat: add typed usage periods"
```

### Task 3: Introduce Versioned, Field-by-Field Settings Migration

**Files:**

- Create: `Shared/CodexUsageSettings.swift`
- Create: `CodexUsageMonitorTests/SettingsMigrationTests.swift`
- Modify: `Shared/CodexUsageSnapshot.swift`
- Modify: `CodexUsageMonitor/ContentView.swift`
- Modify: `CodexUsageMonitor/LimitViews.swift`
- Modify: `CodexUsageMonitor/MenuBarView.swift`
- Modify: `CodexUsageMonitor/CodexUsageMonitorApp.swift`
- Modify: `CodexUsageMonitor.xcodeproj/project.pbxproj`

**Interfaces:**

```swift
struct CodexUsageSettings: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 2
    var schemaVersion: Int
    var appTheme: AppTheme
    var defaultWidgetTheme: WidgetTheme
    var backgroundRefreshEnabled: Bool
    var appPresence: AppPresenceMode
    var menuBarDisplayMode: MenuBarDisplayMode
    var notificationsEnabled: Bool
    var warningThreshold: Int
    var criticalThreshold: Int
}

struct SettingsLoadResult: Equatable {
    var settings: CodexUsageSettings
    var repairedFields: [String]
    var importedLegacyValues: Bool
    var legacyWidgetSeed: CodexUsageWidgetSettingsBySize?
}

struct LegacySettingsSource {
    var object: (String) -> Any?
    var widgetSettings: CodexUsageWidgetSettingsBySize?
}

enum CodexUsageSettingsStore {
    static func load() -> SettingsLoadResult
    static func load(data: Data?, legacy: LegacySettingsSource) -> SettingsLoadResult
    static func save(_ settings: CodexUsageSettings) throws
}
```

- [ ] **Step 1: Add V1 migration fixtures**

Cover:

- Missing V2 file plus V1 `settings.json`.
- Existing `UserDefaults` values for app theme, background refresh, menu bar, app presence, and notification thresholds.
- Missing new fields.
- One malformed field beside valid fields.
- Unknown future fields.

The malformed-field test must prove only that field defaults:

```swift
#expect(result.settings.backgroundRefreshEnabled == false)
#expect(result.settings.warningThreshold == 70)
#expect(result.repairedFields == ["warningThreshold"])
```

- [ ] **Step 2: Verify migration tests fail**

Run the focused test suite and expect missing-type failures.

- [ ] **Step 3: Implement the decoder and one-time importer**

Store V2 app preferences at a new `settings-v2.json` URL. Keep the legacy widget `settings.json` separate and read-only as a migration seed. Decode a keyed container with `decodeIfPresent` per field. Clamp thresholds to `1...100`; preserve valid values; tolerate unknown fields without invalidating the payload; record repaired field names; atomically write with `Data.write(options: .atomic)`. Import only legacy UserDefaults keys that are actually present when no V2 file exists. Do not import notification-deduplication keys, delete legacy values, or persist the widget seed inside app preferences.

- [ ] **Step 4: Replace touched `@AppStorage` uses**

Inject one `CodexUsageSettingsModel` from `CodexUsageMonitorApp` and bind touched app-preference views to its concrete properties. Leave onboarding flags/state under `OnboardingStateStore` until Task 5. Do not create a generic preference framework.

- [ ] **Step 5: Prove upgrade safety**

Run focused tests, all tests, then launch over a copied V1 Application Support directory and verify the copied settings remain equivalent after first launch.

- [ ] **Step 6: Commit**

```bash
rtk git add Shared/CodexUsageSettings.swift Shared/CodexUsageSnapshot.swift CodexUsageMonitor CodexUsageMonitorTests/SettingsMigrationTests.swift CodexUsageMonitor.xcodeproj
rtk git commit -m "feat: preserve settings through V2 upgrades"
```

### Task 4: Route Every Refresh Through One Coordinator

**Files:**

- Modify: `CodexUsageMonitor/SnapshotRefresh.swift`
- Create: `CodexUsageMonitor/RefreshCoordinator.swift`
- Create: `CodexUsageMonitor/SourceChangeMonitor.swift`
- Modify: `CodexUsageMonitor/BackgroundRefreshAgent.swift`
- Modify: `CodexUsageMonitor/CodexUsageMonitorApp.swift`
- Modify: `CodexUsageMonitor/MenuBarView.swift`
- Modify: `CodexUsageMonitor/ContentView.swift`
- Modify: `scripts/RefreshSnapshot.swift`
- Create: `CodexUsageMonitorTests/RefreshCoordinatorTests.swift`
- Modify: `CodexUsageMonitor.xcodeproj/project.pbxproj`

**Interfaces:**

```swift
enum RefreshTrigger: String, Codable, Sendable {
    case launch, foreground, sourceChange, fallbackTimer, manual, backgroundAgent, wake
}

enum RefreshOutcome: String, Codable, Sendable {
    case updated, unchanged, permissionRequired, failed
}

struct RefreshResult: Sendable {
    var outcome: RefreshOutcome
    var snapshot: CodexUsageSnapshot?
    var message: String
}

actor RefreshCoordinator {
    static let shared = RefreshCoordinator()
    func refresh(trigger: RefreshTrigger, force: Bool = false) async -> RefreshResult
}
```

- [ ] **Step 1: Add failing coalescing tests**

Inject a closure-backed refresh engine and assert ten simultaneous requests call it once. Assert `manual` passes `force == true`, while fingerprint-equal background calls return `.unchanged`.

- [ ] **Step 2: Implement the coordinator**

Store one in-flight `Task<RefreshResult, Never>`. Await it for concurrent callers and clear it only after completion. If a forced manual request arrives behind an unforced in-flight pass, queue exactly one forced follow-up instead of coalescing it away. Retain `flock` as cross-process protection.

- [ ] **Step 3: Make one refresh engine authoritative**

The engine must:

1. Fingerprint Codex and Headroom sources.
2. Read or reuse cached data.
3. expire old limit windows;
4. atomically save one snapshot;
5. call `WidgetCenter.shared.reloadAllTimelines()`;
6. post `.codexUsageSnapshotDidChange`;
7. save last attempt, success, outcome, duration, fingerprint, and widget-reload request time.

- [ ] **Step 4: Add native source monitoring**

Use FSEvents for `~/.codex/sessions` and detected Headroom data paths. Debounce events by one second and request `.sourceChange`. Stop the stream on app termination. Do not watch from the widget extension or background helper process.

- [ ] **Step 5: Replace every caller**

- App launch: `.launch`
- `NSApplication.didBecomeActiveNotification`: `.foreground`
- wake notification: `.wake`
- app timer: `.fallbackTimer`
- menu/app button: `.manual`, `force: true`
- `--background-refresh`: `.backgroundAgent`

The synchronous background process must check persisted approved-access state before touching `~/.codex`; otherwise return `.permissionRequired` without prompting. Keep onboarding’s reader access probe, remove its direct snapshot write, and follow approval with a coordinator refresh.

Delete `scripts/RefreshSnapshot.swift` after repository search confirms it has no production caller.

- [ ] **Step 6: Validate background behavior**

Run the coordinator tests, `scripts/BackgroundLaunchCheck.swift`, and a packaged launch with the app closed. Confirm one prohibited-activation process exits and no extra menu-bar item appears.

- [ ] **Step 7: Commit**

```bash
rtk git add CodexUsageMonitor Shared scripts CodexUsageMonitorTests/RefreshCoordinatorTests.swift CodexUsageMonitor.xcodeproj
rtk git commit -m "feat: coordinate every snapshot refresh"
```

### Task 5: Replace Onboarding Overlay with a Deterministic Native Sheet

**Files:**

- Modify: `CodexUsageMonitor/OnboardingStateStore.swift`
- Rewrite: `CodexUsageMonitor/OnboardingView.swift`
- Create: `CodexUsageMonitorTests/OnboardingStateTests.swift`
- Modify: `CodexUsageMonitor.xcodeproj/project.pbxproj`

**Interfaces:**

```swift
enum CodexDataAccessState: Equatable {
    case notRequested
    case requesting
    case approved
    case needsManualAction(String)
    case failed(String)
}

enum SetupRequirement: String, Codable, CaseIterable {
    case codexDataAccess
    case backgroundRefresh
    case widgetRegistration
}

struct OnboardingState: Codable, Equatable {
    static let currentSchemaVersion = 2
    var schemaVersion: Int
    var lastPresentedVersion: String
    var completedRequirements: Set<SetupRequirement>
    var dismissedUpdateChecklistVersion: String?
    var updatedAt: Date
}
```

- [ ] **Step 1: Write migration and state-transition tests**

Assert schema-1 completed users retain completion. Assert pressing request changes state synchronously to `.requesting`; installing the LaunchAgent alone cannot advance access; denied/failed stays on the permission page.

- [ ] **Step 2: Implement a real access probe**

Add a reader probe that distinguishes readable Codex data, permission errors, absent data, and unexpected IO failures without changing the stored “requested” flag before resolution.

- [ ] **Step 3: Build the centered sheet**

Keep `ContentView` mounted and present a `540x500` resizable native sheet containing three stable pages:

1. local-only privacy explanation;
2. Codex access state and request/repair action;
3. background refresh and widget-registration confirmation.

Use an in-sheet page transition; remove `GeometryReader` spotlight rectangles, `SpotlightDimmer`, and `AppTourOverlay`.

- [ ] **Step 4: Add update setup checklist**

On updates, show only unmet `SetupRequirement` rows. A skip action displays the approved warning and records dismissal for that app version without falsely marking requirements complete. Keep “Run Setup” in Settings and Help.

- [ ] **Step 5: Validate**

Run tests and Xcode previews for requesting, delayed, approved, needs-manual-action, failed, skipped, and migrated states. Resize the host window while the sheet is open and confirm no clipping.

- [ ] **Step 6: Commit**

```bash
rtk git add CodexUsageMonitor/OnboardingStateStore.swift CodexUsageMonitor/OnboardingView.swift CodexUsageMonitorTests/OnboardingStateTests.swift CodexUsageMonitor.xcodeproj
rtk git commit -m "feat: make setup deterministic and unclipped"
```

### Task 6: Build the Compact Analysis-First App Shell

**Files:**

- Modify: `CodexUsageMonitor/ContentView.swift`
- Create: `CodexUsageMonitor/AppChrome.swift`
- Create: `CodexUsageMonitor/AnalysisView.swift`
- Create: `CodexUsageMonitor/ModelsView.swift`
- Create: `CodexUsageMonitor/WidgetsView.swift`
- Create: `CodexUsageMonitor/SettingsView.swift`
- Create: `CodexUsageMonitor/DataHealthView.swift`
- Modify: `CodexUsageMonitor/LimitViews.swift`
- Modify: `CodexUsageMonitor/CodexUsageMonitorApp.swift`
- Modify: `CodexUsageMonitor.xcodeproj/project.pbxproj`

**Interfaces:**

```swift
enum AppSection: String, CaseIterable, Identifiable {
    case analysis, models, widgets, settings
}

struct AnalysisSelection: Equatable {
    var period: UsagePeriod = .today
    var measure: UsageMeasure = .tokens
}
```

- [ ] **Step 1: Add selection regression tests**

Set `period = .today`, `measure = .tokens`, and assert the presented value is today’s token count even when `currentModel` is populated.

- [ ] **Step 2: Implement the icon-rail shell**

Use a fixed 52-point rail, native buttons with tooltips/accessibility labels, a flexible content region, and the data-health control anchored to the rail bottom. Keep window minimum size `980x660`.

- [ ] **Step 3: Implement Adaptive Mosaic**

Use `Grid`/`ViewThatFits` with two curated arrangements:

- width at least 1,050: chart spans two columns with four compact modules beside/below it;
- narrower width: chart full-width, then a two-column compact module grid.

Give the chart a minimum height of 230 points, `.chartPlotStyle` padding, and no negative offsets or clipping masks.

- [ ] **Step 4: Implement destinations**

- Analysis: period selector, token activity, top model, API-equivalent estimate, Headroom savings, sessions, comparisons, limit history.
- Models: period-filtered share, tokens, and API-equivalent estimate.
- Widgets: family/style/size preview browser and instructions for native Edit Widget.
- Settings: migrated app preferences, updater, setup, notifications, background/menu/Dock controls.

- [ ] **Step 5: Render explicit data states**

For each module and widget semantic value, distinguish no usage, refreshing, fresh complete, fresh partial, stale cached, permission blocked, source unavailable, and parse/write failure. Keep valid partial modules visible; include text or an accessibility label for every state.

- [ ] **Step 6: Implement data-health popover**

Map stored refresh status to Fresh, Refreshing, Stale, Permission required, or Error. Show last success, snapshot age, source state, last widget reload request, and one `Refresh now` button that awaits `.manual` and reports its result.

- [ ] **Step 7: Xcode visual QA**

Capture the real app at `980x660`, `1080x720`, and `1440x900`, with empty, partial, fresh, stale, and error data. Verify charts remain within their canvas and compact labels do not truncate important values.

- [ ] **Step 8: Commit**

```bash
rtk git add CodexUsageMonitor Shared/UsageMetrics.swift CodexUsageMonitorTests/UsageMetricsTests.swift CodexUsageMonitor.xcodeproj
rtk git commit -m "feat: add compact analysis workspace"
```

### Task 7: Add Native Per-Widget Configuration

**Files:**

- Create: `Shared/WidgetConfiguration.swift`
- Modify: `CodexUsageWidget/CodexUsageWidget.swift`
- Create: `CodexUsageMonitorTests/WidgetConfigurationTests.swift`
- Modify: `CodexUsageMonitor.xcodeproj/project.pbxproj`

**Interfaces:**

```swift
enum CodexWidgetFamily: String, Codable, CaseIterable, Sendable {
    case limits, usagePulse, costLens, modelMix, headroomImpact, sessionLive, dashboard
}

enum CodexWidgetStyle: String, Codable, CaseIterable, Sendable {
    case precisionInstrument, nativeGlass, signalGrid
}

enum DashboardArrangement: String, Codable, CaseIterable, Sendable {
    case balanced, limitsFirst, activityFirst
}

struct WidgetDisplayConfiguration: Equatable, Sendable {
    var family: CodexWidgetFamily
    var style: CodexWidgetStyle
    var theme: WidgetTheme
    var period: UsagePeriod
    var dashboardArrangement: DashboardArrangement
}
```

- [ ] **Step 1: Write configuration mapping tests**

For all seven families, three styles, four periods, and three arrangements, assert normalization preserves supported choices and ignores dashboard arrangement outside `.dashboard`.

- [ ] **Step 2: Define App Intents**

Use one intent per family so Edit Widget shows only relevant controls:

- Limits and Session Live: style, theme.
- Usage Pulse, Cost Lens, Model Mix, Headroom Impact: style, theme, period.
- Modular Dashboard: style, theme, period, arrangement.

Each intent maps to `WidgetDisplayConfiguration`; no renderer reads App Intent types directly.

- [ ] **Step 3: Convert the provider**

Create a generic `AppIntentTimelineProvider` that loads only the shared snapshot and converts the intent to normalized display configuration. Request the next timeline after three minutes.

- [ ] **Step 4: Preserve the legacy widget kind**

Use kind `CodexUsageWidget` for Usage Pulse. Add six stable kinds for the other families. When a migrated Usage Pulse intent has default values, seed presentation from existing V1 per-size settings without overwriting them.

- [ ] **Step 5: Run tests and extension build**

Run configuration tests and build the widget extension for arm64 macOS.

- [ ] **Step 6: Commit**

```bash
rtk git add Shared/WidgetConfiguration.swift CodexUsageWidget/CodexUsageWidget.swift CodexUsageMonitorTests/WidgetConfigurationTests.swift CodexUsageMonitor.xcodeproj
rtk git commit -m "feat: configure widgets per instance"
```

### Task 8: Implement Three Shared Widget Styles

**Files:**

- Create: `Shared/WidgetComponents.swift`
- Create: `Shared/WidgetStyleViews.swift`
- Refactor: `Shared/CodexUsageCardView.swift`
- Modify: `CodexUsageMonitor.xcodeproj/project.pbxproj`

**Produces:**

```swift
struct WidgetSemanticContent {
    var eyebrow: String
    var heroValue: String
    var heroLabel: String
    var secondaryValues: [WidgetLabeledValue]
    var chart: WidgetChartContent?
    var freshness: WidgetFreshness
}

struct CodexWidgetStyledContainer<Content: View>: View {
    var style: CodexWidgetStyle
    var theme: WidgetTheme
    @ViewBuilder var content: Content
}
```

- [ ] **Step 1: Extract semantic components**

Move formatting, hero metrics, compact charts, gauges, stat grids, and accessibility labels out of the legacy card. Keep `CodexUsageCardView` as a compatibility wrapper for the V1 preview path.

- [ ] **Step 2: Implement style shells**

- Precision Instrument: dark numeric surface, hairline rules, restrained gauge marks.
- Native Glass: one macOS material-like translucent field with native hierarchy.
- Signal Grid: controlled modules and subtle grid texture.

Use the existing app/widget theme colors and WidgetKit rendering mode. In tinted/monochrome mode, remove decorative color reliance and retain hierarchy through weight, opacity, and shape.

- [ ] **Step 3: Add accessibility behavior**

Every hero value exposes metric plus period; charts expose a concise trend summary; freshness and error states use text/icon in addition to color; Dynamic Type scaling must not hide the hero value.

- [ ] **Step 4: Build and inspect representative previews**

Preview each style in small, medium, and large, plus tinted and monochrome examples. Fix overflow before family views are added.

- [ ] **Step 5: Commit**

```bash
rtk git add Shared/WidgetComponents.swift Shared/WidgetStyleViews.swift Shared/CodexUsageCardView.swift CodexUsageMonitor.xcodeproj
rtk git commit -m "feat: add three native widget styles"
```

### Task 9: Implement the Seven Curated Widget Families

**Files:**

- Create: `Shared/WidgetFamilyViews.swift`
- Modify: `CodexUsageWidget/CodexUsageWidget.swift`
- Create: `CodexUsageWidget/CodexUsageWidgetPreviews.swift`
- Modify: `CodexUsageMonitor/WidgetsView.swift`
- Modify: `CodexUsageMonitorTests/WidgetConfigurationTests.swift`
- Modify: `CodexUsageMonitor.xcodeproj/project.pbxproj`

**Produces:** One renderer per `CodexWidgetFamily`, each supporting `.systemSmall`, `.systemMedium`, and `.systemLarge`.

- [ ] **Step 1: Add family-value tests**

Assert exact hero semantics:

- Limits: remaining percentage, not used percentage.
- Usage Pulse: tokens for selected period.
- Cost Lens: API-equivalent estimate for selected period.
- Model Mix: selected-period top model and share.
- Headroom Impact: saved tokens plus rate/cost avoided.
- Session Live: current session age/model/turns/tokens/freshness.
- Dashboard: curated modules determined by arrangement.

- [ ] **Step 2: Implement progressive disclosure**

For every family:

- Small: one hero plus essential context.
- Medium: comparison/secondary value or compact trend.
- Large: history and richer breakdown.

Do not duplicate formatting or data selection inside family views.

- [ ] **Step 3: Add curated dashboard arrangements**

Implement only `balanced`, `limitsFirst`, and `activityFirst`. Use fixed tested layouts per WidgetKit size; do not add drag, arbitrary resize, or a module registry.

- [ ] **Step 4: Build the preview matrix**

Create Xcode previews that cover all 63 family/size/style combinations with deterministic fixture snapshots. Add separate light, dark, tinted, and monochrome checks without multiplying redundant combinations.

- [ ] **Step 5: Register and inspect on the real desktop**

Build/install the app, register the extension, add representative instances of every family, edit styles/themes/periods, close the app, refresh the snapshot, and confirm no family is blank.

- [ ] **Step 6: Commit**

```bash
rtk git add Shared/WidgetFamilyViews.swift CodexUsageWidget CodexUsageMonitor/WidgetsView.swift CodexUsageMonitorTests/WidgetConfigurationTests.swift CodexUsageMonitor.xcodeproj
rtk git commit -m "feat: add curated V2 widget catalog"
```

### Task 10: Complete Upgrade, Runtime, Performance, and Signing Validation

**Files:**

- Modify: `CodexUsageMonitor.xcodeproj/project.pbxproj`
- Modify: `CodexUsageMonitor/Info.plist`
- Modify: `CodexUsageWidget/Info.plist`
- Modify: `scripts/install_widget.sh`
- Modify: `scripts/package_release.sh`
- Modify: `DISTRIBUTION.md`
- Create: `docs/snapshot-schema-v2.md`

- [ ] **Step 1: Set the product version**

Set `MARKETING_VERSION = 2.0.0` for app and widget. Keep build identifiers internal and absent from user-facing copy.

- [ ] **Step 2: Run every automated check**

```bash
rtk xcodebuild test -project CodexUsageMonitor.xcodeproj -scheme CodexUsageMonitor -destination 'platform=macOS' -derivedDataPath build/V2Tests
rtk xcrun swiftc Shared/CodexUsageSnapshot.swift scripts/CodexUsageReaderCheck.swift -o /tmp/CodexUsageReaderCheck
rtk /tmp/CodexUsageReaderCheck
rtk xcrun swiftc Shared/CodexUsageSnapshot.swift CodexUsageMonitor/HeadroomSavingsCollector.swift scripts/HeadroomSavingsCollectorCheck.swift -lsqlite3 -o /tmp/HeadroomSavingsCollectorCheck
rtk /tmp/HeadroomSavingsCollectorCheck
rtk xcrun swiftc CodexUsageMonitor/OnboardingStateStore.swift scripts/OnboardingStateStoreCheck.swift -o /tmp/OnboardingStateStoreCheck
rtk /tmp/OnboardingStateStoreCheck
rtk xcrun swiftc Shared/CodexUsageSnapshot.swift scripts/RateLimitReaderCheck.swift -o /tmp/RateLimitReaderCheck
rtk /tmp/RateLimitReaderCheck
```

Expected: all tests/checks pass.

- [ ] **Step 3: Build Debug and Release through Xcode**

```bash
rtk xcodebuild -project CodexUsageMonitor.xcodeproj -scheme CodexUsageMonitor -configuration Debug -destination 'platform=macOS' build
rtk xcodebuild -project CodexUsageMonitor.xcodeproj -scheme CodexUsageMonitor -configuration Release -destination 'platform=macOS' -derivedDataPath build/V2Release build
```

Expected: both builds succeed with team `Y9F67Z9663`.

- [ ] **Step 4: Validate app behavior**

Check:

- Fresh install and completed onboarding.
- Delayed, denied, failed, repaired, and skipped setup.
- Upgrade from copied V1.2.0, V1.3.0, and V1.3.4 settings.
- Today always displays today’s tokens.
- Minimum/default/large window chart bounds.
- Main app closed for at least nine minutes while snapshot age remains within the three-minute target except documented sleep/login scheduling.
- Manual refresh updates app, menu bar, snapshot, and requests widget reload once.
- Menu-bar hidden/full/background modes create no duplicate process or blank Settings window.

- [ ] **Step 5: Document the platform-neutral snapshot contract**

Write `docs/snapshot-schema-v2.md` with every public field name, JSON type, unit, optionality, freshness rule, period boundary, cost-estimate definition, limit meaning, and unknown-model behavior. Include one sanitized complete example. Do not add Windows runtime code.

- [ ] **Step 6: Profile real builds**

Use Instruments to record idle CPU/memory, unchanged refresh, changed refresh, widget timeline rendering, and analysis scrolling. Treat sustained idle CPU above 1%, repeated unchanged refresh above one second, or refresh-process lifetime above 15 seconds as release blockers.

- [ ] **Step 7: Package and verify signatures**

After Xcode automatic signing:

```bash
rtk codesign --verify --deep --strict --verbose=4 build/V2Release/Build/Products/Release/CodexUsageMonitor.app
rtk codesign -dv --verbose=4 build/V2Release/Build/Products/Release/CodexUsageMonitor.app
rtk codesign -dv --verbose=4 build/V2Release/Build/Products/Release/CodexUsageMonitor.app/Contents/PlugIns/CodexUsageWidget.appex
rtk codesign -dv --verbose=4 build/V2Release/Build/Products/Release/CodexUsageMonitor.app/Contents/Frameworks/Sparkle.framework
```

Expected: strict verification succeeds and authorities identify Nolan’s Apple Development Personal Team. `spctl` may still reject public distribution because this is not Developer ID/notarized; document that honestly.

- [ ] **Step 8: Inspect the packaged artifact**

Install into `~/Applications`, launch outside DerivedData, verify widget discovery/editing, run Sparkle’s EdDSA archive signing, and confirm release notes call it a non-notarized preview.

- [ ] **Step 9: Commit the validated V2 build**

```bash
rtk git add CodexUsageMonitor.xcodeproj CodexUsageMonitor CodexUsageWidget Shared scripts docs/snapshot-schema-v2.md DISTRIBUTION.md
rtk git commit -m "release: prepare Codex Usage Monitor 2.0"
```

Do not tag, publish, or replace the user’s installed copy until Nolan reviews the packaged V2 candidate.
