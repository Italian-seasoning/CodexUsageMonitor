import SwiftUI
import Combine
import AppKit
import Charts

extension Notification.Name {
    static let showCodexUsageCompactPreview = Notification.Name("showCodexUsageCompactPreview")
}

enum SnapshotDisplay {
    static func load() -> CodexUsageSnapshot? {
        guard let snapshot = CodexUsageSnapshotStore.load() else { return nil }
        guard OnboardingStateStore.hasCurrentCodexDataAccess() else { return snapshot }
        return CodexSessionNames.applying(to: snapshot, from: FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/session_index.jsonl"))
    }
}

struct DetailedContentView: View {
    @EnvironmentObject private var settingsModel: CodexUsageSettingsModel
    @State private var section = AppSection.history
    @State private var analysisSelection = AnalysisSelection()
    @State private var snapshot = SnapshotDisplay.load() ?? .empty
    @State private var refreshRecord = BackgroundRefreshAgent.loadRecord()
    @State private var isRefreshing = false
    @State private var presentsDataHealth = false
    private let snapshotTimer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    private var health: SnapshotHealth {
        SnapshotHealth(snapshot: snapshot, record: refreshRecord, isRefreshing: isRefreshing)
    }

    var body: some View {
        ZStack {
            WindowBackdrop(light: settingsModel.settings.appTheme == .runway).ignoresSafeArea()
            AppPalette.windowTint.ignoresSafeArea()

            HStack(spacing: 0) {
                AppRail(
                    selection: $section,
                    presentsDataHealth: $presentsDataHealth,
                    health: health
                )

                Group {
                    switch section {
                    case .analysis, .history:
                        AnalysisView(snapshot: snapshot, health: health, selection: $analysisSelection, section: .history)
                    case .sessions:
                        SessionsView(snapshot: snapshot, health: health)
                    case .models:
                        ModelsView(snapshot: snapshot, health: health)
                    case .widgets:
                        WidgetsView(snapshot: snapshot)
                    case .settings:
                        SettingsView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .overlay(alignment: .bottomLeading) {
                if presentsDataHealth {
                    DataHealthView(
                        snapshot: $snapshot,
                        record: $refreshRecord,
                        isRefreshing: $isRefreshing
                    )
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.28), radius: 18, y: 8)
                    .padding(.leading, 64)
                    .padding(.bottom, 16)
                }
            }
        }
        .frame(minWidth: 980, idealWidth: 1080, minHeight: 660, idealHeight: 720)
        .preferredColorScheme(settingsModel.settings.appTheme.colorScheme)
        .environment(\.colorScheme, settingsModel.settings.appTheme.colorScheme)
        .foregroundStyle(AppPalette.text)
        .tint(AppPalette.accent)
        .id(settingsModel.settings.appTheme)
        .onReceive(NotificationCenter.default.publisher(for: .codexUsageSnapshotDidChange)) { _ in
            snapshot = SnapshotDisplay.load() ?? snapshot
            refreshRecord = BackgroundRefreshAgent.loadRecord()
        }
        .onReceive(snapshotTimer) { _ in
            snapshot = SnapshotDisplay.load() ?? snapshot
            refreshRecord = BackgroundRefreshAgent.loadRecord()
        }
    }
}


/// Navigation pulls out of the window's glass edge into the transparent gutter.
struct ContentView: View {
    @EnvironmentObject private var settingsModel: CodexUsageSettingsModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var snapshot = SnapshotDisplay.load() ?? .empty
    @State private var section = AppSection.analysis
    @State private var selectedSessionID: String?
    @State private var railOpen = false
    @State private var stretch: CGFloat = 0
    @State private var edgeAnchor: CGFloat = 250
    @Namespace private var glassNamespace
    @State private var hoveredSection: AppSection?
    @State private var analysisSelection = AnalysisSelection(period: .sevenDays)
    @State private var showsSessionHistory = false
    @State private var presentsDataHealth = false
    @State private var isRefreshing = false
    @State private var refreshRecord = BackgroundRefreshAgent.loadRecord()
    @State private var showsRefreshFailure = false
    @State private var refreshFailureMessage = ""
    private let timer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    private var activity: CodexSessionActivity? {
        snapshot.sessionActivity.first { $0.id == selectedSessionID }
            ?? snapshot.sessionActivity.first { $0.status() == "Working" }
            ?? snapshot.sessionActivity.first
    }

