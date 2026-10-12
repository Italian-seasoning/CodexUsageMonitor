import AppKit
import SwiftUI

enum AppTypeScale {
    static let caption: CGFloat = 11
    static let label: CGFloat = 12
    static let body: CGFloat = 13
    static let sectionTitle: CGFloat = 14
    static let pageTitle: CGFloat = 18
    static let value: CGFloat = 22
}

enum AppSection: String, CaseIterable, Identifiable {
    case analysis
    case history
    case sessions
    case models
    case widgets
    case settings

    var id: Self { self }

    var title: String {
        switch self {
        case .analysis: "Activity"
        case .history: "Trends"
        case .sessions: "Sessions"
        case .models: "Models"
        case .widgets: "Widgets"
        case .settings: "Settings"
        }
    }

    var subtitle: String {
        switch self {
        case .analysis: "Your current chat and remaining limits"
        case .history: "Usage over time, API estimates, and savings"
        case .sessions: "Find a chat and inspect its recorded usage"
        case .models: "Compare model usage and API estimates"
        case .widgets: "Desktop widgets"
        case .settings: "Appearance and monitoring"
        }
    }

    var symbol: String {
        switch self {
        case .analysis: "waveform.path"
        case .history: "chart.xyaxis.line"
        case .sessions: "rectangle.stack"
        case .models: "cpu"
        case .widgets: "square.grid.2x2.fill"
        case .settings: "gearshape"
        }
    }
}

struct AnalysisSelection: Equatable {
    var period: UsagePeriod = .today
    var measure: UsageMeasure = .tokens
    var usesCustomDates = false
    var startDate: Date = Calendar.current.date(byAdding: .day, value: -6, to: .now) ?? .now
    var endDate: Date = .now
}

struct AppRail: View {
    @Binding var selection: AppSection
    @Binding var presentsDataHealth: Bool
    var health: SnapshotHealth

    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .scaledToFit()
                .frame(width: 32, height: 32)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(AppPalette.panelBorder, lineWidth: 1)
                }
                .accessibilityLabel("Codex Usage")
                .padding(.bottom, 5)

            ForEach(AppSection.allCases.filter { $0 != .analysis }) { section in
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
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 16) {
                labels.fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 12)
                trailing
            }
            VStack(alignment: .leading, spacing: 10) {
                labels
                trailing
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
        .controlSize(.small)
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) { Divider().overlay(AppPalette.divider) }
    }

    private var labels: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(section.title).font(.system(size: AppTypeScale.pageTitle, weight: .semibold))
            Text(section.subtitle)
                .font(.system(size: AppTypeScale.caption))
                .foregroundStyle(AppPalette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct InspectorSection<Content: View>: View {
    var title: String
    var subtitle: String? = nil
    var subtitleInline = false
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            if subtitleInline {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(title)
                            .font(.system(size: AppTypeScale.sectionTitle, weight: .semibold))
                        if let subtitle {
                            Text(subtitle)
                                .font(.system(size: AppTypeScale.caption))
                                .foregroundStyle(AppPalette.muted)
                        }
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    labels
                }
            } else {
                labels
            }
            content
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appGlassPanel(cornerRadius: 16)
    }

    private var labels: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: AppTypeScale.sectionTitle, weight: .semibold))
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: AppTypeScale.caption))
                    .foregroundStyle(AppPalette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Keep the overview inside one viewport and provide direct access to its details.
struct MagneticScrollView<Overview: View, Details: View>: View {
    @ViewBuilder var overview: (CGFloat) -> Overview
    @ViewBuilder var details: Details
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            let height = max(0, geometry.size.height - 28)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(spacing: 8) {
                            overview(max(0, height - 32))
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                            Spacer(minLength: 0)
                            Button {
                                withAnimation(reduceMotion ? nil : .snappy(duration: 0.3)) {
                                    proxy.scrollTo("details", anchor: .top)
                                }
                            } label: {
                                Label("Details", systemImage: "chevron.down")
                                    .font(.system(size: AppTypeScale.caption, weight: .medium))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 4)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Show more details")
                            .keyboardShortcut(.downArrow, modifiers: .option)
                            .help("Show more details · ⌥↓")
                        }
                        .frame(height: height, alignment: .top)
                        .id("overview")
                        details
                            .frame(minHeight: height, alignment: .top)
                            .id("details")
                    }
                    .padding(14)
                }
                .scrollIndicators(.hidden)
            }
        }
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
        VStack(alignment: .leading, spacing: 5) {
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
            if state.kind != .freshComplete {
                Text(state.title)
                    .font(.system(size: AppTypeScale.caption, weight: .semibold))
                    .foregroundStyle(state.color)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 108, maxHeight: 108, alignment: .topLeading)
        .appGlassPanel(cornerRadius: 15)
        .accessibilityElement(children: .combine)
        .accessibilityHint(state.title)
    }
}

