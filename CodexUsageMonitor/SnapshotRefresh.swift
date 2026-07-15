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

    static func run() -> CodexUsageSnapshot? {
        let startedAt = Date()
        guard let lock = RefreshLock.acquire() else {
            return CodexUsageSnapshotStore.load()
        }
        defer { lock.release() }

        let previous = CodexUsageSnapshotStore.load()
        let previousRecord = BackgroundRefreshAgent.loadRecord()
        let reader = CodexUsageReader()
        let headroomCollector = HeadroomSavingsCollector()
        let fingerprint = reader.sourceFingerprint() + "|" + headroomCollector.sourceFingerprint()
        let candidate: CodexUsageSnapshot?

        if previousRecord?.sourceFingerprint == fingerprint, var cached = previous {
            let now = Date()
            cached.generatedAt = now
            if var limits = cached.rateLimits {
                if limits.fiveHour?.isCurrent(at: now) != true { limits.fiveHour = nil }
                if limits.weekly?.isCurrent(at: now) != true { limits.weekly = nil }
                cached.rateLimits = limits
            }
            candidate = cached
        } else {
            let headroom = headroomCollector.collect() ?? previous?.cachedHeadroomActivity
            let snapshot = reader.snapshot(headroomActivity: headroom)
            candidate = snapshot.hasUsage ? snapshot : previous
        }

        guard let candidate, CodexUsageSnapshotStore.save(candidate) else {
            let error = "Could not save the refreshed snapshot."
            BackgroundRefreshAgent.saveRecord(
                BackgroundRefreshRecord(
                    lastAttempt: startedAt,
                    lastSuccess: BackgroundRefreshAgent.loadRecord()?.lastSuccess,
                    durationSeconds: Date().timeIntervalSince(startedAt),
                    error: error,
                    sourceFingerprint: fingerprint
                )
            )
            logger.error("\(error, privacy: .public)")
            return nil
        }

        WidgetCenter.shared.reloadTimelines(ofKind: "CodexUsageWidget")
        LimitNotificationManager.evaluate(candidate)
        BackgroundRefreshAgent.saveRecord(
            BackgroundRefreshRecord(
                lastAttempt: startedAt,
                lastSuccess: Date(),
                durationSeconds: Date().timeIntervalSince(startedAt),
                error: nil,
                sourceFingerprint: fingerprint
            )
        )
        NotificationCenter.default.post(name: .codexUsageSnapshotDidChange, object: nil)
        logger.debug("Snapshot refreshed in \(Date().timeIntervalSince(startedAt), privacy: .public) seconds")
        return candidate
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
