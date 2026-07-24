import SwiftUI

extension Notification.Name {
    static let showCodexUsageTour = Notification.Name("showCodexUsageTour")
}

struct CodexUsageRootView: View {
    @EnvironmentObject private var settingsModel: CodexUsageSettingsModel
    @AppStorage("CodexUsageMonitor.hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("CodexUsageMonitor.hasRequestedCodexAccess") private var hasRequestedCodexAccess = false
    @State private var showsWelcome = false
    @State private var showsSkipWarning = false
    @State private var tourStep: Int?
    @State private var isRequestingAccess = false
    private let currentVersion: String

    init() {
        let version = OnboardingStateStore.currentAppVersion
        currentVersion = version
        _showsWelcome = State(initialValue: OnboardingStateStore.shouldPresent(appVersion: version))
    }

    var body: some View {
        ZStack {
            if showsWelcome {
                OnboardingWelcomeView(
                    isRequestingAccess: isRequestingAccess,
                    needsCodexAccess: !hasRequestedCodexAccess,
                    backgroundRefreshEnabled: $settingsModel.settings.backgroundRefreshEnabled,
                    onSkip: { showsSkipWarning = true },
                    onStartTour: {
                        requestCodexAccess {
                            showsWelcome = false
                            tourStep = 0
                        }
                    }
                )
                .transition(.opacity)
            } else {
                ContentView()
                if let tourStep {
                    AppTourOverlay(
                        step: tourStep,
                        onBack: { self.tourStep = max(0, tourStep - 1) },
                        onNext: {
                            if tourStep == AppTourStep.allCases.count - 1 {
                                finishOnboarding()
                            } else {
                                self.tourStep = tourStep + 1
                            }
                        },
                        onSkip: { showsSkipWarning = true }
                    )
                    .transition(.opacity)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            if OnboardingStateStore.shouldPresent(appVersion: currentVersion) {
                showsWelcome = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showCodexUsageTour)) { _ in
            showsWelcome = false
            tourStep = 0
        }
        .alert("Skip onboarding?", isPresented: $showsSkipWarning) {
            Button("Continue Onboarding", role: .cancel) {}
            Button("Skip Anyway") { completeOnboarding(completed: false) }
        } message: {
            Text("Your existing settings will be kept. If Codex access or a new setup step is missing, usage and widgets may stay empty until you run onboarding from the Help menu.")
        }
    }

    private func finishOnboarding() {
        completeOnboarding(completed: true)
    }

    private func completeOnboarding(completed: Bool) {
        let hasEverCompletedOnboarding = hasCompletedOnboarding || completed
        hasCompletedOnboarding = hasEverCompletedOnboarding
        OnboardingStateStore.markPresented(
            appVersion: currentVersion,
            completed: hasEverCompletedOnboarding
        )
        if completed {
            let enabled = settingsModel.settings.backgroundRefreshEnabled
            Task.detached(priority: .utility) {
                _ = BackgroundRefreshAgent.setEnabled(enabled)
            }
        }
        withAnimation(.easeOut(duration: 0.2)) {
            showsWelcome = false
            tourStep = nil
        }
    }

    private func requestCodexAccess(then completion: @escaping () -> Void) {
        guard !isRequestingAccess else { return }
        guard !hasRequestedCodexAccess else {
            completion()
            return
        }

        isRequestingAccess = true
        Task {
            let snapshot = await Task.detached(priority: .userInitiated) {
                CodexUsageReader().snapshot()
            }.value
            if snapshot.hasUsage {
                CodexUsageSnapshotStore.save(snapshot)
            }
            hasRequestedCodexAccess = true
            isRequestingAccess = false
            completion()
        }
    }
}

private struct OnboardingWelcomeView: View {
    var isRequestingAccess: Bool
    var needsCodexAccess: Bool
    @Binding var backgroundRefreshEnabled: Bool
    var onSkip: () -> Void
    var onStartTour: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isAnimating = false

    var body: some View {
        ZStack {
            Color(red: 0.035, green: 0.035, blue: 0.035).ignoresSafeArea()

            Circle()
                .fill(Color(red: 1, green: 0.388, blue: 0.388).opacity(0.12))
                .frame(width: 540, height: 540)
                .blur(radius: 100)
                .offset(x: 260, y: -210)
                .scaleEffect(isAnimating ? 1.06 : 0.94)

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button("Skip tour") { onSkip() }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.white.opacity(0.68))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .contentShape(Rectangle())
                }

                Spacer()

                HStack(spacing: 64) {
                    AnimatedUsageMark(isAnimating: isAnimating && !reduceMotion)
                        .frame(width: 300, height: 300)

                    VStack(alignment: .leading, spacing: 20) {
                        Text("See what Codex is doing right now.")
                            .font(.system(size: 38, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .fixedSize(horizontal: false, vertical: true)

                        Text("Codex Usage reads your local Codex logs to calculate usage, model-aware API estimates, and Headroom savings. Your logs stay on this Mac.")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.7))
                            .lineSpacing(4)
                            .frame(maxWidth: 430, alignment: .leading)

                        HStack(spacing: 8) {
                            Label("Local only", systemImage: "lock.fill")
                            Label("One access request", systemImage: "checkmark.shield")
                            Label("3-min background refresh", systemImage: "clock.arrow.circlepath")
                        }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.58))

                        Toggle("Keep widgets fresh while the app is closed", isOn: $backgroundRefreshEnabled)
                            .toggleStyle(.switch)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.78))

                        Button(action: onStartTour) {
                            Label(
                                isRequestingAccess ? "Requesting access" : needsCodexAccess ? "Allow access & tour the app" : "Tour the app",
                                systemImage: isRequestingAccess ? "ellipsis" : "arrow.right"
                            )
                                .font(.system(size: 14, weight: .semibold))
                                .padding(.horizontal, 18)
                                .padding(.vertical, 11)
                                .foregroundStyle(.white)
                                .background(OnboardingPalette.accent, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .cursorGlowBorder(radius: 10, accent: OnboardingPalette.accent)
                        }
                        .buttonStyle(.plain)
                        .disabled(isRequestingAccess)
                        .accessibilityHint(needsCodexAccess ? "Requests local Codex log access, then starts a five-step tour" : "Starts a five-step tour")
                    }
                    .frame(maxWidth: 470, alignment: .leading)
                }