    private var motion: Animation? { reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.82) }

    var body: some View {
        workspace
        .preferredColorScheme(settingsModel.settings.appTheme.colorScheme)
        .environment(\.colorScheme, settingsModel.settings.appTheme.colorScheme)
        .onChange(of: settingsModel.settings.appTheme, initial: true) { _, theme in
            NSApp.windows.first { $0.identifier?.rawValue == "Runway.MainWindow" }?
                .appearance = NSAppearance(named: theme == .runway ? .aqua : .darkAqua)
        }
        .foregroundStyle(.primary)
        .font(.system(size: AppTypeScale.body))
        .controlSize(.small)
        .tint(settingsModel.settings.appTheme.accent)
        .frame(minWidth: 448, idealWidth: 480, minHeight: 460, idealHeight: 500)
        .background {
            Button("Show navigation") { revealRail() }
                .keyboardShortcut("n", modifiers: [.command, .option])
                .hidden().accessibilityHidden(true)
            ForEach(Array(AppSection.allCases.enumerated()), id: \.element) { index, item in
                Button(item.title) { select(item) }
                    .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: [.command])
                    .hidden().accessibilityHidden(true)
            }
        }
        .onReceive(timer) { _ in reload() }
        .onReceive(NotificationCenter.default.publisher(for: .codexUsageSnapshotDidChange)) { _ in reload() }
        .onExitCommand(perform: dismissRail)
        .alert("Refresh failed", isPresented: $showsRefreshFailure) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(refreshFailureMessage)
        }
    }

    private var workspace: some View {
        GeometryReader { geometry in
            let shape = WorkspaceGlassShape(pull: reduceMotion ? 0 : stretch, anchor: edgeAnchor)
            ZStack(alignment: .topLeading) {
                workspaceSurface(shape)
                    .allowsHitTesting(false)
                VStack(spacing: 0) {
                    windowControls
                    Group {
                        switch section {
                        case .analysis: activityPage
                        case .history: AnalysisView(snapshot: snapshot, health: health, selection: $analysisSelection, section: .history)
                        case .sessions: sessionsPage
                        case .models: ModelsView(snapshot: snapshot, health: health)
                        case .widgets: WidgetsView(snapshot: snapshot)
                        case .settings: SettingsView()
                        }
                    }
                    .id(section)
                    .transition(reduceMotion ? .opacity : .asymmetric(
                        insertion: .offset(x: 0, y: 12).combined(with: .opacity),
                        removal: .opacity
                    ))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .padding(.leading, 76)
                .padding(.trailing, 12)
                .padding(.vertical, 12)
                .workspaceGlass(shape: shape, namespace: glassNamespace, opaque: reduceTransparency)

                if !railOpen {
                    Capsule()
                        .fill(Color.primary.opacity(0.38))
                        .frame(width: 3, height: 32)
                        .position(x: 82 - stretch * 32, y: geometry.size.height / 2)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                if railOpen {
                    navigationRail
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                        .padding(.leading, 41 - WorkspaceNavigationGeometry.width / 2)
                        .transition(reduceMotion ? .opacity : .offset(x: 18).combined(with: .opacity))
                }
                mouseTracking(height: geometry.size.height)
            }
            .coordinateSpace(name: "workspace")
            .animation(motion, value: section)
        }
    }

    @ViewBuilder private func workspaceSurface(_ shape: WorkspaceGlassShape) -> some View {
        if reduceTransparency {
            shape.fill(Color(nsColor: .windowBackgroundColor))
        } else {
            WorkspaceBackdrop(pull: shape.pull, anchor: shape.anchor, light: settingsModel.settings.appTheme == .runway)
            if settingsModel.settings.appTheme == .runway {
                shape.fill(settingsModel.settings.appTheme.windowTint)
            }
        }
    }

    private var windowControls: some View {
        HStack(spacing: 7) {
            Button { NSApp.keyWindow?.close() } label: {
                Circle().fill(Color.red.opacity(0.8)).frame(width: 11, height: 11)
                    .frame(width: 20, height: 20).contentShape(Rectangle())
            }
                .accessibilityLabel("Close window")
                .help("Close window")
            Button { NSApp.keyWindow?.miniaturize(nil) } label: {
                Circle().fill(Color.yellow.opacity(0.9)).frame(width: 11, height: 11)
                    .frame(width: 20, height: 20).contentShape(Rectangle())
            }
                .accessibilityLabel("Minimize window")
                .help("Minimize window")
            Button { NSApp.keyWindow?.zoom(nil) } label: {
                Circle().fill(Color.green.opacity(0.8)).frame(width: 11, height: 11)
                    .frame(width: 20, height: 20).contentShape(Rectangle())
            }
                .accessibilityLabel("Zoom window")
                .help("Zoom window")
            if #available(macOS 15.0, *) {
                Color.clear
                    .frame(maxWidth: .infinity)
                    .frame(height: 20)
                    .contentShape(Rectangle())
                    .gesture(WindowDragGesture())
                    .accessibilityHidden(true)
            } else {
                Spacer()
            }
            if section == .analysis {
                Text(section.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 22).padding(.top, 15).padding(.bottom, 3)
    }

    private func mouseTracking(height: CGFloat) -> some View {
        GlassEdgeCapture(
            railOpen: railOpen,
            onHover: { point in
                if let point, WorkspaceNavigationGeometry.isEdge(point, height: height) {
                    withAnimation(motion) {
                        edgeAnchor = min(max(point.y, 98), height - 98)
                    }
                }
                let item = railOpen ? point.flatMap {
                    WorkspaceNavigationGeometry.section(at: $0, height: height)
                } : nil
                hoveredSection = item
                if let item, item != section {
                    select(item)
                }
            },
            onPull: { progress, y in
                edgeAnchor = min(max(y, 98), height - 98)
                if progress == 0 {
                    withAnimation(motion) { stretch = 0 }
                } else { stretch = progress }
            },
            onReveal: { y in
                edgeAnchor = min(max(y, 98), height - 98)
                revealRail()
            },
            onDismiss: dismissRail
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var navigationRail: some View {
        VStack(spacing: 0) {
            ForEach(AppSection.allCases) { item in
                Button { select(item); dismissRail() } label: {
                    Image(systemName: item.symbol)
                        .font(.system(size: 17, weight: .medium))
                        .frame(width: 40, height: 42)
                        .foregroundStyle(section == item ? settingsModel.settings.appTheme.accent : .primary)
                        .background(
                            section == item ? settingsModel.settings.appTheme.accent.opacity(0.18)
                                : hoveredSection == item ? Color.white.opacity(0.08) : .clear,
                            in: RoundedRectangle(cornerRadius: 12)
                        )
                        .frame(width: WorkspaceNavigationGeometry.width, height: WorkspaceNavigationGeometry.rowHeight)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(item.title)
                .accessibilityLabel(item.title)
                .accessibilityAddTraits(section == item ? .isSelected : [])
            }
        }
        .padding(.vertical, 7)
        .frame(width: WorkspaceNavigationGeometry.width, height: WorkspaceNavigationGeometry.height)
        .navigationGlass(namespace: glassNamespace, opaque: reduceTransparency)
    }

    private var activityPage: some View {
        MagneticScrollView { height in
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Menu {
                            Button("Follow latest activity") { selectedSessionID = nil }
                            Divider()
                            ForEach(snapshot.sessionActivity) { session in
                                Button(session.displayTitle) {
                                    selectedSessionID = session.id
                                }
                            }
                        } label: {
                            Text(selectedSessionID == nil ? "Latest chat" : "Selected chat").lineLimit(1)
                        }.menuStyle(.borderlessButton).fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel("Choose session")
                        Spacer(minLength: 8)
                        Text(activity?.status() ?? "Awaiting data")
                            .foregroundStyle(activity?.status() == "Working" ? AppPalette.positive : .secondary)
                    }
                    .font(.system(size: 11, weight: .medium))
                    if let title = activity?.displayTitle {
                        Text(title)
                            .font(.system(size: 15, weight: .medium))
                            .lineLimit(2)
                            .help(title)
                    }
                    HStack {
                        Text(ModelPricingCatalog.displayName(for: activity?.model ?? snapshot.currentModel))
                            .lineLimit(1).minimumScaleFactor(0.85)
                        Spacer(minLength: 8)
                        if let tokens = activity?.contextTokens, let window = activity?.contextWindow, window > 0 {
                            Text("\((Double(tokens) / Double(window)).formatted(.percent.precision(.fractionLength(0)))) context")
                                .monospacedDigit()
                                .help("\(tokens.compactTokenString) / \(window.compactTokenString) context tokens")
                        }
                    }
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                let usage = activity?.usage ?? snapshot.currentSession
                VStack(alignment: .leading, spacing: 10) {
                    Text("Session usage")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(usage.total.compactTokenString)
                            .font(.system(size: 36, weight: .semibold)).tracking(-1.2).monospacedDigit()
                        Text("tokens").font(.system(size: 12)).foregroundStyle(.secondary)
                        Spacer(minLength: 8)
                        Text("\((activity?.requests ?? snapshot.currentSessionTurns ?? 0).formatted()) requests")
                            .font(.system(size: 12)).monospacedDigit().foregroundStyle(.secondary)
                    }
                    if let points = activity?.usageHistory, !points.isEmpty {
                        WidgetSparkline(chart: WidgetChartContent(
                            points: points.map { WidgetChartPoint(date: $0.date, value: Double($0.totalTokens)) },
                            accessibilitySummary: "Session token history, latest \(usage.total.compactTokenString) tokens"
                        ), palette: activityPalette)
                        .frame(height: max(24, height - 362))
                        HStack {
                            Text("Recent history")
                            Spacer()
                            Text("Latest")
                        }
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 4)
                VStack(alignment: .leading, spacing: 10) {
                    Text("Remaining allowance")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    HStack(alignment: .top, spacing: 20) {
                        if snapshot.rateLimits?.showsFiveHour == true {
                        WidgetAllowanceMeter(title: "5-hour", window: snapshot.rateLimits?.fiveHour, palette: activityPalette,
                            showsConsumption: true, consumptionRate: snapshot.rateLimits?.consumptionPer15Minutes(for: snapshot.rateLimits?.fiveHour))
                        }
                        WidgetAllowanceMeter(title: "Weekly", window: snapshot.rateLimits?.weekly, palette: activityPalette,
                            showsConsumption: true, consumptionRate: snapshot.rateLimits?.consumptionPer15Minutes(for: snapshot.rateLimits?.weekly))
                    }
                }
                .padding(12)
                .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))
                Spacer(minLength: 0)
                HStack {
                    Button { presentsDataHealth = true } label: {
                        HStack(spacing: 5) {
                            Circle().fill(health.color).frame(width: 5, height: 5)
                            Text(health.title).font(.system(size: 11))
                        }
                    }
                    .buttonStyle(.plain).help(health.detail)
                    .popover(isPresented: $presentsDataHealth) {
                        DataHealthView(snapshot: $snapshot, record: $refreshRecord, isRefreshing: $isRefreshing)
                            .frame(width: 320).padding(14)
                    }
                    Spacer()
                    Button {
                        isRefreshing = true
                        Task {
                            let result = await RefreshCoordinator.shared.refresh(trigger: .manual, force: true)
                            reload()
                            isRefreshing = false
                            if result.outcome == .failed {
                                refreshFailureMessage = result.message
                                showsRefreshFailure = true
                            }
                        }
                    } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.plain).help("Refresh local data")
                    .accessibilityLabel("Refresh local data")
                    .disabled(isRefreshing)
                }
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .frame(minHeight: height, alignment: .top)
        } details: {
            InspectorSection(title: "Session details") {
                let usage = activity?.usage ?? snapshot.currentSession
                VStack(spacing: 8) {
                    detail("Reasoning", activity?.reasoningEffort?.capitalized)
                    detail("Recorded events", (activity?.usageHistory).map { $0.count.formatted() })
                    detail("Tools", activity?.toolCalls.map(String.init))
                    detail("Failures", activity?.toolFailures.map(String.init))
                    detail("Last tool", activity?.lastTool)
                    detail("Context", activity?.contextTokens.map { $0.compactTokenString })
                    detail("Context window", activity?.contextWindow.map { $0.compactTokenString })
                    detail("Input", usage.input.compactTokenString)
                    detail("Cached input", usage.cachedInput.compactTokenString)
                    detail("Cached share", usage.input > 0 ? (Double(usage.cachedInput) / Double(usage.input) * 100).compactPercentString : nil)
                    detail("Output", usage.output.compactTokenString)
                    detail("Reasoning output", usage.reasoningOutput.compactTokenString)
                    detail("Turn duration", activity?.turnDurationSeconds.map { String(format: "%.1fs", $0) })
                    detail("First token", activity?.firstTokenSeconds.map { String(format: "%.1fs", $0) })
                    detail("Provider", activity?.provider)
                    detail("CLI version", activity?.cliVersion)
                    detail("Approvals", activity?.approvalPolicy)
                    detail("Sandbox", activity?.sandboxMode)
                }.font(.system(size: 11))
            }
        }
    }

    private var sessionsPage: some View {
        VStack(spacing: 0) {
            AppSectionHeader(section: .sessions) {
                Picker("Sessions", selection: $showsSessionHistory) {
                    Text("Recent activity").tag(false)
                    Text("History").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 220)
            }
            if showsSessionHistory {
                SessionsView(snapshot: snapshot, health: health, compact: true) { id in
                    selectedSessionID = id
                    select(.analysis)
                }
            } else { activeSessionsPage }
        }
    }

    private var activeSessionsPage: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Recent chats").font(.system(size: AppTypeScale.sectionTitle, weight: .semibold))
                    Spacer()
                    Text("\(snapshot.sessionActivity.filter { $0.status() == "Working" }.count) working")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }.padding(.bottom, 4)
                if snapshot.sessionActivity.isEmpty {
                    ContentUnavailableView("No recent activity", systemImage: "rectangle.stack",
                        description: Text("Chats appear after the next local refresh."))
                }
                ForEach(snapshot.sessionActivity) { session in sessionButton(session) }
                Button("Browse chat history", systemImage: "clock.arrow.circlepath") { showsSessionHistory = true }
                    .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.secondary)
                    .padding(.top, 8)
            }.padding(18)
        }
    }

    private func sessionButton(_ session: CodexSessionActivity) -> some View {
        Button {
            selectedSessionID = session.id
            select(.analysis)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.displayTitle).fontWeight(.medium).lineLimit(2).help(session.displayTitle)
                    Text(ModelPricingCatalog.displayName(for: session.model))
                        .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 4) {
                    Text(session.usage.total.compactTokenString)
                        .font(.system(size: AppTypeScale.sectionTitle, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text(session.status()).font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .appGlassPanel(cornerRadius: 12)
        }.buttonStyle(.plain)
            .help("View activity for \(session.displayTitle)")
    }

    private var health: SnapshotHealth { SnapshotHealth(snapshot: snapshot, record: refreshRecord, isRefreshing: isRefreshing) }

    private var activityPalette: WidgetStylePalette {
        WidgetStylePalette(primary: .primary, secondary: .secondary,
            accent: settingsModel.settings.appTheme.accent,
            track: .primary.opacity(0.12), separator: .primary.opacity(0.08),
            highlight: settingsModel.settings.appTheme == .runway
                ? settingsModel.settings.appTheme.gradientLeading : settingsModel.settings.appTheme.accent)
    }

    @ViewBuilder private func detail(_ title: String, _ value: String?) -> some View {
        if let value { HStack { Text(title).foregroundStyle(.secondary); Spacer(); Text(value).lineLimit(1) } }
    }

    private func revealRail() {
        guard !railOpen else { return }
        withAnimation(motion) { railOpen = true; stretch = 0 }
    }

    private func dismissRail() {
        hoveredSection = nil
        withAnimation(motion) { railOpen = false; stretch = 0 }
    }

    private func select(_ item: AppSection) {
        guard item != section else { return }
        withAnimation(motion) { section = item }
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    }

    private func reload() {
        snapshot = SnapshotDisplay.load() ?? snapshot
        refreshRecord = BackgroundRefreshAgent.loadRecord()
    }
}

