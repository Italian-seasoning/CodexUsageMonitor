import Foundation
import Security
import UserNotifications

enum LimitNotificationManager {
    private static let resetIdentifiers = [300, 10_080].map { "limit-reset-\($0)" }

    static func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) == true
    }

    static func evaluate(_ snapshot: CodexUsageSnapshot, now: Date = .now) {
        let defaults = UserDefaults.standard
        let settings = CodexUsageSettingsStore.load().settings
        guard settings.notificationsEnabled, let limits = snapshot.rateLimits else { return }
        let warning = settings.warningThreshold
        let critical = settings.criticalThreshold

        for window in [limits.fiveHour, limits.weekly].compactMap({ $0 }) where window.isCurrent(at: now) {
            scheduleReset(for: window, now: now)
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

    static func cancelScheduledResets() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: resetIdentifiers)
    }

    private static func scheduleReset(for window: RateLimitWindow, now: Date) {
        let delay = window.resetsAt.timeIntervalSince(now)
        guard delay >= 10 else { return }
        let period = window.windowMinutes == 300 ? "5-hour" : "weekly"
        let content = UNMutableNotificationContent()
        content.title = "Codex usage reset"
        content.body = "Your \(period) usage window has reset. Full capacity is available again."
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "limit-reset-\(window.windowMinutes)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
        )
        UNUserNotificationCenter.current().add(request)
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

enum PhoneResetNotificationManager {
    private static let sequenceID = "codex-five-hour-reset"
    private static let scheduledResetKey = "CodexUsageMonitor.ntfyScheduledReset"
    private static let maximumDelay: TimeInterval = 3 * 86_400

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
              let request = scheduledRequest(topic: topic, window: window, now: now)
        else { return }

        let reset = window.resetsAt.timeIntervalSince1970
        guard UserDefaults.standard.double(forKey: scheduledResetKey) != reset else { return }
        guard await send(request) else { return }
        UserDefaults.standard.set(reset, forKey: scheduledResetKey)
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

    static func scheduledRequest(topic: String, window: RateLimitWindow, now: Date) -> URLRequest? {
        let delay = window.resetsAt.timeIntervalSince(now)
        guard window.windowMinutes == 300, delay >= 10, delay <= maximumDelay,
              let url = endpoint(topic: topic)
        else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 8
        request.setValue("Codex usage reset", forHTTPHeaderField: "Title")
        request.setValue("high", forHTTPHeaderField: "Priority")
        request.setValue("white_check_mark,hourglass", forHTTPHeaderField: "Tags")
        request.setValue(String(Int(window.resetsAt.timeIntervalSince1970)), forHTTPHeaderField: "At")
        request.httpBody = Data("Your 5-hour Codex usage window has reset. Full capacity is available again.".utf8)
        return request
    }

    private static func testRequest(topic: String) -> URLRequest? {
        guard let url = URL(string: "https://ntfy.sh/\(topic)") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 8
        request.setValue("Codex Usage Monitor", forHTTPHeaderField: "Title")
        request.setValue("white_check_mark", forHTTPHeaderField: "Tags")
        request.httpBody = Data("Phone notifications are connected.".utf8)
        return request
    }

    private static func endpoint(topic: String) -> URL? {
        guard !topic.isEmpty,
              topic.count <= 64,
              topic.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" })
        else { return nil }
        return URL(string: "https://ntfy.sh/\(topic)/\(sequenceID)")
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
