#!/usr/bin/env python3
"""Measure shortcut/first-frame latency on two private outputs; isolated-gui only.

Run through the desktop helper. --source accepts another tools directory for
before/after comparisons. Software-rendered results are comparative, not a
measurement of the working Hyprland session. Includes the real Python shortcut,
capture commands, IPC and first full-size overlay frame on both outputs.
"""

import argparse
import json
import os
from pathlib import Path
import statistics
import subprocess
import shlex
import sys
import tempfile
import time


def wait_for(check, message, timeout=10):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        value = check()
        if value:
            return value
        time.sleep(.01)
    raise AssertionError(message)


def main():
    assert 'agent-desktops' in os.environ.get('XDG_RUNTIME_DIR', ''), 'Use isolated-gui'
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, default=Path(__file__).resolve().parents[1] / 'config/tools')
    parser.add_argument('--samples', type=int, default=6)
    args = parser.parse_args()
    if args.samples < 2:
        parser.error('--samples must include a first open and at least one repeat')
    source = args.source.resolve()
    runtime = Path(os.environ['XDG_RUNTIME_DIR'])
    with tempfile.TemporaryDirectory(prefix='capture-startup-', dir=runtime) as temporary:
        root = Path(temporary)
        (root / 'sway.conf').write_text('output HEADLESS-1 mode 2560x1440 pos 0 1080\n'
                                       'output HEADLESS-2 mode 1920x1080 pos 320 0\n')
        env = dict(os.environ, WLR_BACKENDS='headless', WLR_HEADLESS_OUTPUTS='2',
                   WLR_RENDERER='pixman', WLR_LIBINPUT_NO_DEVICES='1',
                   XDG_CONFIG_HOME=str(root / 'config'), XDG_CACHE_HOME=str(root / 'cache'),
                   XDG_STATE_HOME=str(root / 'state'))
        with (root / 'gui.log').open('w') as log:
            compositor = subprocess.Popen(['/usr/bin/sway', '--unsupported-gpu', '-c', str(root / 'sway.conf')],
                                          env=env, stdout=log, stderr=log)
            shell = desktop = shortcut = None
            try:
                display = wait_for(lambda: next((p for p in runtime.glob('wayland-*') if p.is_socket()), None),
                                   'No private Wayland display')
                env.update(QT_QPA_PLATFORM='wayland', WAYLAND_DISPLAY=display.name)
                config = str(source / 'capture-daemon.qml')
                desktop_config = str(source.parent / 'shell/shell.qml')
                (root / 'empty.json').write_text('{}')
                env['DOTFILES_SHELL_FIXTURE'] = str(root / 'empty.json')

                def ipc(method, *values):
                    result = subprocess.run(['/usr/bin/quickshell', 'ipc', '--path', config,
                                             'call', 'capture', method, *values], env=env,
                                            capture_output=True, text=True, timeout=3)
                    return json.loads(result.stdout) if result.returncode == 0 and result.stdout.strip() else None

                desktop = subprocess.Popen(['/usr/bin/quickshell', '--path', desktop_config], env=env, stdout=log, stderr=log)

                def desktop_ready():
                    result = subprocess.run(['/usr/bin/quickshell', 'ipc', '--path', desktop_config,
                                             'call', 'shell', 'status'], env=env,
                                            capture_output=True, text=True, timeout=3)
                    return result.returncode == 0

                wait_for(desktop_ready, 'Fixture shell did not start')
                shell = subprocess.Popen(['/usr/bin/quickshell', '--path', config], env=env, stdout=log, stderr=log)
                wait_for(lambda: (ipc('status') or {}).get('ready'), 'Worker did not warm up')
                monitors = [dict(name='HEADLESS-1', width=2560, height=1440, x=0, y=1080, scale=1, focused=True),
                            dict(name='HEADLESS-2', width=1920, height=1080, x=320, y=0, scale=1, focused=False)]
                # Sway supplies real frames; only the Hyprland monitor query and
                # service PID lookup need fixtures. Neither accesses the user bus.
                (root / 'monitors.json').write_text(json.dumps(monitors))
                (root / 'bin').mkdir()
                query = root / 'bin/hyprctl'
                query.write_text('#!/bin/sh\nif [ "$1" = monitors ]; then\nexec /usr/bin/cat '
                                 + shlex.quote(str(root / 'monitors.json')) + '\nfi\nexit 1\n')
                service = root / 'bin/systemctl'
                service.write_text('#!/bin/sh\nif [ "$2" = show ] && [ "$3" = dotfiles-hyprland-capture.service ]; then\n'
                                   + f"printf '%s\\n' {shell.pid}\nexit 0\nfi\nexit 1\n")
                query.chmod(0o755)
                service.chmod(0o755)
                env['PATH'] = str(root / 'bin') + os.pathsep + env['PATH']
                (root / 'state/dotfiles/hyprland').mkdir(parents=True, exist_ok=True)
                (root / 'state/dotfiles/hyprland/capture.json').write_text(json.dumps(
                    {'region': dict(x=100, y=1150, width=500, height=300)}))
                samples = []
                for index in range(args.samples):
                    started = time.time() * 1000
                    shortcut = subprocess.Popen([sys.executable, str(source / 'capture.py'), 'select', 'region'],
                                                env=env, stdout=log, stderr=log)

                    def rendered():
                        status = ipc('status')
                        if shortcut.poll() is not None:
                            raise AssertionError(f'Shortcut exited before presenting: {shortcut.returncode}')
                        frames = status.get('frames', {}) if status else {}
                        return status if len(frames) == len(monitors) and min(frames.values()) >= started else None

                    status = wait_for(rendered, 'Both outputs did not render')
                    sample = dict(sample=index, shortcut_to_frame_ms=round(max(status['frames'].values()) - started))
                    samples.append(sample)
                    print(json.dumps(sample), flush=True)
                    ipc('cancel')
                    assert shortcut.wait(timeout=5) == 0, 'Shortcut did not finish'
                    wait_for(lambda: not (ipc('status') or {}).get('active', True), 'Worker did not finish')
                print(json.dumps(dict(first_open_ms=samples[0]['shortcut_to_frame_ms'],
                                      repeat_median_ms=statistics.median(s['shortcut_to_frame_ms'] for s in samples[1:]))))
            except Exception:
                log.flush()
                print((root / 'gui.log').read_text())
                raise
            finally:
                if shortcut and shortcut.poll() is None:
                    shortcut.terminate()
                    shortcut.wait(timeout=5)
                if shell:
                    shell.terminate()
                    shell.wait(timeout=5)
                if desktop:
                    desktop.terminate()
                    desktop.wait(timeout=5)
                compositor.terminate()
                compositor.wait(timeout=5)


if __name__ == '__main__':
    main()