struct SessionUsageChart: View {
    var points: [CodexTokenPoint]
    var accent: Color
    var showsCaption = true
    @State private var selectedDate: Date?

    private var selectedPoint: CodexTokenPoint? {
        guard let selectedDate else { return nil }
        return points.min { abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate)) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if showsCaption {
                HStack {
                    Text("SESSION ACTIVITY").tracking(1.2)
                    Spacer()
                    if let point = selectedPoint {
                        Text(point.totalTokens.compactTokenString).monospacedDigit()
                    } else {
                        Text("\(points.count) recorded events")
                    }
                }
                .font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
            }
            if points.isEmpty {
                Text("Waiting for recorded token events")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Chart {
                    ForEach(points) { point in
                        AreaMark(x: .value("Time", point.date), y: .value("Tokens", point.totalTokens))
                            .interpolationMethod(.monotone)
                            .foregroundStyle(LinearGradient(colors: [accent.opacity(0.22), accent.opacity(0.01)], startPoint: .top, endPoint: .bottom))
                        LineMark(x: .value("Time", point.date), y: .value("Tokens", point.totalTokens))
                            .interpolationMethod(.monotone).foregroundStyle(accent).lineStyle(StrokeStyle(lineWidth: 1.8))
                        if points.count == 1 {
                            PointMark(x: .value("Time", point.date), y: .value("Tokens", point.totalTokens)).foregroundStyle(accent)
                        }
                    }
                    if let point = selectedPoint {
                        RuleMark(x: .value("Selected event", point.date))
                            .foregroundStyle(.secondary.opacity(0.4))
                    }
                }
                .chartXSelection(value: $selectedDate)
                .chartYAxis(.hidden)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                        AxisValueLabel(format: .dateTime.hour().minute()).font(.system(size: 10))
                    }
                }
                .accessibilityLabel("Recorded cumulative session tokens")
                .accessibilityValue(points.last.map { "\($0.totalTokens.formatted()) tokens across \(points.count) events" } ?? "No events")
            }
        }
    }
}

struct CompactLimitRow: View {
    var title: String
    var window: RateLimitWindow?
    var accent: Color

    var body: some View {
        VStack(spacing: 5) {
            HStack {
                Text(title).fontWeight(.medium)
                Spacer()
                if let window, window.isCurrent() {
                    Text("\(window.remainingPercent.compactPercentString) left").monospacedDigit()
                    Text("· \(window.resetText())").foregroundStyle(.secondary)
                } else {
                    Text("Awaiting data").foregroundStyle(.secondary)
                }
            }
            .font(.system(size: 11))
            ProgressView(value: window?.isCurrent() == true ? (window?.remainingPercent ?? 0) / 100 : 0)
                .tint(accent)
        }
        .accessibilityElement(children: .combine)
    }
}
