import Foundation
import WidgetKit

@main
struct RefreshSnapshot {
    static func main() {
        let previous = CodexUsageSnapshotStore.load()
        let headroom = HeadroomSavingsCollector().collect() ?? previous?.cachedHeadroomActivity
        let snapshot = CodexUsageReader().snapshot(headroomActivity: headroom)
        if snapshot.hasUsage {
            CodexUsageSnapshotStore.save(snapshot)
        } else if previous == nil {
            CodexUsageSnapshotStore.save(snapshot)
        }
        CodexUsageSnapshotStore.saveAllSettings(CodexUsageSnapshotStore.loadAllSettings())
        WidgetCenter.shared.reloadTimelines(ofKind: "CodexUsageWidget")
        print("Wrote \(CodexUsageSnapshotStore.snapshotURL.path) · \(snapshot.sessionCount ?? 0) sessions · \(snapshot.lifetime.total) tokens")
    }
}
