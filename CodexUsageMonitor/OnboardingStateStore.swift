import Foundation

struct OnboardingState: Codable, Equatable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var lastPresentedVersion: String
    var completed: Bool
    var updatedAt: Date
}

enum OnboardingStateStore {
    static let stateURL: URL = {
        let fileManager = FileManager.default
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("CodexUsageMonitor/onboarding.json")
    }()

    static var currentAppVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development"
    }

    static func load(from url: URL = stateURL) -> OnboardingState? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(OnboardingState.self, from: data)
    }

    static func shouldPresent(appVersion: String, state: OnboardingState?) -> Bool {
        guard let state, state.schemaVersion == OnboardingState.currentSchemaVersion else { return true }
        return state.lastPresentedVersion != appVersion
    }

    static func shouldPresent(appVersion: String = currentAppVersion, from url: URL = stateURL) -> Bool {
        shouldPresent(appVersion: appVersion, state: load(from: url))
    }

    static func completedCurrentVersion(
        appVersion: String = currentAppVersion,
        from url: URL = stateURL
    ) -> Bool {
        guard let state = load(from: url) else { return false }
        return state.schemaVersion == OnboardingState.currentSchemaVersion
            && state.lastPresentedVersion == appVersion
            && state.completed
    }

    @discardableResult
    static func markPresented(
        appVersion: String = currentAppVersion,
        completed: Bool,
        at date: Date = Date(),
        to url: URL = stateURL
    ) -> Bool {
        let state = OnboardingState(
            schemaVersion: OnboardingState.currentSchemaVersion,
            lastPresentedVersion: appVersion,
            completed: completed,
            updatedAt: date
        )

        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(state).write(to: url, options: .atomic)
            return load(from: url) == state
        } catch {
            return false
        }
    }
}
