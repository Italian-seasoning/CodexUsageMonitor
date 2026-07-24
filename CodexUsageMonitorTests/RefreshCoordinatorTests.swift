import Foundation
import Testing
@testable import CodexUsageMonitor

@Suite
struct RefreshCoordinatorTests {
    @Test("Simultaneous refresh requests share one engine pass")
    func coalescesSimultaneousRequests() async {
        let calls = CallRecorder()
        let coordinator = RefreshCoordinator { trigger, force in
            await calls.record(trigger: trigger, force: force)
            try? await Task.sleep(for: .milliseconds(50))
            return RefreshResult(outcome: .updated, snapshot: nil, message: "updated")
        }

        await withTaskGroup(of: RefreshResult.self) { group in
            for _ in 0..<10 {
                group.addTask {
                    await coordinator.refresh(trigger: .sourceChange)
                }
            }
            for await result in group {
                #expect(result.outcome == .updated)
            }
        }

        #expect(await calls.count == 1)
    }

    @Test("Manual refresh always reaches the engine as forced")
    func manualRefreshIsForced() async {
        let calls = CallRecorder()
        let coordinator = RefreshCoordinator { trigger, force in
            await calls.record(trigger: trigger, force: force)
            return RefreshResult(outcome: .updated, snapshot: nil, message: "updated")
        }

        _ = await coordinator.refresh(trigger: .manual)

        #expect(await calls.values == [RecordedCall(trigger: .manual, force: true)])
    }

    @Test("A forced request behind an unforced pass queues one follow-up")
    func queuesOneForcedFollowUp() async {
        let calls = CallRecorder()
        let coordinator = RefreshCoordinator { trigger, force in
            await calls.record(trigger: trigger, force: force)
            try? await Task.sleep(for: .milliseconds(40))
            return RefreshResult(outcome: .updated, snapshot: nil, message: "updated")
        }

        async let background = coordinator.refresh(trigger: .backgroundAgent)
        while await calls.count == 0 {
            await Task.yield()
        }
        async let firstManual = coordinator.refresh(trigger: .manual)
        async let secondManual = coordinator.refresh(trigger: .manual)
        _ = await [background, firstManual, secondManual]

        #expect(await calls.count == 2)
        #expect(await calls.values.last?.force == true)
    }

    @Test("Matching fingerprints make an unforced background pass unchanged")
    func matchingFingerprintIsUnchanged() async {
        let coordinator = RefreshCoordinator { trigger, force in
            let unchanged = SnapshotRefresh.canReuseSnapshot(
                previousFingerprint: "same",
                currentFingerprint: "same",
                hasSnapshot: true,
                force: force
            )
            return RefreshResult(
                outcome: trigger == .backgroundAgent && unchanged ? .unchanged : .updated,
                snapshot: nil,
                message: "complete"
            )
        }

        let result = await coordinator.refresh(trigger: .backgroundAgent)

        #expect(result.outcome == .unchanged)
    }
}

private struct RecordedCall: Equatable {
    var trigger: RefreshTrigger
    var force: Bool
}

private actor CallRecorder {
    private(set) var values: [RecordedCall] = []
    var count: Int { values.count }

    func record(trigger: RefreshTrigger, force: Bool) {
        values.append(RecordedCall(trigger: trigger, force: force))
    }
}
