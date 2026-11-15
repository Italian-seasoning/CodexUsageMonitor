import Foundation

enum RefreshTrigger: String, Codable, Sendable {
    case launch
    case foreground
    case sourceChange
    case fallbackTimer
    case manual
    case backgroundAgent
    case wake
}

enum RefreshOutcome: String, Codable, Sendable {
    case updated
    case unchanged
    case permissionRequired
    case failed
}

struct RefreshResult: @unchecked Sendable {
    var outcome: RefreshOutcome
    var snapshot: CodexUsageSnapshot?
    var message: String
}

actor RefreshCoordinator {
    typealias Engine = @Sendable (RefreshTrigger, Bool) async -> RefreshResult

    static let shared = RefreshCoordinator(isSourceAppRunning: {
        await MainActor.run { SourceChangeMonitor.isSourceAppRunning }
    })

    private struct Flight {
        var id: UUID
        var force: Bool
        var task: Task<RefreshResult, Never>
    }

    private let engine: Engine
    private var inFlight: Flight?

    init(isSourceAppRunning: @escaping @Sendable () async -> Bool = { true },
         engine: @escaping Engine = { trigger, force in
        let result = await Task.detached(priority: .utility) {
            SnapshotRefresh.run(trigger: trigger, force: force)
        }.value
        if result.outcome == .updated || result.outcome == .unchanged {
            await PhoneResetNotificationManager.scheduleIfNeeded(result.snapshot)
        }
        return result
    }) {
        self.engine = { trigger, force in
            if trigger != .manual {
                guard await isSourceAppRunning() else {
                    return RefreshResult(outcome: .unchanged, snapshot: nil,
                        message: "Automatic refresh is paused while ChatGPT and Codex are closed.")
                }
            }
            return await engine(trigger, force)
        }
    }

    func refresh(trigger: RefreshTrigger, force: Bool = false) async -> RefreshResult {
        let force = force || trigger == .manual
        if let current = inFlight {
            if force && !current.force {
                let next = makeFlight(force: true) { [engine] in
                    _ = await current.task.value
                    return await engine(trigger, true)
                }
                inFlight = next
                return await finish(next)
            }
            return await finish(current)
        }

        let next = makeFlight(force: force) { [engine] in
            await engine(trigger, force)
        }
        inFlight = next
        return await finish(next)
    }

    private func makeFlight(
        force: Bool,
        operation: @escaping @Sendable () async -> RefreshResult
    ) -> Flight {
        Flight(id: UUID(), force: force, task: Task(operation: operation))
    }

    func refreshAfterSourceChange() async -> RefreshResult {
        // A source event can arrive after the current pass already read its fingerprint.
        if let current = inFlight { _ = await finish(current) }
        return await refresh(trigger: .sourceChange)
    }

    private func finish(_ flight: Flight) async -> RefreshResult {
        let result = await flight.task.value
        if inFlight?.id == flight.id {
            inFlight = nil
        }
        return result
    }
}
