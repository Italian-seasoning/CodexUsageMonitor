import Darwin
import Foundation

struct BackgroundRefreshRecord: Codable, Equatable {
    var lastAttempt: Date
    var lastSuccess: Date?
    var durationSeconds: Double
    var error: String?
    var sourceFingerprint: String? = nil
}

struct BackgroundRefreshAgentStatus {
    var enabled: Bool
    var installed: Bool
    var loaded: Bool
    var lastSuccess: Date?

    var detail: String {
        if !enabled { return "Off" }
        if !BackgroundRefreshAgent.isStableInstall { return "Move the app to Applications first" }
        if !installed || !loaded { return "Needs repair" }
        guard let lastSuccess else { return "Scheduled every 3 minutes" }
        return "Last refreshed \(lastSuccess.formatted(date: .omitted, time: .shortened))"
    }
}

enum BackgroundRefreshAgent {
    static let enabledKey = "CodexUsageMonitor.backgroundRefreshEnabled"
    static let identifier = "com.nolankrahn.CodexUsageMonitor.refresh"
    static let interval: TimeInterval = 180

    static var isStableInstall: Bool {
        let path = Bundle.main.bundleURL.standardizedFileURL.path
        let homeApplications = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications", isDirectory: true).path
        return path.hasPrefix("/Applications/") || path.hasPrefix(homeApplications + "/")
    }

    static func installIfEnabled() {
        guard UserDefaults.standard.bool(forKey: enabledKey) else { return }
        _ = install()
    }

    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        UserDefaults.standard.set(enabled, forKey: enabledKey)
        return enabled ? install() : uninstall()
    }

    @discardableResult
    static func install() -> Bool {
        guard isStableInstall, let executable = Bundle.main.executableURL else { return false }
        let fileManager = FileManager.default
        let directory = plistURL.deletingLastPathComponent()
        let plist: [String: Any] = [
            "Label": identifier,
            "ProgramArguments": [executable.path, "--background-refresh"],
            "RunAtLoad": true,
            "StartInterval": Int(interval),
            "ThrottleInterval": 60,
            "ProcessType": "Background",
            "LowPriorityIO": true,
            "Nice": 10,
            "AbandonProcessGroup": true
        ]

        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            if (try? Data(contentsOf: plistURL)) == data, isLoaded { return true }
            if isLoaded { _ = launchctl(["bootout", domain, plistURL.path]) }
            try data.write(to: plistURL, options: .atomic)
            guard launchctl(["bootstrap", domain, plistURL.path]) == 0 else { return false }
            _ = launchctl(["kickstart", "-k", service])
            return isLoaded
        } catch {
            return false
        }
    }

    @discardableResult
    static func uninstall() -> Bool {
        if isLoaded { _ = launchctl(["bootout", domain, plistURL.path]) }
        try? FileManager.default.removeItem(at: plistURL)
        return !FileManager.default.fileExists(atPath: plistURL.path) && !isLoaded
    }

    static func status() -> BackgroundRefreshAgentStatus {
        BackgroundRefreshAgentStatus(
            enabled: UserDefaults.standard.bool(forKey: enabledKey),
            installed: FileManager.default.fileExists(atPath: plistURL.path),
            loaded: isLoaded,
            lastSuccess: loadRecord()?.lastSuccess
        )
    }

    static func saveRecord(_ record: BackgroundRefreshRecord) {
        do {
            try FileManager.default.createDirectory(
                at: CodexUsageSnapshotStore.backgroundStatusURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try JSONEncoder().encode(record).write(to: CodexUsageSnapshotStore.backgroundStatusURL, options: .atomic)
        } catch {
            // Status is diagnostic only; a failed status write must not fail refresh.
        }
    }

    static func loadRecord() -> BackgroundRefreshRecord? {
        guard let data = try? Data(contentsOf: CodexUsageSnapshotStore.backgroundStatusURL) else { return nil }
        return try? JSONDecoder().decode(BackgroundRefreshRecord.self, from: data)
    }

    private static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(identifier).plist")
    }

    private static var domain: String { "gui/\(getuid())" }
    private static var service: String { "\(domain)/\(identifier)" }
    private static var isLoaded: Bool { launchctl(["print", service]) == 0 }

    private static func launchctl(_ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        } catch {
            return -1
        }
    }
}
