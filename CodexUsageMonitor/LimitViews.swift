import Charts
import SwiftUI

struct LimitSummaryStrip: View {
    var snapshot: CodexUsageSnapshot

    var body: some View {
        HStack(spacing: 1) {
            LimitSummaryCell(
                label: "5-hour",
                value: percent(snapshot.rateLimits?.fiveHour),
                detail: reset(snapshot.rateLimits?.fiveHour)
            )
            LimitSummaryCell(
                label: "Weekly",
                value: percent(snapshot.rateLimits?.weekly),
                detail: reset(snapshot.rateLimits?.weekly)
            )
            LimitSummaryCell(
                label: "Pace",
                value: snapshot.rateLimits?.pace.label ?? "Unavailable",
                detail: "Based on elapsed time"
            )
            LimitSummaryCell(
                label: "Next reset",
                value: snapshot.rateLimits?.nearestReset?.resetText() ?? "—",
                detail: "Local Codex record"
            )
        }
        .appGlassPanel(cornerRadius: 16)
    }

    private func percent(_ window: RateLimitWindow?) -> String {
        window.map { "\(Int($0.remainingPercent.rounded()))% left" } ?? "—"
    }

    private func reset(_ window: RateLimitWindow?) -> String {
        window.map { "Resets in \($0.resetText())" } ?? "No current window"
    }
}

private struct LimitSummaryCell: View {
    var label: String
    var value: String
    var detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(detail)
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color.clear)
    }
}

struct LimitHistoryChart: View {
    var history: [RateLimitHistoryPoint]

    var body: some View {
        if history.isEmpty {
            Text("Rate-limit history will appear after Codex reports a limit window.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        } else {
            Chart(history) { point in
                if let value = point.fiveHourUsedPercent {
                    LineMark(x: .value("Time", point.date), y: .value("5-hour", 100 - value))
                        .foregroundStyle(by: .value("Window", "5-hour"))
                }
                if let value = point.weeklyUsedPercent {
                    LineMark(x: .value("Time", point.date), y: .value("Weekly", 100 - value))
                        .foregroundStyle(by: .value("Window", "Weekly"))
                }
            }
            .chartYScale(domain: 0...100)
            .chartForegroundStyleScale([
                "5-hour": AppPalette.accent,
                "Weekly": AppPalette.accent.opacity(0.5)
            ])
            .chartLegend(position: .bottom, spacing: 8)
            .frame(height: 120)
        }
    }
}

struct LimitPreferencesView: View {
    @EnvironmentObject private var settingsModel: CodexUsageSettingsModel
    @State private var agentStatus = BackgroundRefreshAgentStatus(
        enabled: CodexUsageSettingsStore.load().settings.backgroundRefreshEnabled,
        installed: false,
        loaded: false,
        lastSuccess: nil
    )

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Refresh in background", isOn: $settingsModel.settings.backgroundRefreshEnabled)
                .onChange(of: settingsModel.settings.backgroundRefreshEnabled) { _, enabled in
                    updateAgentStatus { _ = BackgroundRefreshAgent.setEnabled(enabled) }
                }
            Text(agentStatus.detail)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

            if settingsModel.settings.backgroundRefreshEnabled && (!agentStatus.installed || !agentStatus.loaded) {
                Button("Repair background refresh") {
                    updateAgentStatus { _ = BackgroundRefreshAgent.install() }
                }
                .buttonStyle(.link)
            }

            LabeledContent("Menu bar") {
                Picker("Menu bar", selection: $settingsModel.settings.menuBarDisplayMode) {
                    ForEach(MenuBarDisplayMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .labelsHidden()
                .frame(width: 150)
            }
            if settingsModel.settings.menuBarDisplayMode == .hidden {
                Text("Reopen Codex Usage to show the menu bar item again.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            LabeledContent("Show app in") {
                Picker("Show app in", selection: $settingsModel.settings.appPresence) {
                    ForEach(AppPresenceMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .labelsHidden()
                .frame(width: 150)
                .onChange(of: settingsModel.settings.appPresence) { _, value in
                    AppPresenceMode.apply(value)
                }
            }

            Divider()
            Toggle("Limit notifications", isOn: $settingsModel.settings.notificationsEnabled)
                .onChange(of: settingsModel.settings.notificationsEnabled) { _, enabled in
                    guard enabled else { return }
                    Task {
                        if !(await LimitNotificationManager.requestAuthorization()) {
                            settingsModel.settings.notificationsEnabled = false
                        }
                    }
                }

            if settingsModel.settings.notificationsEnabled {
                LabeledContent("Warning") {
                    Picker("Warning", selection: $settingsModel.settings.warningThreshold) {
                        ForEach([60, 70, 80], id: \.self) { Text("\($0)%").tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 76)
                }
                LabeledContent("Critical") {
                    Picker("Critical", selection: $settingsModel.settings.criticalThreshold) {
                        ForEach([85, 90, 95], id: \.self) { Text("\($0)%").tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 76)
                }
            }
        }
        .onAppear { updateAgentStatus() }
    }

    private func updateAgentStatus(action: @escaping @Sendable () -> Void = {}) {
        Task {
            agentStatus = await Task.detached(priority: .utility) {
                action()
                return BackgroundRefreshAgent.status()
            }.value
        }
    }
}
