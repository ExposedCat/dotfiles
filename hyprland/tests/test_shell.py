"""Exercise Ethernet status parsing without touching the system network."""

import importlib.util
from pathlib import Path
import subprocess
import unittest
from unittest.mock import patch


spec = importlib.util.spec_from_file_location("hyprland_shell", Path(__file__).parents[1] / "config/shell/shell.py")
shell = importlib.util.module_from_spec(spec)
spec.loader.exec_module(shell)


class EthernetStatusTests(unittest.TestCase):
    def status(self, output, speed="2500\n"):
        result = subprocess.CompletedProcess([], 0, output, "")
        with patch.object(shell.subprocess, "run", return_value=result), patch.object(Path, "read_text", return_value=speed):
            return shell.ethernet_status()

    def test_only_ethernet_devices_are_included(self):
        status = self.status("enp5s0:ethernet:connected\nwlan0:wifi:connected\nlo:loopback:connected (externally)\n")
        self.assertFalse(status["unavailable"])
        self.assertEqual(len(status["devices"]), 1)
        self.assertEqual({key: status["devices"][0][key] for key in ("name", "state", "speed")}, {"name": "enp5s0", "state": "Connected", "speed": 2500})

    def test_externally_configured_connection_keeps_negotiated_speed(self):
        status = self.status("enp5s0:ethernet:connected (externally)\n")
        self.assertEqual(status["devices"][0]["speed"], 2500)
        self.assertTrue(status["devices"][0]["connected"])

    def test_disconnected_device_does_not_report_stale_link_speed(self):
        status = self.status("enp5s0:ethernet:disconnected\nenp6s0:ethernet:unavailable\n")
        self.assertEqual([d["speed"] for d in status["devices"]], [0, 0])
        self.assertEqual(status["devices"][1]["state"], "Cable unplugged")

    def test_missing_or_invalid_speed_does_not_hide_connection_status(self):
        for speed in ("-1", "unknown"):
            with self.subTest(speed=speed):
                self.assertEqual(self.status("enp5s0:ethernet:connected\n", speed)["devices"][0]["speed"], 0)
        result = subprocess.CompletedProcess([], 0, "enp5s0:ethernet:connected\n", "")
        with patch.object(shell.subprocess, "run", return_value=result), patch.object(Path, "read_text", side_effect=OSError):
            self.assertEqual(shell.ethernet_status()["devices"][0]["state"], "Connected")

    def test_networkmanager_failure_is_distinct_from_no_ethernet_devices(self):
        self.assertEqual(self.status("wlan0:wifi:connected\n"), {"devices": [], "unavailable": False})
        for failure in (FileNotFoundError(), subprocess.TimeoutExpired("nmcli", 3), subprocess.CalledProcessError(1, "nmcli")):
            with self.subTest(failure=failure), patch.object(shell.subprocess, "run", side_effect=failure):
                self.assertEqual(shell.ethernet_status(), {"devices": [], "unavailable": True})


if __name__ == "__main__":
    unittest.main()
