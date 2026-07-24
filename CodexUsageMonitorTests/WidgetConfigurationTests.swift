import Testing
@testable import CodexUsageMonitor

@Suite
struct WidgetConfigurationTests {
    @Test("Configuration preserves supported choices and scopes dashboard arrangements")
    func configurationNormalization() {
        for family in CodexWidgetFamily.allCases {
            for style in CodexWidgetStyle.allCases {
                for period in UsagePeriod.allCases {
                    for arrangement in DashboardArrangement.allCases {
                        let configuration = WidgetDisplayConfiguration(
                            family: family,
                            style: style,
                            theme: .darkGlass,
                            period: period,
                            dashboardArrangement: arrangement
                        )
                        let normalized = configuration.normalized()

                        #expect(normalized.family == family)
                        #expect(normalized.style == style)
                        #expect(normalized.theme == .darkGlass)
                        #expect(normalized.period == period)
                        #expect(normalized.dashboardArrangement == (family == .dashboard ? arrangement : .balanced))
                    }
                }
            }
        }
    }
}
