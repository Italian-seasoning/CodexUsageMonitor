import Foundation

@main
struct OnboardingStateStoreCheck {
    static func main() throws {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let url = directory.appendingPathComponent("onboarding.json")
        defer { try? fileManager.removeItem(at: directory) }

        precondition(OnboardingStateStore.shouldPresent(appVersion: "1.2.0", from: url))
        precondition(OnboardingStateStore.markPresented(appVersion: "1.2.0", completed: true, at: Date(timeIntervalSince1970: 1), to: url))
        precondition(!OnboardingStateStore.shouldPresent(appVersion: "1.2.0", from: url))
        precondition(OnboardingStateStore.completedCurrentVersion(appVersion: "1.2.0", from: url))
        precondition(OnboardingStateStore.shouldPresent(appVersion: "1.3.0", from: url))
        precondition(!OnboardingStateStore.completedCurrentVersion(appVersion: "1.3.0", from: url))

        try Data("not json".utf8).write(to: url, options: .atomic)
        precondition(OnboardingStateStore.shouldPresent(appVersion: "1.2.0", from: url))
        print("OnboardingStateStoreCheck passed")
    }
}
