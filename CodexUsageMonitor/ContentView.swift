import AppKit
import SwiftUI
import WidgetKit

struct ContentView: View {
    @AppStorage("CodexUsageMonitor.appTheme") private var appTheme = AppTheme.crimson.rawValue
    @State private var snapshot = CodexUsageSnapshotStore.load() ?? .empty
    @State private var settingsBySize = CodexUsageSnapshotStore.loadAllSettings()
    @State private var previewSize = PreviewSize.medium
    @State private var isRefreshing = false
    @State private var refreshMessage = "Using the latest cached snapshot."
    @State private var hasDraftChanges = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(AppPalette.divider)
            HStack(spacing: 0) {
                inspector
                Divider().overlay(AppPalette.divider)
                previewStage
            }
            footer
        }
        .frame(minWidth: 980, idealWidth: 1080, minHeight: 660, idealHeight: 720)
        .background(AppPalette.background)
        .foregroundStyle(AppPalette.text)
        .tint(AppPalette.accent)
    }

    private var header: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "terminal.fill")
                    .font(.system(size: 14, weight: .bold))
                    .frame(width: 32, height: 32)
                    .foregroundStyle(.white)
                    .background(AppPalette.accent, in: RoundedRectangle(cornerRadius: 9, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Codex Usage Monitor")
                        .font(.system(size: 19, weight: .bold))
                    Text("Local Codex usage, model costs, and Headroom savings")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppPalette.muted)
                }

                Spacer()

                Picker("Widget size", selection: $previewSize) {
                    ForEach(PreviewSize.allCases) { size in
                        Text(size.title).tag(size)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 196)
            }

            HStack(spacing: 1) {
                OverviewMetric(label: "Session", value: snapshot.currentSession.total.compactTokenString)
                OverviewMetric(label: "Today", value: snapshot.today.total.compactTokenString)
                OverviewMetric(label: "Lifetime", value: snapshot.lifetime.total.compactTokenString)
                OverviewMetric(label: "Total API estimate", value: snapshot.estimatedCostUSD.compactCurrencyString, accent: true)
                OverviewMetric(label: "Headroom tokens saved", value: headroomSavedText)
            }
            .background(AppPalette.divider)
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(AppPalette.divider, lineWidth: 1)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
    }

    private var inspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Configure \(previewSize.title)")
                        .font(.system(size: 15, weight: .bold))
                    Text(previewSize.configurationHint)
                        .font(.system(size: 12))
                        .foregroundStyle(AppPalette.muted)
                }

                InspectorSection(title: "Appearance") {
                    LabeledContent("App theme") {
                        Picker("App theme", selection: $appTheme) {
                            ForEach(AppTheme.allCases) { theme in
                                Text(theme.label).tag(theme.rawValue)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 146)
                    }

                    LabeledContent("Widget theme") {
                        Picker("Widget theme", selection: themeBinding) {
                            ForEach(WidgetTheme.allCases) { theme in
                                Text(theme.label).tag(theme)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 146)
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
                        .frame(width: 164)
                    }

                    if previewSize != .small {
                        LabeledContent("Chart") {
                            Picker("Chart", selection: chartMetricBinding) {
                                ForEach(ChartMetric.allCases) { metric in
                                    Text(metric.label).tag(metric)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 164)
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
                                .frame(width: 164)
                            }
                        }
                    }
                }

                if let headroom = snapshot.headroom, headroom.isAvailable {
                    InspectorSection(title: "Headroom") {
                        HeadroomRow(label: "Saved today", value: "\(headroom.todayTokensSaved.compactTokenString) tokens")
                        HeadroomRow(label: "Total saved", value: "\(headroom.lifetimeTokensSaved.compactTokenString) tokens")
                        HeadroomRow(label: "Savings rate", value: headroom.savingsPercent.compactPercentString)
                        HeadroomRow(label: "Est. cost avoided", value: headroom.costSavedUSD.compactCurrencyString)
                        if let trackingStartedAt = headroom.trackingStartedAt {
                            Text("Tracked since \(trackingStartedAt.formatted(date: .abbreviated, time: .omitted))")
                                .font(.system(size: 11))
                                .foregroundStyle(AppPalette.muted)
                        }
                    }
                }

                InspectorSection(title: "Total API-equivalent estimate") {
                    PricingSummary(snapshot: snapshot)
                }
            }
            .padding(18)
        }
        .frame(width: 342)
        .background(AppPalette.inspector)
    }

    private var previewStage: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Widget preview")
                        .font(.system(size: 15, weight: .bold))
                    Text(hasDraftChanges ? "Unsaved changes" : "Saved settings")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(hasDraftChanges ? AppPalette.accent : AppPalette.muted)
                }
                Spacer()
                DataFreshnessBadge(snapshot: snapshot)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 16)

            ZStack {
                AppPalette.preview

                CodexUsageCardPreview(
                    snapshot: snapshot,
                    settings: activeSettings,
                    size: previewSize.cardSize
                )
                .frame(width: previewSize.frame.width, height: previewSize.frame.height)
                .shadow(color: .black.opacity(0.38), radius: 24, y: 12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(spacing: 12) {
                Label("\(snapshot.sessionCount ?? 0) sessions", systemImage: "rectangle.stack")
                Label("\(snapshot.turnCount ?? 0) requests", systemImage: "arrow.triangle.2.circlepath")
                if snapshot.headroom?.isAvailable == true {
                    Label("Headroom active", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(AppPalette.accent)
                }
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(AppPalette.muted)
            .padding(.horizontal, 22)
            .padding(.vertical, 13)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
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
                Label(isRefreshing ? "Refreshing" : "Refresh data", systemImage: "arrow.clockwise")
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .foregroundStyle(AppPalette.text.opacity(isRefreshing ? 0.48 : 0.92))
                    .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(AppPalette.divider, lineWidth: 1)
                    }
                    .cursorGlowBorder(radius: 9, accent: AppPalette.accent, isEnabled: !isRefreshing)
            }
            .buttonStyle(.plain)
            .disabled(isRefreshing)

            Button {
                saveSettings()
            } label: {
                Label("Apply \(previewSize.title)", systemImage: "checkmark")
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .foregroundStyle(.white.opacity(hasDraftChanges ? 1 : 0.48))
                    .background(
                        AppPalette.accent.opacity(hasDraftChanges ? 1 : 0.22),
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                    )
                    .cursorGlowBorder(radius: 9, accent: AppPalette.accent, isEnabled: hasDraftChanges)
            }
            .buttonStyle(.plain)
            .disabled(!hasDraftChanges)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(AppPalette.footer)
        .overlay(alignment: .top) { Divider().overlay(AppPalette.divider) }
    }

    private var activeSettings: CodexUsageWidgetSettings {
        settingsBySize.settings(for: previewSize.widgetSize)
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
        let previous = snapshot

        Task {
            let fresh = await Task.detached(priority: .userInitiated) {
                let headroom = HeadroomSavingsCollector().collect() ?? previous.cachedHeadroomActivity
                return CodexUsageReader().snapshot(headroomActivity: headroom)
            }.value
            snapshot = fresh
            if fresh.hasUsage { CodexUsageSnapshotStore.save(fresh) }
            WidgetCenter.shared.reloadTimelines(ofKind: "CodexUsageWidget")
            refreshMessage = "Data refreshed from local sources."
            isRefreshing = false
        }
    }

    private func saveSettings() {
        CodexUsageSnapshotStore.saveAllSettings(settingsBySize)
        WidgetCenter.shared.reloadTimelines(ofKind: "CodexUsageWidget")
        hasDraftChanges = false
        refreshMessage = "\(previewSize.title) settings applied to WidgetKit."
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
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(accent ? AppPalette.accent : AppPalette.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AppPalette.muted)
        }
        .padding(.horizontal, 13)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .background(AppPalette.panel)
    }
}

