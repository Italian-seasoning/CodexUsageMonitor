#!/usr/bin/env python3
"""Exercise the real installer in a temporary filesystem with OS command doubles."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
import zipfile


SCRIPT = Path(__file__).resolve().parents[1] / "scripts/install_widget.sh"
LSREGISTER = "/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister"
SHIM = r'''#!/usr/bin/env python3
import json, os, pathlib, subprocess, sys
name = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
root = pathlib.Path(os.environ["RUNWAY_TEST_ROOT"])
with (root / "commands.jsonl").open("a") as log:
    log.write(json.dumps([name, args]) + "\n")
if name == "xcodebuild":
    app = pathlib.Path(args[args.index("-derivedDataPath") + 1]) / "Build/Products/Release/Runway.app"
    (app / "Contents/PlugIns/RunwayWidget.appex").mkdir(parents=True, exist_ok=True)
    (app / "payload").write_text("new")
elif name == "launchctl":
    state = root / "loaded.json"
    loaded = json.loads(state.read_text())
    label = args[-1].split("/")[-1].removesuffix(".plist")
    if args[0] == "print":
        sys.exit(0 if label in loaded else 113)
    if args[0] == "bootout":
        if os.environ.get("RUNWAY_TEST_FAIL_BOOTOUT") and "CodexUsageMonitor" in label:
            sys.exit(1)
        loaded.remove(label)
    elif args[0] == "bootstrap":
        if os.environ.get("RUNWAY_TEST_FAIL_BOOTSTRAP"):
            sys.exit(1)
        loaded.append(label)
    state.write_text(json.dumps(loaded))
elif name == "pgrep":
    sys.exit(0 if os.environ.get("RUNWAY_TEST_APP_RUNNING") == "1" and "CodexUsageMonitor" not in args[-1] else 1)
elif name == "mv":
    if os.environ.get("RUNWAY_TEST_FAIL_MOVE") and "New-Runway.app" in args[0]:
        sys.exit(1)
    sys.exit(subprocess.call(["/bin/mv"] + args))
elif name == "ditto":
    if os.environ.get("RUNWAY_TEST_FAIL_STAGE") and "-c" not in args:
        sys.exit(1)
    if os.environ.get("RUNWAY_TEST_FAIL_ARCHIVE") and "-c" in args:
        sys.exit(1)
    sys.exit(subprocess.call(["/usr/bin/ditto"] + args))
elif name == "lsregister" and os.environ.get("RUNWAY_TEST_FAIL_UNREGISTER"):
    if args == ["-u", str(root / "Applications/Runway.app")]:
        sys.exit(1)
'''


class InstallChecks(unittest.TestCase):
    def run_install(self, failure=None, legacy_real=False, lock_busy=False, app_symlink=False,
                    running=True, loaded=("Runway", "CodexUsageMonitor")):
        temporary = tempfile.TemporaryDirectory(prefix="runway-install-check-")
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name)
        (root / "scripts").mkdir()
        (root / "bin").mkdir()
        (root / "agents").mkdir()
        (root / "scratch").mkdir()
        (root / "cache").mkdir()
        if lock_busy:
            (root / "cache/install.lock").write_text(str(os.getpid()) + "\n")
        app = root / "Applications/Runway.app"
        if app_symlink:
            target = app.with_name("Original.app")
            target.mkdir(parents=True)
            app.symlink_to("Original.app")
        else:
            app.mkdir(parents=True)
        (app / "payload").write_text("previous")
        alias = app.with_name("CodexUsageMonitor.app")
        if legacy_real:
            alias.mkdir()
            (alias / "payload").write_text("legacy")
        else:
            alias.symlink_to("Runway.app")
        for label in ("Runway", "CodexUsageMonitor"):
            (root / f"agents/com.codexusage.{label}.refresh.plist").write_text("old job")
        (root / "loaded.json").write_text(json.dumps([f"com.codexusage.{label}.refresh" for label in loaded]))
        for name in ("xcodebuild", "launchctl", "pgrep", "pkill", "pluginkit", "open", "killall", "lsregister", "mv", "ditto"):
            command = root / "bin" / name
            command.write_text(SHIM)
            command.chmod(0o755)
        source = SCRIPT.read_text().replace("/Applications/", str(root / "Applications") + "/")
        source = source.replace("$HOME/Library/LaunchAgents", str(root / "agents"))
        source = source.replace("$HOME/Library/Caches/com.codexusage.Runway", str(root / "cache"))
        for original, name in ((LSREGISTER, "lsregister"), ("/usr/bin/open", "open"), ("/usr/bin/killall", "killall")):
            source = source.replace(original, str(root / "bin" / name))
        fixture = root / "scripts/install_widget.sh"
        fixture.write_text(source)
        environment = dict(os.environ, PATH=str(root / "bin") + os.pathsep + os.environ["PATH"],
                           TMPDIR=str(root / "scratch") + "/", RUNWAY_TEST_ROOT=str(root),
                           RUNWAY_TEST_APP_RUNNING="1" if running else "0")
        if failure:
            environment[failure] = "1"
        if failure == "RUNWAY_TEST_FAIL_BOOTSTRAP_AND_MOVE":
            environment.update(RUNWAY_TEST_FAIL_BOOTSTRAP="1", RUNWAY_TEST_FAIL_MOVE="1")
        result = subprocess.run(["/bin/bash", str(fixture)], env=environment, capture_output=True, text=True, timeout=30)
        commands = [json.loads(line) for line in (root / "commands.jsonl").read_text().splitlines()]
        return root, app, alias, result, commands

    def test_success_archives_previous_app_and_removes_alias_and_agents(self):
        root, app, alias, result, commands = self.run_install()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((app / "payload").read_text(), "new")
        self.assertFalse(alias.is_symlink(), "legacy app alias must not be recreated")
        self.assertEqual(list((root / "agents").glob("*.plist")), [])
        backups = list((root / "build/install-backups.noindex").rglob("Previous-Runway.app.zip"))
        self.assertEqual(len(backups), 1)
        with zipfile.ZipFile(backups[0]) as archive:
            self.assertEqual(archive.read("Runway.app/payload"), b"previous")
        self.assertEqual(list(backups[0].parent.rglob("*.app")), [])
        actions = [args for name, args in commands if name == "lsregister"]
        self.assertIn(["-u", str(app)], actions)
        build = next(args for name, args in commands if name == "xcodebuild")
        derived = Path(build[build.index("-derivedDataPath") + 1])
        self.assertTrue(any(args[0] == "-u" and Path(args[1]) == derived / "Build/Products/Release/Runway.app"
                            for args in actions))
        self.assertFalse(derived.exists(), "temporary build must not remain a discoverable app")
        self.assertFalse((root / "cache/install.lock").exists())
        self.assertIn(["-f", "-R", "-trusted", str(app)], actions)

    def test_failed_replacement_restores_previous_app(self):
        root, app, _, result, commands = self.run_install("RUNWAY_TEST_FAIL_MOVE")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((app / "payload").read_text(), "previous")
        self.assertIn(("open", [str(app)]), [(name, args) for name, args in commands])
        self.assert_previous_agents(root)

    def test_failed_archiving_preserves_installed_app(self):
        root, app, _, result, commands = self.run_install("RUNWAY_TEST_FAIL_ARCHIVE")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((app / "payload").read_text(), "previous")
        self.assert_previous_agents(root)
        self.assertFalse(any(name == "pkill" for name, _ in commands))

    def test_failed_retirement_restores_displaced_legacy_app(self):
        root, app, legacy, result, commands = self.run_install("RUNWAY_TEST_FAIL_UNREGISTER", legacy_real=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((app / "payload").read_text(), "previous")
        self.assertEqual((legacy / "payload").read_text(), "legacy")
        self.assertTrue(any(name == "open" for name, _ in commands))
        self.assert_previous_agents(root)

    def assert_previous_agents(self, root, loaded=("Runway", "CodexUsageMonitor")):
        for label in ("Runway", "CodexUsageMonitor"):
            self.assertEqual((root / f"agents/com.codexusage.{label}.refresh.plist").read_text(), "old job")
        self.assertEqual(set(json.loads((root / "loaded.json").read_text())),
                         {f"com.codexusage.{label}.refresh" for label in loaded})

    def test_staging_failure_does_not_stop_running_app_or_agents(self):
        root, _, _, result, commands = self.run_install("RUNWAY_TEST_FAIL_STAGE")
        self.assertNotEqual(result.returncode, 0)
        self.assert_previous_agents(root)
        self.assertFalse(any(name == "pkill" for name, _ in commands))

    def test_rollback_does_not_load_disabled_agent_or_launch_closed_app(self):
        root, _, _, result, commands = self.run_install("RUNWAY_TEST_FAIL_MOVE", running=False, loaded=("Runway",))
        self.assertNotEqual(result.returncode, 0)
        self.assert_previous_agents(root, loaded=("Runway",))
        self.assertFalse(any(name == "open" for name, _ in commands))

    def test_partial_agent_retirement_restores_previous_configuration(self):
        root, _, _, result, _ = self.run_install("RUNWAY_TEST_FAIL_BOOTOUT")
        self.assertNotEqual(result.returncode, 0)
        self.assert_previous_agents(root)

    def test_failed_agent_restoration_keeps_recovery_copies(self):
        root, app, _, result, _ = self.run_install("RUNWAY_TEST_FAIL_BOOTSTRAP_AND_MOVE")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((app / "payload").read_text(), "previous")
        self.assertEqual(len(list((root / "scratch").glob("runway-install.*/Agents/*.plist"))), 2)
        self.assertIn("recovery files retained", result.stderr)

    def test_busy_installer_does_not_replace_app_or_retire_agents(self):
        root, app, _, result, commands = self.run_install(lock_busy=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((app / "payload").read_text(), "previous")
        self.assertEqual(len(list((root / "agents").glob("*.plist"))), 2)
        self.assertFalse(any(name in ("pkill", "mv", "open") for name, _ in commands))

    def test_failed_replacement_restores_relative_app_symlink(self):
        _, app, _, result, _ = self.run_install("RUNWAY_TEST_FAIL_MOVE", app_symlink=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(app.is_symlink())
        self.assertEqual(os.readlink(app), "Original.app")
        self.assertEqual((app / "payload").read_text(), "previous")


if __name__ == "__main__":
    unittest.main()
