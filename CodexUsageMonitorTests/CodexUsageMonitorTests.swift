import Foundation
import AppKit
import Security
import LocalAuthentication
import SwiftUI
import Testing
@testable import CodexUsageMonitor

@Test("Streaming JSONL handles split UTF-8, large rows, CRLF, malformed rows and a final row", arguments: [1, 7, 65_536])
func streamingJSONLBoundaries(chunkSize: Int) throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: url) }
    let largeValue = String(repeating: "🚆", count: chunkSize == 1 ? 40 : 20_000)
    let rows: [[String: Any]] = [["id": 1, "text": "héllo 🚆"], ["id": 2, "text": largeValue], ["id": 3]]
    var bytes = Data([10])
    for row in rows.dropLast() {
        bytes.append(try JSONSerialization.data(withJSONObject: row))
        bytes.append(contentsOf: [13, 10])
    }
    bytes.append(Data("malformed\n{\"truncated\":\n".utf8))
    bytes.append(try JSONSerialization.data(withJSONObject: rows.last!))
    try bytes.write(to: url)
    var ids: [Int] = []
    try JSONLFileReader.forEachRow(at: url, chunkSize: chunkSize) { row in
        ids.append(row["id"] as! Int)
        if row["id"] as? Int == 2 { #expect(row["text"] as? String == largeValue) }
    }
    #expect(ids == [1, 2, 3])
}

@Test("Streaming JSONL propagates unreadable file errors")
func streamingJSONLReadFailure() {
    #expect(throws: (any Error).self) {
        try JSONLFileReader.forEachRow(at: URL(fileURLWithPath: "/nonexistent/\(UUID().uuidString).jsonl")) { _ in }
    }
}

@Test("Saved chat names update independently, tolerate broken rows, and never load unrelated titles")
func savedChatNames() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let index = directory.appendingPathComponent("session_index.jsonl")
    let rows = """
    {"id":"chat-a","thread_name":"Old name"}
    broken row
    {"id":"other-chat","thread_name":"Private unrelated title"}
    {"id":"chat-a","thread_name":"  Build   the UI  "}
    """
    try Data(rows.utf8).write(to: index)
    #expect(CodexSessionNames.load(for: ["chat-a"], from: index) == ["chat-a": "Build the UI"])
    var snapshot = CodexUsageSnapshot.empty
    snapshot.sessionActivity = [CodexSessionActivity(id: "chat-a", project: "project")]
    snapshot.recentSessions = [CodexSessionSummary(id: "chat-a#123", startedAt: .now, updatedAt: .now,
        usage: .zero, turns: 1, model: "gpt-6.1-sol", estimatedCostUSD: nil)]
    let named = CodexSessionNames.applying(to: snapshot, from: index)
    #expect(named.sessionActivity.first?.displayTitle == "Build the UI")
    #expect(named.recentSessions.first?.displayTitle == "Build the UI")
    #expect(named.recentSessions.first?.sessionID == "chat-a")
    let missing = CodexSessionNames.applying(to: named, from: directory.appendingPathComponent("missing"))
    #expect(missing.sessionActivity.first?.displayTitle == "project")
    #expect(missing.recentSessions.first?.displayTitle == "Session chat-a")
    // Old snapshots omit title fields; optional metadata must stay backwards compatible.
    let legacy = try JSONEncoder().encode(snapshot)
    #expect(try JSONDecoder().decode(CodexUsageSnapshot.self, from: legacy) == snapshot)
    let oversized = String(repeating: "x", count: 80_000) + "\n" + rows
    try Data(oversized.utf8).write(to: index)
    #expect(CodexSessionNames.load(for: ["chat-a"], from: index)["chat-a"] == "Build the UI")
}

