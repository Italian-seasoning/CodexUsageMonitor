# Codex Usage Monitor - Windows and Linux

Created by [Italian-seasoning](https://github.com/Italian-seasoning).
Simple companion clients for the [original Mac app](https://github.com/Italian-seasoning/CodexUsageMonitor).

## Windows

Open `CodexUsageMonitor-Windows.exe` from the release downloads. The compact
desktop window shows remaining allowance, consumption per 15 minutes, and token
history. Enter dates as `YYYY-MM-DD`, then click Refresh. Hover a chart bar for
its exact value. This preview is unsigned.

To run from source, install Python 3.11 or newer with Tkinter, then run:

```powershell
py monitor.py --gui
```

## Linux ASCII terminal

Requires Python 3.11 or newer; no third-party Python packages are needed.

```sh
python3 monitor.py
python3 monitor.py --from 2026-10-01 --to 2026-10-11
python3 monitor.py --once
python3 monitor.py --json
```

The terminal refreshes every minute. Press Ctrl+C to quit. Redirected output is
printed once. The chart shows the last 14 active days; totals cover the selected
range. Windows charts show the last 31 active days.

## Data

Install Codex CLI and run `codex login` for live account allowance. Local usage
comes from `~/.codex/sessions` and `~/.codex/archived_sessions`. `CODEX_HOME` or
`--codex-home` can select another directory. Windows users running Codex inside
WSL should run the Linux client inside that same WSL environment.

Pro accounts show weekly allowance without five-hour clutter. Account polling
is limited to once per minute. Rate estimates need at least ten minutes of
recent observations and do not span allowance resets. Failed account requests
retain the last observation with a visible cached status; expired windows are
not shown as current.

The clients do not read sign-in tokens or send transcripts anywhere. The Codex
CLI uses its existing sign-in to retrieve allowance. Only account percentages
and recent rate observations are saved under `%LOCALAPPDATA%/CodexUsageMonitor`
on Windows or `~/.local/state/CodexUsageMonitor` on Linux. Local token totals are
estimates from recorded events, not billing records. These simple clients do
not include the Mac app's desktop widgets, Headroom data, or model cost estimates.

Please retain the creator credit and original repository link in forks and
redesigns. See the repository's `CREDITS.md`.
