"""Codex Usage Monitor: standard-library Windows and ASCII Linux clients."""
from __future__ import annotations

import argparse
from collections import defaultdict
from datetime import date, datetime, timedelta
import json
import math
import os
from pathlib import Path
import queue
import shutil
import subprocess
import sys
import threading
import time

VERSION = "4.0.1"


def stamp(value):
    return datetime.fromisoformat(value.replace("Z", "+00:00")).timestamp()


def limits_from(result, now):
    limits = (result.get("rateLimitsByLimitId") or {}).get("codex") or result.get("rateLimits")
    if not isinstance(limits, dict):
        raise ValueError("Codex did not return account limits")
    output = {"plan": limits.get("planType", "unknown"), "observed": now, "windows": []}
    for key in ("primary", "secondary"):
        entry = limits.get(key) or {}
        used, minutes, reset = entry.get("usedPercent"), entry.get("windowDurationMins"), entry.get("resetsAt")
        if not all(isinstance(x, (int, float)) and not isinstance(x, bool) and math.isfinite(x) for x in (used, minutes, reset)):
            continue
        if minutes not in (300, 10080) or not 0 <= used <= 100 or reset <= now:
            continue
        if minutes == 300 and str(output["plan"]).lower().startswith("pro"):
            continue
        output["windows"].append({"minutes": minutes, "used": used, "reset": reset, "observed": now})
    return output


def read_account(now, timeout=15):
    command = shutil.which("codex")
    if not command:
        raise RuntimeError("Install Codex CLI and run codex login to read allowance")
    process = subprocess.Popen(
        [command, "app-server"], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL, text=True, encoding="utf-8",
        creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
    )
    messages = queue.Queue()

    def receive():
        try:
            for line in process.stdout:
                try:
                    messages.put(json.loads(line))
                except (ValueError, TypeError):
                    pass
        finally:
            messages.put(None)

    reader = threading.Thread(target=receive, daemon=True)
    reader.start()
    deadline = time.monotonic() + timeout

    def send(message):
        process.stdin.write(json.dumps(message) + "\n")
        process.stdin.flush()

    def response(identifier):
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise TimeoutError("Codex account request timed out")
            try:
                value = messages.get(timeout=remaining)
            except queue.Empty:
                raise TimeoutError("Codex account request timed out") from None
            if value is None:
                raise RuntimeError("Codex CLI disconnected; check codex login")
            if value.get("id") == identifier:
                if "error" in value:
                    raise RuntimeError("Codex account unavailable; check codex login")
                return value.get("result", {})

    try:
        send({"id": 0, "method": "initialize", "params": {"clientInfo": {"name": "Codex Usage Monitor", "version": VERSION}}})
        response(0)
        send({"method": "initialized", "params": {}})
        send({"id": 1, "method": "account/rateLimits/read"})
        return limits_from(response(1), now)
    finally:
        if process.poll() is None:
            process.terminate()
        try:
            process.wait(timeout=2)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()
        reader.join(timeout=2)
        process.stdin.close()
        process.stdout.close()


def rate_per_15(window, samples, now):
    if now - window["observed"] > 300 or window["observed"] > now:
        return None
    points = sorted((s for s in samples if s["minutes"] == window["minutes"]
                     and abs(s["reset"] - window["reset"]) <= 2
                     and now - 900 <= s["observed"] <= now), key=lambda s: s["observed"])
    if len(points) < 2 or points[-1]["observed"] - points[0]["observed"] < 600:
        return None
    if any(b["used"] < a["used"] or b["observed"] - a["observed"] > 600 for a, b in zip(points, points[1:])):
        return None
    return (points[-1]["used"] - points[0]["used"]) * 900 / (points[-1]["observed"] - points[0]["observed"])


