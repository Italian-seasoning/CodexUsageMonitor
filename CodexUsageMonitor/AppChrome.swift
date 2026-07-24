import AppKit
import SwiftUI

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
        case .analysis: "waveform.path.ecg"
        case .models: "square.stack.3d.up"
        case .widgets: "rectangle.3.group"
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
            Image(systemName: "terminal.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(AppPalette.accent, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .accessibilityLabel("Codex Usage")
                .padding(.bottom, 5)

            ForEach(AppSection.allCases) { section in
                Button {
                    selection = section
                } label: {
                    Image(systemName: section.symbol)
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 34, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(selection == section ? Color.white : AppPalette.muted)
                .background(
                    selection == section ? AppPalette.accent.opacity(0.9) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
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
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
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
                    .font(.system(size: 22, weight: .semibold))
                Text(section.subtitle)
                    .font(.system(size: 11, weight: .medium))
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
                    .font(.system(size: 13, weight: .semibold))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 10, weight: .medium))
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
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(AppPalette.muted)
                Spacer()
                Circle()
                    .fill(state.color)
                    .frame(width: 5, height: 5)
                    .accessibilityHidden(true)
            }
            Text(value)
                .font(.system(size: 21, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(accent ? AppPalette.accent : AppPalette.text)
                .lineLimit(1)
                .minimumScaleFactor(0.62)
            Text(detail)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(AppPalette.muted)
                .lineLimit(2)
            Text(state.title)
                .font(.system(size: 9, weight: .semibold))
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
