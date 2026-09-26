# Codex Usage Monitor

A native macOS app and WidgetKit extension for local Codex usage, model-aware
API-equivalent cost estimates, Headroom savings, and configurable desktop widgets.

> [!WARNING]
> **Preview software.** The current build is not signed with an Apple Developer ID
> or notarized by Apple. macOS may require Control-clicking the app and choosing
> **Open**. Treat it as a test build, not a finished production release.

[Download the unsigned preview](https://github.com/Italian-seasoning/CodexUsageMonitor/releases/latest/download/CodexUsageMonitor-macOS.dmg)
· [View the website](https://italian-seasoning.github.io/CodexUsageMonitor/)
· [Report an issue](https://github.com/Italian-seasoning/CodexUsageMonitor/issues)

## What it tracks

- Local session, today, seven-day, and month token usage; account lifetime tokens when the Codex CLI is available
- Input, cached input, output, and reasoning tokens
- Requests, sessions, streaks, context use, and visible chart peaks
- Recorded models and API-equivalent cost estimates by model
- Top model today, seven days, this month, and lifetime
- Headroom tokens saved, savings rate, and estimated cost avoided
- Live account five-hour and weekly Codex limits, reset times, pace, and local seven-day history
- A native menu bar meter with percentage, meter, and reset-countdown modes
- Background widget snapshots every minute while the app is closed
- Independent settings for small, medium, and large widgets

## Privacy

Codex Usage Monitor reads local Codex logs and the local Headroom database. When
the Codex CLI or ChatGPT desktop app is installed, it also asks Codex's
app-server for account lifetime usage and current limits. The app-server may
contact OpenAI using your existing sign-in. The monitor does not upload prompts,
responses, or local session history. GitHub is
used only for optional Sparkle updates. See the full [privacy policy](docs/privacy.html).

## Requirements

- macOS 14 or later
- Apple silicon or Intel Mac
- Codex local session logs in `~/.codex/sessions`
- ChatGPT desktop app or Codex CLI signed in to the same account for profile lifetime totals and live limits; otherwise local estimates are shown
- Headroom is optional

## Build

Open `CodexUsageMonitor.xcodeproj` in Xcode and run the
`CodexUsageMonitor` scheme. Sparkle resolves through Swift Package Manager.

Release packaging and GitHub publishing are documented in
[`DISTRIBUTION.md`](DISTRIBUTION.md).

## Version

Current preview: **3.1.1**

Codex Usage Monitor is independent software and is not affiliated with OpenAI.