                Spacer()
            }
            .padding(28)
        }
        .frame(minWidth: 980, minHeight: 660)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true)) {
                isAnimating = true
            }
        }
    }
}

private struct AnimatedUsageMark: View {
    var isAnimating: Bool

    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .trim(from: 0.08 + Double(index) * 0.08, to: 0.68 + Double(index) * 0.07)
                    .stroke(
                        index == 0 ? OnboardingPalette.accent : Color.white.opacity(0.13 + Double(index) * 0.06),
                        style: StrokeStyle(lineWidth: index == 0 ? 4 : 2, lineCap: .round)
                    )
                    .frame(width: 226 - CGFloat(index) * 42, height: 226 - CGFloat(index) * 42)
                    .rotationEffect(.degrees(isAnimating ? 280 - Double(index) * 110 : -34 + Double(index) * 18))
            }

            HStack(alignment: .bottom, spacing: 8) {
                ForEach([34, 58, 82, 48, 104, 72, 118], id: \.self) { height in
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(height == 118 ? OnboardingPalette.accent : Color.white.opacity(0.18))
                        .frame(width: 12, height: CGFloat(height) * (isAnimating ? 1 : 0.76))
                }
            }
            .frame(height: 130, alignment: .bottom)

            Image(systemName: "terminal.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(Color.black, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 12).stroke(OnboardingPalette.accent.opacity(0.7)) }
                .offset(y: 93)
        }
        .animation(.easeInOut(duration: 1.8), value: isAnimating)
        .accessibilityHidden(true)
    }
}

private enum AppTourStep: Int, CaseIterable {
    case sizes
    case metrics
    case limits
    case preview
    case actions

    var title: String {
        switch self {
        case .sizes: "Start with a widget size"
        case .metrics: "Choose what matters"
        case .limits: "Know your limit pace"
        case .preview: "Preview the real widget"
        case .actions: "Refresh, then apply"
        }
    }

