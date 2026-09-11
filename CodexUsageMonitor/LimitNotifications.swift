import Foundation
import Security
import UserNotifications

enum LimitNotificationManager {
    private static let resetIdentifiers = [300, 10_080].map { "limit-reset-\($0)" }
    private static let resetTolerance: TimeInterval = 5 * 60

    static func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) == true
    }

    static func evaluate(_ snapshot: CodexUsageSnapshot, now: Date = .now) {
        let defaults = UserDefaults.standard
        let settings = CodexUsageSettingsStore.load().settings
        cancelScheduledResets()
        guard let limits = snapshot.rateLimits else { return }
        let warning = settings.warningThreshold
        let critical = settings.criticalThreshold
        let windows = [limits.fiveHour, limits.weekly].compactMap { $0 }

        for window in windows where window.isCurrent(at: now) {
            if recordConfirmedReset(for: window, now: now, defaults: defaults), settings.notificationsEnabled {
                let period = window.windowMinutes == 300 ? "5-hour" : "weekly"
                send(
                    identifier: "limit-reset-\(window.windowMinutes)-\(Int(window.resetsAt.timeIntervalSince1970))",
                    title: "Codex limit reset",
                    body: "Your \(period) usage window reset is confirmed."
                )
            }
            guard settings.notificationsEnabled else { continue }
            let threshold = window.usedPercent >= Double(critical) ? critical
                : window.usedPercent >= Double(warning) ? warning
                : nil
            guard let threshold else { continue }
            let key = notificationKey(for: window, threshold: threshold)
            let fixedReset = defaults.double(forKey: key)
            let previousReset = fixedReset > 0 ? fixedReset : previousNotifiedReset(
                defaults: defaults,
                windowMinutes: window.windowMinutes,
                threshold: threshold
            )
            if fixedReset <= 0, previousReset > 0 {
                defaults.set(previousReset, forKey: key)
            }
            guard isNewReset(window.resetsAt, after: previousReset) else { continue }
            defaults.set(window.resetsAt.timeIntervalSince1970, forKey: key)
            let period = window.windowMinutes == 300 ? "5-hour" : "weekly"
            send(
                identifier: key,
                title: threshold == critical ? "Codex limit risk" : "Codex usage warning",
                body: "The \(period) window is at \(Int(window.usedPercent.rounded()))% and resets in \(window.resetText(at: now))."
            )
        }
    }

    static func cancelScheduledResets() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: resetIdentifiers)
    }

    static func isNewReset(_ reset: Date, after previousReset: TimeInterval) -> Bool {
        previousReset <= 0 || reset.timeIntervalSince1970 > previousReset + resetTolerance
    }

    static func previousNotifiedReset(
        defaults: UserDefaults,
        windowMinutes: Int,
        threshold: Int
    ) -> TimeInterval {
        let prefix = "CodexUsageMonitor.notified.\(windowMinutes)."
        let suffix = ".\(threshold)"
        return defaults.dictionaryRepresentation().keys.compactMap { key in
            guard key.hasPrefix(prefix),
                  key.hasSuffix(suffix),
                  key.count > prefix.count + suffix.count,
                  defaults.bool(forKey: key)
            else { return nil }
            return TimeInterval(key.dropFirst(prefix.count).dropLast(suffix.count))
        }.max() ?? 0
    }

    static func isConfirmedReset(
        previousReset: TimeInterval,
        window: RateLimitWindow,
        now: Date
    ) -> Bool {
        let currentReset = window.resetsAt.timeIntervalSince1970
        let minimumAdvance = TimeInterval(window.windowMinutes * 60) / 2
        return previousReset > 0
            && previousReset <= now.timeIntervalSince1970
            && currentReset >= previousReset + minimumAdvance
    }

    private static func recordConfirmedReset(
        for window: RateLimitWindow,
        now: Date,
        defaults: UserDefaults
    ) -> Bool {
        let observedKey = "CodexUsageMonitor.observedReset.v2.\(window.windowMinutes)"
        let notifiedKey = "CodexUsageMonitor.notifiedReset.v2.\(window.windowMinutes)"
        let previousReset = defaults.double(forKey: observedKey)
        let currentReset = window.resetsAt.timeIntervalSince1970
        if currentReset > previousReset {
            defaults.set(currentReset, forKey: observedKey)
        }
        guard isConfirmedReset(previousReset: previousReset, window: window, now: now),
              isNewReset(window.resetsAt, after: defaults.double(forKey: notifiedKey))
        else { return false }
        defaults.set(currentReset, forKey: notifiedKey)
        return true
    }

    private static func notificationKey(for window: RateLimitWindow, threshold: Int) -> String {
        "CodexUsageMonitor.notified.\(window.windowMinutes).\(threshold)"
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

enum PhoneResetNotificationManager {
    private static let sequenceID = "codex-five-hour-reset"
    private static let scheduledResetKey = "CodexUsageMonitor.ntfyScheduledReset"
    private static let observedResetKey = "CodexUsageMonitor.ntfyObservedReset.v2"
    private static let notifiedResetKey = "CodexUsageMonitor.ntfyNotifiedReset.v2"

    static var topicURL: String? {
        NtfyTopicStore.load().map { "https://ntfy.sh/\($0)" }
    }

    static func ensureTopic() -> String? {
        NtfyTopicStore.load() ?? NtfyTopicStore.create()
    }

    static func scheduleIfNeeded(_ snapshot: CodexUsageSnapshot?, now: Date = .now) async {
        let settings = CodexUsageSettingsStore.load().settings
        guard settings.phoneNotificationsEnabled,
              let topic = NtfyTopicStore.load(),
              let window = snapshot?.rateLimits?.fiveHour,
              window.isCurrent(at: now)
        else { return }

        let defaults = UserDefaults.standard
        if defaults.double(forKey: scheduledResetKey) > 0 {
            await cancelScheduled()
            guard defaults.double(forKey: scheduledResetKey) == 0 else { return }
        }

        let previousReset = defaults.double(forKey: observedResetKey)
        let currentReset = window.resetsAt.timeIntervalSince1970
        if currentReset > previousReset {
            defaults.set(currentReset, forKey: observedResetKey)
        }
        guard LimitNotificationManager.isConfirmedReset(
            previousReset: previousReset,
            window: window,
            now: now
        ),
              LimitNotificationManager.isNewReset(
                window.resetsAt,
                after: defaults.double(forKey: notifiedResetKey)
              ),
              let request = confirmedResetRequest(topic: topic, window: window, previousReset: previousReset, now: now)
        else { return }
        guard await send(request) else { return }
        defaults.set(currentReset, forKey: notifiedResetKey)
    }

    static func sendTest() async -> Bool {
        guard let topic = ensureTopic(), let request = testRequest(topic: topic) else { return false }
        return await send(request)
    }

    static func cancelScheduled() async {
        guard let topic = NtfyTopicStore.load(),
              let url = endpoint(topic: topic)
        else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.timeoutInterval = 8
        if await send(request) {
            UserDefaults.standard.removeObject(forKey: scheduledResetKey)
        }
    }

    static func confirmedResetRequest(
        topic: String,
        window: RateLimitWindow,
        previousReset: TimeInterval,
        now: Date
    ) -> URLRequest? {
        guard window.windowMinutes == 300,
              LimitNotificationManager.isConfirmedReset(previousReset: previousReset, window: window, now: now),
              let url = topicEndpoint(topic: topic)
        else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 8
        request.setValue("Codex usage reset", forHTTPHeaderField: "Title")
        request.setValue("high", forHTTPHeaderField: "Priority")
        request.setValue("white_check_mark,hourglass", forHTTPHeaderField: "Tags")
        request.httpBody = Data("Your 5-hour Codex usage reset is confirmed.".utf8)
        return request
    }

    private static func testRequest(topic: String) -> URLRequest? {
        guard let url = topicEndpoint(topic: topic) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 8
        request.setValue("Codex Usage Monitor", forHTTPHeaderField: "Title")
        request.setValue("white_check_mark", forHTTPHeaderField: "Tags")
        request.httpBody = Data("Phone notifications are connected.".utf8)
        return request
    }

    private static func endpoint(topic: String) -> URL? {
        topicEndpoint(topic: topic)?.appendingPathComponent(sequenceID)
    }

    private static func topicEndpoint(topic: String) -> URL? {
        guard !topic.isEmpty,
              topic.count <= 64,
              topic.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" })
        else { return nil }
        return URL(string: "https://ntfy.sh/\(topic)")
    }

    private static func send(_ request: URLRequest) async -> Bool {
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse).map { 200..<300 ~= $0.statusCode } == true
        } catch {
            return false
        }
    }
}

private enum NtfyTopicStore {
    private static let service = "com.codexusage.CodexUsageMonitor.ntfy"
    private static let account = "reset-topic"

    static func load() -> String? {
        var result: CFTypeRef?
        let status = SecItemCopyMatching([
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ] as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func create() -> String? {
        let topic = "codex-" + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let status = SecItemAdd([
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlock,
            kSecValueData: Data(topic.utf8),
        ] as CFDictionary, nil)
        return status == errSecSuccess ? topic : nil
    }
}
