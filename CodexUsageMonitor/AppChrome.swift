import AppKit
import SwiftUI

enum AppTypeScale {
    static let caption: CGFloat = 11
    static let label: CGFloat = 12
    static let body: CGFloat = 13
    static let sectionTitle: CGFloat = 14
    static let pageTitle: CGFloat = 22
    static let value: CGFloat = 22
}

enum AppSection: String, CaseIterable, Identifiable {
    case analysis
    case models
    case widgets
    case settings

    var id: Self { self }

    var title: String {
        switch self {
        case .analysis: "Analysis"
        case .models: "Models"
        case .widgets: "Widgets"
        case .settings: "Settings"
        }
    }

    var subtitle: String {
        switch self {
        case .analysis: "Usage, limits, cost, and local savings"
        case .models: "Period-aware model mix and API estimates"
        case .widgets: "Browse and configure the WidgetKit collection"
        case .settings: "Appearance, refresh, notifications, and updates"
        }
    }

    var symbol: String {
        switch self {
        case .analysis: "chart.xyaxis.line"
        case .models: "water.waves"
        case .widgets: "square.grid.2x2.fill"
        case .settings: "gearshape"
        }
    }
}

struct AnalysisSelection: Equatable {
    var period: UsagePeriod = .today
    var measure: UsageMeasure = .tokens
}

struct AppRail: View {
    @Binding var selection: AppSection
    @Binding var presentsDataHealth: Bool
    var health: SnapshotHealth

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "sun.horizon.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(
                    LinearGradient(
                        colors: [AppPalette.sun, AppPalette.accent],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                )
                .accessibilityLabel("Codex Usage")
                .padding(.bottom, 5)

            ForEach(AppSection.allCases) { section in
                Button {
                    selection = section
                } label: {
                    Image(systemName: section.symbol)
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 34, height: 30)
                        .background(
                            selection == section ? AppPalette.accent.opacity(0.9) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(selection == section ? Color.white : AppPalette.muted)
                .frame(width: 34, height: 30)
                .help(section.title)
                .accessibilityLabel(section.title)
                .accessibilityAddTraits(selection == section ? .isSelected : [])
            }

            Spacer(minLength: 8)

            Button {
                presentsDataHealth.toggle()
            } label: {
                Image(systemName: health.symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(health.color)
                    .frame(width: 34, height: 30)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(width: 34, height: 30)
            .help("Data health: \(health.title)")
            .accessibilityLabel("Data health, \(health.title)")
        }
        .padding(.vertical, 13)
        .frame(width: 52)
        .background(.thinMaterial)
        .overlay(alignment: .trailing) { Divider().overlay(AppPalette.divider) }
    }
}

struct AppSectionHeader<Trailing: View>: View {
    var section: AppSection
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(section.title)
                    .font(.system(size: AppTypeScale.pageTitle, weight: .semibold))
                Text(section.subtitle)
                    .font(.system(size: AppTypeScale.label, weight: .medium))
                    .foregroundStyle(AppPalette.muted)
            }
            Spacer(minLength: 12)
            trailing
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 14)
        .overlay(alignment: .bottom) { Divider().overlay(AppPalette.divider) }
    }
}

struct InspectorSection<Content: View>: View {
    var title: String
    var subtitle: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: AppTypeScale.sectionTitle, weight: .semibold))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: AppTypeScale.caption, weight: .medium))
                        .foregroundStyle(AppPalette.muted)
                }
            }
            content
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appGlassPanel(cornerRadius: 16)
    }
}

struct MetricModule: View {
    var eyebrow: String
    var value: String
    var detail: String
    var symbol: String
    var state: SnapshotHealth
    var accent = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Label(eyebrow, systemImage: symbol)
                    .font(.system(size: AppTypeScale.caption, weight: .semibold))
                    .foregroundStyle(AppPalette.muted)
                Spacer()
                Circle()
                    .fill(state.color)
                    .frame(width: 5, height: 5)
                    .accessibilityHidden(true)
            }
            Text(value)
                .font(.system(size: AppTypeScale.value, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(accent ? AppPalette.accent : AppPalette.text)
                .lineLimit(1)
                .minimumScaleFactor(0.62)
            Text(detail)
                .font(.system(size: AppTypeScale.caption, weight: .medium))
                .foregroundStyle(AppPalette.muted)
                .lineLimit(2)
            Text(state.title)
                .font(.system(size: AppTypeScale.caption, weight: .semibold))
                .foregroundStyle(state.color)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
        .appGlassPanel(cornerRadius: 15)
        .accessibilityElement(children: .combine)
    }
}

@MainActor
enum AppPalette {
    static let windowTint = Color(red: 0.015, green: 0.12, blue: 0.15).opacity(0.72)
    static let divider = Color.white.opacity(0.11)
    static let text = Color(red: 0.996, green: 0.996, blue: 0.996)
    static let muted = Color(red: 0.79, green: 0.9, blue: 0.9).opacity(0.76)
    static let sun = Color(red: 1, green: 0.68, blue: 0.27)
    static var accent: Color {
        CodexUsageMonitorApp.sharedSettingsModel.settings.appTheme.accent
    }
}

extension AppTheme {
    var label: String { self == .crimson ? "Summer" : "Graphite" }
    var accent: Color {
        self == .crimson
            ? Color(red: 0.12, green: 0.78, blue: 0.76)
            : Color(red: 0.42, green: 0.67, blue: 1)
    }
}

struct WindowBackdrop: NSViewRepresentable {
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
                .regular.tint(Color(red: 0.02, green: 0.21, blue: 0.24).opacity(0.26)),
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
