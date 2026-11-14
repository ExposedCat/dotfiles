"""Check Linux counter deltas and unavailable GPU handling with local fixtures."""
import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from collections import namedtuple

spec = importlib.util.spec_from_file_location('system_stats', Path(__file__).parents[1] / 'config/shell/system_stats.py')
stats = importlib.util.module_from_spec(spec)
spec.loader.exec_module(stats)


class SystemStatsTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.now = 10
        self.sampler = stats.Sampler(self.root, lambda: self.now)
        self.write('proc/stat', 'cpu 100 0 100 800 0 0 0 0\n')
        self.write('proc/meminfo', 'MemTotal: 1000 kB\nMemAvailable: 400 kB\nSwapTotal: 100 kB\nSwapFree: 75 kB\n')
        self.write('proc/uptime', '1234.5 999\n')
        self.net(1000, 500)
        usage = namedtuple('usage', 'total used free')(1000, 300, 700)
        patcher = patch.object(stats.shutil, 'disk_usage', return_value=usage)
        patcher.start(); self.addCleanup(patcher.stop)

    def write(self, name, contents):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(contents)

    def net(self, rx, tx):
        self.write('proc/net/dev', 'header\nheader\nlo: 999999 0 0 0 0 0 0 0 999999 0 0 0 0 0 0 0\neth0: ' + str(rx) + ' 0 0 0 0 0 0 0 ' + str(tx) + ' 0 0 0 0 0 0 0\n')

    def test_counter_deltas_and_memory(self):
        first = self.sampler.sample()
        self.assertIsNone(first['cpu'])
        self.assertEqual(first['memory'], 60)
        self.assertEqual(first['swapUsed'], 25 * 1024)
        self.assertEqual(first['disk'], 30)
        self.write('proc/stat', 'cpu 150 0 150 900 0 0 0 0\n')
        self.net(3000, 1500)
        self.now += 2
        second = self.sampler.sample()
        self.assertEqual(second['cpu'], 50)
        self.assertEqual(second['down'], 1000)
        self.assertEqual(second['up'], 500)
        self.assertIsNone(second['gpu'])

    def test_amd_gpu_temperature_and_vram(self):
        self.write('sys/class/drm/card1/device/gpu_busy_percent', '24')
        self.write('sys/class/drm/card1/device/mem_info_vram_used', '4096')
        self.write('sys/class/drm/card1/device/mem_info_vram_total', '16384')
        self.write('sys/class/drm/card1/device/hwmon/hwmon3/temp1_input', '47000')
        self.write('sys/class/hwmon/hwmon1/temp2_label', 'Tdie')
        self.write('sys/class/hwmon/hwmon1/temp2_input', '55500')
        sample = self.sampler.sample()
        self.assertEqual((sample['gpu'], sample['gpuTemperature'], sample['vramUsed'], sample['vramTotal']), (24, 47, 4096, 16384))
        self.assertEqual(sample['cpuTemperature'], 55.5)

    def test_network_counter_reset_does_not_show_negative_rates(self):
        self.sampler.sample()
        self.now += 1
        self.net(0, 0)
        sample = self.sampler.sample()
        self.assertEqual(sample['down'], 0)
        self.assertEqual(sample['up'], 0)