class Collector:
    def __init__(self, home=None, state_dir=None):
        self.home = Path(home or os.environ.get("CODEX_HOME", Path.home() / ".codex"))
        base = Path(os.environ.get("LOCALAPPDATA", Path.home() / ".local" / "state"))
        self.state_dir = Path(state_dir or base / "CodexUsageMonitor")
        self.files = {}
        self.account = None
        self.samples = []
        self.last_attempt = 0
        self.account_error = None
        try:
            state = json.loads((self.state_dir / "allowance.json").read_text())
            self.samples = state.get("samples", [])
            self.account = state.get("account")
        except (OSError, ValueError, TypeError):
            pass

    def usage(self, start, end):
        paths = []
        errors = 0
        for name in ("sessions", "archived_sessions"):
            try:
                paths.extend((self.home / name).rglob("*.jsonl"))
            except OSError:
                errors += 1
        seen = set()
        days = defaultdict(int)
        requests = 0
        parsed = []
        for path in paths:
            try:
                stat = path.stat()
                fingerprint = (stat.st_size, stat.st_mtime_ns)
                cached = self.files.get(path)
                if cached is None or cached[0] != fingerprint:
                    events = []
                    previous = None
                    primary = path.stem
                    lineage = set()
                    started = None
                    with path.open(encoding="utf-8", errors="replace") as handle:
                        for line in handle:
                            try:
                                row = json.loads(line)
                                payload = row.get("payload") or {}
                                if row.get("type") == "session_meta" and payload.get("thread_source") == "subagent":
                                    events = []
                                    break
                                if row.get("type") == "session_meta":
                                    lineage.update(value for value in (payload.get("id"), payload.get("session_id")) if isinstance(value, str))
                                    if started is None:
                                        primary = payload.get("id", path.stem)
                                        started = payload.get("timestamp", "")
                                    continue
                                if payload.get("type") != "token_count":
                                    continue
                                info = payload.get("info") or {}
                                values = info.get("total_token_usage") or {}
                                total = values.get("total_tokens")
                                cumulative = tuple(values.get(key, 0) for key in ("input_tokens", "cached_input_tokens", "output_tokens", "reasoning_output_tokens", "total_tokens"))
                                if not isinstance(total, int) or total < 0 or cumulative == previous:
                                    continue
                                recorded = row["timestamp"]
                                day = datetime.fromtimestamp(stamp(recorded)).date().isoformat()
                                delta = (info.get("last_token_usage") or {}).get("total_tokens")
                                if not isinstance(delta, int) or delta <= 0:
                                    delta = max(0, total - (previous[-1] if previous else 0))
                                previous = cumulative
                                if delta > 0:
                                    events.append((recorded, total, day, delta, cumulative))
                            except (ValueError, TypeError, KeyError, AttributeError, OverflowError):
                                continue
                    self.files[path] = (fingerprint, events, primary, lineage | {primary}, started or (events[0][0] if events else ""))
                parsed.append(self.files[path])
            except OSError:
                errors += 1
        canonical = []
        for item in sorted(parsed, key=lambda item: item[4]):
            _, events, primary, lineage, _ = item
            sequence = [event[4] for event in events]
            ancestors = [seq for identity, seq in canonical if identity in lineage
                         and len(seq) <= len(sequence) and sequence[:len(seq)] == seq]
            skip = max((len(seq) for seq in ancestors), default=0)
            canonical.append((primary, sequence))
            for recorded, total, day, delta, cumulative in events[skip:]:
                key = (recorded, cumulative)
                if key not in seen and start <= day <= end:
                    seen.add(key)
                    days[day] += delta
                    requests += 1
        active_paths = set(paths)
        self.files = {p: value for p, value in self.files.items() if p in active_paths}
        return {"days": dict(sorted(days.items())), "tokens": sum(days.values()), "events": requests,
                "files": len(paths), "errors": errors}

    def refresh(self, start, end):
        now = time.time()
        if now - self.last_attempt >= 60:
            self.last_attempt = now
            try:
                self.account = read_account(now)
                self.account_error = None
                self.samples = [s for s in self.samples if now - 3600 <= s["observed"] <= now]
                self.samples.extend(self.account["windows"])
                self.state_dir.mkdir(parents=True, exist_ok=True, mode=0o700)
                temporary = self.state_dir / f"allowance-{os.getpid()}.tmp"
                temporary.write_text(json.dumps({"account": self.account, "samples": self.samples}))
                temporary.replace(self.state_dir / "allowance.json")
            except (OSError, RuntimeError, ValueError, TypeError, KeyError) as error:
                self.account_error = str(error)
        account = self.account or {"plan": "unknown", "observed": 0, "windows": []}
        windows = []
        for window in account["windows"]:
            if window["reset"] > now:
                windows.append({**window, "rate": rate_per_15(window, self.samples, now)})
        usage = self.usage(start, end)
        return {"version": VERSION, "start": start, "end": end, "updated": now,
                "plan": account["plan"], "windows": windows, "usage": usage,
                "stale": now - account["observed"] > 180 or self.account_error is not None,
                "status": self.account_error or ("Account current" if account["observed"] else "Waiting for Codex")}


