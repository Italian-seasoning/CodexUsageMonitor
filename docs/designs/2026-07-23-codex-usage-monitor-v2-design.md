# Codex Usage Monitor V2 Design

Status: Approved product design; implementation planning pending.

## Purpose

V2 turns Codex Usage Monitor into an analysis-first macOS utility with a broader native widget catalog, more reliable setup and refresh behavior, and stronger upgrade safety. It retains local-only data collection and keeps status glanceable through widgets and the menu bar while making the main app valuable for deeper analysis.

## Scope

V2 includes:

- A compact, analysis-first main app.
- Seven native WidgetKit families across small, medium, and large sizes.
- Three selectable widget styles.
- Per-widget native configuration.
- A single coordinated refresh path.
- Reliable first-run onboarding and compact update setup.
- Versioned settings migration.
- Explicit handling for stale, partial, unavailable, and permission-blocked data.
- Xcode-based functional, visual, performance, packaging, and upgrade validation.

Windows support is a separate follow-up project. V2 documents its shared snapshot schema so a future Windows client can reproduce the same metrics without forcing the macOS app into a cross-platform framework.

## Product Principles

- The main app prioritizes analysis; widgets and the menu bar prioritize status.
- Curated widgets are the default. Customization must not require a generic layout engine.
- Cozy means readable type, soft geometry, and calm spacing, not oversized empty areas.
- Data correctness outranks decoration. The UI must never silently substitute one metric for another.
- Refresh should be quiet when healthy and easy to inspect or repair when unhealthy.
- Existing settings survive updates. New defaults apply only to new fields.
- Native macOS and WidgetKit behavior is preferred over custom infrastructure.

## Main App

### Navigation

The app uses a compact icon rail with these destinations:

1. Analysis
2. Models
3. Widgets
4. Settings
5. Data health, anchored at the bottom

Icons have native tooltips and accessibility labels. The rail remains visible while preserving almost the full width for analysis.

### Analysis Layout

The opening screen uses a compact Adaptive Mosaic. It combines the varied module shapes of a mobile home screen with desktop-responsive sizing.

The first viewport contains:

- A dominant token-activity visualization.
- Smaller modules for top model, API-equivalent estimate, Headroom savings, and sessions.
- A period control for Today, 7D, Month, and Lifetime.

Additional comparisons and history continue below in a calm vertical flow. Modules reflow at narrower widths instead of compressing charts beyond their useful size. Charts own explicit layout bounds, internal plot padding, and minimum useful dimensions so axes, marks, and labels cannot be clipped by the icon rail, scroll container, or neighboring modules.

### Metric Semantics

Period selection and metric selection are separate typed values. Selecting Today changes the time window but does not change the chosen metric. The Today token module always reads today's token total. Models are displayed only by model-specific modules or filters.

API cost values are always labeled as API-equivalent estimates and never presented as ChatGPT subscription spending.

## Widget Catalog

V2 ships these native WidgetKit families:

1. **Limits** — five-hour and weekly remaining, pace, reset countdown, and risk state.
2. **Usage Pulse** — token activity for Today, 7D, Month, or Lifetime, including trend and peak context.
3. **Cost Lens** — API-equivalent estimates for the chosen period and total.
4. **Model Mix** — top model, token share, volume, and model-specific estimated cost.
5. **Headroom Impact** — tokens saved, savings rate, estimated cost avoided, and recent trend.
6. **Session Live** — current session age, model, turns, tokens, activity state, and freshness.
7. **Modular Dashboard** — curated module arrangements built from the same tested components.

Every family supports small, medium, and large sizes through progressive disclosure:

- Small presents one hero value and essential context.
- Medium adds a comparison, secondary measure, or compact trend.
- Large adds history and richer breakdowns.

The Modular Dashboard offers only known-good arrangements for each size. It does not expose freeform placement or arbitrary resizing.

### Widget Styles

Each widget instance offers three styles through native macOS Edit Widget configuration:

- **Precision Instrument** — dark, numeric, gauge- and rule-driven.
- **Native Glass** — one translucent surface with generous type and native hierarchy.
- **Signal Grid** — controlled modular geometry and display texture.

Style, theme, period, and family-specific options are configured independently per widget instance. Two instances can use different styles and themes simultaneously.

Styles share semantic typography, formatting, accessibility, chart, and data components. They change presentation rather than duplicating metric logic.

## Component Boundaries

V2 uses the existing shared snapshot as the data source. The implementation is divided into focused native components:

- **Snapshot readers and collectors** parse local Codex and Headroom sources.
- **Refresh coordinator** owns every scan and snapshot write.
- **Metric formatting and selection** map typed periods and metrics to display values.
- **Analysis modules** render app-level charts and summaries.
- **Widget family views** define progressive disclosure by WidgetKit family.
- **Widget style renderers** apply Precision Instrument, Native Glass, or Signal Grid presentation to shared semantic content.
- **Settings store** owns versioned preferences and migrations.
- **Setup state** models permission, background service, and widget registration progress.

No new UI framework, chart dependency, database, or generic widget engine is introduced unless Xcode profiling or a concrete platform limitation proves the native implementation insufficient.

## Refresh Architecture

One refresh coordinator is the only path from source records to the shared snapshot.

Refresh can be triggered by:

- A relevant Codex or Headroom source change, with debounce.
- App launch or return to foreground.
- A quiet background fallback that attempts to refresh the shared snapshot at least every three minutes while the user session is active.
- Manual Refresh now.
- Recovery after sleep or a relevant account or source-state change.

The coordinator:

1. Coalesces concurrent requests into one in-flight refresh.
2. Checks source fingerprints and exits quickly when nothing changed.
3. Reads and validates source data.
4. Writes one complete snapshot atomically.
5. Reloads WidgetKit timelines after a successful write.
6. Records success time or a structured failure state.

