import SwiftUI
import WidgetKit

struct WidgetsView: View {
    var snapshot: CodexUsageSnapshot
    @State private var family = WidgetPreviewFamily.usagePulse
    @State private var style = WidgetPreviewStyle.precision
    @State private var size = WidgetPreviewSize.medium
    @State private var settingsBySize = CodexUsageSnapshotStore.loadAllSettings()

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
                                ForEach(WidgetPreviewFamily.allCases) { item in
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
                                    ForEach(WidgetPreviewStyle.allCases) { Text($0.title).tag($0) }
                                }
                                .labelsHidden()
                                .frame(width: 165)
                            }
                            Picker("Size", selection: $size) {
                                ForEach(WidgetPreviewSize.allCases) { Text($0.title).tag($0) }
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
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
                    if family == .usagePulse {
                        CodexUsageCardPreview(
                            snapshot: snapshot,
                            settings: settingsBySize.settings(for: size.widgetSize),
                            size: size.cardSize
                        )
                        .frame(width: size.frame.width, height: size.frame.height)
                    } else {
                        upcomingPreview
                            .frame(width: size.frame.width, height: size.frame.height)
                    }
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
            colors: [Color.black.opacity(0.03), AppPalette.accent.opacity(0.05)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var upcomingPreview: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(family.title.uppercased(), systemImage: family.symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(AppPalette.accent)
            Spacer()
            Text(family.sampleValue(snapshot))
                .font(.system(size: size == .small ? 25 : 32, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            Text(family.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(size == .large ? 3 : 1)
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(AppPalette.accent.opacity(style == .signal ? 0.45 : 0.16))
        }
        .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
    }
}

private enum WidgetPreviewFamily: String, CaseIterable, Identifiable {
    case limits, usagePulse, costLens, modelMix, headroomImpact, sessionLive, dashboard
    var id: Self { self }

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

    func sampleValue(_ snapshot: CodexUsageSnapshot) -> String {
        switch self {
        case .limits: "\(Int(snapshot.rateLimits?.weekly?.remainingPercent.rounded() ?? 0))% left"
        case .usagePulse: snapshot.today.total.compactTokenString
        case .costLens: snapshot.todayEstimatedCostUSD.compactCurrencyString
        case .modelMix: ModelPricingCatalog.displayName(for: snapshot.topModelToday)
        case .headroomImpact: (snapshot.headroom?.todayTokensSaved ?? 0).compactTokenString
        case .sessionLive: snapshot.currentSession.total.compactTokenString
        case .dashboard: snapshot.last7DaysUsage.total.compactTokenString
        }
    }
}

private enum WidgetPreviewStyle: String, CaseIterable, Identifiable {
    case precision, glass, signal
    var id: Self { self }
    var title: String {
        switch self {
        case .precision: "Precision Instrument"
        case .glass: "Native Glass"
        case .signal: "Signal Grid"
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