def ascii_view(data, width=72):
    width = max(36, min(width, 100))
    lines = ["CODEX USAGE MONITOR  " + VERSION, "by Italian-seasoning", "-" * width,
             f"{data['start']} to {data['end']}   Plan: {data['plan']}", ""]
    for window in data["windows"]:
        left = 100 - window["used"]
        count = round(left / 5)
        title = "Weekly" if window["minutes"] == 10080 else "5-hour"
        rate = "awaiting samples" if window["rate"] is None else f"{window['rate']:.1f} percentage points / 15 min"
        lines += [f"{title}: {left:.0f}% left  [{'#' * count}{'.' * (20-count)}]",
                  "  Rate: " + rate, "  Resets: " + datetime.fromtimestamp(window["reset"]).strftime("%a %b %d %H:%M")]
    if not data["windows"]:
        lines.append("No current allowance reported")
    usage = data["usage"]
    lines += ["", f"{usage['tokens']:,} tokens | {usage['events']:,} recorded usage events", ""]
    peak = max(usage["days"].values(), default=1) or 1
    for day, value in list(usage["days"].items())[-14:]:
        bar = "#" * round(value / peak * (width - 30))
        lines.append(f"{day} {bar:<{width-30}} {value:>12,}")
    if len(usage["days"]) > 14:
        lines.append("Chart: last 14 active days; totals cover the full range")
    if usage["files"] == 0:
        lines.append("No local Codex transcripts found")
    if usage["errors"]:
        lines.append(f"Partial local history: {usage['errors']} unreadable source(s)")
    lines += ["", ("STALE / CACHED: " if data["stale"] else "LIVE: ") + data["status"],
              "Refreshed " + datetime.fromtimestamp(data["updated"]).strftime("%H:%M:%S"), "Ctrl+C to quit"]
    return "\n".join(line.encode("ascii", "replace").decode()[:width] for line in lines)


def desktop(collector, start, end, smoke=False):
    import tkinter as tk
    from tkinter import ttk
    root = tk.Tk()
    root.title("Codex Usage Monitor")
    root.geometry("720x600")
    root.minsize(560, 420)
    frame = ttk.Frame(root, padding=20)
    frame.pack(fill="both", expand=True)
    ttk.Label(frame, text="Codex Usage", font=("Segoe UI", 22, "bold")).pack(anchor="w")
    ttk.Label(frame, text="Created by Italian-seasoning").pack(anchor="w", pady=(0, 16))
    controls = ttk.Frame(frame)
    controls.pack(fill="x")
    start_var, end_var = tk.StringVar(value=start), tk.StringVar(value=end)
    for title, variable in (("From", start_var), ("To", end_var)):
        ttk.Label(controls, text=title).pack(side="left", padx=(0, 5))
        ttk.Entry(controls, textvariable=variable, width=12).pack(side="left", padx=(0, 12))
    status = tk.StringVar(value="Reading Codex...")
    allowance = ttk.Frame(frame)
    allowance.pack(fill="x", pady=18)
    total = ttk.Label(frame, font=("Segoe UI", 20, "bold"))
    total.pack(anchor="w")
    canvas = tk.Canvas(frame, background="#14202a", highlightthickness=0, height=230)
    canvas.pack(fill="both", expand=True, pady=12)
    ttk.Label(frame, textvariable=status, wraplength=660).pack(anchor="w")
    messages = queue.Queue()
    busy = False
    latest = None

    def draw(_event=None):
        canvas.delete("all")
        if latest is None:
            return
        points = list(latest["usage"]["days"].items())[-31:]
        if not points:
            canvas.create_text(20, 30, anchor="nw", fill="white", text="No recorded usage in this range")
            return
        width, height = canvas.winfo_width(), canvas.winfo_height()
        peak = max(v for _, v in points) or 1
        step = (width - 32) / len(points)
        for index, (day, value) in enumerate(points):
            x = 16 + index * step
            bar = canvas.create_rectangle(x, height-30-(height-60)*value/peak, x+step*.72, height-30, fill="#68d6eb", outline="")
            canvas.tag_bind(bar, "<Enter>", lambda _event, d=day, v=value: status.set(f"{d}: {v:,} tokens"))
        canvas.create_text(16, height-12, anchor="w", fill="white", text=points[0][0])
        canvas.create_text(width-16, height-12, anchor="e", fill="white", text=points[-1][0])

    def refresh():
        nonlocal busy
        if busy:
            return
        try:
            first, last = valid_range(start_var.get(), end_var.get())
        except ValueError as error:
            status.set(str(error))
            return
        busy = True
        button.state(["disabled"])
        status.set("Refreshing...")

        def work():
            try:
                messages.put(collector.refresh(first, last))
            except Exception as error:
                messages.put(error)
        threading.Thread(target=work, daemon=True).start()

    def poll():
        nonlocal busy, latest
        try:
            result = messages.get_nowait()
        except queue.Empty:
            pass
        else:
            busy = False
            button.state(["!disabled"])
            if isinstance(result, Exception):
                status.set("Refresh failed: " + str(result))
            else:
                latest = result
                for widget in allowance.winfo_children():
                    widget.destroy()
                for window in result["windows"]:
                    name = "Weekly" if window["minutes"] == 10080 else "5-hour"
                    rate = "Rate awaiting samples" if window["rate"] is None else f"{window['rate']:.1f} percentage points / 15 min"
                    ttk.Label(allowance, text=f"{name}  {100-window['used']:.0f}% remaining", font=("Segoe UI", 14, "bold")).pack(anchor="w")
                    ttk.Progressbar(allowance, value=100-window["used"]).pack(fill="x", pady=4)
                    reset = datetime.fromtimestamp(window["reset"]).strftime("%a %H:%M")
                    ttk.Label(allowance, text=f"{rate}   -   Resets {reset}").pack(anchor="w")
                if not result["windows"]:
                    ttk.Label(allowance, text="No current allowance reported").pack(anchor="w")
                total.config(text=f"{result['usage']['tokens']:,} tokens")
                status.set(("Cached - " if result["stale"] else "") + result["status"] + f" | {result['usage']['events']:,} usage events")
                draw()
        root.after(200, poll)

    def periodic():
        refresh()
        root.after(60_000, periodic)

    button = ttk.Button(controls, text="Refresh", command=refresh)
    button.pack(side="right")
    canvas.bind("<Configure>", draw)
    poll()
    periodic()
    if smoke:
        root.after(2000, root.destroy)
    root.mainloop()


