"""Check source preservation and the order of replacing the system PDF viewer."""

import copy
import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch


spec = importlib.util.spec_from_file_location("local_apps", Path(__file__).with_name("manage.py"))
apps = importlib.util.module_from_spec(spec)
spec.loader.exec_module(apps)


class SetupTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.state = self.root / "state"
        self.state.mkdir()
        for target, value in (("STATE", self.state), ("SOURCES", copy.deepcopy(apps.SOURCES))):
            replacement = patch.object(apps, target, value)
            replacement.start()
            self.addCleanup(replacement.stop)
        replacement = patch.object(Path, "home", return_value=self.root)
        replacement.start()
        self.addCleanup(replacement.stop)

    def test_cache_key_is_read_only_and_scoped_to_the_app(self):
        with patch.object(apps, "host") as host:
            original = apps.build_key("papers")
            apps.SOURCES["bazecor"]["revision"] = "a" * 40
            self.assertEqual(original, apps.build_key("papers"))
            apps.SOURCES["papers"]["revision"] = "b" * 40
            self.assertNotEqual(original, apps.build_key("papers"))
            host.assert_not_called()

    def test_checkout_preserves_modified_source(self):
        repository = self.root / "upstream"
        subprocess.run(["git", "init", "--quiet", str(repository)], check=True)
        (repository / "file").write_text("original")
        subprocess.run(["git", "add", "file"], cwd=repository, check=True)
        subprocess.run(["git", "-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid",
                        "-c", "commit.gpgsign=false", "commit", "--quiet", "-m", "fixture"],
                       cwd=repository, check=True)
        revision = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=repository, text=True).strip()
        apps.SOURCES["papers"] = {"url": str(repository), "revision": revision}
        source = apps.checkout("papers")
        (source / "file").write_text("my changes")
        with self.assertRaisesRegex(RuntimeError, "Preserving modified build source"):
            apps.checkout("papers")
        self.assertEqual((source / "file").read_text(), "my changes")

    def test_equivalent_device_rules_do_not_request_administrator_authentication(self):
        source = self.state / "bazecor/source/src/main/utils/udev.ts"
        source.parent.mkdir(parents=True)
        source.write_text("const udevRulesToWrite = `\\\nrule\n`;\n")
        installed = subprocess.CompletedProcess([], 0, stdout="rule\n\n")
        with patch.object(apps.subprocess, "run", return_value=installed), patch.object(apps, "host") as host:
            apps.install_device_rules("bazecor")
            host.assert_not_called()

    def test_system_papers_is_removed_only_after_the_fork_is_confirmed(self):
        artifact = self.root / "repo"
        artifact.mkdir()
        (self.state / "papers").mkdir()
        for outcome in ("failed", "wrong-origin", "success"):
            calls = []

            def host(*args, **kwargs):
                calls.append(args)
                if args[:3] == ("flatpak", "--user", "remotes"):
                    return "papers-local"
                if args[:3] == ("flatpak", "--user", "install") and outcome == "failed":
                    raise subprocess.CalledProcessError(1, args)
                if args[:4] == ("flatpak", "--user", "info", "--show-origin"):
                    return "flathub" if outcome == "wrong-origin" else "papers-local"
                if args[:3] == ("flatpak", "--system", "list"):
                    return "org.gnome.Papers"
                return None

            with self.subTest(outcome=outcome), patch.object(apps, "host", side_effect=host):
                if outcome == "success":
                    apps.install("papers", artifact)
                    install = next(i for i, call in enumerate(calls) if call[:3] == ("flatpak", "--user", "install"))
                    confirmation = next(i for i, call in enumerate(calls) if call[:4] == ("flatpak", "--user", "info", "--show-origin"))
                    removal = next(i for i, call in enumerate(calls) if call[:3] == ("flatpak", "--system", "uninstall"))
                    self.assertLess(install, confirmation)
                    self.assertLess(confirmation, removal)
                else:
                    with self.assertRaises((RuntimeError, subprocess.CalledProcessError)):
                        apps.install("papers", artifact)
                    self.assertFalse(any(call[:3] == ("flatpak", "--system", "uninstall") for call in calls))
                self.assertFalse(any("--delete-data" in call for call in calls))


if __name__ == "__main__":
    unittest.main()