    var detail: String {
        switch self {
        case .sizes: "Each size keeps its own theme, primary metric, chart, and supporting stats."
        case .metrics: "Token totals, requests, Headroom tokens, model, and API-equivalent cost can be arranged per widget."
        case .limits: "The menu bar, history chart, reset countdown, and widgets all read the same local rate-limit snapshot."
        case .preview: "This is the same shared SwiftUI view WidgetKit renders on your desktop. Charts use the visible peak as their scale."
        case .actions: "Refresh reads local Codex logs immediately. Apply saves this size’s layout to WidgetKit."
        }
    }
}

private struct AppTourOverlay: View {
    var step: Int
    var onBack: () -> Void
    var onNext: () -> Void
    var onSkip: () -> Void

    private var item: AppTourStep { AppTourStep(rawValue: step) ?? .sizes }

    var body: some View {
        GeometryReader { proxy in
            let highlight = highlightRect(for: item, size: proxy.size)
            ZStack {
                SpotlightDimmer(highlight: highlight)
                    .ignoresSafeArea()

                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(OnboardingPalette.accent, lineWidth: 2)
                    .frame(width: highlight.width, height: highlight.height)
                    .position(x: highlight.midX, y: highlight.midY)
                    .shadow(color: OnboardingPalette.accent.opacity(0.45), radius: 10)
                    .allowsHitTesting(false)

                TourCallout(
                    step: step,
                    item: item,
                    onBack: onBack,
                    onNext: onNext,
                    onSkip: onSkip
                )
                .frame(width: 350)
                .position(calloutPosition(for: item, size: proxy.size))
            }
        }
        .accessibilityAddTraits(.isModal)
    }

    private func highlightRect(for step: AppTourStep, size: CGSize) -> CGRect {
        switch step {
        case .sizes: CGRect(x: size.width - 204, y: 18, width: 184, height: 56)
        case .metrics: CGRect(x: 14, y: 390, width: 326, height: min(250, size.height - 415))
        case .limits: CGRect(x: 20, y: 126, width: size.width - 40, height: 62)
        case .preview: CGRect(x: 366, y: 225, width: size.width - 382, height: size.height - 300)
        case .actions: CGRect(x: size.width - 330, y: size.height - 67, width: 312, height: 54)
        }
    }

    private func calloutPosition(for step: AppTourStep, size: CGSize) -> CGPoint {
        switch step {
        case .sizes: CGPoint(x: size.width - 220, y: 230)
        case .metrics: CGPoint(x: 535, y: 330)
        case .limits: CGPoint(x: 535, y: 305)
        case .preview: CGPoint(x: 190, y: 340)
        case .actions: CGPoint(x: size.width - 230, y: size.height - 175)
        }
    }
}

private struct SpotlightDimmer: View {
    var highlight: CGRect

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black.opacity(0.78)))
            context.blendMode = .destinationOut
            context.fill(
                Path(roundedRect: highlight, cornerRadius: 14),
                with: .color(.white)
            )
        }
        .compositingGroup()
    }
}

private struct TourCallout: View {
    var step: Int
    var item: AppTourStep
    var onBack: () -> Void
    var onNext: () -> Void
    var onSkip: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("\(step + 1) of \(AppTourStep.allCases.count)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(OnboardingPalette.accent)
                Spacer()
                Button("Skip tour", action: onSkip)
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.white.opacity(0.6))
            }

            Text(item.title)
                .font(.system(size: 22, weight: .bold, design: .rounded))
            Text(item.detail)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.68))
                .lineSpacing(3)

            HStack {
                if step > 0 {
                    Button("Back", action: onBack)
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.white.opacity(0.72))
                }
                Spacer()
                Button(step == AppTourStep.allCases.count - 1 ? "Finish tour" : "Next", action: onNext)
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .foregroundStyle(.white)
                    .background(OnboardingPalette.accent, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
        }
        .padding(20)
        .foregroundStyle(.white)
        .background(Color(red: 0.07, green: 0.07, blue: 0.07), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.12)) }
        .shadow(color: .black.opacity(0.45), radius: 8, y: 4)
    }
}

private enum OnboardingPalette {
    static let accent = Color(red: 1, green: 0.388, blue: 0.388)
}
