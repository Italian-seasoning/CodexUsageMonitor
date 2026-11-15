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

enum BackgroundRefreshAgent {
    static let identifier = "com.codexusage.Runway.refresh"
    static let legacyIdentifier = "com.codexusage.CodexUsageMonitor.refresh"

    static var isStableInstall: Bool {
        let path = Bundle.main.bundleURL.standardizedFileURL.path
        let homeApplications = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications", isDirectory: true).path
        return path.hasPrefix("/Applications/") || path.hasPrefix(homeApplications + "/")
    }

    @discardableResult
    static func uninstall() -> Bool {
        guard canManageInstalledAgents else { return false }
        let ownService = ProcessInfo.processInfo.environment["XPC_SERVICE_NAME"]
        // A launchd-invoked migration must boot out its own job last: that terminates this process.
        let labels: [String] = ownService == legacyIdentifier
            ? [identifier, legacyIdentifier] : [legacyIdentifier, identifier]
        var removed = true
        for label in labels {
            let result = removeAgent(identifier: label, directory: plistURL.deletingLastPathComponent(),
                domain: domain, allowed: true, isOwnService: label == ownService, run: launchctl)
            removed = result && removed
        }
        return removed
    }

    static func canManageAgents(bundleIdentifier: String?, isStableInstall: Bool) -> Bool {
        isStableInstall && bundleIdentifier == "com.codexusage.CodexUsageMonitor"
    }

    private static var canManageInstalledAgents: Bool {
        canManageAgents(bundleIdentifier: Bundle.main.bundleIdentifier, isStableInstall: isStableInstall)
    }

    /// Use the service label so upgrades can stop a loaded job whose plist was moved or removed.
    /// Keep its registration file intact if launchctl cannot confirm the job was stopped.
    static func removeAgent(identifier: String, directory: URL, domain: String,
                            allowed: Bool, isOwnService: Bool = false, run: ([String]) -> Int32) -> Bool {
        guard allowed else { return false }
        let service = "\(domain)/\(identifier)"
        let status = run(["print", service])
        // `launchctl print` uses 113 for a missing service; other failures do not prove it is gone.
        let serviceNotFound: Int32 = 113
        guard status == 0 || status == serviceNotFound else { return false }
        let registrationURL = directory.appendingPathComponent("\(identifier).plist")
        let registration = isOwnService ? try? Data(contentsOf: registrationURL) : nil
        if isOwnService && FileManager.default.fileExists(atPath: registrationURL.path) {
            // Self-bootout may never return, so remove the recurring registration first.
            guard registration != nil else { return false }
            do { try FileManager.default.removeItem(at: registrationURL) } catch { return false }
        }
        if status == 0 {
            guard run(["bootout", service]) == 0,
                  run(["print", service]) == serviceNotFound else {
                if isOwnService, let registration { try? registration.write(to: registrationURL, options: .atomic) }
                return false
            }
        }
        do {
            try FileManager.default.removeItem(at: registrationURL)
            return true
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
            return true
        } catch {
            return false
        }
    }

    static func saveRecord(_ record: BackgroundRefreshRecord) {
        do {
            try FileManager.default.createDirectory(
                at: CodexUsageSnapshotStore.backgroundStatusURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try JSONEncoder().encode(record).write(to: CodexUsageSnapshotStore.backgroundStatusURL, options: .atomic)
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .codexUsageSnapshotDidChange, object: nil)
            }
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
