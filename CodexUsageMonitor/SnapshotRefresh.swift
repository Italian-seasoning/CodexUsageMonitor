import Darwin
import Foundation
import OSLog
import WidgetKit

extension Notification.Name {
    static let codexUsageSnapshotDidChange = Notification.Name("codexUsageSnapshotDidChange")
}

enum CodexWidgetReloader {
    private static let logger = Logger(subsystem: "com.codexusage.CodexUsageMonitor", category: "WidgetRefresh")

    @discardableResult
    static func reloadAll() -> Bool {
        guard WidgetDataBridge.syncToWidgetExtension() else {
            logger.error("Could not synchronize local widget data into the widget extension container")
            return false
        }
        WidgetCenter.shared.reloadTimelines(ofKind: CodexWidgetKind.primary)
        return true
    }
}

enum SnapshotRefresh {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.codexusage.CodexUsageMonitor",
        category: "BackgroundRefresh"
    )

    static func run(trigger: RefreshTrigger, force: Bool = false) -> RefreshResult {
        autoreleasepool { performRefresh(trigger: trigger, force: force) }
    }

    private static func performRefresh(trigger: RefreshTrigger, force: Bool) -> RefreshResult {
        let startedAt = Date()
        if !OnboardingStateStore.hasCurrentCodexDataAccess() {
            let message = "Codex data access has not been approved."
            saveRecord(
                startedAt: startedAt,
                outcome: .permissionRequired,
                message: message,
                fingerprint: nil,
                widgetReloadRequestedAt: nil
            )
            return RefreshResult(outcome: .permissionRequired, snapshot: nil, message: message)
        }

        guard let lock = RefreshLock.acquire() else {
            return RefreshResult(
                outcome: .unchanged,
                snapshot: CodexUsageSnapshotStore.load(),
                message: "Another refresh process is already running."
            )
        }
        defer { lock.release() }

        let previous = CodexUsageSnapshotStore.load()
        let previousRecord = BackgroundRefreshAgent.loadRecord()
        let reader = CodexUsageReader()
        let headroomCollector = HeadroomSavingsCollector()
        let fingerprint = reader.sourceFingerprint() + "|legacy-history-v1|" + ModelPricingCatalog.version + headroomCollector.sourceFingerprint()
        let reuseCached = canReuseSnapshot(
            previousFingerprint: previousRecord?.sourceFingerprint,
            currentFingerprint: fingerprint,
            hasSnapshot: previous != nil,
            force: force
        ) && previous?.generatedAt.map { Calendar.current.isDate($0, inSameDayAs: startedAt) } == true
        var candidate: CodexUsageSnapshot?
        var outcome: RefreshOutcome

        if reuseCached, var cached = previous {
            let now = Date()
            cached.generatedAt = now
            if var limits = cached.rateLimits {
                if limits.fiveHour?.isCurrent(at: now) != true { limits.fiveHour = nil }
                if limits.weekly?.isCurrent(at: now) != true { limits.weekly = nil }
                cached.rateLimits = limits
            }
            candidate = cached
            outcome = .unchanged
        } else {
            let headroom = headroomCollector.collect() ?? previous?.cachedHeadroomActivity
            let snapshot = reader.snapshot(headroomActivity: headroom)
                .mergingLegacyHistory(CodexUsageSnapshotStore.loadLegacyHistory())
            if snapshot.hasUsage {
                candidate = snapshot
                outcome = .updated
            } else if let previous, previous.hasUsage {
                let message = "No readable Codex usage was found. Keeping the last successful snapshot."
                saveRecord(startedAt: startedAt, outcome: .failed, message: message,
                    fingerprint: nil, widgetReloadRequestedAt: nil)
                return RefreshResult(outcome: .failed, snapshot: previous, message: message)
            } else {
                candidate = previous
                outcome = .unchanged
            }
        }

        guard var candidate else {
            let message = "No Codex usage was found and no previous snapshot is available."
            saveRecord(
                startedAt: startedAt,
                outcome: .failed,
                message: message,
                fingerprint: fingerprint,
                widgetReloadRequestedAt: nil
            )
            logger.error("\(message, privacy: .public)")
            return RefreshResult(outcome: .failed, snapshot: nil, message: message)
        }

        let shouldReadAccount = shouldReadAccount(lastAttempt: previousRecord?.lastAccountAttempt, trigger: trigger, now: startedAt)
        let account = shouldReadAccount ? CodexAccountReader.read() : nil
        candidate.rateLimits = mergedLimits(local: candidate.rateLimits, previous: previous?.rateLimits,
            account: account?.rateLimits, now: Date())
        if let account {
            candidate.accountLifetimeTokens = account.lifetimeTokens ?? previous?.accountLifetimeTokens
            if candidate.accountLifetimeTokens != previous?.accountLifetimeTokens
                || candidate.rateLimits?.fiveHour?.usedPercent != previous?.rateLimits?.fiveHour?.usedPercent
                || candidate.rateLimits?.weekly?.usedPercent != previous?.rateLimits?.weekly?.usedPercent
                || candidate.rateLimits?.fiveHour?.resetsAt != previous?.rateLimits?.fiveHour?.resetsAt
                || candidate.rateLimits?.weekly?.resetsAt != previous?.rateLimits?.weekly?.resetsAt {
                outcome = .updated
            }
        } else {
            candidate.accountLifetimeTokens = previous?.accountLifetimeTokens
        }
        if candidate.rateLimits != previous?.rateLimits { outcome = .updated }

        // Refresh names even when token logs are unchanged: chat renames live in a separate index.
        let namesURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/session_index.jsonl")
        let namedCandidate = CodexSessionNames.applying(to: candidate, from: namesURL)
        if namedCandidate.sessionActivity != candidate.sessionActivity
            || namedCandidate.recentSessions != candidate.recentSessions { outcome = .updated }
        candidate = namedCandidate
        candidate.appearanceTheme = CodexUsageSettingsStore.load().settings.appTheme.rawValue
        if candidate.appearanceTheme != previous?.appearanceTheme { outcome = .updated }
        guard CodexUsageSnapshotStore.save(candidate) else {
            let message = "Could not save the refreshed snapshot."
            saveRecord(
                startedAt: startedAt,
                outcome: .failed,
                message: message,
                fingerprint: fingerprint,
                widgetReloadRequestedAt: nil
            )
            logger.error("\(message, privacy: .public)")
            return RefreshResult(outcome: .failed, snapshot: previous, message: message)
        }

        let shouldReloadWidget = shouldReloadWidget(
            outcome: outcome,
            trigger: trigger,
            syncPending: previousRecord?.widgetSyncPending == true,
            lastRequested: previousRecord?.widgetReloadRequestedAt
        )
        // Keep the heartbeat current even when WidgetKit does not need a redraw.
        let widgetSynced = shouldReloadWidget
            ? CodexWidgetReloader.reloadAll()
            : WidgetDataBridge.syncToWidgetExtension()
        let widgetReloaded = shouldReloadWidget && widgetSynced
        let widgetReloadRequestedAt = widgetReloaded ? Date() : nil
        LimitNotificationManager.evaluate(candidate)
        saveRecord(
            startedAt: startedAt,
            outcome: outcome,
            message: nil,
            fingerprint: fingerprint,
            widgetReloadRequestedAt: widgetReloadRequestedAt,
            widgetSyncPending: !widgetSynced,
            lastAccountAttempt: shouldReadAccount ? startedAt : previousRecord?.lastAccountAttempt,
            lastAccountSuccess: account != nil ? Date() : previousRecord?.lastAccountSuccess
        )
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .codexUsageSnapshotDidChange, object: nil)
        }
        let message = outcome == .updated
            ? "Snapshot refreshed with the latest Codex data."
            : "Sources are unchanged; the cached snapshot remains current."
        logger.debug("Snapshot refresh \(outcome.rawValue, privacy: .public) in \(Date().timeIntervalSince(startedAt), privacy: .public) seconds")
        return RefreshResult(outcome: outcome, snapshot: candidate, message: message)
    }

    static func canReuseSnapshot(
        previousFingerprint: String?,
        currentFingerprint: String,
        hasSnapshot: Bool,
        force: Bool
    ) -> Bool {
        !force && hasSnapshot && previousFingerprint == currentFingerprint
    }

    static func shouldReadAccount(lastAttempt: Date?, trigger: RefreshTrigger, now: Date) -> Bool {
        trigger == .manual || trigger == .wake || trigger == .launch
            || lastAttempt.map { now.timeIntervalSince($0) >= 60 } != false
    }

    static func mergedLimits(local: CodexRateLimits?, previous: CodexRateLimits?, account: CodexRateLimits?, now: Date) -> CodexRateLimits? {
        guard local != nil || previous != nil || account != nil else { return nil }
        var result = local ?? previous ?? CodexRateLimits(fiveHour: nil, weekly: nil, history: [])
        if let account {
            // Missing windows in a successful account response are authoritative.
            result.fiveHour = account.fiveHour
            result.weekly = account.weekly
            result.accountObservedAt = now
        } else if let checked = previous?.accountObservedAt {
            result.accountObservedAt = checked
            if result.fiveHour.map({ $0.observedAt > checked }) != true { result.fiveHour = previous?.fiveHour }
            if result.weekly.map({ $0.observedAt > checked }) != true { result.weekly = previous?.weekly }
        }
        if result.fiveHour?.windowMinutes != 300 || result.fiveHour?.isCurrent(at: now) != true { result.fiveHour = nil }
        if result.weekly?.windowMinutes != 10_080 || result.weekly?.isCurrent(at: now) != true { result.weekly = nil }
        let samples = (previous?.consumptionSamples ?? []) + (local?.consumptionSamples ?? [])
            + [result.fiveHour, result.weekly].compactMap { $0 }
        var buckets: [String: RateLimitWindow] = [:]
        for sample in samples where sample.observedAt >= now.addingTimeInterval(-3_600) && sample.observedAt <= now {
            let key = "\(sample.windowMinutes):\(Int(sample.observedAt.timeIntervalSince1970 / 60))"
            if buckets[key].map({ $0.observedAt <= sample.observedAt }) ?? true { buckets[key] = sample }
        }
        result.consumptionSamples = buckets.values.sorted { $0.observedAt < $1.observedAt }
        return result
    }

    static func shouldReloadWidget(
        outcome: RefreshOutcome,
        trigger: RefreshTrigger,
        syncPending: Bool,
        lastRequested: Date? = nil,
        now: Date = .now
    ) -> Bool {
        if syncPending || trigger == .launch || trigger == .wake || trigger == .manual { return true }
        return outcome == .updated && lastRequested.map { now.timeIntervalSince($0) >= 60 } != false
    }

    private static func saveRecord(
        startedAt: Date,
        outcome: RefreshOutcome,
        message: String?,
        fingerprint: String?,
        widgetReloadRequestedAt: Date?,
        widgetSyncPending: Bool? = nil,
        lastAccountAttempt: Date? = nil,
        lastAccountSuccess: Date? = nil
    ) {
        let previous = BackgroundRefreshAgent.loadRecord()
        BackgroundRefreshAgent.saveRecord(
            BackgroundRefreshRecord(
                lastAttempt: startedAt,
                lastSuccess: outcome == .failed || outcome == .permissionRequired
                    ? previous?.lastSuccess
                    : Date(),
                outcome: outcome,
                durationSeconds: Date().timeIntervalSince(startedAt),
                error: message,
                sourceFingerprint: fingerprint ?? previous?.sourceFingerprint,
                widgetReloadRequestedAt: widgetReloadRequestedAt ?? previous?.widgetReloadRequestedAt,
                widgetSyncPending: widgetSyncPending ?? previous?.widgetSyncPending,
                lastAccountAttempt: lastAccountAttempt ?? previous?.lastAccountAttempt,
                lastAccountSuccess: lastAccountSuccess ?? previous?.lastAccountSuccess
            )
        )
    }
}