@Test("Chat browsing combines dates, names and models; unpriced estimates sort last")
func sessionBrowserFiltering() {
    let now = Date(timeIntervalSince1970: 1_790_000_000)
    let a = CodexSessionSummary(id: "a#1", startedAt: now, updatedAt: now,
        usage: TokenUsage(input: 20, cachedInput: 5, output: 10, reasoningOutput: 2, total: 30),
        turns: 2, model: "gpt-6.1-sol", estimatedCostUSD: nil, title: "Build the UI")
    var b = a
    b.id = "b#1"; b.title = "Naming study"; b.estimatedCostUSD = 0
    var old = a
    old.id = "old#1"; old.updatedAt = now.addingTimeInterval(-32 * 86_400)
    #expect(SessionBrowser.filtered([a, b, old], range: .thirtyDays, search: " UI ", sort: .recent, now: now).map(\.id) == [a.id])
    #expect(SessionBrowser.filtered([a, b], range: .today, search: "sol", sort: .cost, now: now).map(\.id) == [b.id, a.id])
    #expect(SessionBrowser.filtered([a, b], range: .today, search: "missing", sort: .recent, now: now).isEmpty)
    #expect(!SessionRange.today.includes(now.addingTimeInterval(1), now: now))
}

@Test("Glass workspace leaves a clear gutter and stretches only at its edge")
func glassWorkspaceKeepsTransparentCutout() {
    let rect = CGRect(x: 0, y: 0, width: 480, height: 500)
    let closed = WorkspaceGlassShape(pull: 0, anchor: 250).path(in: rect)
    let stretched = WorkspaceGlassShape(pull: 1, anchor: 250).path(in: rect)
    #expect(closed.contains(CGPoint(x: 240, y: 250)))
    #expect(!closed.contains(CGPoint(x: 50, y: 250)))
    #expect(stretched.contains(CGPoint(x: 50, y: 250)))
    #expect(!stretched.contains(CGPoint(x: 50, y: 60)))
    #expect(!closed.contains(CGPoint(x: 479, y: 499)))
}

@Test("Dock hover covers full rows and remains vertically centered at every window size")
func glassDockHoverGeometry() {
    for windowHeight: CGFloat in [460, 500, 720] {
        let top = (windowHeight - WorkspaceNavigationGeometry.height) / 2
        for (index, section) in AppSection.allCases.enumerated() {
            let y = top + 7 + CGFloat(index) * WorkspaceNavigationGeometry.rowHeight
            for x: CGFloat in [12.5, 20, 41, 62, 69.5] {
                for offset: CGFloat in [0.5, 24.5, 48.5] {
                    #expect(WorkspaceNavigationGeometry.section(at: CGPoint(x: x, y: y + offset), height: windowHeight) == section)
                }
            }
        }
        #expect(WorkspaceNavigationGeometry.section(at: CGPoint(x: 41, y: top + 1), height: windowHeight) == AppSection.allCases.first)
        #expect(WorkspaceNavigationGeometry.section(at: CGPoint(x: 41, y: windowHeight - top - 1), height: windowHeight) == AppSection.allCases.last)
        #expect(WorkspaceNavigationGeometry.section(at: CGPoint(x: 71, y: windowHeight / 2), height: windowHeight) == nil)
        #expect(WorkspaceNavigationGeometry.section(at: CGPoint(x: 41, y: top - 1), height: windowHeight) == nil)
        #expect(WorkspaceNavigationGeometry.isEdge(CGPoint(x: 80, y: windowHeight / 2), height: windowHeight))
        #expect(!WorkspaceNavigationGeometry.isEdge(CGPoint(x: 100, y: windowHeight / 2), height: windowHeight))
    }
}

