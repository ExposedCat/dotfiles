"""Check byte-preserving clipboard recall and lock readiness without a desktop."""

import contextlib
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch


spec = importlib.util.spec_from_file_location("hyprland_desktop", Path(__file__).parents[1] / "config/tools/desktop.py")
desktop = importlib.util.module_from_spec(spec)
spec.loader.exec_module(desktop)


class DesktopTests(unittest.TestCase):
    def test_clipboard_copy_preserves_binary_content(self):
        binary = b"\x89PNG\r\n\x1a\n\x00\xff\t\n"
        with patch.object(desktop, "run") as call:
            call.return_value.stdout = binary
            desktop.clipboard_copy("25")
        self.assertEqual(call.call_args_list[0].args, ("cliphist", "decode"))
        self.assertEqual(call.call_args_list[0].kwargs["input"], b"25")
        self.assertEqual(call.call_args_list[1].kwargs["input"], binary)

    def test_clipboard_preview_is_data_not_an_executable_command(self):
        result = subprocess.CompletedProcess([], 0, '25\t<script>$(touch unwanted)</script>\n26\timage preview\n', '')
        with patch.object(desktop.subprocess, "run", return_value=result), contextlib.redirect_stdout(io.StringIO()) as output:
            desktop.clipboard_list()
        self.assertEqual(json.loads(output.getvalue())[0], {"id": "25", "preview": "<script>$(touch unwanted)</script>"})

    def test_idle_verification_is_invalidated_by_lock_configuration_changes(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            state = root / "state"
            state.mkdir()
            config = root / "hyprlock.conf"
            config.write_text("tested config")
            with patch.object(desktop, "ROOT", root), patch.object(desktop, "STATE", state):
                self.assertFalse(desktop.idle_ready())
                (state / "lock-verified").write_text(desktop.hashlib.sha256(config.read_bytes()).hexdigest())
                self.assertTrue(desktop.idle_ready())
                config.write_text("changed config")
                self.assertFalse(desktop.idle_ready())


if __name__ == "__main__":
    unittest.main()
