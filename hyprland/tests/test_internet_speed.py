"""Bandwidth tests use transfer payloads/timings, never idle NIC counters."""

import contextlib
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("internet_speed", Path(__file__).parents[1] / "config/shell/internet_speed.py")
speed = importlib.util.module_from_spec(spec)
spec.loader.exec_module(speed)


class InternetSpeedTests(unittest.TestCase):
    def transfer(self, direction, *, code=0, http=200, count=1_000_000):
        metadata = {"http_code": http, "size_download": count, "size_upload": count,
                    "time_total": 2, "time_starttransfer": 1.99 if direction == "upload" else 1,
                    "time_pretransfer": 1}
        completed = subprocess.CompletedProcess([], code, json.dumps(metadata), "")
        with patch.object(speed.subprocess, "run", return_value=completed), patch.object(speed.time, "monotonic", return_value=10):
            return speed.transfer(direction, 1_000_000, Path("synthetic-payload.bin"))

    def test_download_excludes_connection_and_response_wait(self):
        self.assertEqual(speed.aggregate([self.transfer("download")])["mbps"], 8)

    def test_upload_includes_upload_time_instead_of_only_response_body_time(self):
        self.assertEqual(speed.aggregate([self.transfer("upload")])["mbps"], 8)

    def test_parallel_transfers_use_the_shared_wall_clock_interval(self):
        result = speed.aggregate([{"bytes": 1_000_000, "start": 0, "end": 2},
                                  {"bytes": 1_000_000, "start": 1, "end": 3}])
        self.assertAlmostEqual(result["mbps"], 16 / 3)

    def test_http_failure_is_not_reported_as_slow_internet(self):
        with self.assertRaises(speed.SpeedTestError):
            self.transfer("download", code=22, http=429)

    def test_short_success_payload_is_rejected(self):
        with self.assertRaises(speed.SpeedTestError):
            self.transfer("download", count=1024)

    def test_bounded_partial_download_is_measurable_but_unacknowledged_upload_is_not(self):
        self.assertGreater(speed.aggregate([self.transfer("download", code=28, count=100_000)])["mbps"], 0)
        with self.assertRaises(speed.SpeedTestError):
            self.transfer("upload", code=28, count=100_000)

    def test_invalid_timings_are_not_reported_as_infinite_bandwidth(self):
        with self.assertRaises(speed.SpeedTestError):
            speed.aggregate([{"bytes": 100, "start": 1, "end": 1}])

    def test_ramp_up_has_a_bounded_payload_size(self):
        sizes = []
        def transfer(direction, size, upload_path=None):
            sizes.append(size)
            return {"bytes": size, "start": 0, "end": 0.05}
        with patch.object(speed, "transfer", side_effect=transfer):
            self.assertGreater(speed.measure_direction("download"), 0)
        self.assertTrue(all(size <= speed.MAX_BYTES for size in sizes))
        self.assertEqual(max(sizes), speed.MAX_BYTES)
        self.assertLessEqual(len(sizes), 1 + speed.STREAMS * 3)

    def test_result_cache_is_atomic_and_private(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "nested/result.json"
            result = {"download": 925.1, "upload": 412.8, "measuredAt": 123}
            speed.save_result(result, path)
            self.assertEqual(json.loads(path.read_text()), {"version": 1, "result": result})
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)
            self.assertEqual(list(path.parent.iterdir()), [path])

    def test_failure_keeps_previous_successful_measurement(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "result.json"
            path.write_text("previous result")
            with patch.object(speed, "cache_path", return_value=path), patch.object(speed, "measure", side_effect=speed.SpeedTestError("Offline")), contextlib.redirect_stdout(io.StringIO()) as output, contextlib.redirect_stderr(io.StringIO()):
                self.assertEqual(speed.run_cli(), 1)
            self.assertIn("error", json.loads(output.getvalue()))
            self.assertEqual(path.read_text(), "previous result")

    def test_measurement_reports_both_phases_and_timestamp(self):
        events = []
        with patch.object(speed, "measure_direction", side_effect=[925.123, 412.789]), patch.object(speed.time, "time", return_value=123):
            result = speed.measure(events.append)
        self.assertEqual(events, [{"phase": "download"}, {"phase": "upload"}])
        self.assertEqual(result["download"], 925.1)
        self.assertEqual(result["upload"], 412.8)
        self.assertEqual(result["measuredAt"], 123000)


if __name__ == "__main__":
    unittest.main()
