import AppKit
import SwiftUI
import WidgetKit

struct ContentView: View {
    @EnvironmentObject private var settingsModel: CodexUsageSettingsModel
    @State private var snapshot = CodexUsageSnapshotStore.load() ?? .empty
    @State private var settingsBySize = CodexUsageSnapshotStore.loadAllSettings()
    @State private var previewSize = PreviewSize.medium
    @State private var selection: AppSection? = .overview
    @State private var isRefreshing = false
    @State private var refreshMessage = "Using the latest cached snapshot."
    @State private var hasDraftChanges = false

    var body: some View {
        ZStack {
            WindowBackdrop()
                .ignoresSafeArea()
            AppPalette.windowTint
                .ignoresSafeArea()

            HStack(spacing: 0) {
                sidebar
                    .frame(width: 204)
                Divider().overlay(AppPalette.divider)
                detail
            }
        }
        .frame(minWidth: 980, idealWidth: 1080, minHeight: 660, idealHeight: 720)
        .foregroundStyle(AppPalette.text)
        .tint(AppPalette.accent)
        .onReceive(NotificationCenter.default.publisher(for: .codexUsageSnapshotDidChange)) { _ in
            snapshot = CodexUsageSnapshotStore.load() ?? snapshot
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "terminal.fill")
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 30, height: 30)
                    .foregroundStyle(.white)
                    .background(AppPalette.accent, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 1) {
                    Text("Codex Usage")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Local monitor")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(AppPalette.muted)
                }
            }
            .padding(.horizontal, 12)

            List(AppSection.allCases, selection: $selection) { section in
                Label(section.title, systemImage: section.symbol)
                    .tag(section)
                    .font(.system(size: 13, weight: .medium))
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 5) {
                Label("\(snapshot.sessionCount ?? 0) sessions", systemImage: "rectangle.stack")
                Label("\(snapshot.turnCount ?? 0) requests", systemImage: "arrow.triangle.2.circlepath")
                if snapshot.headroom?.isAvailable == true {
                    Label("Headroom active", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(AppPalette.accent)
                }
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(AppPalette.muted)
            .padding(12)
        }
        .padding(.top, 18)
        .padding(.bottom, 8)
        .background(.thinMaterial)
    }

    private var detail: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(selectedSection.title)
                        .font(.system(size: 21, weight: .semibold))
                    Text(selectedSection.subtitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(AppPalette.muted)
                }
                Spacer()
                DataFreshnessBadge(snapshot: snapshot)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 14)

            Divider().overlay(AppPalette.divider)

            Group {
                switch selectedSection {
                case .overview: overview
                case .widget: widgetEditor
                case .settings: settings
                }
            }

            actionBar
        }
        .background(.clear)
    }

    private var overview: some View {
        ScrollView {
            VStack(spacing: 16) {
                HStack(spacing: 0) {
                    OverviewMetric(
                        label: "Weekly remaining",
                        value: snapshot.rateLimits?.weekly.map {
                            "\(Int($0.remainingPercent.rounded()))%"
                        } ?? "—",
                        accent: true
                    )
                    metricDivider
                    OverviewMetric(label: "Today", value: snapshot.today.total.compactTokenString)
                    metricDivider
                    OverviewMetric(
                        label: "Current model",
                        value: ModelPricingCatalog.displayName(for: snapshot.currentModel)
                    )
                    metricDivider
                    OverviewMetric(label: "API estimate today", value: snapshot.todayEstimatedCostUSD.compactCurrencyString)
                }
                .appGlassPanel(cornerRadius: 16)

                LimitSummaryStrip(snapshot: snapshot)

                HStack(alignment: .top, spacing: 16) {
                    InspectorSection(title: "Limit history", subtitle: "Remaining allowance over seven days") {
                        LimitHistoryChart(history: snapshot.rateLimits?.history ?? [])
                    }
                    .frame(maxWidth: .infinity)

                    InspectorSection(title: "Widget", subtitle: previewSize.configurationHint) {
                        Picker("Widget size", selection: $previewSize) {
                            ForEach(PreviewSize.allCases) { size in
                                Text(size.title).tag(size)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        compactPreview
                    }
                    .frame(width: 390)
                }

                HStack(alignment: .top, spacing: 16) {
                    InspectorSection(title: "Model cost estimate", subtitle: "API-equivalent pricing from local logs") {
                        PricingSummary(snapshot: snapshot)
                    }
                    .frame(maxWidth: .infinity)

                    if let headroom = snapshot.headroom, headroom.isAvailable {
                        InspectorSection(title: "Headroom", subtitle: "Local compression savings") {
                            HeadroomRow(label: "Saved today", value: "\(headroom.todayTokensSaved.compactTokenString) tokens")
                            HeadroomRow(label: "Total saved", value: "\(headroom.lifetimeTokensSaved.compactTokenString) tokens")
                            HeadroomRow(label: "Savings rate", value: headroom.savingsPercent.compactPercentString)
                            HeadroomRow(label: "Est. cost avoided", value: headroom.costSavedUSD.compactCurrencyString)
                        }
                        .frame(width: 300)
                    }
                }
            }
            .padding(20)
        }
    }

    private var widgetEditor: some View {
        HStack(spacing: 16) {
            ScrollView {
                VStack(spacing: 14) {
                    InspectorSection(title: "Widget size", subtitle: previewSize.configurationHint) {
                        Picker("Widget size", selection: $previewSize) {
                            ForEach(PreviewSize.allCases) { size in
                                Text(size.title).tag(size)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                    }

                    InspectorSection(title: "Appearance") {
                        LabeledContent("Widget theme") {
                            Picker("Widget theme", selection: themeBinding) {
                                ForEach(WidgetTheme.allCases) { theme in
                                    Text(theme.label).tag(theme)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 156)
                        }
                        if previewSize != .small {
                            Toggle("Show supporting stats", isOn: showStatsBinding)
                        }
                    }

                    InspectorSection(title: "Metrics") {
                        LabeledContent("Primary") {
                            Picker("Primary", selection: primaryMetricBinding) {
                                ForEach(PrimaryMetric.allCases) { metric in
                                    Text(metric.label).tag(metric)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 170)
                        }
                        if previewSize != .small {
                            LabeledContent("Chart") {
                                Picker("Chart", selection: chartMetricBinding) {
                                    ForEach(ChartMetric.allCases) { metric in
                                        Text(metric.label).tag(metric)
                                    }
                                }
                                .labelsHidden()
                                .frame(width: 170)
                            }
                        }
                        if activeSettings.showsStats && previewSize.statSlotCount > 0 {
                            Divider().overlay(AppPalette.divider)
                            ForEach(0..<previewSize.statSlotCount, id: \.self) { index in
                                LabeledContent(previewSize.statSlotLabel(index)) {
                                    Picker("Stat \(index + 1)", selection: statSlotBinding(index)) {
                                        ForEach(StatMetric.selectableCases) { metric in
                                            Text(metric.label).tag(metric)
                                        }
                                    }
                                    .labelsHidden()
                                    .frame(width: 170)
                                }
                            }
                        }
                    }
                }
                .padding(18)
            }
            .frame(width: 350)

            ZStack {
                Color.black.opacity(0.06)

                CodexUsageCardPreview(
                    snapshot: snapshot,
                    settings: activeSettings,
                    size: previewSize.cardSize
                )
                .frame(width: previewSize.frame.width, height: previewSize.frame.height)
                .shadow(color: .black.opacity(0.28), radius: 12, y: 6)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Live preview")
                        .font(.system(size: 13, weight: .semibold))
                    Text(hasDraftChanges ? "Unsaved changes" : "Saved settings")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(hasDraftChanges ? AppPalette.accent : AppPalette.muted)
                }
                .padding(16)
            }
            .appGlassPanel(cornerRadius: 18)
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var settings: some View {
        ScrollView {
            VStack(spacing: 16) {
                InspectorSection(title: "Appearance", subtitle: "Keep the app accent separate from the widget theme") {
                    LabeledContent("App theme") {
                        Picker("App theme", selection: $settingsModel.settings.appTheme) {
                            ForEach(AppTheme.allCases) { theme in
                                Text(theme.label).tag(theme)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 160)
                    }
                }

                InspectorSection(title: "Application behavior", subtitle: "Menu bar, Dock, refresh, and notifications") {
                    LimitPreferencesView()
                }

                InspectorSection(title: "Onboarding") {
                    Button("Run Setup") {
                        NotificationCenter.default.post(name: .showCodexUsageTour, object: nil)
                    }
                }
            }
            .frame(maxWidth: 680)
            .padding(20)
            .frame(maxWidth: .infinity)
        }
    }

    private var actionBar: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(isRefreshing ? AppPalette.accent : AppPalette.muted)
                .frame(width: 6, height: 6)
            Text(refreshMessage)
                .font(.system(size: 11))
                .foregroundStyle(AppPalette.muted)
                .lineLimit(1)

            Spacer()

            Button {
                refresh()
            } label: {
                Label(isRefreshing ? "Refreshing widgets" : "Refresh widgets", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .cursorGlowBorder(radius: 18, accent: AppPalette.accent, isEnabled: !isRefreshing)
            .disabled(isRefreshing)

            if selectedSection == .widget {
                Button {
                    saveSettings()
                } label: {
                    Label("Apply \(previewSize.title)", systemImage: "checkmark")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .cursorGlowBorder(radius: 18, accent: AppPalette.accent, isEnabled: hasDraftChanges)
                .disabled(!hasDraftChanges)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(.thinMaterial)
        .overlay(alignment: .top) { Divider().overlay(AppPalette.divider) }
    }

    private var compactPreview: some View {
        ZStack {
            Color.black.opacity(0.06)
            CodexUsageCardPreview(
                snapshot: snapshot,
                settings: activeSettings,
                size: previewSize.cardSize
            )
            .frame(
                width: previewSize == .small ? 120 : 240,
                height: previewSize == .large ? 240 : 120
            )
        }
        .frame(height: previewSize == .large ? 260 : 142)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var metricDivider: some View {
        Divider()
            .overlay(AppPalette.divider)
            .padding(.vertical, 12)
    }

    private var activeSettings: CodexUsageWidgetSettings {
        settingsBySize.settings(for: previewSize.widgetSize)
    }

    private var selectedSection: AppSection {
        selection ?? .overview
    }

    private var headroomSavedText: String {
        guard let headroom = snapshot.headroom, headroom.isAvailable else { return "—" }
        return headroom.lifetimeTokensSaved.compactTokenString
    }

    private var showStatsBinding: Binding<Bool> {
        Binding { activeSettings.showsStats } set: { value in
            updateActiveSettings { $0.showsStats = value }
        }
    }

    private var themeBinding: Binding<WidgetTheme> {
        Binding { activeSettings.theme } set: { value in
            updateActiveSettings { $0.theme = value }
        }
    }

    private var primaryMetricBinding: Binding<PrimaryMetric> {
        Binding { activeSettings.primaryMetric } set: { value in
            updateActiveSettings { $0.primaryMetric = value }
        }
    }

    private var chartMetricBinding: Binding<ChartMetric> {
        Binding { activeSettings.chartMetric } set: { value in
            updateActiveSettings { $0.chartMetric = value }
        }
    }

    private func statSlotBinding(_ index: Int) -> Binding<StatMetric> {
        Binding {
            activeSettings.normalizedStatSlots[index]
        } set: { value in
            updateActiveSettings {
                var slots = $0.normalizedStatSlots
                if let existing = slots.firstIndex(of: value), existing != index {
                    slots[existing] = slots[index]
                }
                slots[index] = value
                $0.statSlots = slots
            }
        }
    }

    private func updateActiveSettings(_ change: (inout CodexUsageWidgetSettings) -> Void) {
        var settings = activeSettings
        change(&settings)
        settings.chartDayCount = previewSize == .large ? 14 : 7
        settingsBySize.set(settings, for: previewSize.widgetSize)
        hasDraftChanges = true
    }

    private func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        refreshMessage = "Reading Codex logs and Headroom savings…"
        Task {
            let result = await RefreshCoordinator.shared.refresh(trigger: .manual, force: true)
            guard let fresh = result.snapshot, fresh.hasUsage else {
                refreshMessage = result.message
                isRefreshing = false
                return
            }

            let settingsSaved = CodexUsageSnapshotStore.saveAllSettings(settingsBySize)
            guard settingsSaved else {
                refreshMessage = "Could not hand the refreshed data to WidgetKit."
                isRefreshing = false
                return
            }

            snapshot = fresh
            hasDraftChanges = false
            refreshMessage = result.message
            isRefreshing = false
        }
    }

    private func saveSettings() {
        CodexUsageSnapshotStore.saveAllSettings(settingsBySize)
        WidgetCenter.shared.reloadAllTimelines()
        hasDraftChanges = false
        refreshMessage = "\(previewSize.title) settings applied to WidgetKit."
    }
}

private enum AppSection: String, CaseIterable, Identifiable {
    case overview
    case widget
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .widget: "Widget"
        case .settings: "Settings"
        }
    }

    var subtitle: String {
        switch self {
        case .overview: "Usage, limits, models, and savings"
        case .widget: "Configure the desktop widget"
        case .settings: "Appearance and background behavior"
        }
    }

    var symbol: String {
        switch self {
        case .overview: "chart.xyaxis.line"
        case .widget: "rectangle.3.group"
        case .settings: "gearshape"
        }
    }
}

private enum PreviewSize: String, CaseIterable, Identifiable {
    case small
    case medium
    case large

    var id: String { rawValue }

    var title: String {
        switch self {
        case .small: "1×1"
        case .medium: "1×2"
        case .large: "2×2"
        }
    }

    var configurationHint: String {
        switch self {
        case .small: "One value, plus the active model and estimated API cost."
        case .medium: "Seven daily bars, each scaled to the visible peak."
        case .large: "Fourteen daily bars with a model-aware cost summary."
        }
    }

    var frame: CGSize {
        switch self {
        case .small: CGSize(width: 170, height: 170)
        case .medium: CGSize(width: 340, height: 170)
        case .large: CGSize(width: 340, height: 340)
        }
    }

    var widgetSize: CodexUsageWidgetSize {
        switch self {
        case .small: .small
        case .medium: .medium
        case .large: .large
        }
    }

    var cardSize: CodexUsageCardSize {
        switch self {
        case .small: .small
        case .medium: .medium
        case .large: .large
        }
    }

    var statSlotCount: Int {
        switch self {
        case .small: 0
        case .medium: 3
        case .large: 4
        }
    }

    func statSlotLabel(_ index: Int) -> String {
        switch self {
        case .small: "Stat"
        case .medium, .large: "Stat \(index + 1)"
        }
    }
}

private struct OverviewMetric: View {
    var label: String
    var value: String
    var accent = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.system(size: 21, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(accent ? AppPalette.accent : AppPalette.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AppPalette.muted)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
    }
}

private struct InspectorSection<Content: View>: View {
    var title: String
    var subtitle: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppPalette.text)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(AppPalette.muted)
                }
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appGlassPanel(cornerRadius: 16)
    }
}

private struct HeadroomRow: View {
    var label: String
    var value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(AppPalette.muted)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
                .monospacedDigit()
        }
        .font(.system(size: 11))
    }
}

private struct PricingSummary: View {
    var snapshot: CodexUsageSnapshot

    private var models: [ModelUsage] {
        Array((snapshot.modelUsage ?? []).prefix(5))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(snapshot.estimatedCostUSD.compactCurrencyString)
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("Estimated from local logs")
                        .font(.system(size: 11))
                        .foregroundStyle(AppPalette.muted)
                }
                Spacer()
                Text(ModelPricingCatalog.displayName(for: snapshot.currentModel))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppPalette.accent)
                    .lineLimit(1)
            }

            if !models.isEmpty {
                Divider().overlay(AppPalette.divider)
                ForEach(models) { model in
                    HStack(spacing: 8) {
                        Text(ModelPricingCatalog.displayName(for: model.model))
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text(model.usage.total.compactTokenString)
                            .foregroundStyle(AppPalette.muted)
                            .monospacedDigit()
                        Text(ModelPricingCatalog.pricing(for: model.model) == nil ? "Unpriced" : model.estimatedCostUSD.compactCurrencyString)
                            .fontWeight(.semibold)
                            .monospacedDigit()
                    }
                    .font(.system(size: 11))
                }
            }

            if let unpriced = snapshot.unpricedTokens, unpriced > 0 {
                Text("\(unpriced.compactTokenString) tokens are excluded because no matching public rate is available.")
                    .font(.system(size: 11))
                    .foregroundStyle(AppPalette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("Estimate uses recorded model, uncached input, cached input, and output. It is not ChatGPT subscription spending.")
                .font(.system(size: 11))
                .foregroundStyle(AppPalette.muted)
                .fixedSize(horizontal: false, vertical: true)

            if let url = URL(string: ModelPricingCatalog.sourceURL) {
                Link("OpenAI standard API pricing", destination: url)
                    .font(.system(size: 11, weight: .semibold))
            }
        }
    }
}

private struct DataFreshnessBadge: View {
    var snapshot: CodexUsageSnapshot

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isFresh ? AppPalette.accent : AppPalette.muted)
                .frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppPalette.muted)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .appGlassPanel(cornerRadius: 999)
    }

    private var isFresh: Bool {
        guard let generatedAt = snapshot.generatedAt else { return false }
        return Date().timeIntervalSince(generatedAt) < 5 * 60
    }

    private var label: String {
        guard let generatedAt = snapshot.generatedAt else { return "No snapshot" }
        return "Updated \(generatedAt.formatted(date: .omitted, time: .shortened))"
    }
}

@MainActor
private enum AppPalette {
    static let windowTint = Color.black.opacity(0.12)
    static let divider = Color.white.opacity(0.11)
    static let text = Color(red: 0.996, green: 0.996, blue: 0.996)
    static let muted = Color.white.opacity(0.68)
    static var accent: Color {
        CodexUsageMonitorApp.sharedSettingsModel.settings.appTheme.accent
    }
}

extension AppTheme {
    var label: String { self == .crimson ? "Crimson" : "Graphite" }
    var accent: Color {
        self == .crimson
            ? Color(red: 1, green: 0.388, blue: 0.388)
            : Color(red: 0.42, green: 0.67, blue: 1)
    }
}

private struct WindowBackdrop: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.isEmphasized = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

extension View {
    @ViewBuilder
    func appGlassPanel(cornerRadius: CGFloat) -> some View {
        if #available(macOS 26.0, *) {
            glassEffect(
                .regular.tint(Color.black.opacity(0.18)),
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
        } else {
            background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                }
        }
    }
}
