import Foundation

@main
struct OnboardingStateStoreCheck {
    static func main() throws {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let url = directory.appendingPathComponent("onboarding.json")
        defer { try? fileManager.removeItem(at: directory) }

        precondition(OnboardingStateStore.shouldPresent(appVersion: "2.0.3", from: url))

        let complete = OnboardingState(
            lastPresentedVersion: "2.0.3",
            completedRequirements: Set(SetupRequirement.allCases),
            dismissedUpdateChecklistVersion: nil,
            updatedAt: Date(timeIntervalSince1970: 1)
        )
        OnboardingStateStore.save(complete, to: url)
        precondition(!OnboardingStateStore.shouldPresent(appVersion: "2.0.3", from: url))
        precondition(OnboardingStateStore.completedCurrentVersion(appVersion: "2.0.3", from: url))
        precondition(OnboardingStateStore.shouldPresent(appVersion: "2.0.4", from: url))
        precondition(!OnboardingStateStore.hasCurrentCodexDataAccess(appVersion: "2.0.4", state: complete))

        var dismissed = complete
        dismissed.lastPresentedVersion = "2.0.4"
        dismissed.completedRequirements.remove(.widgetRegistration)
        dismissed.dismissedUpdateChecklistVersion = "2.0.4"
        OnboardingStateStore.save(dismissed, to: url)
        precondition(!OnboardingStateStore.shouldPresent(appVersion: "2.0.4", from: url))
        precondition(!OnboardingStateStore.completedCurrentVersion(appVersion: "2.0.4", from: url))

        var incomplete = complete
        incomplete.completedRequirements.remove(.backgroundRefresh)
        OnboardingStateStore.save(incomplete, to: url)
        precondition(!OnboardingStateStore.completedCurrentVersion(appVersion: "2.0.3", from: url))

        try Data("not json".utf8).write(to: url, options: .atomic)
        precondition(OnboardingStateStore.shouldPresent(appVersion: "2.0.3", from: url))
        print("OnboardingStateStoreCheck passed")
    }
}