@MainActor
enum AppPalette {
    static var windowTint: Color {
        CodexUsageMonitorApp.sharedSettingsModel.settings.appTheme.windowTint
    }
    static var divider: Color {
        CodexUsageMonitorApp.sharedSettingsModel.settings.appTheme.panelBorder
    }
    static let text = Color.primary
    static var muted: Color {
        Color.primary.opacity(0.82)
    }
    static var gradientLeading: Color {
        CodexUsageMonitorApp.sharedSettingsModel.settings.appTheme.gradientLeading
    }
    static var panelTint: Color {
        CodexUsageMonitorApp.sharedSettingsModel.settings.appTheme.panelTint
    }
    static var panelBorder: Color {
        CodexUsageMonitorApp.sharedSettingsModel.settings.appTheme.panelBorder
    }
    static var accent: Color {
        CodexUsageMonitorApp.sharedSettingsModel.settings.appTheme.accent
    }

    static var chartMuted: Color { accent.opacity(0.72) }
    static var chartTrack: Color { text.opacity(0.08) }
    static var chartGrid: Color { text.opacity(0.09) }
    static let positive = Color(red: 0.28, green: 0.84, blue: 0.52)
    static let warning = Color(red: 1, green: 0.71, blue: 0.24)
    static let critical = Color(red: 1, green: 0.31, blue: 0.36)
}

extension AppTheme {
    var label: String {
        switch self {
        case .crimson: "Summer"
        case .classicRed: "Classic Red"
        case .graphite: "Graphite"
        case .rain: "Vancouver Rain"
        case .autumn: "Autumn"
        }
    }

    var accent: Color {
        switch self {
        case .crimson: Color(red: 0.12, green: 0.78, blue: 0.76)
        case .classicRed: Color(red: 0.98, green: 0.16, blue: 0.21)
        case .graphite: Color(red: 0.42, green: 0.67, blue: 1)
        case .rain: Color(red: 0.48, green: 0.76, blue: 0.91)
        case .autumn: Color(red: 0.96, green: 0.64, blue: 0.35)
        }
    }

    var windowTint: Color {
        switch self {
        case .crimson: Color(red: 0.015, green: 0.12, blue: 0.15).opacity(0.72)
        case .classicRed: Color(red: 0.035, green: 0.033, blue: 0.038).opacity(0.82)
        case .graphite: Color(red: 0.035, green: 0.045, blue: 0.07).opacity(0.76)
        case .rain: Color(red: 0.035, green: 0.09, blue: 0.13).opacity(0.38)
        case .autumn: Color(red: 0.13, green: 0.075, blue: 0.055).opacity(0.38)
        }
    }

    var panelTint: Color {
        switch self {
        case .crimson: Color(red: 0.02, green: 0.21, blue: 0.24).opacity(0.26)
        case .classicRed: Color(red: 0.11, green: 0.105, blue: 0.115).opacity(0.34)
        case .graphite: Color(red: 0.075, green: 0.095, blue: 0.14).opacity(0.3)
        case .rain, .autumn: accent.opacity(0.055)
        }
    }

    var panelBorder: Color {
        switch self {
        case .crimson: accent.opacity(0.2)
        case .classicRed: Color.white.opacity(0.1)
        case .graphite: accent.opacity(0.16)
        case .rain, .autumn: Color.white.opacity(0.15)
        }
    }

    var muted: Color {
        .secondary
    }

    var gradientLeading: Color {
        switch self {
        case .crimson: Color(red: 1, green: 0.68, blue: 0.27)
        case .classicRed: Color(red: 1, green: 0.36, blue: 0.28)
        case .graphite: Color(red: 0.3, green: 0.42, blue: 0.64)
        case .rain: Color(red: 0.26, green: 0.43, blue: 0.51)
        case .autumn: Color(red: 0.63, green: 0.30, blue: 0.15)
        }
    }
}

