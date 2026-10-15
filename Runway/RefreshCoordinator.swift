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

    static let shared = RefreshCoordinator()

    private struct Flight {
        var id: UUID
        var force: Bool
        var task: Task<RefreshResult, Never>
    }

    private let engine: Engine
    private var inFlight: Flight?

    init(engine: @escaping Engine = { trigger, force in
        await Task.detached(priority: .utility) {
            SnapshotRefresh.run(trigger: trigger, force: force)
        }.value
    }) {
        self.engine = engine
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

    private func finish(_ flight: Flight) async -> RefreshResult {
        let result = await flight.task.value
        if inFlight?.id == flight.id {
            inFlight = nil
        }
        return result
    }
}
