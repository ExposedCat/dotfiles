"""Exercise install/restore behavior in temporary directories, without a desktop."""

import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch


spec = importlib.util.spec_from_file_location("hyprland_manage", Path(__file__).parents[1] / "manage.py")
manage = importlib.util.module_from_spec(spec)
spec.loader.exec_module(manage)


class InstallTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.source = self.root / "source"
        self.target = self.root / "config/hypr"
        self.backups = self.root / "state/backups"
        self.source.mkdir()
        (self.source / "hyprland.lua").write_text("new config")
        self.target.mkdir(parents=True)
        (self.target / "hyprland.lua").write_text("original config")
        (self.target / "hyprlock.conf").write_text("unrelated file")
        for key, value in (("SOURCE", self.source), ("TARGET", self.target), ("BACKUPS", self.backups)):
            patcher = patch.object(manage, key, value)
            patcher.start()
            self.addCleanup(patcher.stop)
        for key in ("verify", "reload_session"):
            patcher = patch.object(manage, key)
            setattr(self, key, patcher.start())
            self.addCleanup(patcher.stop)

    def test_install_noop_and_full_rollback(self):
        manage.install()
        self.assertEqual((self.target / "hyprland.lua").read_text(), "new config")
        self.assertEqual((self.target / "hyprlock.conf").read_text(), "unrelated file")
        self.assertEqual(len(list(self.backups.iterdir())), 1)
        manage.install()
        self.assertEqual(len(list(self.backups.iterdir())), 1)
        self.assertEqual(self.reload_session.call_count, 1)
        (self.target / "hyprlock.conf").write_text("later change")
        manage.rollback(None)
        self.assertEqual((self.target / "hyprland.lua").read_text(), "original config")
        self.assertEqual((self.target / "hyprlock.conf").read_text(), "unrelated file")
        saved = [p for p in self.backups.iterdir()
                 if json.loads((p / "metadata.json").read_text())["kind"] == "rollback"]
        self.assertEqual((saved[0] / "hypr/hyprlock.conf").read_text(), "later change")

    def test_invalid_staged_config_does_not_touch_installation(self):
        self.verify.side_effect = [None, RuntimeError("invalid module")]
        with self.assertRaisesRegex(RuntimeError, "invalid module"):
            manage.install()
        self.assertEqual((self.target / "hyprland.lua").read_text(), "original config")
        self.assertFalse(self.backups.exists())
        self.reload_session.assert_not_called()

    def test_support_files_are_installed_and_checked(self):
        (self.source / "tools").mkdir()
        (self.source / "tools/desktop.py").write_text("helper")
        (self.source / "hypridle.conf").write_text("idle config")
        manage.install()
        self.assertEqual((self.target / "tools/desktop.py").read_text(), "helper")
        self.assertEqual((self.target / "hypridle.conf").read_text(), "idle config")
        (self.target / "hypridle.conf").write_text("changed")
        self.assertEqual(manage.differences(), ["hypridle.conf"])

    def test_failed_reload_restores_original_files(self):
        self.reload_session.side_effect = [RuntimeError("reload failed"), None]
        with self.assertRaisesRegex(RuntimeError, "reload failed"):
            manage.install()
        self.assertEqual((self.target / "hyprland.lua").read_text(), "original config")
        self.assertEqual((self.target / "hyprlock.conf").read_text(), "unrelated file")
        self.assertEqual(self.reload_session.call_count, 2)

    def test_linked_module_directory_cannot_write_outside_staging(self):
        external = self.root / "external"
        external.mkdir()
        (external / "input.lua").write_text("keep me")
        (self.target / "modules").symlink_to(external, target_is_directory=True)
        (self.source / "modules").mkdir()
        (self.source / "modules/input.lua").write_text("replacement")
        with self.assertRaisesRegex(RuntimeError, "Linked configuration directory"):
            manage.install()
        self.assertEqual((external / "input.lua").read_text(), "keep me")
        self.assertEqual((self.target / "hyprland.lua").read_text(), "original config")


if __name__ == "__main__":
    unittest.main()