@Test("Pointer-only edge pull snaps without a click and trackpad gestures have independent thresholds")
@MainActor
func glassEdgeMouseTracking() throws {
    let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 480, height: 500), styleMask: .borderless, backing: .buffered, defer: false)
    let view = GlassEdgeCaptureView(frame: CGRect(x: 0, y: 0, width: 480, height: 500))
    window.contentView = view
    defer { view.stopMonitoring(); window.contentView = nil }
    var revealedAt: CGFloat?
    var pull: CGFloat = 0
    var haptics = 0
    view.onPull = { progress, _ in pull = progress }
    view.onReveal = { revealedAt = $0 }
    view.onSnapFeedback = { haptics += 1 }
    func event(_ type: NSEvent.EventType, x: CGFloat, y: CGFloat) throws -> NSEvent {
        try #require(NSEvent.mouseEvent(with: type, location: CGPoint(x: x, y: 500 - y), modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 0))
    }
    #expect(view.handle(try event(.mouseMoved, x: 80, y: 250)) != nil)
    #expect(revealedAt == nil)
    _ = view.handle(try event(.mouseMoved, x: 64, y: 250))
    #expect(pull == 0.5)
    _ = view.handle(try event(.mouseMoved, x: 110, y: 250))
    #expect(pull == 0)
    _ = view.handle(try event(.mouseMoved, x: 80, y: 250))
    _ = view.handle(try event(.mouseMoved, x: 48, y: 250))
    #expect(revealedAt == 250)
    #expect(haptics == 1)
    _ = view.handle(try event(.mouseMoved, x: 40, y: 250))
    #expect(haptics == 1)
    view.railOpen = true
    view.railOpen = false
    revealedAt = nil
    #expect(view.handle(try event(.leftMouseDown, x: 80, y: 250)) != nil)
    #expect(view.handle(try event(.leftMouseDragged, x: 20, y: 250)) != nil)
    #expect(revealedAt == nil)
    #expect(view.hitTest(CGPoint(x: 80, y: 250)) == nil)
    let edge = CGPoint(x: 80, y: 250)
    #expect(!view.handleScroll(at: edge, outwardDelta: 10, verticalDelta: 30, precise: true, phase: .began, momentum: false))
    #expect(!view.handleScroll(at: edge, outwardDelta: 50, verticalDelta: 0, precise: false, phase: .began, momentum: false))
    #expect(!view.handleScroll(at: CGPoint(x: 200, y: 250), outwardDelta: 50, verticalDelta: 0, precise: true, phase: .began, momentum: false))
    #expect(view.handleScroll(at: edge, outwardDelta: 24, verticalDelta: 0, precise: true, phase: .began, momentum: false))
    #expect(pull == 0.5)
    #expect(view.handleScroll(at: edge, outwardDelta: 0, verticalDelta: 0, precise: true, phase: .ended, momentum: false))
    #expect(pull == 0)
    #expect(revealedAt == nil)
    #expect(view.handleScroll(at: edge, outwardDelta: 48, verticalDelta: 0, precise: true, phase: .began, momentum: false))
    #expect(revealedAt == 250)
    #expect(haptics == 2)
    #expect(!view.handleScroll(at: edge, outwardDelta: 100, verticalDelta: 0, precise: true, phase: .changed, momentum: true))
    #expect(haptics == 2)
    let escape = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
        timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "\u{1b}",
        charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53))
    var dismissed = false
    view.onDismiss = { dismissed = true }
    #expect(view.handle(escape) == nil)
    #expect(dismissed)
    #expect(view.handle(escape) != nil)
    #expect(view.accessibilityPerformPress())
    #expect(haptics == 3)
}

@Test("Automatic phone-topic reads cannot display a Keychain password prompt")
func phoneTopicReadsAreNoninteractive() {
    #expect((NtfyTopicStore.readQuery()[kSecUseAuthenticationContext] as? LAContext)?.interactionNotAllowed == true)
    #expect((NtfyTopicStore.readQuery(allowInteraction: true)[kSecUseAuthenticationContext] as? LAContext)?.interactionNotAllowed == false)
}

@Test("Monthly Headroom uses recorded daily savings and distinguishes missing data from zero")
func monthlyHeadroomUsesRecordedDays() {
    var snapshot = CodexUsageSnapshot.empty
    let date = Date(timeIntervalSince1970: 1_705_000_000)
    snapshot.generatedAt = date
    #expect(snapshot.headroomTokensSaved(for: .month) == nil)
    snapshot.headroom = .zero
    snapshot.headroom?.lifetimeTokensSaved = 900
    snapshot.headroom?.todayTokensSaved = 20
    snapshot.headroom?.last7DaysTokensSaved = 70
    #expect(snapshot.headroomTokensSaved(for: .lifetime) == 900)
    #expect(snapshot.headroomTokensSaved(for: .today) == 20)
    snapshot.activityDays = [.init(date: date, usage: .zero, sessions: 0, headroomSaved: 30)]
    #expect(snapshot.headroomTokensSaved(for: .month) == 30)
    snapshot.activityDays[0].headroomSaved = 0
    #expect(snapshot.headroomTokensSaved(for: .month) == 0)
}

@Test("Empty snapshot starts at zero")
func emptySnapshotStartsAtZero() {
    #expect(CodexUsageSnapshot.empty.today.total == 0)
    #expect(CodexUsageSnapshot.empty.lifetime.total == 0)
}

@Test("Background refresh runs once per minute")
func backgroundRefreshRunsOncePerMinute() {
    #expect(BackgroundRefreshAgent.interval == 60)
}