def valid_range(start, end):
    try:
        first, last = date.fromisoformat(start), date.fromisoformat(end)
    except ValueError:
        raise ValueError("Use dates in YYYY-MM-DD format") from None
    if first > last or last > date.today():
        raise ValueError("Start must be before end, and end cannot be in the future")
    return first.isoformat(), last.isoformat()


def main():
    parser = argparse.ArgumentParser(description="Codex Usage Monitor by Italian-seasoning")
    parser.add_argument("--gui", action="store_true", help="Open the simple desktop window")
    parser.add_argument("--once", action="store_true", help="Print once and exit")
    parser.add_argument("--json", action="store_true", help="Print one machine-readable snapshot")
    parser.add_argument("--from", dest="start", default=(date.today()-timedelta(days=6)).isoformat())
    parser.add_argument("--to", dest="end", default=date.today().isoformat())
    parser.add_argument("--codex-home", type=Path, help="Override the Codex data directory")
    parser.add_argument("--smoke-test", action="store_true", help=argparse.SUPPRESS)
    args = parser.parse_args()
    try:
        start, end = valid_range(args.start, args.end)
    except ValueError as error:
        parser.error(str(error))
    collector = Collector(args.codex_home)
    if args.smoke_test:
        now = time.time()
        fixture = {"version": VERSION, "start": start, "end": end, "updated": now,
                   "plan": "pro", "stale": False, "status": "Demo data",
                   "windows": [{"minutes": 10080, "used": 28, "reset": now+86400, "observed": now, "rate": 1.2}],
                   "usage": {"tokens": 12000, "events": 3, "files": 1, "errors": 0, "days": {end: 12000}}}
        collector.refresh = lambda _start, _end: fixture
    if args.gui or (sys.platform == "win32" and not (args.once or args.json)):
        desktop(collector, start, end, args.smoke_test)
        return
    try:
        while True:
            data = collector.refresh(start, end)
            if args.json:
                print(json.dumps(data))
                break
            if sys.stdout.isatty() and not args.once:
                print("\033[2J\033[H", end="")
            print(ascii_view(data, shutil.get_terminal_size().columns), flush=True)
            if args.once or not sys.stdout.isatty():
                break
            time.sleep(60)
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