private final class RefreshLock {
    private let descriptor: Int32

    private init(descriptor: Int32) {
        self.descriptor = descriptor
    }

    static func acquire() -> RefreshLock? {
        let url = CodexUsageSnapshotStore.refreshLockURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let descriptor = Darwin.open(url.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { return nil }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            Darwin.close(descriptor)
            return nil
        }
        return RefreshLock(descriptor: descriptor)
    }

    func release() {
        flock(descriptor, LOCK_UN)
        Darwin.close(descriptor)
    }
}

struct CodexAccountData {
    var lifetimeTokens: Int?
    var rateLimits: CodexRateLimits?
}

enum CodexAccountReader {
    static func read() -> CodexAccountData? {
        let process = Process()
        let bundledCLI = [
            "/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex",
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex").path
        ].first { FileManager.default.isExecutableFile(atPath: $0) }
        process.executableURL = URL(fileURLWithPath: bundledCLI ?? "/usr/bin/env")
        process.arguments = bundledCLI == nil ? ["codex", "app-server"] : ["app-server"]
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + (environment["PATH"] ?? "/usr/bin:/bin")
        process.environment = environment
        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        let lock = NSLock()
        let signal = DispatchSemaphore(value: 0)
        var buffer = Data()
        var responses: [Int: [String: Any]] = [:]

        output.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            lock.lock()
            buffer.append(chunk)
            while let newline = buffer.firstIndex(of: 10) {
                let line = Data(buffer[..<newline])
                buffer.removeSubrange(...newline)
                if let object = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
                   let id = object["id"] as? Int {
                    responses[id] = object
                    signal.signal()
                }
            }
            lock.unlock()
        }
        defer {
            output.fileHandleForReading.readabilityHandler = nil
            if process.isRunning { process.terminate() }
        }
        do { try process.run() } catch { return nil }