@Test("Menu bar label formats both limit rows")
func menuBarLabelFormatsBothLimitRows() {
    let window = RateLimitWindow(
        usedPercent: 24.6,
        windowMinutes: 300,
        resetsAt: .now.addingTimeInterval(3_600),
        observedAt: .now
    )

    #expect(CodexMenuBarLabel.labelText(prefix: "5H", window: window, mode: .percentage) == "5H 75%")
    #expect(CodexMenuBarLabel.labelText(prefix: "W", window: window, mode: .percentage) == "W 75%")
    #expect(CodexMenuBarLabel.labelText(prefix: "W", window: nil, mode: .percentage) == "W —")
}

@Test("Phone reset request is sent only after a confirmed five-hour reset")
func phoneResetRequestRequiresConfirmedReset() throws {
    let now = try #require(ISO8601DateFormatter().date(from: "2026-08-30T12:00:00Z"))
    let window = RateLimitWindow(
        usedPercent: 1,
        windowMinutes: 300,
        resetsAt: now.addingTimeInterval(5 * 3_600),
        observedAt: now
    )

    let request = try #require(PhoneResetNotificationManager.confirmedResetRequest(
        topic: "codex-private-topic",
        window: window,
        previousReset: now.addingTimeInterval(-1).timeIntervalSince1970,
        now: now
    ))

    #expect(request.url?.absoluteString == "https://ntfy.sh/codex-private-topic")
    #expect(request.httpMethod == "POST")
    #expect(request.value(forHTTPHeaderField: "At") == nil)
}

@Test("Reset notification state ignores timestamp jitter and older windows")
func resetNotificationStateRejectsDuplicateWindows() throws {
    let reset = try #require(ISO8601DateFormatter().date(from: "2026-08-30T13:00:00Z"))
    let stored = reset.timeIntervalSince1970

    #expect(LimitNotificationManager.isNewReset(reset, after: 0))
    #expect(!LimitNotificationManager.isNewReset(reset.addingTimeInterval(1), after: stored))
    #expect(!LimitNotificationManager.isNewReset(reset.addingTimeInterval(-3_600), after: stored))
    #expect(LimitNotificationManager.isNewReset(reset.addingTimeInterval(5 * 3_600), after: stored))
}

@Test("Legacy reset alert state migrates without sending again")
func legacyResetNotificationStateIsRecognized() throws {
    let suiteName = "CodexUsageMonitorTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    defaults.set(true, forKey: "CodexUsageMonitor.notified.300.1788226971.80")

    #expect(LimitNotificationManager.previousNotifiedReset(
        defaults: defaults,
        windowMinutes: 300,
        threshold: 80
    ) == 1_788_226_971)
    #expect(LimitNotificationManager.previousNotifiedReset(
        defaults: defaults,
        windowMinutes: 300,
        threshold: 95
    ) == 0)
}

@Test("Reset notifications require an observed window transition")
func resetNotificationsRequireObservedTransition() throws {
    let now = try #require(ISO8601DateFormatter().date(from: "2026-08-30T12:00:00Z"))
    let fiveHour = RateLimitWindow(
        usedPercent: 1,
        windowMinutes: 300,
        resetsAt: now.addingTimeInterval(5 * 3_600),
        observedAt: now
    )
    let weekly = RateLimitWindow(
        usedPercent: 77,
        windowMinutes: 10_080,
        resetsAt: now.addingTimeInterval(6 * 86_400),
        observedAt: now
    )

    #expect(LimitNotificationManager.isConfirmedReset(
        previousReset: now.addingTimeInterval(-1).timeIntervalSince1970,
        window: fiveHour,
        now: now
    ))
    #expect(!LimitNotificationManager.isConfirmedReset(
        previousReset: weekly.resetsAt.timeIntervalSince1970,
        window: weekly,
        now: now
    ))
    #expect(PhoneResetNotificationManager.confirmedResetRequest(
        topic: "codex-private-topic",
        window: fiveHour,
        previousReset: fiveHour.resetsAt.timeIntervalSince1970,
        now: now
    ) == nil)
}

