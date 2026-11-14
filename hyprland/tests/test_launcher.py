"""Verify the calculator and app ranking helpers used by the actual QML view."""
from pathlib import Path
import shutil
import subprocess
import unittest


class LauncherTests(unittest.TestCase):
    def test_launcher_helpers(self):
        node = shutil.which('node')
        if not node:
            self.skipTest('Node.js is unavailable')
        result = subprocess.run([node, str(Path(__file__).with_name('launcher.js'))], text=True, capture_output=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
