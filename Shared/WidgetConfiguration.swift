import Foundation

enum CodexWidgetFamily: String, Codable, CaseIterable, Identifiable, Sendable {
    case limits
    case usagePulse
    case costLens
    case modelMix
    case headroomImpact
    case sessionLive
    case dashboard

    var id: Self { self }
}

enum CodexWidgetStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case precisionInstrument
    case nativeGlass
    case signalGrid

    var id: Self { self }
}

enum DashboardArrangement: String, Codable, CaseIterable, Identifiable, Sendable {
    case balanced
    case limitsFirst
    case activityFirst

    var id: Self { self }
}

enum WidgetPresetMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case summer
    case darkGlass
    case frosted
    case signal
    case saved
    case custom

    var id: Self { self }

    func presentation(
        savedPreset: SavedWidgetPreset? = nil,
        customStyle: CodexWidgetStyle = .precisionInstrument,
        customTheme: WidgetTheme = .crimson
    ) -> (style: CodexWidgetStyle, theme: WidgetTheme) {
        switch self {
        case .summer: (.precisionInstrument, .crimson)
        case .darkGlass: (.nativeGlass, .darkGlass)
        case .frosted: (.nativeGlass, .frostedWhite)
        case .signal: (.signalGrid, .darkGlass)
        case .saved: (savedPreset?.style ?? .precisionInstrument, savedPreset?.theme ?? .crimson)
        case .custom: (customStyle, customTheme)
        }
    }
}

struct SavedWidgetPreset: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var name: String
    var style: CodexWidgetStyle
    var theme: WidgetTheme
}

enum SavedWidgetPresetStore {
    static let url = URL(
        fileURLWithPath: ProcessInfo.processInfo.environment["HOME"]
            ?? FileManager.default.homeDirectoryForCurrentUser.path,
        isDirectory: true
    )
        .appendingPathComponent("Library/Application Support/CodexUsageMonitor/widget-presets.json")

    static func load() -> [SavedWidgetPreset] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([SavedWidgetPreset].self, from: data)) ?? []
    }

    @discardableResult
    static func save(_ presets: [SavedWidgetPreset]) -> Bool {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try JSONEncoder().encode(presets).write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }
}

struct WidgetDisplayConfiguration: Equatable, Sendable {
    var family: CodexWidgetFamily
    var style: CodexWidgetStyle
    var theme: WidgetTheme
    var period: UsagePeriod
    var dashboardArrangement: DashboardArrangement

    func normalized() -> Self {
        var result = self
        if family != .dashboard {
            result.dashboardArrangement = .balanced
        }
        return result
    }
}
