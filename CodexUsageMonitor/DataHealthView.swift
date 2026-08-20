import SwiftUI

enum SnapshotHealthKind: Equatable {
    case noUsage
    case refreshing
    case freshComplete
    case freshPartial
    case staleCached
    case permissionRequired
    case sourceUnavailable
    case error
}

struct SnapshotHealth: Equatable {
    var kind: SnapshotHealthKind
    var detail: String

    init(snapshot: CodexUsageSnapshot, record: BackgroundRefreshRecord?, isRefreshing: Bool) {
        if isRefreshing {
            kind = .refreshing
            detail = "Reading local Codex sources"
        } else if record?.outcome == .permissionRequired {
            kind = .permissionRequired
            detail = record?.error ?? "Codex data needs permission"
        } else if record?.outcome == .failed {
            kind = .error
            detail = record?.error ?? "The last refresh failed"
        } else if !snapshot.hasUsage {
            kind = record == nil ? .noUsage : .sourceUnavailable
            detail = record == nil ? "No recorded usage yet" : "No readable usage source was found"
        } else if let generatedAt = snapshot.generatedAt,
                  Date().timeIntervalSince(generatedAt) > 10 * 60 {
            kind = .staleCached
            detail = "Showing the latest cached snapshot"
        } else if snapshot.rateLimits == nil || (snapshot.modelUsage ?? []).isEmpty {
            kind = .freshPartial
            detail = "Valid usage is available; some sources are missing"
        } else {
            kind = .freshComplete
            detail = "All primary sources are current"
        }
    }

    var title: String {
        switch kind {
        case .noUsage: "No usage"
        case .refreshing: "Refreshing"
        case .freshComplete: "Fresh"
        case .freshPartial: "Fresh · Partial"
        case .staleCached: "Stale · Cached"
        case .permissionRequired: "Permission required"
        case .sourceUnavailable: "Source unavailable"
        case .error: "Error"
        }
    }

    var symbol: String {
        switch kind {
        case .noUsage: "circle.dashed"
        case .refreshing: "arrow.trianglehead.2.clockwise.rotate.90"
        case .freshComplete: "checkmark.circle.fill"
        case .freshPartial: "circle.lefthalf.filled"
        case .staleCached: "clock.badge.exclamationmark"
        case .permissionRequired: "lock.trianglebadge.exclamationmark"
        case .sourceUnavailable: "externaldrive.badge.xmark"
        case .error: "exclamationmark.triangle.fill"
        }
    }

    @MainActor var color: Color {
        switch kind {
        case .freshComplete: .green
        case .refreshing, .freshPartial: AppPalette.accent
        case .noUsage, .staleCached, .sourceUnavailable: .secondary
        case .permissionRequired: .orange
        case .error: .red
        }
    }
}

struct DataHealthView: View {
    @Binding var snapshot: CodexUsageSnapshot
    @Binding var record: BackgroundRefreshRecord?
    @Binding var isRefreshing: Bool
    @State private var message = "Using the latest stored refresh record."

    private var health: SnapshotHealth {
        SnapshotHealth(snapshot: snapshot, record: record, isRefreshing: isRefreshing)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 9) {
                Image(systemName: health.symbol)
                    .foregroundStyle(health.color)
                VStack(alignment: .leading, spacing: 1) {
                    Text(health.title).font(.headline)
                    Text(health.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            healthRow("Last success", date: record?.lastSuccess)
            healthRow("Snapshot", date: snapshot.generatedAt)
            healthRow("Widget reload", date: record?.widgetReloadRequestedAt)
            LabeledContent("Source") {
                Text(sourceLabel)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .font(.caption)

            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                refresh()
            } label: {
                Label(isRefreshing ? "Refreshing…" : "Refresh now", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isRefreshing)
            .accessibilityHint("Waits for local sources and WidgetKit to finish refreshing")
        }
        .padding(16)
        .frame(width: 320)
    }

    private var sourceLabel: String {
        if record?.outcome == .permissionRequired { return "Permission blocked" }
        if record?.sourceFingerprint == nil { return "Not detected" }
        return record?.outcome == .failed ? "Read failed" : "Local Codex logs"
    }

    @ViewBuilder
    private func healthRow(_ label: String, date: Date?) -> some View {
        LabeledContent(label) {
            Text(date?.formatted(date: .abbreviated, time: .shortened) ?? "Never")
                .foregroundStyle(.secondary)
        }
        .font(.caption)
    }

    private func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        message = "Reading Codex logs and updating WidgetKit…"
        Task {
            let result = await RefreshCoordinator.shared.refresh(trigger: .manual, force: true)
            if let refreshed = result.snapshot {
                snapshot = refreshed
            }
            record = BackgroundRefreshAgent.loadRecord()
            message = result.message
            isRefreshing = false
        }
    }
}