Widgets only read the shared snapshot. They never scan session folders directly.

Manual refresh is authoritative and runs the same coordinator with a user-visible result. Background refresh never requests permission and never launches a Dock or menu-bar UI process.

The three-minute target applies to checking and updating the shared snapshot, not to a guaranteed visible widget redraw. WidgetKit may coalesce or defer timeline reloads. Data health reports the actual snapshot age and last requested widget reload so throttling is visible rather than mistaken for stale collection.

### Refresh UI

Healthy refresh remains mostly invisible. A data-health icon sits at the bottom of the icon rail and displays one of these semantic states:

- Fresh
- Refreshing
- Stale
- Permission required
- Error

Opening it reveals the last successful refresh, source status, and Refresh now. Repair instructions appear only when required.

## Onboarding and Setup

### First Run

First-run setup uses a native centered sheet with explicit steps:

1. Explain local data access and privacy.
2. Request access to local Codex data.
3. Confirm background refresh and widget registration.

Pressing Request permission immediately moves the row into a requesting state. It then resolves to approved, denied, needs manual action, or failed. The flow never advances merely because a launch agent appeared, and it never hides an unresolved permission state.

The existing target-anchored tour overlay is removed. Tours use stable sheet pages and do not depend on measuring or aligning to controls behind them.

### Updates

Updates do not replay full onboarding. A compact Setup required checklist appears only when a new feature has an unmet requirement. Users can dismiss it, and the same checklist remains accessible from Settings and data health.

## Settings Persistence

Settings use an explicit schema version and field-by-field migration.

- Existing values are decoded before defaults are considered.
- New fields receive defaults without replacing existing fields.
- Unknown future fields do not invalidate the entire settings payload.
- Invalid individual fields fall back independently and produce a diagnostic record.
- Updates never delete settings as a repair strategy.
- Widget instance configuration remains owned by WidgetKit and App Intents; app-wide preferences remain in the shared settings store.

Upgrade validation includes representative settings from every public V1 release that changed the schema.

## Error and Empty States

The UI distinguishes:

- No usage yet
- Data refreshing
- Fresh complete data
- Fresh partial data
- Stale cached data
- Permission blocked
- Source unavailable
- Parse or snapshot-write failure

Color is never the only signal. Every state includes text or an icon with an accessibility label. Partial data keeps valid modules visible and marks only affected modules unavailable.

## Lincoln Report Acceptance Requirements

V2 is not complete until all reported issues are covered by deterministic acceptance checks:

1. Request permission provides immediate feedback and does not skip ahead because background refresh was installed.
2. Visualizations remain inside their allocated canvas at minimum, default, and large window sizes.
3. Existing settings survive installation over an older version.
4. Today displays today's tokens and never resolves to the current model value.
5. Onboarding and tour content never clip or drift away from their controls.

## Xcode Validation

Implementation and release validation use Xcode and `xcodebuild` as the primary toolchain.

### Automated Checks

- Settings migration from representative V1 payloads.
- Typed period-to-metric mapping.
- Refresh coalescing, debounce, source fingerprinting, and atomic write behavior.
- Setup state transitions for delayed, approved, denied, failed, and repaired access.
- Widget family value selection and progressive disclosure.
- Snapshot decoding with missing, partial, and malformed optional data.

### Visual and Runtime Checks

- Xcode previews for every widget family, size, and style.
- Targeted visual regression captures covering each style and each size without testing redundant combinations.
- Main-window checks at minimum, default, and large sizes.
- Light, dark, tinted, and monochrome widget rendering.
- Keyboard navigation, accessibility labels, contrast, and reduced motion.
- Fresh install, completed onboarding, skipped update setup, and upgrade-from-V1 flows.
- Permission approved, denied, delayed, and manually repaired flows.
- Background refresh with the main app closed.
- Shared-snapshot age staying within the three-minute target during an active user session, with an explicit allowance for macOS scheduling after sleep or login.
- Manual refresh updating the app, menu bar, shared snapshot, and widgets together.
- Packaged application launch and widget discovery outside the build products directory.

### Performance Checks

Instruments is used to measure rather than guess:

- Idle CPU and memory.
- Unchanged-data refresh duration.
- Changed-data refresh duration.
- Widget timeline rendering.
- Main analysis view layout and scrolling.

## Signing and Distribution

Debug, test, and preview release builds use Xcode automatic signing with Nolan's Apple Development certificate and Personal Team. The app, widget extension, Sparkle framework, and nested helper code must pass deep strict signature verification.

Personal Team signing improves bundle integrity and local launch behavior, but it is not Developer ID distribution or Apple notarization. It does not promise warning-free installation on another person's Mac, and it may require renewed development provisioning. Public release notes must continue to identify the app as a preview and must not claim notarization. Sparkle update archives remain separately signed with the existing Sparkle EdDSA key.

## Windows Follow-Up Boundary

V2 documents the shared snapshot fields, units, optionality, freshness semantics, and metric definitions in a platform-neutral schema. The future Windows project may implement its own collector and UI against that contract.

V2 does not introduce a cross-platform UI toolkit, background-service abstraction, or shared runtime solely for future Windows support.

## Completion Criteria

V2 is ready for release when:

- All seven widget families render correctly in every supported size and style.
- The compact Adaptive Mosaic remains unclipped and useful across supported window sizes.
- Lincoln's reported issues pass deterministic checks.
- Refresh remains quiet and low-resource while still recoverable manually.
- Settings survive representative upgrades.
- The real packaged app and widgets pass Xcode, runtime, accessibility, performance, and signature validation.
- Release messaging accurately describes Personal Team signing and non-notarized preview status.