/// Static reflected light gives the material depth without decorative motion.
struct AmbientBackdrop: View {
    var theme: AppTheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                RadialGradient(
                    colors: [theme.accent.opacity(0.11), .clear],
                    center: .topLeading,
                    startRadius: 0,
                    endRadius: geometry.size.width * 0.9
                )
                RadialGradient(
                    colors: [theme.gradientLeading.opacity(0.055), .clear],
                    center: .bottomTrailing,
                    startRadius: 0,
                    endRadius: geometry.size.width * 0.7
                )
            }
        }
        .opacity(reduceTransparency ? 0 : 1)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct WindowBackdrop: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var light = false

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        view.isEmphasized = !light
        if light { view.appearance = NSAppearance(named: .aqua) }
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
    }
}

/// The clear left gutter belongs to the window, not a painted rectangular backdrop.
struct WorkspaceGlassShape: Shape {
    var pull: CGFloat
    var anchor: CGFloat
    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(pull, anchor) }
        set { pull = newValue.first; anchor = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        let body = rect.insetBy(dx: 12, dy: 12)
        let left: CGFloat = 76
        let right = body.maxX
        let top = body.minY
        let bottom = body.maxY
        let radius: CGFloat = 28
        let center = min(max(anchor, top + 85), bottom - 85)
        let bulge = max(0, min(pull, 1)) * 42
        var path = Path()
        path.move(to: CGPoint(x: left + radius, y: top))
        path.addLine(to: CGPoint(x: right - radius, y: top))
        path.addQuadCurve(to: CGPoint(x: right, y: top + radius), control: CGPoint(x: right, y: top))
        path.addLine(to: CGPoint(x: right, y: bottom - radius))
        path.addQuadCurve(to: CGPoint(x: right - radius, y: bottom), control: CGPoint(x: right, y: bottom))
        path.addLine(to: CGPoint(x: left + radius, y: bottom))
        path.addQuadCurve(to: CGPoint(x: left, y: bottom - radius), control: CGPoint(x: left, y: bottom))
        path.addLine(to: CGPoint(x: left, y: center + 64))
        path.addCurve(to: CGPoint(x: left - bulge, y: center),
                      control1: CGPoint(x: left, y: center + 24),
                      control2: CGPoint(x: left - bulge, y: center + 30))
        path.addCurve(to: CGPoint(x: left, y: center - 64),
                      control1: CGPoint(x: left - bulge, y: center - 30),
                      control2: CGPoint(x: left, y: center - 24))
        path.addLine(to: CGPoint(x: left, y: top + radius))
        path.addQuadCurve(to: CGPoint(x: left + radius, y: top), control: CGPoint(x: left, y: top))
        path.closeSubpath()
        return path
    }
}

/// Mask the native material directly. SwiftUI clipping flattens desktop blur.
struct WorkspaceBackdrop: NSViewRepresentable, Animatable {
    var pull: CGFloat
    var anchor: CGFloat
    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(pull, anchor) }
        set { pull = newValue.first; anchor = newValue.second }
    }

    func makeNSView(context: Context) -> WorkspaceEffectView {
        let view = WorkspaceEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.appearance = NSAppearance(named: .darkAqua)
        view.alphaValue = 1
        return view
    }

    func updateNSView(_ view: WorkspaceEffectView, context: Context) {
        view.shape = WorkspaceGlassShape(pull: pull, anchor: anchor)
        view.updateMask()
    }
}

final class WorkspaceEffectView: NSVisualEffectView {
    var shape = WorkspaceGlassShape(pull: 0, anchor: 250)
    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        updateMask()
    }

    func updateMask() {
        guard bounds.width > 0, bounds.height > 0 else { return }
        let path = shape.path(in: bounds).cgPath
        maskImage = NSImage(size: bounds.size, flipped: true) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.setFillColor(NSColor.white.cgColor)
            context.addPath(path)
            context.fillPath()
            return true
        }
    }
}

