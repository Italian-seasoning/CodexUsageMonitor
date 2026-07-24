import Foundation

enum CodexDataAccessState: Equatable {
    case notRequested
    case requesting
    case approved
    case needsManualAction(String)
    case failed(String)
}

enum SetupRequirement: String, Codable, CaseIterable {
    case codexDataAccess
    case backgroundRefresh
    case widgetRegistration
}

struct OnboardingState: Codable, Equatable {
    static let currentSchemaVersion = 2

    var schemaVersion: Int
    var lastPresentedVersion: String
    var completedRequirements: Set<SetupRequirement>
    var dismissedUpdateChecklistVersion: String?
    var updatedAt: Date

    init(
        schemaVersion: Int = currentSchemaVersion,
        lastPresentedVersion: String,
        completedRequirements: Set<SetupRequirement>,
        dismissedUpdateChecklistVersion: String?,
        updatedAt: Date
    ) {
        self.schemaVersion = schemaVersion
        self.lastPresentedVersion = lastPresentedVersion
        self.completedRequirements = completedRequirements
        self.dismissedUpdateChecklistVersion = dismissedUpdateChecklistVersion
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try values.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        let legacyCompleted = try values.decodeIfPresent(Bool.self, forKey: .completed) ?? false
        self.schemaVersion = Self.currentSchemaVersion
        self.lastPresentedVersion = try values.decodeIfPresent(String.self, forKey: .lastPresentedVersion) ?? ""
        self.completedRequirements = schemaVersion == 1 && legacyCompleted
            ? Set(SetupRequirement.allCases)
            : try values.decodeIfPresent(Set<SetupRequirement>.self, forKey: .completedRequirements) ?? []
        self.dismissedUpdateChecklistVersion = try values.decodeIfPresent(
            String.self,
            forKey: .dismissedUpdateChecklistVersion
        )
        self.updatedAt = try values.decodeIfPresent(Date.self, forKey: .updatedAt) ?? .distantPast
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(Self.currentSchemaVersion, forKey: .schemaVersion)
        try values.encode(lastPresentedVersion, forKey: .lastPresentedVersion)
        try values.encode(completedRequirements, forKey: .completedRequirements)
        try values.encodeIfPresent(dismissedUpdateChecklistVersion, forKey: .dismissedUpdateChecklistVersion)
        try values.encode(updatedAt, forKey: .updatedAt)
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case lastPresentedVersion
        case completed
        case completedRequirements
        case dismissedUpdateChecklistVersion
        case updatedAt
    }
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

    static func save(_ state: OnboardingState, to url: URL = stateURL) {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(state).write(to: url, options: .atomic)
        } catch {
            // Setup state is recoverable and will be offered again if persistence fails.
        }
    }

    static func shouldPresent(appVersion: String, state: OnboardingState?) -> Bool {
        guard let state else { return true }
        let unmet = Set(SetupRequirement.allCases).subtracting(state.completedRequirements)
        return !unmet.isEmpty && state.dismissedUpdateChecklistVersion != appVersion
    }

    static func shouldPresent(appVersion: String = currentAppVersion, from url: URL = stateURL) -> Bool {
        shouldPresent(appVersion: appVersion, state: load(from: url))
    }

    static func completedCurrentVersion(
        appVersion: String = currentAppVersion,
        from url: URL = stateURL
    ) -> Bool {
        guard let state = load(from: url) else { return false }
        return state.completedRequirements == Set(SetupRequirement.allCases)
    }
}

enum CodexDataAccessProbe {
    static func run(
        at sessionsURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/sessions")
    ) -> CodexDataAccessState {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: sessionsURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            return .needsManualAction("No Codex sessions folder was found. Open Codex once, then try again.")
        }

        do {
            _ = try FileManager.default.contentsOfDirectory(
                at: sessionsURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
            return .approved
        } catch let error as CocoaError
            where error.code == .fileReadNoPermission || error.code == .fileReadNoSuchFile {
            return .needsManualAction("Allow Codex Usage to read your Codex data, then try again.")
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}
