import SwiftUI

#Preview("Precision Instrument") {
    CodexWidgetFamilyView(
        snapshot: .empty,
        configuration: .init(
            family: .usagePulse,
            style: .precisionInstrument,
            theme: .crimson,
            period: .sevenDays,
            dashboardArrangement: .balanced
        ),
        size: .medium,
        monochrome: false
    )
    .frame(width: 340, height: 170)
}

#Preview("Native Glass") {
    CodexWidgetFamilyView(
        snapshot: .empty,
        configuration: .init(
            family: .limits,
            style: .nativeGlass,
            theme: .frostedWhite,
            period: .today,
            dashboardArrangement: .balanced
        ),
        size: .small,
        monochrome: false
    )
    .frame(width: 170, height: 170)
}

#Preview("Signal Grid") {
    CodexWidgetFamilyView(
        snapshot: .empty,
        configuration: .init(
            family: .dashboard,
            style: .signalGrid,
            theme: .monochrome,
            period: .month,
            dashboardArrangement: .activityFirst
        ),
        size: .large,
        monochrome: true
    )
    .frame(width: 340, height: 340)
}
