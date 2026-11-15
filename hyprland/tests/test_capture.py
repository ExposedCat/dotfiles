"""Geometry and output checks without capturing the working desktop."""

import base64
import importlib.util
import json
import os
import shutil
import signal
import subprocess
from pathlib import Path
import tempfile
import unittest
from unittest.mock import Mock, patch


spec = importlib.util.spec_from_file_location("capture", Path(__file__).parents[1] / "config/tools/capture.py")
try:
    from PIL import Image
except ImportError:
    Image = None

capture = importlib.util.module_from_spec(spec)
spec.loader.exec_module(capture)


class CaptureTests(unittest.TestCase):
    def test_warm_capture_returns_when_ui_signals_completion(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            (directory / "result.json").write_text('{"done":true}')
            responses = [subprocess.CompletedProcess([], 0, "123\n", ""),
                         subprocess.CompletedProcess([], 0, "true\n", "")]
            with patch.object(capture.subprocess, "run", side_effect=responses) as run:
                self.assertTrue(capture.open_warm_capture(directory))
            self.assertIn("capture-daemon.qml", run.call_args.args[0][3])

    def test_missing_warm_worker_uses_cold_fallback(self):
        response = subprocess.CompletedProcess([], 0, "0\n", "")
        with patch.object(capture.subprocess, "run", return_value=response) as run:
            self.assertFalse(capture.open_warm_capture(Path("/unused")))
        self.assertEqual(run.call_count, 1)

    def test_crashed_warm_worker_does_not_leave_shortcut_waiting(self):
        responses = [subprocess.CompletedProcess([], 0, "123\n", ""),
                     subprocess.CompletedProcess([], 0, "true\n", "")]
        with tempfile.TemporaryDirectory() as temporary, \
             patch.object(capture.subprocess, "run", side_effect=responses), \
             patch.object(capture.os, "kill", side_effect=ProcessLookupError):
            with self.assertRaisesRegex(RuntimeError, "stopped before finishing"):
                capture.open_warm_capture(Path(temporary))

    def test_capture_outputs_finishes_both_raw_variants_and_skips_disabled_displays(self):
        monitors = [{"name": "HP", "x": 0, "y": 1080, "width": 2560, "height": 1440,
                     "scale": 1, "focused": True},
                    {"name": "disabled", "disabled": True}]
        def write_raw(*command):
            Path(command[-1]).write_bytes(b"P6\n1 1\n255\n\x60\x90\xc0")
        with tempfile.TemporaryDirectory() as temporary, patch.object(capture, "run", side_effect=write_raw) as call:
            outputs = capture.capture_outputs(monitors, Path(temporary))
            self.assertEqual(len(outputs), 1)
            self.assertEqual(call.call_count, 2)
            self.assertEqual(outputs[0]["width"], 2560)
            self.assertTrue((Path(temporary) / "screen-0.ppm").is_file())
            self.assertTrue((Path(temporary) / "screen-0-cursor.ppm").is_file())
            self.assertTrue(all(command.args[1:3] == ("-t", "ppm") for command in call.call_args_list))

    def test_failed_parallel_capture_is_reported(self):
        monitors = [{"name": "HP", "x": 0, "y": 0, "width": 2560, "height": 1440,
                     "scale": 1, "focused": True}]
        with tempfile.TemporaryDirectory() as temporary, patch.object(capture, "run", side_effect=RuntimeError("capture failed")):
            with self.assertRaisesRegex(RuntimeError, "capture failed"):
                capture.capture_outputs(monitors, Path(temporary))

    def test_window_selection_preserves_global_coordinates(self):
        outputs = [{"name": "Dell", "x": 320, "y": 0, "width": 1920, "height": 1080},
                   {"name": "HP", "x": 0, "y": 1080, "width": 2560, "height": 1440}]
        selected = capture.window_selection({"at": [120, 1100], "size": [600, 400]}, outputs)
        self.assertEqual(selected, {"x": 120, "y": 1100, "width": 600, "height": 400})

    def test_window_selection_clips_offscreen_pixels(self):
        outputs = [{"name": "HP", "x": 0, "y": 1080, "width": 2560, "height": 1440}]
        selected = capture.window_selection({"at": [-20, 1080], "size": [100, 100]}, outputs)
        self.assertEqual(selected["x"], 0)
        self.assertEqual(selected["width"], 80)
        with self.assertRaisesRegex(RuntimeError, "no active window"):
            capture.window_selection({}, outputs)

    def test_record_shortcut_stops_active_recording_without_opening_selector(self):
        with patch.object(capture, "recording", return_value=True), patch.object(capture.subprocess, "run"), patch.object(capture, "run") as call:
            capture.select("record")
        call.assert_called_once_with("systemctl", "--user", "stop", capture.RECORD_UNIT)

    def test_recording_geometry_and_cursor_option(self):
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary) / "video.mp4"
            output.write_bytes(b"fixture")
            data = {"outputs": [{"name": "Dell", "x": 320, "y": 0, "width": 1920, "height": 1080}]}
            with patch.object(capture, "session", return_value=(Path(temporary), data)), \
                 patch.object(capture, "output_path", return_value=output), patch.object(capture, "run") as call:
                capture.record_area("Dell", 400, 200, 641, 481, False)
                args = call.call_args.args
                self.assertEqual(args[args.index("--geometry") + 1], "720,200 640x480")
                self.assertIn("--no-cursor", args)
                self.assertIn("--property=KillSignal=SIGINT", args)
                capture.record_area("Dell", 400, 200, 640, 480, True)
                self.assertNotIn("--no-cursor", call.call_args.args)

    def test_window_selection_spans_outputs_and_negative_coordinates(self):
        outputs = [{"name": "Left", "x": -800, "y": 0, "width": 800, "height": 600},
                   {"name": "Right", "x": 0, "y": 100, "width": 1200, "height": 800}]
        rect = capture.window_selection({"at": [-200, 50], "size": [600, 400]}, outputs)
        self.assertEqual(rect, {"x": -200, "y": 50, "width": 600, "height": 400})
        self.assertEqual(len(capture.selected_outputs(rect, outputs)), 2)

    def test_preferences_round_trip_separate_regions_and_cursor(self):
        with tempfile.TemporaryDirectory() as temporary, patch.dict(os.environ, {"XDG_STATE_HOME": temporary}):
            value = {"region": {"x": -100, "y": 25, "width": 200, "height": 80},
                     "record": {"x": 10, "y": 40, "width": 500, "height": 200}, "cursor": True}
            capture.save_preferences(value)
            self.assertEqual(capture.load_preferences(), value)
            self.assertEqual(capture.preferences_path().stat().st_mode & 0o777, 0o600)
            capture.preferences_path().write_text("invalid")
            self.assertEqual(capture.load_preferences(), {})

    def test_desktop_recording_does_not_clip_at_monitor_boundary(self):
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary) / "video.mp4"
            output.write_bytes(b"fixture")
            data = {"outputs": [{"name": "Left", "x": -800, "y": 0, "width": 800, "height": 600},
                                {"name": "Right", "x": 0, "y": 0, "width": 800, "height": 600}]}
            with patch.object(capture, "session", return_value=(Path(temporary), data)), \
                 patch.object(capture, "output_path", return_value=output), patch.object(capture, "run") as call:
                capture.record_area("desktop", -200, 30, 401, 301, True)
                args = call.call_args.args
                self.assertIn("record-worker", args)
                self.assertEqual(json.loads(args[args.index("record-worker") + 1]),
                                 {"x": -200, "y": 30, "width": 400, "height": 300})
                self.assertIn("--property=KillMode=mixed", args)

    @unittest.skipUnless(Image, "Pillow is required for direct window capture")
    def test_frozen_composite_handles_scaling_offsets_and_empty_gaps(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            Image.new("RGB", (40, 60), "red").save(root / "left.png")
            Image.new("RGB", (80, 80), "lime").save(root / "right.png")
            outputs = [{"name": "Left", "x": -40, "y": 0, "width": 40, "height": 60, "scale": 1,
                        "plain": (root / "left.png").as_uri()},
                       {"name": "Right", "x": 20, "y": 20, "width": 40, "height": 40, "scale": 2,
                        "plain": (root / "right.png").as_uri()}]
            im = capture.frozen_image(outputs, {"x": -20, "y": 0, "width": 80, "height": 60})
            self.assertEqual(im.size, (160, 120))
            self.assertEqual(im.getpixel((10, 60)), (255, 0, 0))
            self.assertEqual(im.getpixel((60, 60)), (0, 0, 0))
            self.assertEqual(im.getpixel((110, 60)), (0, 255, 0))
            self.assertEqual(im.getpixel((110, 10)), (0, 0, 0))

    @unittest.skipUnless(Image, "Pillow is required for direct window capture")
    def test_window_shortcut_copies_and_saves_without_launching_ui(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            Image.new("RGB", (100, 100), "red").save(root / "screen.png")
            Image.new("RGB", (100, 100), "lime").save(root / "cursor.png")
            outputs = [{"name": "Main", "x": 0, "y": 0, "width": 100, "height": 100, "scale": 1,
                        "plain": (root / "screen.png").as_uri(), "cursor": (root / "cursor.png").as_uri()}]
            def run(*args, **kwargs):
                if args[:2] == ("hyprctl", "monitors"):
                    return subprocess.CompletedProcess(args, 0, "[]")
                if args[:2] == ("hyprctl", "activewindow"):
                    return subprocess.CompletedProcess(args, 0, '{"at":[10,20],"size":[30,40]}')
            with patch.dict(os.environ, {"XDG_RUNTIME_DIR": temporary}), \
                 patch.object(capture, "capture_outputs", return_value=outputs), \
                 patch.object(capture, "load_preferences", return_value={"cursor": True}), \
                 patch.object(capture, "output_path", return_value=root / "saved.png"), \
                 patch.object(capture, "open_warm_capture") as warm, patch.object(capture, "run", side_effect=run) as call:
                capture.select("window")
                warm.assert_not_called()
                self.assertEqual(call.call_args.args, ("wl-copy", "--type", "image/png"))
                self.assertEqual(call.call_args.kwargs["input"], (root / "saved.png").read_bytes())
                with Image.open(root / "saved.png") as image:
                    self.assertEqual(image.size, (30, 40))
                    self.assertEqual(image.getpixel((0, 0)), (0, 255, 0))

    @unittest.skipUnless(Image and shutil.which("ffmpeg") and shutil.which("ffprobe"), "Pillow and FFmpeg required")
    def test_video_composition_keeps_output_positions_scale_and_gaps(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            for name, color, size in [("left", "red", "40x60"), ("right", "lime", "80x80")]:
                subprocess.run(["ffmpeg", "-v", "error", "-f", "lavfi", "-i", f"color=c={color}:s={size}:d=0.3",
                                "-c:v", "ffv1", str(root / (name + ".mkv"))], check=True)
            clips = [{"path": root / "left.mkv", "output": {"x": -40, "y": 0, "width": 40, "height": 60, "scale": 1}},
                     {"path": root / "right.mkv", "output": {"x": 20, "y": 20, "width": 40, "height": 40, "scale": 2}}]
            capture.compose_recordings(clips, {"x": -20, "y": 0, "width": 80, "height": 60}, root / "result.mp4")
            subprocess.run(["ffmpeg", "-v", "error", "-ss", "0.1", "-i", str(root / "result.mp4"),
                            "-frames:v", "1", str(root / "frame.png")], check=True)
            with Image.open(root / "frame.png") as image:
                self.assertEqual(image.size, (160, 120))
                self.assertGreater(image.getpixel((10, 60))[0], 220)
                self.assertLess(max(image.getpixel((60, 60))), 20)
                self.assertGreater(image.getpixel((110, 60))[1], 220)
                self.assertLess(max(image.getpixel((110, 10))), 20)

    def test_record_worker_stops_owned_children_then_combines_and_cleans_parts(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            outputs = [{"name": "Left", "x": -400, "y": 0, "width": 400, "height": 300},
                       {"name": "Right", "x": 0, "y": 0, "width": 400, "height": 300}]
            children = []
            def start(command):
                Path(command[command.index("--filename") + 1]).write_bytes(b"fixture")
                process = Mock()
                process.poll.return_value = None
                process.wait.side_effect = lambda **_: setattr(process.poll, "return_value", 0)
                children.append(process)
                return process
            previous = signal.getsignal(signal.SIGINT)
            rect = {"x": -100, "y": 20, "width": 200, "height": 100}
            with patch.object(capture, "session", return_value=(root, {"outputs": outputs})), \
                 patch.object(capture.subprocess, "Popen", side_effect=start) as spawn, \
                 patch.object(capture.time, "sleep", side_effect=lambda _: signal.getsignal(signal.SIGINT)()), \
                 patch.object(capture, "compose_recordings") as compose:
                capture.record_worker(rect, False, root / "video.mp4")
            self.assertEqual(len(children), 2)
            self.assertTrue(all("--no-cursor" in call.args[0] for call in spawn.call_args_list))
            for child in children:
                child.send_signal.assert_any_call(signal.SIGINT)
                child.wait.assert_called()
            self.assertEqual(compose.call_args.args[1], rect)
            self.assertEqual(len(compose.call_args.args[0]), 2)
            self.assertEqual(list(root.glob("video-parts-*")), [])
            self.assertEqual(signal.getsignal(signal.SIGINT), previous)

    def test_export_copies_exact_png_and_saves_it(self):
        png = base64.b64decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a9e8AAAAASUVORK5CYII=")
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            source, output = directory / "render.png", directory / "saved.png"
            source.write_bytes(png)
            with patch.object(capture, "session", return_value=(directory, {"render": str(source)})), \
                 patch.object(capture, "output_path", return_value=output), patch.object(capture, "run") as call:
                capture.export_image()
                self.assertEqual(output.read_bytes(), png)
                call.assert_called_once_with("wl-copy", "--type", "image/png", input=png)


if __name__ == "__main__":
    unittest.main()
