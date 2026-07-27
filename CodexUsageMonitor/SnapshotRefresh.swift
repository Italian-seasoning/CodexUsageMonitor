import Darwin
import Foundation
import OSLog
import WidgetKit

extension Notification.Name {
    static let codexUsageSnapshotDidChange = Notification.Name("codexUsageSnapshotDidChange")
}

enum SnapshotRefresh {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.nolankrahn.CodexUsageMonitor",
        category: "BackgroundRefresh"
    )

    static func run(trigger: RefreshTrigger, force: Bool = false) -> RefreshResult {
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
        let fingerprint = reader.sourceFingerprint() + "|" + headroomCollector.sourceFingerprint()
        let reuseCached = canReuseSnapshot(
            previousFingerprint: previousRecord?.sourceFingerprint,
            currentFingerprint: fingerprint,
            hasSnapshot: previous != nil,
            force: force
        )
        let candidate: CodexUsageSnapshot?
        let outcome: RefreshOutcome

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
            if snapshot.hasUsage {
                candidate = snapshot
                outcome = .updated
            } else {
                candidate = previous
                outcome = .unchanged
            }
        }

        guard let candidate else {
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

        WidgetCenter.shared.reloadAllTimelines()
        let widgetReloadRequestedAt = Date()
        LimitNotificationManager.evaluate(candidate)
        saveRecord(
            startedAt: startedAt,
            outcome: outcome,
            message: nil,
            fingerprint: fingerprint,
            widgetReloadRequestedAt: widgetReloadRequestedAt
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

    private static func saveRecord(
        startedAt: Date,
        outcome: RefreshOutcome,
        message: String?,
        fingerprint: String?,
        widgetReloadRequestedAt: Date?
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
                widgetReloadRequestedAt: widgetReloadRequestedAt
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