@Test("Reader splits and prices a chat across active days", arguments: ["gpt-5.6-sol", "gpt-6.1-sol"])
func readerSplitsChatAcrossActiveDays(model: String) throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let log = """
    {"type":"session_meta","payload":{"id":"session-1","session_id":"session-1","timestamp":"2026-07-31T10:00:00Z"}}
    {"type":"turn_context","payload":{"model":"\(model)"}}
    {"timestamp":"2026-07-31T10:01:00Z","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":80,"cached_input_tokens":20,"output_tokens":20,"reasoning_output_tokens":0,"total_tokens":100},"last_token_usage":{"input_tokens":80,"cached_input_tokens":20,"output_tokens":20,"reasoning_output_tokens":0,"total_tokens":100}}}}
    {"timestamp":"2026-07-31T10:05:00Z","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":200,"cached_input_tokens":50,"output_tokens":50,"reasoning_output_tokens":0,"total_tokens":250},"last_token_usage":{"input_tokens":120,"cached_input_tokens":30,"output_tokens":30,"reasoning_output_tokens":0,"total_tokens":150}}}}
    {"timestamp":"2026-08-01T09:15:00Z","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":240,"cached_input_tokens":60,"output_tokens":60,"reasoning_output_tokens":0,"total_tokens":300},"last_token_usage":{"input_tokens":40,"cached_input_tokens":10,"output_tokens":10,"reasoning_output_tokens":0,"total_tokens":50}}}}
    """
    try Data(log.utf8).write(to: directory.appendingPathComponent("session-1.jsonl"))

    let now = try #require(ISO8601DateFormatter().date(from: "2026-08-01T12:00:00Z"))
    let reader = CodexUsageReader(sessionsDirectory: directory, cacheURL: directory.appendingPathComponent("reader-cache.plist"))
    let snapshot = reader.snapshot(now: now)
    let newest = try #require(snapshot.recentSessions.first)
    let previous = try #require(snapshot.recentSessions.last)

    #expect(snapshot.recentSessions.count == 2)
    #expect(newest.id.hasPrefix("session-1#"))
    #expect(newest.model == model)
    #expect(newest.turns == 1)
    #expect(newest.usage.total == 50)
    #expect(previous.turns == 2)
    #expect(previous.usage.total == 250)
    #expect(previous.estimatedCostUSD != nil)
    let pricing = try #require(ModelPricingCatalog.pricing(for: model))
    let cost = pricing.estimatedCost(for: snapshot.lifetime)
    #expect(abs(snapshot.estimatedCostUSD - cost) < 0.000_001)
    let modelEstimate = try #require(snapshot.modelUsage?.first).estimatedCostUSD
    #expect(abs(modelEstimate - cost) < 0.000_001)
    #expect(snapshot.unpricedTokens == 0)
    #expect(reader.snapshot(now: now).estimatedCostUSD == snapshot.estimatedCostUSD)
}

@Test("GPT-6.1 Sol uses its own cache rates and the 272K context boundary")
func sol61Pricing() throws {
    let pricing = try #require(ModelPricingCatalog.pricing(for: "gpt-6.1-sol"))
    #expect(ModelPricingCatalog.pricing(for: "gpt-6.1-sol-2026-10-01") == pricing)
    #expect(pricing.inputPerMillion == 2)
    #expect(pricing.cachedInputPerMillion == 0.1)
    #expect(pricing.outputPerMillion == 10)
    let short = TokenUsage(input: 272_000, cachedInput: 100_000, output: 10_000, reasoningOutput: 0, total: 282_000)
    let long = TokenUsage(input: 272_001, cachedInput: 100_000, output: 10_000, reasoningOutput: 0, total: 282_001)
    #expect(abs(pricing.estimatedCost(for: short) - 0.454) < 0.000_001)
    #expect(abs(pricing.estimatedCost(for: long) - 0.858004) < 0.000_001)
}

@Test("Missing model rates remain distinct from zero and recorded estimates")
func missingModelRatesRemainUnavailable() {
    let unpriced = ModelUsage(model: "unknown-model", usage: .zero, turns: 0, estimatedCostUSD: 0)
    let pricedZero = ModelUsage(model: "gpt-6-sol", usage: .zero, turns: 0, estimatedCostUSD: 0)
    let recorded = ModelUsage(model: "retired-model", usage: .zero, turns: 0, estimatedCostUSD: 2.5)
    #expect(unpriced.availableCostEstimateUSD == nil)
    #expect(pricedZero.availableCostEstimateUSD == 0)
    #expect(recorded.availableCostEstimateUSD == 2.5)
}
