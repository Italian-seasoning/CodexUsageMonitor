# Glass, navigation, and usage accuracy

Keep Apple glass throughout the shared workspace. Pearl concept was rejected. Removed ambient gradient from workspace and menu panel, and heavy dark scrims from workspace and navigation. Workspace uses clear SwiftUI glass over native behind-window material; all pages share it. Preserve accessibility reduced-transparency fallback.

Sidebar opens from outward pointer movement without a button, or a precise horizontal trackpad gesture. Threshold snap provides haptic feedback. Hovering each rail icon selects its page without closing the rail. Hardware gesture feel and haptic strength still need user evaluation.

Added custom inclusive date ranges and allowance consumption in percentage points per 15 minutes. Rates require adequate recent observations in the same reset window; missing or stale evidence displays an unavailable state.

Account allowance windows now map by duration, not primary/secondary position. An authoritative response can clear a missing five-hour limit. Verified live account and app both reported 67% weekly used (33% remaining), with no five-hour window. Values continue changing with usage.

Refresh changes include capped account polling, source-event coalescing, archived-session indexing, unchanged-file reuse, atomic widget synchronization, and aged widget timelines. Installer restores the refresh agent. Live app/widget snapshot bytes matched with a six-second-old snapshot; warmed unchanged refresh measured 0.034 seconds. Initial archive indexing remains more expensive. WidgetKit controls actual desktop redraw timing.

Validation: 65 Xcode tests passed before final hover/glass-only changes. Subsequent release builds and installation succeeded. Final test bundle: build/verified-oct11.xcresult. Custom date calculations tested; interactive date-picker verification was interrupted by user interaction. Installed UI inspected, but visual acceptance remains with user. Removed old backups, obsolete check binaries, and debug DerivedData; retained production build and test evidence.
