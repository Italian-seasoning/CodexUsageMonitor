import Darwin
import Foundation
import OSLog

enum CodexWidgetKind {
    static let primary = "CodexUsageWidget"
    static let all: Set<String> = [primary]
}

enum WidgetDataBridge {
    private static let productionWidgetBundleIdentifier = "com.codexusage.CodexUsageMonitor.widget3"

    static let homeDirectoryURL = getpwuid(getuid())
        .map { URL(fileURLWithPath: String(cString: $0.pointee.pw_dir), isDirectory: true) }
        ?? FileManager.default.homeDirectoryForCurrentUser

    static var currentDirectoryURL: URL {
        dataDirectoryURL(
            bundleIdentifier: Bundle.main.bundleIdentifier,
            homeDirectory: homeDirectoryURL
        )
    }

    static var extensionDirectoryURL: URL {
        dataDirectoryURL(
            bundleIdentifier: widgetBundleIdentifier,
            homeDirectory: homeDirectoryURL
        )
    }

    static func dataDirectoryURL(bundleIdentifier: String?, homeDirectory: URL) -> URL {
        if let bundleIdentifier, bundleIdentifier.hasSuffix(".widget3") {
            return homeDirectory
                .appendingPathComponent("Library/Containers/\(bundleIdentifier)/Data", isDirectory: true)
                .appendingPathComponent("Library/Application Support/CodexUsageMonitor", isDirectory: true)
        }
        return homeDirectory
            .appendingPathComponent("Library/Application Support/CodexUsageMonitor", isDirectory: true)
    }

    @discardableResult
    static func syncToWidgetExtension() -> Bool {
        guard currentDirectoryURL != extensionDirectoryURL else { return true }

        do {
            let fileManager = FileManager.default
            try fileManager.createDirectory(at: extensionDirectoryURL, withIntermediateDirectories: true)

            for name in ["snapshot.json", "desktop-widgets.json", "widget-appearance.json"] {
                let source = currentDirectoryURL.appendingPathComponent(name)
                guard fileManager.fileExists(atPath: source.path) else { continue }
                try Data(contentsOf: source).write(
                    to: extensionDirectoryURL.appendingPathComponent(name),
                    options: .atomic
                )
            }

            let sourceBackgrounds = currentDirectoryURL.appendingPathComponent("widget-backgrounds", isDirectory: true)
            let destinationBackgrounds = extensionDirectoryURL.appendingPathComponent("widget-backgrounds", isDirectory: true)
            for size in CodexUsageWidgetSize.allCases {
                let filename = "\(size.rawValue).jpg"
                let source = sourceBackgrounds.appendingPathComponent(filename)
                guard fileManager.fileExists(atPath: source.path) else { continue }
                try fileManager.createDirectory(at: destinationBackgrounds, withIntermediateDirectories: true)
                try Data(contentsOf: source).write(
                    to: destinationBackgrounds.appendingPathComponent(filename),
                    options: .atomic
                )
            }
            return true
        } catch {
            return false
        }
    }

    private static var widgetBundleIdentifier: String {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
            return productionWidgetBundleIdentifier
        }
        if bundleIdentifier.hasSuffix(".widget3") {
            return bundleIdentifier
        }
        if bundleIdentifier.hasSuffix(".debug") {
            return "\(bundleIdentifier).widget3"
        }
        return productionWidgetBundleIdentifier
    }
}

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
    case classicRed
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
        case .classicRed: (.precisionInstrument, .classicRed)
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

enum WidgetBackgroundMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case styled
    case customImage

    var id: Self { self }
}

struct WidgetDisplayConfiguration: Codable, Equatable, Sendable {
    var family: CodexWidgetFamily
    var style: CodexWidgetStyle
    var theme: WidgetTheme
    var period: UsagePeriod
    var dashboardArrangement: DashboardArrangement
    var background: WidgetBackgroundMode? = nil

    var backgroundMode: WidgetBackgroundMode {
        get { background ?? .styled }
        set { background = newValue == .styled ? nil : newValue }
    }