        func send(_ object: [String: Any]) {
            guard let data = try? JSONSerialization.data(withJSONObject: object) else { return }
            input.fileHandleForWriting.write(data + Data([10]))
        }
        let deadline = Date().addingTimeInterval(5)
        func response(_ id: Int) -> [String: Any]? {
            while Date() < deadline {
                lock.lock()
                let value = responses[id]
                lock.unlock()
                if let value { return value["result"] as? [String: Any] }
                _ = signal.wait(timeout: .now() + min(0.2, deadline.timeIntervalSinceNow))
            }
            return nil
        }

        send(["id": 0, "method": "initialize", "params": ["clientInfo": ["name": "Codex Usage Monitor", "version": "2"]]])
        guard response(0) != nil else { return nil }
        send(["method": "initialized", "params": [:]])
        send(["id": 1, "method": "account/usage/read"])
        send(["id": 2, "method": "account/rateLimits/read"])
        let usage = response(1)
        let limits = response(2).flatMap { decodeRateLimits($0, now: Date()) }
        let lifetime = (usage?["summary"] as? [String: Any])?["lifetimeTokens"] as? Int

        guard lifetime != nil || limits != nil else { return nil }
        return CodexAccountData(lifetimeTokens: lifetime, rateLimits: limits)
    }

    static func decodeRateLimits(_ result: [String: Any], now: Date) -> CodexRateLimits? {
        let byID = result["rateLimitsByLimitId"] as? [String: Any]
        guard let limits = (byID?["codex"] as? [String: Any]) ?? (result["rateLimits"] as? [String: Any]) else { return nil }

        func window(_ key: String) -> RateLimitWindow? {
            guard let entry = limits[key] as? [String: Any],
                  let used = entry["usedPercent"] as? Double,
                  let minutes = entry["windowDurationMins"] as? Int,
                  let reset = entry["resetsAt"] as? TimeInterval,
                  used.isFinite, (0...100).contains(used), reset.isFinite,
                  reset > now.timeIntervalSince1970 else { return nil }
            return RateLimitWindow(usedPercent: used, windowMinutes: minutes,
                                   resetsAt: Date(timeIntervalSince1970: reset), observedAt: now)
        }
        let windows = [window("primary"), window("secondary")].compactMap { $0 }
        return CodexRateLimits(fiveHour: windows.first { $0.windowMinutes == 300 },
            weekly: windows.first { $0.windowMinutes == 10_080 }, history: [], accountObservedAt: now)
    }
}
