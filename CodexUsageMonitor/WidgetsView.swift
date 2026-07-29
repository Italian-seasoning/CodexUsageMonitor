import SwiftUI
import WidgetKit

struct WidgetsView: View {
    var snapshot: CodexUsageSnapshot
    @State private var family = CodexWidgetFamily.usagePulse
    @State private var preset = WidgetPresetMode.summer
    @State private var style = CodexWidgetStyle.precisionInstrument
    @State private var size = WidgetPreviewSize.medium
    @State private var period = UsagePeriod.today
    @State private var theme = WidgetTheme.crimson
    @State private var arrangement = DashboardArrangement.balanced
    @State private var savedPresets = SavedWidgetPresetStore.load()
    @State private var savedPresetID: UUID?
    @State private var presetName = ""

    var body: some View {
        VStack(spacing: 0) {
            AppSectionHeader(section: .widgets) {
                Text("2.0 Collection")
                    .font(.system(size: AppTypeScale.label, weight: .semibold))
                    .foregroundStyle(AppPalette.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .appGlassPanel(cornerRadius: 999)
            }

            GeometryReader { geometry in
                ScrollView {
                    Group {
                        if geometry.size.width >= 760 {
                            HStack(alignment: .top, spacing: 12) {
                                controls
                                    .frame(width: 330)
                                preview
                                    .frame(minHeight: 470)
                            }
                        } else {
                            VStack(spacing: 12) {
                                controls
                                preview
                                    .frame(minHeight: 420)
                            }
                        }
                    }
                    .padding(14)
                }
            }
        }
    }

    private var controls: some View {
        VStack(spacing: 10) {
            InspectorSection(title: "Widget family") {
                Picker("Family", selection: $family) {
                    ForEach(CodexWidgetFamily.allCases) { item in
                        Label(item.title, systemImage: item.symbol).tag(item)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity)

                Text(family.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            InspectorSection(title: "Presentation") {
                LabeledContent("Preset") {
                    Picker("Preset", selection: $preset) {
                        ForEach(WidgetPresetMode.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 165)
                }

                if preset == .saved {
                    LabeledContent("Saved mix") {
                        HStack(spacing: 6) {
                            Picker("Saved mix", selection: $savedPresetID) {
                                Text("Choose").tag(UUID?.none)
                                ForEach(savedPresets) { item in
                                    Text(item.name).tag(Optional(item.id))
                                }
                            }
                            .labelsHidden()
                            Button {
                                deleteSelectedPreset()
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .disabled(savedPresetID == nil)
                            .accessibilityLabel("Delete saved widget preset")
                        }
                        .frame(width: 165)
                    }
                } else if preset == .custom {
                    presentationPickers
                    Divider().overlay(AppPalette.divider)
                    LabeledContent("Save mix") {
                        HStack(spacing: 6) {
                            TextField("Name", text: $presetName)
                            Button("Save") { savePreset() }
                                .disabled(presetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                        .frame(width: 165)
                    }
                } else {
                    Text("\(style.title) · \(theme.label)")
                        .font(.system(size: AppTypeScale.caption, weight: .medium))
                        .foregroundStyle(AppPalette.muted)
                }

                Picker("Size", selection: $size) {
                    ForEach(WidgetPreviewSize.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.segmented)

                if family.supportsPeriod {
                    LabeledContent("Period") {
                        Picker("Period", selection: $period) {
                            ForEach(UsagePeriod.allCases) { Text($0.title).tag($0) }
                        }
                        .labelsHidden()
                        .frame(width: 165)
                    }
                }
                if family == .dashboard {
                    LabeledContent("Arrangement") {
                        Picker("Arrangement", selection: $arrangement) {
                            ForEach(DashboardArrangement.allCases) { Text($0.title).tag($0) }
                        }
                        .labelsHidden()
                        .frame(width: 165)
                    }
                }
            }

            InspectorSection(title: "Native configuration", subtitle: "Each desktop instance keeps its own choices") {
                Label("Add a widget, then Control-click it and choose Edit Widget.", systemImage: "slider.horizontal.3")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear { applyPreset() }
        .onChange(of: preset) { _, _ in applyPreset() }
        .onChange(of: savedPresetID) { _, _ in applyPreset() }
    }

    @ViewBuilder
    private var presentationPickers: some View {
        LabeledContent("Style") {
            Picker("Style", selection: $style) {
                ForEach(CodexWidgetStyle.allCases) { Text($0.title).tag($0) }
            }
            .labelsHidden()
            .frame(width: 165)
        }
        LabeledContent("Theme") {
            Picker("Theme", selection: $theme) {
                ForEach(WidgetTheme.allCases) { Text($0.label).tag($0) }
            }
            .labelsHidden()
            .frame(width: 165)
        }
    }

    private var preview: some View {
        ZStack {
            previewBackdrop
            CodexWidgetFamilyView(
                snapshot: snapshot,
                configuration: previewConfiguration,
                size: size.cardSize,
                monochrome: previewConfiguration.theme == .monochrome,
                paintsBackground: true
            )
            .frame(width: size.frame.width, height: size.frame.height)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(AppPalette.accent.opacity(style == .signalGrid ? 0.45 : 0.16))
            }
            .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .appGlassPanel(cornerRadius: 18)
        .overlay(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 2) {
                Text(family.title).font(.system(size: AppTypeScale.sectionTitle, weight: .semibold))
                Text("\(style.title) · \(size.title)")
                    .font(.system(size: AppTypeScale.caption, weight: .medium))
                    .foregroundStyle(AppPalette.muted)
            }
            .padding(16)
        }
    }

    private var previewBackdrop: some View {
        LinearGradient(
            colors: [AppPalette.sun.opacity(0.04), AppPalette.accent.opacity(0.09)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var previewConfiguration: WidgetDisplayConfiguration {
        WidgetDisplayConfiguration(
            family: family,
            style: style,
            theme: theme,
            period: period,
            dashboardArrangement: arrangement
        )
    }

    private func applyPreset() {
        let saved = savedPresets.first { $0.id == savedPresetID }
        let value = preset.presentation(savedPreset: saved, customStyle: style, customTheme: theme)
        style = value.style
        theme = value.theme
    }

    private func savePreset() {
        let name = presetName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let id = savedPresets.first { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }?.id ?? UUID()
        savedPresets.removeAll { $0.id == id }
        savedPresets.append(SavedWidgetPreset(id: id, name: name, style: style, theme: theme))
        savedPresets.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        guard SavedWidgetPresetStore.save(savedPresets) else { return }
        savedPresetID = id
        presetName = ""
        preset = .saved
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func deleteSelectedPreset() {
        guard let savedPresetID else { return }
        savedPresets.removeAll { $0.id == savedPresetID }
        guard SavedWidgetPresetStore.save(savedPresets) else { return }
        self.savedPresetID = nil
        preset = .custom
        WidgetCenter.shared.reloadAllTimelines()
    }
}

private extension CodexWidgetFamily {
    var title: String {
        switch self {
        case .limits: "Limits"
        case .usagePulse: "Usage Pulse"
        case .costLens: "Cost Lens"
        case .modelMix: "Model Mix"
        case .headroomImpact: "Headroom Impact"
        case .sessionLive: "Session Live"
        case .dashboard: "Modular Dashboard"
        }
    }

    var symbol: String {
        switch self {
        case .limits: "gauge.with.dots.needle.67percent"
        case .usagePulse: "waveform.path.ecg"
        case .costLens: "dollarsign.circle"
        case .modelMix: "square.stack.3d.up"
        case .headroomImpact: "arrow.down.right.and.arrow.up.left"
        case .sessionLive: "bolt.horizontal.circle"
        case .dashboard: "rectangle.3.group"
        }
    }

    var detail: String {
        switch self {
        case .limits: "Remaining 5-hour and weekly allowance."
        case .usagePulse: "Selected-period tokens and activity."
        case .costLens: "Recorded API-equivalent estimate."
        case .modelMix: "Top model and attributed share."
        case .headroomImpact: "Local compression savings."
        case .sessionLive: "Current session activity and freshness."
        case .dashboard: "A curated multi-metric workspace."
        }
    }

    var supportsPeriod: Bool {
        ![.limits, .sessionLive].contains(self)
    }
}

private extension CodexWidgetStyle {
    var title: String {
        switch self {
        case .precisionInstrument: "Precision Instrument"
        case .nativeGlass: "Native Glass"
        case .signalGrid: "Signal Grid"
        }
    }
}

private extension WidgetPresetMode {
    var title: String {
        switch self {
        case .summer: "Summer"
        case .darkGlass: "Dark Glass"
        case .frosted: "Frosted Coast"
        case .signal: "Signal"
        case .saved: "Saved Preset"
        case .custom: "Custom"
        }
    }
}

private extension DashboardArrangement {
    var title: String {
        switch self {
        case .balanced: "Balanced"
        case .limitsFirst: "Limits First"
        case .activityFirst: "Activity First"
        }
    }
}

private enum WidgetPreviewSize: String, CaseIterable, Identifiable {
    case small, medium, large
    var id: Self { self }
    var title: String { self == .small ? "Small" : self == .medium ? "Medium" : "Large" }
    var frame: CGSize {
        self == .small ? CGSize(width: 170, height: 170) :
            self == .medium ? CGSize(width: 340, height: 170) : CGSize(width: 340, height: 340)
    }
    var widgetSize: CodexUsageWidgetSize {
        self == .small ? .small : self == .medium ? .medium : .large
    }
    var cardSize: CodexUsageCardSize {
        self == .small ? .small : self == .medium ? .medium : .large
    }
}