    func normalized() -> Self {
        var result = self
        if family != .dashboard {
            result.dashboardArrangement = .balanced
        }
        return result
    }

    func applying(_ appearance: WidgetAppearanceSelection?) -> Self {
        guard let appearance else { return self }
        var result = self
        result.style = appearance.style
        result.theme = appearance.theme
        return result
    }
}

struct DesktopWidgetConfigurations: Codable, Equatable, Sendable {
    var small: WidgetDisplayConfiguration
    var medium: WidgetDisplayConfiguration
    var large: WidgetDisplayConfiguration

    static func defaults(appearance: WidgetAppearanceSelection? = nil) -> Self {
        let style = appearance?.style ?? .precisionInstrument
        let theme = appearance?.theme ?? .crimson
        return Self(
            small: .init(
                family: .limits,
                style: style,
                theme: theme,
                period: .today,
                dashboardArrangement: .balanced
            ),
            medium: .init(
                family: .usagePulse,
                style: style,
                theme: theme,
                period: .sevenDays,
                dashboardArrangement: .balanced
            ),
            large: .init(
                family: .dashboard,
                style: style,
                theme: theme,
                period: .sevenDays,
                dashboardArrangement: .balanced
            )
        )
    }

    func configuration(for size: CodexUsageWidgetSize) -> WidgetDisplayConfiguration {
        switch size {
        case .small: small
        case .medium: medium
        case .large: large
        }
    }

    mutating func set(_ configuration: WidgetDisplayConfiguration, for size: CodexUsageWidgetSize) {
        switch size {
        case .small: small = configuration.normalized()
        case .medium: medium = configuration.normalized()
        case .large: large = configuration.normalized()
        }
    }
}

enum DesktopWidgetConfigurationsStore {
    private static let logger = Logger(
        subsystem: "com.codexusage.CodexUsageMonitor",
        category: "WidgetConfiguration"
    )

    static let url = WidgetDataBridge.currentDirectoryURL
        .appendingPathComponent("desktop-widgets.json")

    static func load() -> DesktopWidgetConfigurations {
        guard let data = try? Data(contentsOf: url),
              let configurations = try? JSONDecoder().decode(DesktopWidgetConfigurations.self, from: data)
        else {
            logger.error("Could not load desktop widget configuration")
            return .defaults(appearance: WidgetAppearanceSelectionStore.load())
        }
        logger.notice(
            "Loaded medium widget: \(configurations.medium.family.rawValue, privacy: .public), \(configurations.medium.style.rawValue, privacy: .public), \(configurations.medium.theme.rawValue, privacy: .public), \(configurations.medium.backgroundMode.rawValue, privacy: .public)"
        )
        return configurations
    }

    @discardableResult
    static func save(_ configurations: DesktopWidgetConfigurations) -> Bool {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try JSONEncoder().encode(configurations).write(to: url, options: .atomic)
            return load() == configurations
        } catch {
            return false
        }
    }
}

enum WidgetBackgroundImageStore {
    static let directoryURL = DesktopWidgetConfigurationsStore.url
        .deletingLastPathComponent()
        .appendingPathComponent("widget-backgrounds", isDirectory: true)

    static func url(for size: CodexUsageWidgetSize) -> URL {
        directoryURL.appendingPathComponent("\(size.rawValue).jpg")
    }
}

struct WidgetAppearanceSelection: Codable, Equatable, Sendable {
    var style: CodexWidgetStyle
    var theme: WidgetTheme
}

enum WidgetAppearanceSelectionStore {
    static let url = WidgetDataBridge.currentDirectoryURL
        .appendingPathComponent("widget-appearance.json")

    static func load() -> WidgetAppearanceSelection? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WidgetAppearanceSelection.self, from: data)
    }

    @discardableResult
    static func save(_ selection: WidgetAppearanceSelection?) -> Bool {
        do {
            if let selection {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try JSONEncoder().encode(selection).write(to: url, options: .atomic)
            } else if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
            return load() == selection
        } catch {
            return false
        }
    }
}
