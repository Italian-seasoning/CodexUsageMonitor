import Combine
import Foundation

enum AppTheme: String, Codable, CaseIterable, Identifiable, Sendable {
    case crimson
    case classicRed
    case graphite

    var id: String { rawValue }
}

enum AppPresenceMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case menuBar
    case dock
    case background

    var id: String { rawValue }
}

enum MenuBarDisplayMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case percentage
    case meter
    case reset
    case hidden

    var id: String { rawValue }
}

struct CodexUsageSettings: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 2
    static let `default` = CodexUsageSettings(
        schemaVersion: currentSchemaVersion,
        appTheme: .crimson,
        defaultWidgetTheme: .crimson,
        backgroundRefreshEnabled: false,
        appPresence: .menuBar,
        menuBarDisplayMode: .percentage,
        notificationsEnabled: false,
        warningThreshold: 70,
        criticalThreshold: 90
    )

    var schemaVersion: Int
    var appTheme: AppTheme
    var defaultWidgetTheme: WidgetTheme
    var backgroundRefreshEnabled: Bool
    var appPresence: AppPresenceMode
    var menuBarDisplayMode: MenuBarDisplayMode
    var notificationsEnabled: Bool
    var warningThreshold: Int
    var criticalThreshold: Int
}

struct SettingsLoadResult: Equatable {
    var settings: CodexUsageSettings
    var repairedFields: [String]
    var importedLegacyValues: Bool
    var legacyWidgetSeed: CodexUsageWidgetSettingsBySize?
}

struct LegacySettingsSource {
    var object: (String) -> Any?
    var widgetSettings: CodexUsageWidgetSettingsBySize?
}

enum CodexUsageSettingsStore {
    static func load() -> SettingsLoadResult {
        let data = try? Data(contentsOf: CodexUsageSnapshotStore.settingsV2URL)
        let result = load(
            data: data,
            legacy: LegacySettingsSource(
                object: UserDefaults.standard.object(forKey:),
                widgetSettings: CodexUsageSnapshotStore.loadAllSettingsIfPresent()
            )
        )
        if data == nil {
            try? save(result.settings)
        }
        return result
    }

    static func load(data: Data?, legacy: LegacySettingsSource) -> SettingsLoadResult {
        guard let data else {
            return importLegacy(from: legacy)
        }

        do {
            let payload = try JSONDecoder().decode(SettingsPayload.self, from: data)
            return SettingsLoadResult(
                settings: payload.settings,
                repairedFields: payload.repairedFields,
                importedLegacyValues: false,
                legacyWidgetSeed: legacy.widgetSettings
            )
        } catch {
            return SettingsLoadResult(
                settings: .default,
                repairedFields: ["settings"],
                importedLegacyValues: false,
                legacyWidgetSeed: legacy.widgetSettings
            )
        }
    }

    static func save(_ settings: CodexUsageSettings) throws {
        var settings = settings
        settings.schemaVersion = CodexUsageSettings.currentSchemaVersion
        try FileManager.default.createDirectory(
            at: CodexUsageSnapshotStore.settingsV2URL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try JSONEncoder().encode(settings).write(
            to: CodexUsageSnapshotStore.settingsV2URL,
            options: .atomic
        )
    }

    private static func importLegacy(from legacy: LegacySettingsSource) -> SettingsLoadResult {
        var settings = CodexUsageSettings.default
        var imported = false

        importValue("CodexUsageMonitor.appTheme", from: legacy, into: &settings.appTheme, imported: &imported)
        importValue("CodexUsageMonitor.backgroundRefreshEnabled", from: legacy, into: &settings.backgroundRefreshEnabled, imported: &imported)
        importValue("CodexUsageMonitor.appPresence", from: legacy, into: &settings.appPresence, imported: &imported)
        importValue("CodexUsageMonitor.menuBarDisplayMode", from: legacy, into: &settings.menuBarDisplayMode, imported: &imported)
        importValue("CodexUsageMonitor.limitNotificationsEnabled", from: legacy, into: &settings.notificationsEnabled, imported: &imported)
        importValue("CodexUsageMonitor.limitWarningThreshold", from: legacy, into: &settings.warningThreshold, imported: &imported)
        importValue("CodexUsageMonitor.limitCriticalThreshold", from: legacy, into: &settings.criticalThreshold, imported: &imported)
        settings.warningThreshold = settings.warningThreshold.clamped(to: 1...100)
        settings.criticalThreshold = settings.criticalThreshold.clamped(to: 1...100)

        return SettingsLoadResult(
            settings: settings,
            repairedFields: [],
            importedLegacyValues: imported,
            legacyWidgetSeed: legacy.widgetSettings
        )
    }

    private static func importValue<T>(
        _ key: String,
        from legacy: LegacySettingsSource,
        into value: inout T,
        imported: inout Bool
    ) {
        guard let legacyValue = legacy.object(key) as? T else { return }
        value = legacyValue
        imported = true
    }

    private static func importValue<T: RawRepresentable>(
        _ key: String,
        from legacy: LegacySettingsSource,
        into value: inout T,
        imported: inout Bool
    ) where T.RawValue == String {
        guard let rawValue = legacy.object(key) as? String,
              let legacyValue = T(rawValue: rawValue)
        else { return }
        value = legacyValue
        imported = true
    }
}

@MainActor
final class CodexUsageSettingsModel: ObservableObject {
    @Published var settings: CodexUsageSettings {
        didSet { try? CodexUsageSettingsStore.save(settings) }
    }
    let legacyWidgetSeed: CodexUsageWidgetSettingsBySize?