enum WorkspaceNavigationGeometry {
    static let width: CGFloat = 58
    static let rowHeight: CGFloat = 49
    static var height: CGFloat { CGFloat(AppSection.allCases.count) * rowHeight + 14 }

    static func section(at point: CGPoint, height windowHeight: CGFloat) -> AppSection? {
        let frame = CGRect(x: 41 - width / 2, y: (windowHeight - height) / 2, width: width, height: height)
        guard frame.contains(point) else { return nil }
        let row = Int(max(0, point.y - frame.minY - 7) / rowHeight)
        return AppSection.allCases[min(row, AppSection.allCases.count - 1)]
    }

    static func isEdge(_ point: CGPoint, height: CGFloat) -> Bool {
        CGRect(x: 63, y: 24, width: 29, height: height - 48).contains(point)
    }
}

struct GlassEdgeCapture: NSViewRepresentable {
    var railOpen: Bool
    var onHover: (CGPoint?) -> Void
    var onPull: (CGFloat, CGFloat) -> Void
    var onReveal: (CGFloat) -> Void
    var onDismiss: () -> Void

    func makeNSView(context: Context) -> GlassEdgeCaptureView {
        let view = GlassEdgeCaptureView()
        view.setAccessibilityRole(.button)
        view.setAccessibilityLabel("Show navigation")
        view.setAccessibilityHelp("Move the cursor outward from the left edge, or swipe outward with two fingers. No click needed · ⌘⌥N")
        return view
    }

    func updateNSView(_ view: GlassEdgeCaptureView, context: Context) {
        view.railOpen = railOpen
        view.setAccessibilityElement(!railOpen)
        view.onHover = onHover
        view.onPull = onPull
        view.onReveal = onReveal
        view.onDismiss = onDismiss
    }

    static func dismantleNSView(_ view: GlassEdgeCaptureView, coordinator: ()) {
        view.stopMonitoring()
    }
}

