# Codex Usage Monitor roadmap

## 1.1.3 — Reliable background widgets

### Goal

Keep the shared usage snapshot current while the main app is quit, then ask
WidgetKit to redraw from that fresh snapshot.

### Current failure

The bundled refresh executable and LaunchAgent installer already exist, but the
installer is never called. On the current Mac there is no installed or loaded
`com.nolankrahn.CodexUsageMonitor.refresh` service, so the widget repeatedly reads
the last snapshot written by the app.

### Scope

- Add one onboarding choice for background widget updates and install the bundled
  refresh agent only after consent.
- Run the collector every five minutes from the stable app path in `/Applications`.
- Reinstall or repair the agent after an app update or move.
- Refresh Codex and Headroom data, atomically save the shared snapshot, then call
  `WidgetCenter.reloadTimelines`.
- Replace the one-minute widget timeline request with a realistic five-minute
  policy; WidgetKit still controls the exact redraw time.
- Show background-refresh status, last successful collection, and a **Repair**
  action in the app.
- Keep routine runs silent and retain only actionable errors so logs do not grow
  indefinitely.

### Acceptance checks

- With the main app quit, new Codex usage advances the snapshot timestamp at least
  twice during a 15-minute test.
- The widget reflects the new totals within ten minutes under normal macOS widget
  scheduling.
- Refresh survives logout/login, restart, and a Sparkle app update.
- Disabling background refresh unloads the service and removes its plist.
- A denied data-access request produces one clear app status instead of repeated
  prompts.

### Constraint

The current ad-hoc signature gives macOS no stable Developer ID identity. The app
can minimize prompts, but cannot guarantee that macOS remembers data-access consent
across every unsigned update.

## 1.2.0 — Limit intelligence

### Goal

Add the most useful SessionWatcher-style awareness while remaining a private,
Codex-focused monitor.

### Scope

- Add a native `MenuBarExtra` showing the active five-hour window, weekly usage,
  and nearest reset countdown without opening the main window.
- Add compact menu-bar display modes inspired by CodexBar: percentage, meter,
  reset countdown, and a stale/error indicator.
- Parse the existing local Codex `rate_limits` records: `used_percent`,
  `window_minutes`, and `resets_at`.
- Add a pace indicator comparing usage consumed with time elapsed: **On pace**,
  **Running high**, or **Limit risk**.
- Add a seven-day rate-limit history chart alongside the existing token and cost
  history.
- Add optional native notifications at configurable warning and critical
  thresholds, plus a reset notification.
- Add manual, 1-, 2-, 5-, and 15-minute refresh cadence choices.
- Add five-hour usage, weekly usage, pace, and reset time as widget metrics.
- Keep all limit history local and collect no prompts, code, accounts, or API keys.

### Acceptance checks

- Current percentages and reset times match the newest Codex rate-limit record.
- Pace calculations handle missing records, changed window lengths, and expired
  reset timestamps without displaying fabricated limits.
- Menu-bar, main-window, and widget values come from the same snapshot.
- Notifications fire once per threshold per window and reset for the next window.
- Background CPU and memory remain negligible when Codex logs have not changed.

### Deliberately deferred

- Other AI tools and “best tool now” recommendations.
- Multi-account support.
- iCloud sync, licensing, subscriptions, or 90-day cloud history.
- Copying SessionWatcher’s interface, wording, or branding.

SessionWatcher is a product reference for rate-limit pace, reset timing, and
notifications: <https://sessionwatcher.com/codex>. CodexBar is a reference for
compact meter icons, reset display modes, stale states, and refresh cadence:
<https://github.com/steipete/codexbar>.
