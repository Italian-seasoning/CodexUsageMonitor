import json
from pathlib import Path
import tempfile
import time
import unittest
from unittest.mock import patch

from monitor import Collector, ascii_view, limits_from, rate_per_15, valid_range


class MonitorTests(unittest.TestCase):
    def test_pro_hides_five_hour(self):
        for plan in ("pro", "prolite", "Pro"):
            data = limits_from({"rateLimits": {"planType": plan,
                "primary": {"usedPercent": 25, "windowDurationMins": 300, "resetsAt": 2000},
                "secondary": {"usedPercent": 40, "windowDurationMins": 10080, "resetsAt": 3000}}}, 1000)
            self.assertEqual([w["minutes"] for w in data["windows"]], [10080])

    def test_window_duration_not_position(self):
        result = {"rateLimitsByLimitId": {"codex": {"planType": "plus",
            "primary": {"usedPercent": 25, "windowDurationMins": 10080, "resetsAt": 2000}}}}
        self.assertEqual(limits_from(result, 1000)["windows"][0]["minutes"], 10080)
        self.assertEqual(limits_from({"rateLimits": {}}, 1000)["windows"], [])
        with self.assertRaises(ValueError):
            limits_from({}, 1000)

    def test_invalid_windows(self):
        for used in (-1, 101, float("nan"), None, True):
            result = {"rateLimits": {"primary": {"usedPercent": used, "windowDurationMins": 10080, "resetsAt": 2000}}}
            self.assertEqual(limits_from(result, 1000)["windows"], [])

    def test_rates_exclude_stale_gaps_and_resets(self):
        points = [{"observed": t, "used": v, "reset": 9000, "minutes": 10080}
                  for t, v in ((1000, 10), (1300, 12), (1600, 14), (1900, 16))]
        self.assertEqual(rate_per_15(points[-1], points, 1900), 6)
        self.assertIsNone(rate_per_15(points[-1], points, 2500))
        self.assertIsNone(rate_per_15(points[-1], [points[0], points[-1]], 1900))
        self.assertIsNone(rate_per_15({**points[-1], "reset": 10000}, points, 1900))
        points[2]["used"] = 0
        self.assertIsNone(rate_per_15(points[-1], points, 1900))

    def test_history_cache_archive_dedup_and_range(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "sessions").mkdir()
            (root / "archived_sessions").mkdir()
            def event(day, total, delta):
                return json.dumps({"timestamp": f"2026-01-{day:02}T12:00:00Z", "payload": {"type": "token_count", "info": {
                    "total_token_usage": {"total_tokens": total}, "last_token_usage": {"total_tokens": delta}}}}) + "\n"
            content = event(10, 100, 100) + event(10, 100, 100) + "broken\n" + event(11, 140, 40)
            path = root / "sessions" / "chat.jsonl"
            path.write_text(content)
            (root / "archived_sessions" / "copy.jsonl").write_text(content)
            collector = Collector(root, root / "state")
            self.assertEqual(collector.usage("2026-01-01", "2026-01-31")["tokens"], 140)
            self.assertEqual(collector.usage("2026-01-11", "2026-01-11")["tokens"], 40)
            with path.open("a") as file:
                file.write(event(12, 160, 20))
            self.assertEqual(collector.usage("2026-01-01", "2026-01-31")["tokens"], 160)
            path.unlink()
            self.assertEqual(collector.usage("2026-01-01", "2026-01-31")["tokens"], 140)

    def test_failure_preserves_cached_account_and_throttles(self):
        with tempfile.TemporaryDirectory() as directory:
            collector = Collector(directory, Path(directory) / "state")
            now = time.time()
            account = {"plan": "pro", "observed": now, "windows": [{"used": 30, "minutes": 10080, "reset": now+1000, "observed": now}]}
            with patch("monitor.read_account", return_value=account) as request:
                collector.refresh("2026-01-01", "2026-01-02")
                collector.refresh("2026-01-01", "2026-01-02")
                self.assertEqual(request.call_count, 1)
            collector.last_attempt = 0
            with patch("monitor.read_account", side_effect=RuntimeError("Offline")):
                result = collector.refresh("2026-01-01", "2026-01-02")
            self.assertTrue(result["stale"])
            self.assertEqual(result["windows"][0]["used"], 30)
            self.assertEqual(Collector(directory, Path(directory) / "state").account, account)
            rendered = ascii_view(result)
            self.assertTrue(rendered.isascii())
            self.assertNotIn("5-hour", rendered)
            self.assertIn("STALE", rendered)

    def test_date_validation(self):
        self.assertEqual(valid_range("2026-01-01", "2026-01-01"), ("2026-01-01", "2026-01-01"))
        for first, last in (("bad", "2026-01-01"), ("2026-02-01", "2026-01-01"), ("2026-01-01", "2999-01-01")):
            with self.assertRaises(ValueError):
                valid_range(first, last)

    def test_fork_replay_and_subagents(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "sessions").mkdir()
            def write(name, identities, totals, subagent=False):
                rows = [{"type": "session_meta", "payload": {"id": identities[0],
                         "session_id": identities[-1], "timestamp": f"2026-01-{len(totals):02}T00:00:00Z",
                         "thread_source": "subagent" if subagent else "cli"}}]
                rows += [{"timestamp": f"2026-01-{len(totals):02}T12:{i:02}:00Z", "payload": {
                    "type": "token_count", "info": {"total_token_usage": {"total_tokens": total},
                    "last_token_usage": {"total_tokens": 10}}}} for i, total in enumerate(totals)]
                (root / "sessions" / name).write_text("\n".join(map(json.dumps, rows)))
            write("parent.jsonl", ["parent"], [10])
            write("fork.jsonl", ["fork", "parent"], [10, 20])
            write("agent.jsonl", ["agent"], [10, 20, 30], subagent=True)
            self.assertEqual(Collector(root, root / "state").usage("2026-01-01", "2026-01-31")["tokens"], 20)


if __name__ == "__main__":
    unittest.main()
