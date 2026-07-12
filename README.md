# Codex Usage Monitor

A native macOS app and WidgetKit extension for local Codex usage, model-aware
API-equivalent cost estimates, Headroom savings, and configurable desktop widgets.

[Download the latest release](https://github.com/Italian-seasoning/CodexUsageMonitor/releases/latest/download/CodexUsageMonitor-macOS.dmg)
· [View the website](https://italian-seasoning.github.io/CodexUsageMonitor/)
· [Report an issue](https://github.com/Italian-seasoning/CodexUsageMonitor/issues)

## What it tracks

- Session, today, seven-day, month, and lifetime token usage
- Input, cached input, output, and reasoning tokens
- Requests, sessions, streaks, context use, and visible chart peaks
- Recorded models and API-equivalent cost estimates by model
- Top model today, seven days, this month, and lifetime
- Headroom tokens saved, savings rate, and estimated cost avoided
- Independent settings for small, medium, and large widgets

## Privacy

Codex Usage Monitor reads local Codex logs and the local Headroom database. It
does not upload prompts, responses, usage history, or pricing data. GitHub is
used only for optional Sparkle updates. See the full [privacy policy](docs/privacy.html).

## Requirements

- macOS 14 or later
- Apple silicon or Intel Mac
- Codex local session logs in `~/.codex/sessions`
- Headroom is optional

## Build

Open `CodexUsageMonitor.xcodeproj` in Xcode and run the
`CodexUsageMonitor` scheme. Sparkle resolves through Swift Package Manager.

Release packaging and GitHub publishing are documented in
[`DISTRIBUTION.md`](DISTRIBUTION.md).

## Version

Current release: **1.1.2** (build 4)

Codex Usage Monitor is independent software and is not affiliated with OpenAI.
