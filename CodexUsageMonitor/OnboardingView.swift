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
        if installed { complete(.backgroundRefresh) }
    }

    func recordWidgetRegistration(registered: Bool) {
        if registered { complete(.widgetRegistration) }
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
        state.completedRequirements.insert(requirement)
        state.lastPresentedVersion = appVersion
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
            HStack {
                Label("Codex Usage Setup", systemImage: "checklist")
                    .font(.headline)
                Spacer()
                Text("Step \(model.page + 1) of 3")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
            .id(model.page)
            .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .opacity))
            .animation(.easeInOut(duration: 0.2), value: model.page)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(28)

            Divider()
            footer
                .padding(20)
        }
        .frame(minWidth: 540, idealWidth: 540, minHeight: 500, idealHeight: 500)
        .alert("Skip unfinished setup?", isPresented: $showsSkipWarning) {
            Button("Continue Setup", role: .cancel) {}
            Button("Skip for This Version", role: .destructive) { model.skip() }
        } message: {
            Text("Unfinished items will stay incomplete. Usage or widgets may remain unavailable until you run Setup again.")
        }
    }

    private var privacyPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 44))
                .foregroundStyle(.tint)
            Text("Your usage stays on this Mac")
                .font(.title2.bold())
            Text("Codex Usage reads local Codex session logs and optional Headroom savings. It does not upload your logs, prompts, or usage history.")
                .foregroundStyle(.secondary)
            setupRow(.codexDataAccess, detail: "Read local Codex session files")
            setupRow(.backgroundRefresh, detail: "Keep widgets current when the app is closed")
            setupRow(.widgetRegistration, detail: "Make the widget available to macOS")
            Spacer()
        }
    }

    private var accessPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Allow Codex data access")
                .font(.title2.bold())
            Text("macOS may ask for permission when Codex Usage checks your local sessions folder.")
                .foregroundStyle(.secondary)
            accessStatus
            Button(accessButtonTitle) { model.requestAccess() }
                .buttonStyle(.borderedProminent)
                .disabled(model.dataAccessState == .requesting)
            Spacer()
        }
    }

    private var servicesPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Finish setup")
                .font(.title2.bold())

            if model.unmetRequirements.contains(.backgroundRefresh) {
                Toggle(
                    "Refresh widgets in the background",
                    isOn: $settingsModel.settings.backgroundRefreshEnabled
                )
                .onChange(of: settingsModel.settings.backgroundRefreshEnabled) { _, enabled in
                    model.recordBackgroundRefresh(installed: BackgroundRefreshAgent.setEnabled(enabled))
                }
                if settingsModel.settings.backgroundRefreshEnabled {
                    Button("Install or Repair Background Refresh") {
                        model.recordBackgroundRefresh(installed: BackgroundRefreshAgent.setEnabled(true))
                    }
                }
            }

            if model.unmetRequirements.contains(.widgetRegistration) {
                setupRow(.widgetRegistration, detail: widgetRegistered ? "Widget extension found" : "Widget extension is missing")
                Button("Check Widget Registration") {
                    model.recordWidgetRegistration(registered: widgetRegistered)
                }
            }

            ForEach(model.unmetRequirements, id: \.rawValue) { requirement in
                if requirement != .backgroundRefresh && requirement != .widgetRegistration {
                    setupRow(requirement, detail: "Needs attention")
                }
            }

            if model.unmetRequirements.isEmpty {
                ContentUnavailableView(
                    "Setup Complete",
                    systemImage: "checkmark.circle.fill",
                    description: Text("Codex Usage and its widget are ready.")
                )
            }
            Spacer()
        }
        .onAppear {
            model.recordWidgetRegistration(registered: widgetRegistered)
            if settingsModel.settings.backgroundRefreshEnabled {
                model.recordBackgroundRefresh(installed: BackgroundRefreshAgent.status().installed)
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("Skip") { showsSkipWarning = true }
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
            Label("Not requested", systemImage: "circle")
                .foregroundStyle(.secondary)
        case .requesting:
            HStack { ProgressView(); Text("Checking access…") }
        case .approved:
            Label("Access approved", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .needsManualAction(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        case .failed(let message):
            Label(message, systemImage: "xmark.circle.fill")
                .foregroundStyle(.red)
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

    private func setupRow(_ requirement: SetupRequirement, detail: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: model.state.completedRequirements.contains(requirement)
                ? "checkmark.circle.fill"
                : "circle")
                .foregroundStyle(model.state.completedRequirements.contains(requirement) ? .green : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(requirement.title)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
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
