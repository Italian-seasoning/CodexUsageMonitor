import SwiftUI
import WidgetKit

struct WidgetsView: View {
    var snapshot: CodexUsageSnapshot
    @State private var family = CodexWidgetFamily.usagePulse
    @State private var style = CodexWidgetStyle.precisionInstrument
    @State private var size = WidgetPreviewSize.medium
    @State private var period = UsagePeriod.today
    @State private var theme = WidgetTheme.crimson
    @State private var arrangement = DashboardArrangement.balanced

    var body: some View {
        VStack(spacing: 0) {
            AppSectionHeader(section: .widgets) {
                Text("2.0 Collection")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppPalette.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .appGlassPanel(cornerRadius: 999)
            }

            HStack(spacing: 16) {
                ScrollView {
                    VStack(spacing: 14) {
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
                    .padding(18)
                }
                .frame(width: 340)

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
                        Text(family.title).font(.system(size: 13, weight: .semibold))
                        Text("\(style.title) · \(size.title)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(AppPalette.muted)
                    }
                    .padding(16)
                }
            }
            .padding(18)
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
