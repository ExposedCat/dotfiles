#!/usr/bin/env python3
"""Read and set a selected Hyprland monitor's DDC brightness."""
import fcntl
import json
import os
import subprocess
from pathlib import Path


def monitors():
    return json.loads(subprocess.check_output(['hyprctl', 'monitors', '-j'], text=True, timeout=3))


def read(serial):
    output = subprocess.check_output(['ddcutil', '--sn', serial, '--terse', 'getvcp', '10'], text=True, timeout=5)
    for line in output.splitlines():
        parts = line.split()
        if parts[:3] == ['VCP', '10', 'C'] and len(parts) == 5:
            current, maximum = map(int, parts[3:])
            if maximum > 0 and 0 <= current <= maximum:
                return current, maximum
    raise RuntimeError('Monitor returned an invalid brightness level.')


def listing():
    devices = []
    for monitor in monitors():
        entry = {'name': monitor['name'], 'description': monitor.get('description') or monitor['name'], 'supported': False, 'level': 0, 'error': ''}
        try:
            serial = monitor.get('serial')
            if not serial:
                raise RuntimeError('This monitor has no DDC serial.')
            current, maximum = read(serial)
            entry.update(supported=True, level=current / maximum)
        except (OSError, ValueError, RuntimeError, subprocess.SubprocessError):
            entry['error'] = 'Brightness control is unavailable for this monitor.'
        devices.append(entry)
    return {'devices': devices}


def set_level(output, level):
    if not 0 <= level <= 1:
        raise ValueError('Brightness must be between 0 and 1.')
    monitor = next((m for m in monitors() if m['name'] == output), None)
    if not monitor or not monitor.get('serial'):
        raise RuntimeError('The selected monitor is no longer available.')
    with (Path(os.environ['XDG_RUNTIME_DIR']) / 'dotfiles-monitor-brightness.lock').open('w') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        current, maximum = read(monitor['serial'])
        subprocess.run(['ddcutil', '--sn', monitor['serial'], '--noverify', 'setvcp', '10', str(round(level * maximum))], check=True, timeout=5)
        current, maximum = read(monitor['serial'])
    return {'name': output, 'level': current / maximum, 'current': current, 'maximum': maximum}
