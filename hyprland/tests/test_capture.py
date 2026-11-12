"""Geometry and output checks without capturing the working desktop."""

import base64
import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch


spec = importlib.util.spec_from_file_location("capture", Path(__file__).parents[1] / "config/tools/capture.py")
capture = importlib.util.module_from_spec(spec)
spec.loader.exec_module(capture)


class CaptureTests(unittest.TestCase):
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

    def test_window_selection_uses_monitor_relative_coordinates(self):
        outputs = [{"name": "Dell", "x": 320, "y": 0, "width": 1920, "height": 1080},
                   {"name": "HP", "x": 0, "y": 1080, "width": 2560, "height": 1440}]
        selected = capture.window_selection({"at": [120, 1100], "size": [600, 400]}, outputs)
        self.assertEqual(selected, {"monitor": "HP", "x": 120, "y": 20, "width": 600, "height": 400})

    def test_window_selection_clips_offscreen_pixels(self):
        outputs = [{"name": "HP", "x": 0, "y": 1080, "width": 2560, "height": 1440}]
        selected = capture.window_selection({"at": [-20, 1080], "size": [100, 100]}, outputs)
        self.assertEqual(selected["x"], 0)
        self.assertEqual(selected["width"], 80)
        with self.assertRaisesRegex(RuntimeError, "no active window"):
            capture.window_selection({}, outputs)

    def test_record_shortcut_stops_active_recording_without_opening_selector(self):
        with patch.object(capture, "recording", return_value=True), patch.object(capture, "run") as call:
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
