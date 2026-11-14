"""Check brightness feedback, clipboard recall, and services without a desktop."""

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
    def test_copy_text_preserves_a_negative_scientific_result(self):
        with patch.object(desktop.sys, "argv", ["desktop.py", "copy-text", "--", "-1e+20"]), patch.object(desktop, "run") as run:
            desktop.main()
        self.assertEqual(run.call_args.args, ("wl-copy",))
        self.assertEqual(run.call_args.kwargs["input"], b"-1e+20")

    def test_launcher_routes_to_the_persistent_pill(self):
        with patch.object(desktop.sys, "argv", ["desktop.py", "launcher"]), patch.object(desktop, "run") as run:
            desktop.main()
        self.assertEqual(run.call_args.args[-4:], ("call", "shell", "toggle", "launcher"))

    def test_pill_forwards_input_ordering_timestamp(self):
        with patch.object(desktop.sys, "argv", ["desktop.py", "pill", "hide", "12345"]), patch.object(desktop, "run") as run:
            desktop.main()
        self.assertEqual(run.call_args.args[-5:], ("call", "shell", "gesture", "hide", "12345"))

    def brightness(self, reading="VCP 10 C 85 200\n", direction="up", failure=None):
        monitors = [{"name": "DP-1", "serial": "OTHER", "focused": False},
                    {"name": "DP-3", "serial": "FOCUSED", "focused": True}]

        def result(*args, **kwargs):
            if args[0] == "hyprctl":
                return subprocess.CompletedProcess(args, 0, json.dumps(monitors))
            if "getvcp" in args:
                return subprocess.CompletedProcess(args, 0, reading)
            if failure and (args[0] == "quickshell" or "setvcp" in args):
                raise failure(args)
            return subprocess.CompletedProcess(args, 0, "")

        with tempfile.TemporaryDirectory() as temporary, \
             patch.dict(desktop.os.environ, XDG_RUNTIME_DIR=temporary), \
             patch.object(desktop, "run", side_effect=result) as run:
            desktop.brightness(direction)
        return run.call_args_list

    def test_brightness_reports_readback_for_the_original_focused_monitor(self):
        for direction, sign in (("up", "+"), ("down", "-")):
            with self.subTest(direction=direction):
                calls = self.brightness(direction=direction)
                self.assertEqual(calls[1].args, ("ddcutil", "--sn", "FOCUSED", "--noverify", "setvcp", "10", sign, "5"))
                self.assertEqual(calls[2].args, ("ddcutil", "--sn", "FOCUSED", "--terse", "getvcp", "10"))
                self.assertEqual(calls[3].args[-5:], ("shell", "brightness", "DP-3", "85", "200"))

    def test_failed_brightness_write_does_not_read_or_show_a_level(self):
        def fail(args):
            return subprocess.CalledProcessError(1, args)
        with self.assertRaises(subprocess.CalledProcessError):
            self.brightness(failure=fail)

    def test_invalid_brightness_readback_is_rejected(self):
        for reading in ("VCP 10 ERR", "VCP 10 C 20 0", "VCP 10 C 201 200", "VCP 10 C unknown 100"):
            with self.subTest(reading=reading), self.assertRaises(RuntimeError):
                self.brightness(reading=reading)

    def test_busy_brightness_write_is_dropped(self):
        with patch.object(desktop.fcntl, "flock", side_effect=BlockingIOError), \
             patch.object(desktop, "run", return_value=subprocess.CompletedProcess([], 0, '[{"name":"DP-3","serial":"FOCUSED","focused":true}]')) as run, \
             tempfile.TemporaryDirectory() as temporary, patch.dict(desktop.os.environ, XDG_RUNTIME_DIR=temporary):
            desktop.brightness("up")
        self.assertEqual(run.call_count, 1)

    def test_missing_osd_does_not_fail_a_successful_brightness_change(self):
        def result(*args, **kwargs):
            if args[0] == "hyprctl":
                return subprocess.CompletedProcess(args, 0, '[{"name":"DP-3","serial":"FOCUSED","focused":true}]')
            if "getvcp" in args:
                return subprocess.CompletedProcess(args, 0, "VCP 10 C 100 100")
            if args[0] == "quickshell":
                raise subprocess.CalledProcessError(1, args)
            return subprocess.CompletedProcess(args, 0, "")
        with tempfile.TemporaryDirectory() as temporary, patch.dict(desktop.os.environ, XDG_RUNTIME_DIR=temporary), \
             patch.object(desktop, "run", side_effect=result):
            desktop.brightness("up")

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

    def test_session_stops_legacy_idle_even_with_old_verification_marker(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            state = root / "state"
            state.mkdir()
            (state / "lock-verified").write_text("old verification")
            with patch.object(desktop, "ROOT", root), patch.object(desktop, "STATE", state), \
                 patch.dict(desktop.os.environ, XDG_CURRENT_DESKTOP="Hyprland", XDG_RUNTIME_DIR=temporary), \
                 patch.object(desktop, "active", return_value=True), patch.object(desktop, "service") as service, \
                 patch.object(desktop, "run") as run:
                desktop.session_start(refresh=True)
            self.assertIn(unittest.mock.call("systemctl", "--user", "stop", desktop.PREFIX + "idle"), run.call_args_list)
            self.assertFalse(any(call.args[0] == "idle" for call in service.call_args_list))

    def test_shell_start_waits_for_a_valid_ipc_reply(self):
        replies = [subprocess.CompletedProcess([], 0, "Not ready to accept queries yet.\n", ""),
                   subprocess.CompletedProcess([], 0, '{"polkit":true}', "")]
        with patch.object(desktop.subprocess, "run", side_effect=replies) as run, \
             patch.object(desktop.time, "sleep"):
            desktop.wait_shell()
        self.assertEqual(run.call_count, 2)

    def test_shell_that_exits_before_loading_fails_installation(self):
        reply = subprocess.CompletedProcess([], 1, "", "No running instances")
        with patch.object(desktop.subprocess, "run", return_value=reply), patch.object(desktop.time, "sleep"):
            with self.assertRaisesRegex(RuntimeError, "did not become ready"):
                desktop.wait_shell()

    def test_capture_worker_waits_for_graphics_warmup(self):
        replies = [subprocess.CompletedProcess([], 0, '{"ready":false}', ""),
                   subprocess.CompletedProcess([], 0, '{"ready":true}', "")]
        with patch.object(desktop.subprocess, "run", side_effect=replies) as run, \
             patch.object(desktop.time, "sleep"):
            desktop.wait_shell("tools/capture-daemon.qml", "capture", "ready")
        self.assertEqual(run.call_count, 2)


if __name__ == "__main__":
    unittest.main()
