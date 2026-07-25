import SwiftUI

extension Notification.Name {
    static let showCodexUsageTour = Notification.Name("showCodexUsageTour")
}

@MainActor
final class OnboardingModel: ObservableObject {
    typealias Probe = @Sendable () async -> CodexDataAccessState

    @Published private(set) var state: OnboardingState
    @Published private(set) var dataAccessState: CodexDataAccessState
    @Published private(set) var page: Int
    @Published var isPresented: Bool

    private let appVersion: String
    private let save: (OnboardingState) -> Void
    private let probe: Probe

    init(
        appVersion: String = OnboardingStateStore.currentAppVersion,
        state: OnboardingState? = nil,
        save: @escaping (OnboardingState) -> Void = { OnboardingStateStore.save($0) },
        probe: @escaping Probe = {
            await Task.detached(priority: .userInitiated) {
                CodexDataAccessProbe.run()
            }.value
        }
    ) {
        self.appVersion = appVersion
        self.save = save
        self.probe = probe
        let state = state ?? OnboardingStateStore.load() ?? OnboardingState(
            lastPresentedVersion: "",
            completedRequirements: [],
            dismissedUpdateChecklistVersion: nil,
            updatedAt: .distantPast
        )
        self.state = state
        dataAccessState = state.completedRequirements.contains(.codexDataAccess) ? .approved : .notRequested
        page = Self.firstPage(for: state)
        isPresented = OnboardingStateStore.shouldPresent(appVersion: appVersion, state: state)
    }

    var unmetRequirements: [SetupRequirement] {
        SetupRequirement.allCases.filter { !state.completedRequirements.contains($0) }
    }

    func present() {
        page = Self.firstPage(for: state)
        isPresented = true
    }

    func nextPage() {
        page = min(2, page + 1)
    }

    func previousPage() {
        page = max(0, page - 1)
    }

    func requestAccess() {
        guard dataAccessState != .requesting else { return }
        dataAccessState = .requesting
        Task {
            let result = await probe()
            dataAccessState = result
            guard result == .approved else {
                page = 1
                return
            }
            complete(.codexDataAccess)
            page = 2
            _ = await RefreshCoordinator.shared.refresh(trigger: .manual, force: true)
        }
    }

    func recordBackgroundRefresh(installed: Bool) {
        update(.backgroundRefresh, satisfied: installed)
    }

    func recordWidgetRegistration(registered: Bool) {
        update(.widgetRegistration, satisfied: registered)
    }

    func finish() {
        guard unmetRequirements.isEmpty else { return }
        state.lastPresentedVersion = appVersion
        state.dismissedUpdateChecklistVersion = nil
        persist()
        isPresented = false
    }

    func skip() {
        state.lastPresentedVersion = appVersion
        state.dismissedUpdateChecklistVersion = appVersion
        persist()
        isPresented = false
    }

    private func complete(_ requirement: SetupRequirement) {
        update(requirement, satisfied: true)
    }

    private func update(_ requirement: SetupRequirement, satisfied: Bool) {
        let changed = satisfied
            ? state.completedRequirements.insert(requirement).inserted
            : state.completedRequirements.remove(requirement) != nil
        guard changed else { return }
        if satisfied {
            state.lastPresentedVersion = appVersion
        }
        persist()
    }

    private func persist() {
        state.schemaVersion = OnboardingState.currentSchemaVersion
        state.updatedAt = .now
        save(state)
    }

    private static func firstPage(for state: OnboardingState) -> Int {
        if state.completedRequirements.isEmpty { return 0 }
        if !state.completedRequirements.contains(.codexDataAccess) { return 1 }
        return 2
    }
}

struct CodexUsageRootView: View {
    @StateObject private var onboarding = OnboardingModel()

    var body: some View {
        ContentView()
            .preferredColorScheme(.dark)
            .sheet(isPresented: $onboarding.isPresented) {
                SetupSheet(model: onboarding)
            }
            .onReceive(NotificationCenter.default.publisher(for: .showCodexUsageTour)) { _ in
                onboarding.present()
            }
    }
}

