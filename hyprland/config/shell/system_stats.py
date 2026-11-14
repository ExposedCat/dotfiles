#!/usr/bin/env python3
"""Small Linux system sampler; run only while the system pill is open."""
import json
import shutil
import subprocess
import time
from pathlib import Path


class Sampler:
    def __init__(self, root=Path('/'), clock=time.monotonic):
        self.root = root
        self.clock = clock
        self.previous_cpu = None
        self.previous_net = None

    def read(self, path):
        return (self.root / path.lstrip('/')).read_text().strip()

    def number(self, path):
        try:
            return int(self.read(path))
        except (OSError, ValueError):
            return None

    def sample(self):
        now = self.clock()
        values = list(map(int, self.read('/proc/stat').splitlines()[0].split()[1:9]))
        total, idle = sum(values), values[3] + (values[4] if len(values) > 4 else 0)
        cpu = None
        if self.previous_cpu:
            dt, di = total - self.previous_cpu[0], idle - self.previous_cpu[1]
            if dt > 0:
                cpu = max(0, min(100, 100 * (dt - di) / dt))
        self.previous_cpu = (total, idle)
        memory = {}
        for line in self.read('/proc/meminfo').splitlines():
            key, value = line.split(':', 1)
            memory[key] = int(value.split()[0]) * 1024
        memory_total = memory['MemTotal']
        memory_used = memory_total - memory.get('MemAvailable', memory.get('MemFree', 0))
        rx = tx = 0
        for line in self.read('/proc/net/dev').splitlines()[2:]:
            device, data = line.split(':', 1)
            if device.strip() == 'lo':
                continue
            parts = data.split()
            rx += int(parts[0]); tx += int(parts[8])
        down = up = 0
        if self.previous_net and now > self.previous_net[0]:
            elapsed = now - self.previous_net[0]
            down = max(0, (rx - self.previous_net[1]) / elapsed)
            up = max(0, (tx - self.previous_net[2]) / elapsed)
        self.previous_net = (now, rx, tx)
        disk_path = Path.home() if self.root == Path('/') else self.root
        disks = shutil.disk_usage(disk_path)
        result = {
            'cpu': cpu, 'memoryUsed': memory_used, 'memoryTotal': memory_total,
            'memory': memory_used * 100 / memory_total,
            'swapUsed': memory.get('SwapTotal', 0) - memory.get('SwapFree', 0),
            'down': down, 'up': up, 'diskUsed': disks.used, 'diskTotal': disks.total,
            'disk': disks.used * 100 / disks.total, 'diskPath': str(disk_path), 'uptime': float(self.read('/proc/uptime').split()[0]),
            'gpu': None, 'gpuTemperature': None, 'cpuTemperature': None,
            'vramUsed': None, 'vramTotal': None,
        }
        hwmon = self.root / 'sys/class/hwmon'
        for sensor in hwmon.glob('hwmon*'):
            for label in sensor.glob('temp*_label'):
                try:
                    if label.read_text().strip() in ('Tdie', 'Tctl', 'Package id 0'):
                        result['cpuTemperature'] = int(label.with_name(label.name.replace('_label', '_input')).read_text()) / 1000
                        break
                except (OSError, ValueError):
                    continue
            if result['cpuTemperature'] is not None:
                break
        for card in (self.root / 'sys/class/drm').glob('card[0-9]*'):
            if '-' in card.name:
                continue
            device = card / 'device'
            busy = self.number(str((device / 'gpu_busy_percent').relative_to(self.root)))
            if busy is not None:
                result['gpu'] = busy
                result['vramUsed'] = self.number(str((device / 'mem_info_vram_used').relative_to(self.root)))
                result['vramTotal'] = self.number(str((device / 'mem_info_vram_total').relative_to(self.root)))
                for sensor in (device / 'hwmon').glob('hwmon*/temp1_input'):
                    try:
                        result['gpuTemperature'] = int(sensor.read_text()) / 1000
                    except (OSError, ValueError):
                        pass
                break
        # NVIDIA exposes these through its driver tool rather than the AMD sysfs ABI.
        if result['gpu'] is None and self.root == Path('/') and shutil.which('nvidia-smi'):
            try:
                output = subprocess.check_output(['nvidia-smi', '--query-gpu=utilization.gpu,temperature.gpu,memory.used,memory.total', '--format=csv,noheader,nounits'], text=True, timeout=1)
                gpu, temperature, used, total = map(float, output.splitlines()[0].split(','))
                result.update(gpu=gpu, gpuTemperature=temperature, vramUsed=used * 1048576, vramTotal=total * 1048576)
            except (OSError, ValueError, subprocess.SubprocessError):
                pass
        return result


def watch():
    sampler = Sampler()
    while True:
        try:
            print(json.dumps(sampler.sample()), flush=True)
        except (OSError, ValueError, KeyError) as error:
            print(json.dumps({'error': str(error)}), flush=True)
        time.sleep(1)


if __name__ == '__main__':
    watch()
