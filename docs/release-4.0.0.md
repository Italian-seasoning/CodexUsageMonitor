# Codex Usage Monitor 4.0.0 preview

- Clear Apple Liquid Glass workspace on macOS 26+, with older-system material fallback.
- Pull navigation outward with the cursor without clicking. Hover an icon to switch pages; precise trackpad swipes use a separate threshold and snap feedback.
- Cleaner Trends layout, stronger chart contrast, exact values on hover, and custom inclusive date ranges.
- Remaining allowance and estimated percentage points consumed per 15 minutes. Rates wait for sufficient recent samples and exclude resets and long gaps.
- Correct account-window mapping: a weekly primary limit is no longer mislabeled as five-hour usage. Missing account windows clear old cached values.
- Archived-session history, streaming transcript reads, bounded account polling, coalesced source updates, and shared app/widget snapshots.
- Creator credit and fork-attribution guidance for Italian-seasoning.

Validation: 67 Xcode tests passed after integrating the existing reader memory fix. Release build and installation verified. Physical trackpad/haptic feel and extended sleep/wake behavior remain manual checks. WidgetKit controls actual desktop redraw timing.

This is an ad-hoc signed preview, not an Apple Developer ID notarized release.