private struct SetupSheet: View {
    @ObservedObject var model: OnboardingModel
    @EnvironmentObject private var settingsModel: CodexUsageSettingsModel
    @State private var showsSkipWarning = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: "terminal.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(AppPalette.accent, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Set up Codex Usage")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Private, local, and ready for widgets")
                        .font(.caption)
                        .foregroundStyle(AppPalette.muted)
                }
                Spacer()
                stepProgress
            }
            .padding(20)

            Divider()

            Group {
                switch model.page {
                case 0: privacyPage
                case 1: accessPage
                default: servicesPage
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 34)
            .padding(.vertical, 26)

            Divider()
            footer
                .padding(20)
        }
        .frame(width: 660, height: 520)
        .background(AppPalette.windowTint)
        .alert("Skip unfinished setup?", isPresented: $showsSkipWarning) {
            Button("Continue Setup", role: .cancel) {}
            Button("Skip for This Version", role: .destructive) { model.skip() }
        } message: {
            Text("Unfinished items will stay incomplete. Usage or widgets may remain unavailable until you run Setup again.")
        }
    }

    private var stepProgress: some View {
        HStack(spacing: 7) {
            ForEach(0..<3) { step in
                Capsule()
                    .fill(step <= model.page ? AppPalette.accent : Color.white.opacity(0.14))
                    .frame(width: step == model.page ? 28 : 9, height: 6)
            }
            Text("\(model.page + 1) / 3")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(AppPalette.muted)
                .frame(width: 28, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(model.page + 1) of 3")
    }

    private var privacyPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            pageHeading(
                symbol: "lock.shield.fill",
                title: "Your usage stays on this Mac",
                detail: "Codex Usage reads local session totals and optional Headroom savings. Your prompts and logs are never uploaded."
            )
            setupRow(.codexDataAccess, symbol: "folder.fill", detail: "Read local Codex session totals")
            setupRow(.backgroundRefresh, symbol: "arrow.clockwise", detail: "Keep the shared snapshot current")
            setupRow(.widgetRegistration, symbol: "rectangle.3.group.fill", detail: "Show live data in macOS widgets")
            Spacer()
        }
    }

    private var accessPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            pageHeading(
                symbol: "folder.badge.questionmark",
                title: "Connect your local Codex data",
                detail: "macOS may ask once for permission to read the Codex sessions folder. Nothing leaves your Mac."
            )
            HStack(spacing: 14) {
                accessStatus
                Spacer()
                if model.dataAccessState != .approved {
                    Button(accessButtonTitle) { model.requestAccess() }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.dataAccessState == .requesting)
                }
            }
            .padding(16)
            .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(Color.white.opacity(0.09), lineWidth: 1)
            }
            Spacer()
        }
    }

    private var servicesPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            pageHeading(
                symbol: model.unmetRequirements.isEmpty ? "checkmark.seal.fill" : "slider.horizontal.3",
                title: model.unmetRequirements.isEmpty ? "You’re ready to go" : "Keep widgets up to date",
                detail: model.unmetRequirements.isEmpty
                    ? "The local reader, background refresh, and widget extension are ready."
                    : "Finish the two services that keep your desktop widgets current."
            )

            serviceRow(
                title: "Background refresh",
                detail: BackgroundRefreshAgent.status().detail,
                symbol: "arrow.clockwise",
                complete: model.state.completedRequirements.contains(.backgroundRefresh)
            ) {
                Toggle("", isOn: $settingsModel.settings.backgroundRefreshEnabled)
                    .labelsHidden()
                    .onChange(of: settingsModel.settings.backgroundRefreshEnabled) { _, enabled in
                        model.recordBackgroundRefresh(installed: BackgroundRefreshAgent.setEnabled(enabled))
                    }
                if settingsModel.settings.backgroundRefreshEnabled,
                   !model.state.completedRequirements.contains(.backgroundRefresh) {
                    Button("Repair") {
                        model.recordBackgroundRefresh(installed: BackgroundRefreshAgent.setEnabled(true))
                    }
                    .controlSize(.small)
                }
            }

            serviceRow(
                title: "Widget extension",
                detail: widgetRegistered ? "Available to macOS" : "Extension not found",
                symbol: "rectangle.3.group.fill",
                complete: model.state.completedRequirements.contains(.widgetRegistration)
            ) {
                if !model.state.completedRequirements.contains(.widgetRegistration) {
                    Button("Check Again") {
                        model.recordWidgetRegistration(registered: widgetRegistered)
                    }
                    .controlSize(.small)
                }
            }

            if model.unmetRequirements.contains(.codexDataAccess) {
                Label("Codex data access still needs attention.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            Spacer()
        }
        .onAppear {
            model.recordWidgetRegistration(registered: widgetRegistered)
            guard settingsModel.settings.backgroundRefreshEnabled,
                  BackgroundRefreshAgent.isStableInstall
            else { return }
            Task {
                let installed = await Task.detached(priority: .utility) {
                    BackgroundRefreshAgent.setEnabled(true)
                }.value
                model.recordBackgroundRefresh(installed: installed)
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("Skip") { showsSkipWarning = true }
            if model.page > 0 {
                Button("Back") { model.previousPage() }
            }
            Spacer()
            if model.page == 0 {
                Button("Continue") { model.nextPage() }
                    .buttonStyle(.borderedProminent)
            } else if model.page == 1 {
                Button("Continue") { model.nextPage() }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.dataAccessState != .approved)
            } else {
                Button("Finish") { model.finish() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.unmetRequirements.isEmpty)
            }
        }
    }

    @ViewBuilder
    private var accessStatus: some View {
        switch model.dataAccessState {
        case .notRequested:
            statusLabel("Ready to check", symbol: "circle.dashed", color: AppPalette.muted)
        case .requesting:
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("Checking access…")
            }
        case .approved:
            statusLabel("Access approved", symbol: "checkmark.circle.fill", color: .green)
        case .needsManualAction(let message):
            statusLabel(message, symbol: "exclamationmark.triangle.fill", color: .orange)
        case .failed(let message):
            statusLabel(message, symbol: "xmark.circle.fill", color: .red)
        }
    }

    private var accessButtonTitle: String {
        switch model.dataAccessState {
        case .needsManualAction, .failed: "Try Again"
        case .requesting: "Checking…"
        default: "Request Access"
        }
    }

    private var widgetRegistered: Bool {
        guard let plugins = Bundle.main.builtInPlugInsURL else { return false }
        return FileManager.default.fileExists(
            atPath: plugins.appendingPathComponent("CodexUsageWidget.appex").path
        )
    }

    private func pageHeading(symbol: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(AppPalette.accent)
                .frame(width: 48, height: 48)
                .background(AppPalette.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 24, weight: .semibold))
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(AppPalette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func setupRow(_ requirement: SetupRequirement, symbol: String, detail: String) -> some View {
        HStack(spacing: 13) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppPalette.accent)
                .frame(width: 34, height: 34)
                .background(AppPalette.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(requirement.title).font(.system(size: 13, weight: .semibold))
                Text(detail).font(.caption).foregroundStyle(AppPalette.muted)
            }
            Spacer()
            Image(systemName: model.state.completedRequirements.contains(requirement) ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(model.state.completedRequirements.contains(requirement) ? .green : AppPalette.muted)
        }
        .padding(13)
        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.09), lineWidth: 1)
        }
    }

    private func serviceRow<Controls: View>(
        title: String,
        detail: String,
        symbol: String,
        complete: Bool,
        @ViewBuilder controls: () -> Controls
    ) -> some View {
        HStack(spacing: 13) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(complete ? Color.green : AppPalette.accent)
                .frame(width: 34, height: 34)
                .background(
                    (complete ? Color.green : AppPalette.accent).opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(detail).font(.caption).foregroundStyle(AppPalette.muted)
            }
            Spacer()
            controls()
        }
        .padding(13)
        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.09), lineWidth: 1)
        }
    }

    private func statusLabel(_ title: String, symbol: String, color: Color) -> some View {
        Label(title, systemImage: symbol)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(color)
    }
}

private extension SetupRequirement {
    var title: String {
        switch self {
        case .codexDataAccess: "Codex data access"
        case .backgroundRefresh: "Background refresh"
        case .widgetRegistration: "Widget registration"
        }
    }
}
