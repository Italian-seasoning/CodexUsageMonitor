import Foundation
import Testing
@testable import CodexUsageMonitor

@Suite
struct SettingsMigrationTests {
    @Test("Missing V2 settings import legacy app values and expose the widget seed")
    func importsLegacyValuesWithoutAV2File() {
        var widgetSeed = CodexUsageWidgetSettingsBySize.default
        widgetSeed.medium.theme = .monochrome
        let legacyValues: [String: Any] = [
            "CodexUsageMonitor.appTheme": "graphite",
            "CodexUsageMonitor.backgroundRefreshEnabled": true,
            "CodexUsageMonitor.appPresence": "dock",
            "CodexUsageMonitor.menuBarDisplayMode": "reset",
            "CodexUsageMonitor.limitNotificationsEnabled": true,
            "CodexUsageMonitor.limitWarningThreshold": 80,
            "CodexUsageMonitor.limitCriticalThreshold": 95,
        ]

        let result = CodexUsageSettingsStore.load(
            data: nil,
            legacy: LegacySettingsSource(
                object: { legacyValues[$0] },
                widgetSettings: widgetSeed
            )
        )

        #expect(result.settings.appTheme == .graphite)
        #expect(result.settings.backgroundRefreshEnabled)
        #expect(result.settings.appPresence == .dock)
        #expect(result.settings.menuBarDisplayMode == .reset)
        #expect(result.settings.notificationsEnabled)
        #expect(result.settings.warningThreshold == 80)
        #expect(result.settings.criticalThreshold == 95)
        #expect(result.importedLegacyValues)
        #expect(result.legacyWidgetSeed == widgetSeed)
    }

    @Test("Missing new fields use defaults without being reported as malformed")
    func missingFieldsUseDefaults() throws {
        let data = try jsonData([
            "schemaVersion": 1,
            "backgroundRefreshEnabled": true,
        ])

        let result = CodexUsageSettingsStore.load(data: data, legacy: .empty)

        #expect(result.settings.schemaVersion == CodexUsageSettings.currentSchemaVersion)
        #expect(result.settings.appTheme == .crimson)
        #expect(result.settings.backgroundRefreshEnabled)
        #expect(result.settings.warningThreshold == 70)
        #expect(result.repairedFields.isEmpty)
    }

    @Test("Only a malformed field is repaired beside valid fields")
    func repairsOnlyMalformedField() throws {
        let data = try jsonData([
            "schemaVersion": 2,
            "backgroundRefreshEnabled": false,
            "warningThreshold": "seventy",
        ])

        let result = CodexUsageSettingsStore.load(data: data, legacy: .empty)

        #expect(result.settings.backgroundRefreshEnabled == false)
        #expect(result.settings.warningThreshold == 70)
        #expect(result.repairedFields == ["warningThreshold"])
    }

    @Test("Unknown future fields are ignored and thresholds are clamped")
    func ignoresUnknownFieldsAndClampsThresholds() throws {
        let data = try jsonData([
            "schemaVersion": 2,
            "warningThreshold": 0,
            "criticalThreshold": 140,
            "futureDisplayStyle": "orbital",
        ])

        let result = CodexUsageSettingsStore.load(data: data, legacy: .empty)

        #expect(result.settings.warningThreshold == 1)
        #expect(result.settings.criticalThreshold == 100)
        #expect(result.repairedFields == ["warningThreshold", "criticalThreshold"])
    }

    @Test("Legacy app values are ignored when a V2 file exists")
    func doesNotImportLegacyValuesOverV2Settings() throws {
        let data = try jsonData([
            "schemaVersion": 2,
            "appTheme": "crimson",
        ])
        let legacy = LegacySettingsSource(
            object: { key in
                key == "CodexUsageMonitor.appTheme" ? "graphite" : nil
            },
            widgetSettings: nil
        )

        let result = CodexUsageSettingsStore.load(data: data, legacy: legacy)

        #expect(result.settings.appTheme == .crimson)
        #expect(!result.importedLegacyValues)
    }

    @Test("Widget migration seed remains separate from app preferences")
    func widgetSeedIsNotPersistedInAppSettings() throws {
        var widgetSeed = CodexUsageWidgetSettingsBySize.default
        widgetSeed.small.theme = .frostedWhite

        let result = CodexUsageSettingsStore.load(
            data: nil,
            legacy: LegacySettingsSource(object: { _ in nil }, widgetSettings: widgetSeed)
        )
        let encoded = try JSONEncoder().encode(result.settings)
        let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])

        #expect(result.settings.defaultWidgetTheme == .crimson)
        #expect(result.legacyWidgetSeed == widgetSeed)
        #expect(object["legacyWidgetSeed"] == nil)
        #expect(object["small"] == nil)
    }
}

private extension LegacySettingsSource {
    static var empty: Self {
        LegacySettingsSource(object: { _ in nil }, widgetSettings: nil)
    }
}

private func jsonData(_ object: [String: Any]) throws -> Data {
    try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
}
