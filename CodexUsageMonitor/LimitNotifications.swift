import Foundation
import UserNotifications

enum LimitNotificationManager {
    static let enabledKey = "CodexUsageMonitor.limitNotificationsEnabled"
    static let warningThresholdKey = "CodexUsageMonitor.limitWarningThreshold"
    static let criticalThresholdKey = "CodexUsageMonitor.limitCriticalThreshold"

    static func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) == true
    }

    static func evaluate(_ snapshot: CodexUsageSnapshot, now: Date = .now) {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: enabledKey), let limits = snapshot.rateLimits else { return }
        let warning = defaults.object(forKey: warningThresholdKey) as? Int ?? 70
        let critical = defaults.object(forKey: criticalThresholdKey) as? Int ?? 90

        for window in [limits.fiveHour, limits.weekly].compactMap({ $0 }) where window.isCurrent(at: now) {
            evaluateReset(for: window, now: now, defaults: defaults)
            let threshold = window.usedPercent >= Double(critical) ? critical
                : window.usedPercent >= Double(warning) ? warning
                : nil
            guard let threshold else { continue }
            let key = notificationKey(for: window, threshold: threshold)
            guard !defaults.bool(forKey: key) else { continue }
            defaults.set(true, forKey: key)
            let period = window.windowMinutes == 300 ? "5-hour" : "weekly"
            send(
                identifier: key,
                title: threshold == critical ? "Codex limit risk" : "Codex usage warning",
                body: "The \(period) window is at \(Int(window.usedPercent.rounded()))% and resets in \(window.resetText(at: now))."
            )
        }
    }

    private static func evaluateReset(for window: RateLimitWindow, now: Date, defaults: UserDefaults) {
        let key = "CodexUsageMonitor.lastReset.\(window.windowMinutes)"
        let previous = defaults.double(forKey: key)
        let current = window.resetsAt.timeIntervalSince1970
        defaults.set(current, forKey: key)
        guard previous > 0, previous <= now.timeIntervalSince1970, current > previous else { return }
        let period = window.windowMinutes == 300 ? "5-hour" : "weekly"
        send(
            identifier: "limit-reset-\(window.windowMinutes)-\(Int(current))",
            title: "Codex limit reset",
            body: "Your \(period) usage window has reset."
        )
    }

    private static func notificationKey(for window: RateLimitWindow, threshold: Int) -> String {
        "CodexUsageMonitor.notified.\(window.windowMinutes).\(Int(window.resetsAt.timeIntervalSince1970)).\(threshold)"
    }

    private static func send(identifier: String, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        )
    }
}
