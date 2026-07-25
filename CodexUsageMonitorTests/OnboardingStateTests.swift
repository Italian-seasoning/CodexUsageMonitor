import Foundation
import Testing
@testable import CodexUsageMonitor

@Suite
struct OnboardingStateTests {
    @Test("Completed schema-1 users retain every setup requirement")
    func migratesCompletedSchemaOneState() throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "schemaVersion": 1,
            "lastPresentedVersion": "1.4",
            "completed": true,
            "updatedAt": 0,
        ])
        let state = try JSONDecoder().decode(OnboardingState.self, from: data)

        #expect(state.schemaVersion == OnboardingState.currentSchemaVersion)
        #expect(state.completedRequirements == Set(SetupRequirement.allCases))
        #expect(state.lastPresentedVersion == "1.4")
    }

    @MainActor
    @Test("Requesting access changes state synchronously")
    func requestingStateIsSynchronous() {
        let model = OnboardingModel(
            appVersion: "2.0",
            state: .empty,
            save: { _ in },
            probe: {
                try? await Task.sleep(for: .seconds(1))
                return .approved
            }
        )

        model.requestAccess()

        #expect(model.dataAccessState == .requesting)
    }

    @MainActor
    @Test("Installing background refresh cannot grant Codex access")
    func backgroundRefreshDoesNotGrantAccess() {
        let model = OnboardingModel(
            appVersion: "2.0",
            state: .empty,
            save: { _ in },
            probe: { .approved }
        )

        model.recordBackgroundRefresh(installed: true)

        #expect(model.state.completedRequirements == [.backgroundRefresh])
        #expect(model.dataAccessState == .notRequested)
    }

    @MainActor
    @Test("A failed service recheck revokes stale completion")
    func failedServiceRecheckRevokesCompletion() {
        let model = OnboardingModel(
            appVersion: "2.0",
            state: OnboardingState(
                lastPresentedVersion: "2.0",
                completedRequirements: Set(SetupRequirement.allCases),
                dismissedUpdateChecklistVersion: nil,
                updatedAt: .now
            ),
            save: { _ in },
            probe: { .approved }
        )

        model.recordBackgroundRefresh(installed: false)
        model.recordWidgetRegistration(registered: false)

        #expect(model.unmetRequirements == [.backgroundRefresh, .widgetRegistration])
    }

    @MainActor
    @Test("Denied and failed access remain on the permission page")
    func unresolvedAccessStaysOnPermissionPage() async {
        let failed = OnboardingModel(
            appVersion: "2.0",
            state: .empty,
            save: { _ in },
            probe: { .failed("Unreadable") }
        )

        failed.requestAccess()
        while failed.dataAccessState == .requesting {
            await Task.yield()
        }

        #expect(failed.dataAccessState == .failed("Unreadable"))
        #expect(failed.page == 1)
        #expect(!failed.state.completedRequirements.contains(.codexDataAccess))

        let denied = OnboardingModel(
            appVersion: "2.0",
            state: .empty,
            save: { _ in },
            probe: { .needsManualAction("Permission required") }
        )
        denied.requestAccess()
        while denied.dataAccessState == .requesting {
            await Task.yield()
        }

        #expect(denied.dataAccessState == .needsManualAction("Permission required"))
        #expect(denied.page == 1)
        #expect(!denied.state.completedRequirements.contains(.codexDataAccess))
    }

    @MainActor
    @Test("Skipping records dismissal without completing requirements")
    func skippingDoesNotCompleteRequirements() {
        var saved: OnboardingState?
        let model = OnboardingModel(
            appVersion: "2.0",
            state: .empty,
            save: { saved = $0 },
            probe: { .approved }
        )

        model.skip()

        #expect(saved?.dismissedUpdateChecklistVersion == "2.0")
        #expect(saved?.completedRequirements.isEmpty == true)
        #expect(!model.isPresented)
    }
}

private extension OnboardingState {
    static var empty: Self {
        OnboardingState(
            schemaVersion: currentSchemaVersion,
            lastPresentedVersion: "",
            completedRequirements: [],
            dismissedUpdateChecklistVersion: nil,
            updatedAt: .distantPast
        )
    }
}
