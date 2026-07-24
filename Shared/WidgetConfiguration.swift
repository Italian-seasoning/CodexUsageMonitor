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