    init(result: SettingsLoadResult = CodexUsageSettingsStore.load()) {
        settings = result.settings
        legacyWidgetSeed = result.legacyWidgetSeed
    }
}

private struct SettingsPayload: Decodable {
    var settings: CodexUsageSettings
    var repairedFields: [String]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        var repairedFields: [String] = []
        var settings = CodexUsageSettings.default

        let _: Int = decode(.schemaVersion, from: container, default: settings.schemaVersion, repairedFields: &repairedFields)
        settings.appTheme = decode(.appTheme, from: container, default: settings.appTheme, repairedFields: &repairedFields)
        settings.defaultWidgetTheme = decode(.defaultWidgetTheme, from: container, default: settings.defaultWidgetTheme, repairedFields: &repairedFields)
        settings.backgroundRefreshEnabled = decode(.backgroundRefreshEnabled, from: container, default: settings.backgroundRefreshEnabled, repairedFields: &repairedFields)
        settings.appPresence = decode(.appPresence, from: container, default: settings.appPresence, repairedFields: &repairedFields)
        settings.menuBarDisplayMode = decode(.menuBarDisplayMode, from: container, default: settings.menuBarDisplayMode, repairedFields: &repairedFields)
        settings.notificationsEnabled = decode(.notificationsEnabled, from: container, default: settings.notificationsEnabled, repairedFields: &repairedFields)
        settings.warningThreshold = decode(.warningThreshold, from: container, default: settings.warningThreshold, repairedFields: &repairedFields)
        settings.criticalThreshold = decode(.criticalThreshold, from: container, default: settings.criticalThreshold, repairedFields: &repairedFields)

        let warning = settings.warningThreshold.clamped(to: 1...100)
        if warning != settings.warningThreshold {
            repairedFields.append(CodingKeys.warningThreshold.rawValue)
            settings.warningThreshold = warning
        }
        let critical = settings.criticalThreshold.clamped(to: 1...100)
        if critical != settings.criticalThreshold {
            repairedFields.append(CodingKeys.criticalThreshold.rawValue)
            settings.criticalThreshold = critical
        }

        self.settings = settings
        self.repairedFields = repairedFields
    }

    fileprivate enum CodingKeys: String, CodingKey {
        case schemaVersion
        case appTheme
        case defaultWidgetTheme
        case backgroundRefreshEnabled
        case appPresence
        case menuBarDisplayMode
        case notificationsEnabled
        case warningThreshold
        case criticalThreshold
    }
}

private func decode<T: Decodable>(
    _ key: SettingsPayload.CodingKeys,
    from container: KeyedDecodingContainer<SettingsPayload.CodingKeys>,
    default defaultValue: T,
    repairedFields: inout [String]
) -> T {
    guard container.contains(key) else { return defaultValue }
    do {
        guard let value = try container.decodeIfPresent(T.self, forKey: key) else {
            repairedFields.append(key.rawValue)
            return defaultValue
        }
        return value
    } catch {
        repairedFields.append(key.rawValue)
        return defaultValue
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
