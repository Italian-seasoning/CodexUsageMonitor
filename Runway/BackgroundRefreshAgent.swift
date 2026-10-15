import Darwin
import Foundation

struct BackgroundRefreshRecord: Codable, Equatable {
    var lastAttempt: Date
    var lastSuccess: Date?
    var outcome: RefreshOutcome? = nil
    var durationSeconds: Double
    var error: String?
    var sourceFingerprint: String? = nil
    var widgetReloadRequestedAt: Date? = nil
    var widgetSyncPending: Bool? = nil
    var widgetReloadPending: Bool? = nil
    var lastAccountAttempt: Date? = nil
    var lastAccountSuccess: Date? = nil

    mutating func recordWidgetReload(succeeded: Bool, at date: Date = .now) {
        widgetSyncPending = !succeeded
        widgetReloadPending = !succeeded
        if succeeded { widgetReloadRequestedAt = date }
    }
}

struct BackgroundRefreshAgentStatus: Sendable {
    var enabled: Bool
    var installed: Bool
    var loaded: Bool
    var lastSuccess: Date?

    var detail: String {
        if !enabled { return "Off" }
        if !BackgroundRefreshAgent.isStableInstall {
            return installed ? "Managed by the installed app" : "Move the app to Applications first"
        }
        if !installed || !loaded { return "Needs repair" }
        guard let lastSuccess else { return "Scheduled every minute" }
        return "Last refreshed \(lastSuccess.formatted(date: .omitted, time: .shortened))"
    }
}

enum BackgroundRefreshAgent {
    static let identifier = "com.codexusage.Runway.refresh"
    static let legacyIdentifier = "com.codexusage.CodexUsageMonitor.refresh"
    static let interval: TimeInterval = 60

    static var isStableInstall: Bool {
        let path = Bundle.main.bundleURL.standardizedFileURL.path
        let homeApplications = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications", isDirectory: true).path
        return path.hasPrefix("/Applications/") || path.hasPrefix(homeApplications + "/")
    }

    static func installIfEnabled() {
        if CodexUsageSettingsStore.load().settings.backgroundRefreshEnabled {
            _ = install()
        } else {
            _ = uninstall()
        }
    }

    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        return enabled ? install() : uninstall()
    }

    @discardableResult
    static func install() -> Bool {
        guard canManageInstalledAgents,
              removeAgent(identifier: legacyIdentifier),
              OnboardingStateStore.hasCurrentCodexDataAccess(),
              let executable = Bundle.main.executableURL
        else {
            return false
        }
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
            return isLoaded
        } catch {
            return false
        }
    }

    @discardableResult
    static func uninstall() -> Bool {
        guard canManageInstalledAgents else { return false }
        let legacyRemoved = removeAgent(identifier: legacyIdentifier)
        let currentRemoved = removeAgent(identifier: identifier)
        return legacyRemoved && currentRemoved
    }

    static func canManageAgents(bundleIdentifier: String?, isStableInstall: Bool) -> Bool {
        isStableInstall && bundleIdentifier == "com.codexusage.CodexUsageMonitor"
    }

    private static var canManageInstalledAgents: Bool {
        canManageAgents(bundleIdentifier: Bundle.main.bundleIdentifier, isStableInstall: isStableInstall)
    }

    private static func removeAgent(identifier: String) -> Bool {
        removeAgent(identifier: identifier, directory: plistURL.deletingLastPathComponent(),
            domain: domain, allowed: canManageInstalledAgents, run: launchctl)
    }

    /// Use the service label so upgrades can stop a loaded job whose plist was moved or removed.
    /// Keep its registration file intact if launchctl cannot confirm the job was stopped.
    static func removeAgent(identifier: String, directory: URL, domain: String,
                            allowed: Bool, run: ([String]) -> Int32) -> Bool {
        guard allowed else { return false }
        let service = "\(domain)/\(identifier)"
        let status = run(["print", service])
        // `launchctl print` uses 113 for a missing service; other failures do not prove it is gone.
        let serviceNotFound: Int32 = 113
        guard status == 0 || status == serviceNotFound else { return false }
        if status == 0 {
            guard run(["bootout", service]) == 0,
                  run(["print", service]) == serviceNotFound else { return false }
        }
        do {
            try FileManager.default.removeItem(at: directory.appendingPathComponent("\(identifier).plist"))
            return true
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
            return true
        } catch {
            return false
        }
    }

    static func status() -> BackgroundRefreshAgentStatus {
        BackgroundRefreshAgentStatus(
            enabled: CodexUsageSettingsStore.load().settings.backgroundRefreshEnabled,
            installed: isStableInstall
                ? targetsCurrentExecutable
                : FileManager.default.fileExists(atPath: plistURL.path),
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

    private static var targetsCurrentExecutable: Bool {
        guard let executable = Bundle.main.executableURL?.standardizedFileURL.path,
              let data = try? Data(contentsOf: plistURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let arguments = plist["ProgramArguments"] as? [String]
        else {
            return false
        }
        return arguments.first.map { URL(fileURLWithPath: $0).standardizedFileURL.path } == executable
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