/// Pointer-only pull for a mouse; precise horizontal gestures for a trackpad.
/// No cursor warping, click capture, or device-identification heuristics.
final class GlassEdgeCaptureView: NSView {
    var railOpen = false {
        didSet { if oldValue && !railOpen { cancelPull() } }
    }
    var onHover: ((CGPoint?) -> Void)?
    var onPull: ((CGFloat, CGFloat) -> Void)?
    var onReveal: ((CGFloat) -> Void)?
    var onDismiss: (() -> Void)?
    var onSnapFeedback: () -> Void = {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }
    private var tracking: NSTrackingArea?
    private var eventMonitor: Any?
    private var cancellationObservers: [NSObjectProtocol] = []
    private var pointerOrigin: CGPoint?
    private var scrollOrigin: CGPoint?
    private var scrollDistance: CGFloat = 0
    private var snapped = false
    static let snapDistance: CGFloat = 32
    static let trackpadSnapDistance: CGFloat = 48
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) { track(event) }
    override func mouseMoved(with event: NSEvent) { track(event) }
    override func mouseExited(with event: NSEvent) {
        onHover?(nil)
        cancelPull()
    }

    func handle(_ event: NSEvent) -> NSEvent? {
        guard let window, event.window === window else { return event }
        if event.type == .keyDown {
            if event.keyCode == 53, railOpen || pointerOrigin != nil || scrollOrigin != nil {
                cancelPull()
                onDismiss?()
                return nil
            }
            return event
        }
        let point = convert(event.locationInWindow, from: nil)
        if event.type == .leftMouseDown {
            cancelPull()
            if railOpen, WorkspaceNavigationGeometry.section(at: point, height: bounds.height) == nil { onDismiss?() }
        }
        if event.type == .mouseMoved { track(event) }
        if event.type == .scrollWheel {
            // Normalize to physical finger travel, independent of natural-scroll preference.
            let delta = event.isDirectionInvertedFromDevice ? event.scrollingDeltaX : -event.scrollingDeltaX
            if handleScroll(at: point, outwardDelta: -delta, verticalDelta: event.scrollingDeltaY,
                            precise: event.hasPreciseScrollingDeltas, phase: event.phase,
                            momentum: event.momentumPhase != []) { return nil }
        }
        return event
    }

    func handleScroll(at point: CGPoint, outwardDelta: CGFloat, verticalDelta: CGFloat,
                      precise: Bool, phase: NSEvent.Phase, momentum: Bool) -> Bool {
        guard precise, !momentum else { return false }
        if phase.contains(.cancelled) || phase.contains(.ended) {
            let captured = scrollOrigin != nil
            cancelPull()
            return captured
        }
        if scrollOrigin == nil {
            guard !railOpen, WorkspaceNavigationGeometry.isEdge(point, height: bounds.height),
                  outwardDelta > 0, abs(outwardDelta) > abs(verticalDelta) else { return false }
            cancelPull()
            scrollOrigin = point
        }
        guard let origin = scrollOrigin else { return false }
        scrollDistance = max(0, scrollDistance + outwardDelta)
        if !snapped {
            onPull?(min(1, scrollDistance / Self.trackpadSnapDistance), origin.y)
            if scrollDistance >= Self.trackpadSnapDistance { snap(at: origin.y) }
        }
        return true
    }

    private func track(_ event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        onHover?(bounds.contains(point) ? point : nil)
        guard scrollOrigin == nil, !railOpen, !snapped else { return }
        guard bounds.contains(point), point.x <= 92,
              point.y >= 24, point.y <= bounds.height - 24 else { cancelPull(); return }
        if pointerOrigin == nil, WorkspaceNavigationGeometry.isEdge(point, height: bounds.height) {
            pointerOrigin = point
            onPull?(0, point.y)
        }
        guard let origin = pointerOrigin else { return }
        guard abs(point.y - origin.y) < 70, point.x <= origin.x + 8 else { cancelPull(); return }
        let distance = max(0, origin.x - point.x)
        onPull?(min(1, distance / Self.snapDistance), point.y)
        if distance >= Self.snapDistance { snap(at: point.y) }
    }

    private func snap(at y: CGFloat) {
        snapped = true
        onReveal?(y)
        onSnapFeedback()
    }

    private func cancelPull() {
        if !snapped, let origin = scrollOrigin ?? pointerOrigin { onPull?(0, origin.y) }
        pointerOrigin = nil
        scrollOrigin = nil
        scrollDistance = 0
        snapped = false
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stopMonitoring()
        if let window {
            window.acceptsMouseMovedEvents = true
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .keyDown, .leftMouseDown, .scrollWheel]) { [weak self] event in
                guard let self else { return event }
                return self.handle(event)
            }
            for (name, object) in [(NSApplication.didResignActiveNotification, NSApp as AnyObject), (NSWindow.willCloseNotification, window as AnyObject)] {
                cancellationObservers.append(NotificationCenter.default.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
                    self?.onHover?(nil)
                    self?.cancelPull()
                    self?.onDismiss?()
                })
            }
        }
    }

    func stopMonitoring() {
        cancelPull()
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        eventMonitor = nil
        for observer in cancellationObservers { NotificationCenter.default.removeObserver(observer) }
        cancellationObservers.removeAll()
    }

    deinit {
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        for observer in cancellationObservers { NotificationCenter.default.removeObserver(observer) }
    }

    override func accessibilityPerformPress() -> Bool {
        onReveal?(bounds.height / 2)
        onSnapFeedback()
        return true
    }
}

extension View {
    @ViewBuilder
    func workspaceGlass(shape: WorkspaceGlassShape, namespace: Namespace.ID, opaque: Bool) -> some View {
        if opaque {
            self
        } else if #available(macOS 26.0, *) {
            glassEffect(.clear, in: shape)
                .glassEffectID("workspace", in: namespace)
        } else {
            overlay { shape.stroke(Color.white.opacity(0.15), lineWidth: 0.7) }
        }
    }

    @ViewBuilder
    func navigationGlass(namespace: Namespace.ID, opaque: Bool) -> some View {
        if opaque {
            background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 22))
        } else if #available(macOS 26.0, *) {
            background {
                RoundedRectangle(cornerRadius: 22)
                    .fill(Color.clear)
                    .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 22))
                    .glassEffectID("navigation", in: namespace)
                    .glassEffectTransition(.identity)
            }
        } else {
            background {
                RoundedRectangle(cornerRadius: 22)
                    .fill(.regularMaterial)
            }
        }
    }

    @ViewBuilder
    func appGlassPanel(cornerRadius: CGFloat) -> some View {
        background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.07), lineWidth: 1)
            }
    }
}