private struct InspectorSection<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppPalette.text)
            content
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppPalette.panel, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
        .background(AppPalette.panel, in: Capsule())
        .overlay { Capsule().stroke(AppPalette.divider, lineWidth: 1) }
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

private enum AppPalette {
    static let background = Color(red: 0.063, green: 0.063, blue: 0.063)
    static let inspector = Color(red: 0.072, green: 0.072, blue: 0.072)
    static let preview = Color(red: 0.025, green: 0.025, blue: 0.025)
    static let footer = Color(red: 0.055, green: 0.055, blue: 0.055)
    static let panel = Color(red: 0.092, green: 0.092, blue: 0.092)
    static let divider = Color.white.opacity(0.11)
    static let text = Color(red: 0.996, green: 0.996, blue: 0.996)
    static let muted = Color.white.opacity(0.60)
    static var accent: Color {
        AppTheme(rawValue: UserDefaults.standard.string(forKey: "CodexUsageMonitor.appTheme") ?? "crimson")?.accent
            ?? AppTheme.crimson.accent
    }
}

private enum AppTheme: String, CaseIterable, Identifiable {
    case crimson
    case graphite

    var id: String { rawValue }
    var label: String { self == .crimson ? "Crimson" : "Graphite" }
    var accent: Color {
        self == .crimson
            ? Color(red: 1, green: 0.388, blue: 0.388)
            : Color(red: 0.42, green: 0.67, blue: 1)
    }
}
