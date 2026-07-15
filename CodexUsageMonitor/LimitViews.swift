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
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func percent(_ window: RateLimitWindow?) -> String {
        window.map { "\(Int($0.usedPercent.rounded()))%" } ?? "—"
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
        .background(Color.black.opacity(0.22))
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
                    LineMark(x: .value("Time", point.date), y: .value("5-hour", value))
                        .foregroundStyle(by: .value("Window", "5-hour"))
                }
                if let value = point.weeklyUsedPercent {
                    LineMark(x: .value("Time", point.date), y: .value("Weekly", value))
                        .foregroundStyle(by: .value("Window", "Weekly"))
                }
            }
            .chartYScale(domain: 0...100)
            .chartLegend(position: .bottom, spacing: 8)
            .frame(height: 120)
        }
    }
}

struct LimitPreferencesView: View {
    @AppStorage(BackgroundRefreshAgent.enabledKey) private var backgroundEnabled = false
    @AppStorage(LimitNotificationManager.enabledKey) private var notificationsEnabled = false
    @AppStorage(LimitNotificationManager.warningThresholdKey) private var warningThreshold = 70
    @AppStorage(LimitNotificationManager.criticalThresholdKey) private var criticalThreshold = 90
    @AppStorage("CodexUsageMonitor.menuBarDisplayMode") private var menuBarMode = MenuBarDisplayMode.percentage.rawValue
    @State private var agentStatus = BackgroundRefreshAgent.status()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Refresh in background", isOn: $backgroundEnabled)
                .onChange(of: backgroundEnabled) { _, enabled in
                    _ = BackgroundRefreshAgent.setEnabled(enabled)
                    agentStatus = BackgroundRefreshAgent.status()
                }
            Text(agentStatus.detail)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

            if backgroundEnabled && (!agentStatus.installed || !agentStatus.loaded) {
                Button("Repair background refresh") {
                    _ = BackgroundRefreshAgent.install()
                    agentStatus = BackgroundRefreshAgent.status()
                }
                .buttonStyle(.link)
            }

            LabeledContent("Menu bar") {
                Picker("Menu bar", selection: $menuBarMode) {
                    ForEach(MenuBarDisplayMode.allCases) { mode in
                        Text(mode.label).tag(mode.rawValue)
                    }
                }
                .labelsHidden()
                .frame(width: 150)
            }

            Divider()
            Toggle("Limit notifications", isOn: $notificationsEnabled)
                .onChange(of: notificationsEnabled) { _, enabled in
                    guard enabled else { return }
                    Task {
                        if !(await LimitNotificationManager.requestAuthorization()) {
                            notificationsEnabled = false
                        }
                    }
                }

            if notificationsEnabled {
                LabeledContent("Warning") {
                    Picker("Warning", selection: $warningThreshold) {
                        ForEach([60, 70, 80], id: \.self) { Text("\($0)%").tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 76)
                }
                LabeledContent("Critical") {
                    Picker("Critical", selection: $criticalThreshold) {
                        ForEach([85, 90, 95], id: \.self) { Text("\($0)%").tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 76)
                }
            }
        }
        .onAppear { agentStatus = BackgroundRefreshAgent.status() }
    }
}
