#!/usr/bin/env python3
"""Real banner hover/click test on a private nested compositor; isolated-gui only."""

import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import time


def wait_for(check, message, timeout=6):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        result = check()
        if result:
            return result
        time.sleep(.04)
    raise AssertionError(message)


def main():
    assert 'agent-desktops' in os.environ.get('XDG_RUNTIME_DIR', ''), 'Use isolated-gui'
    qml = Path(__file__).with_suffix('.qml')
    runtime = Path(os.environ['XDG_RUNTIME_DIR'])
    with tempfile.TemporaryDirectory(prefix='notification-input-', dir=runtime) as temporary:
        root = Path(temporary)
        (root / 'sway.conf').write_text('output * mode 1280x800\ndefault_border none\nseat * hide_cursor 10000\n')
        env = dict(os.environ, WLR_BACKENDS='x11', WLR_RENDERER='pixman', WLR_LIBINPUT_NO_DEVICES='1',
                   DOTFILES_SHELL_SOURCE=os.environ.get('DOTFILES_SHELL_SOURCE', str(qml.parents[1] / 'config/shell')),
                   XDG_STATE_HOME=str(root / 'state'), XDG_CACHE_HOME=str(root / 'cache'))
        with (root / 'gui.log').open('w') as log:
            compositor = subprocess.Popen(['/usr/bin/sway', '-c', str(root / 'sway.conf')],
                                          env=env, stdout=log, stderr=log)
            shell = None
            try:
                display = wait_for(lambda: next((p for p in runtime.glob('wayland-*') if p.is_socket()), None),
                                   'No private Wayland display')
                env.update(QT_QPA_PLATFORM='wayland', WAYLAND_DISPLAY=display.name)
                shell = subprocess.Popen(['/usr/bin/qs', '--no-color', '-p', str(qml)],
                                         env=env, stdout=log, stderr=log)

                def ipc(method):
                    result = subprocess.run(['/usr/bin/qs', 'ipc', '-p', str(qml), 'call',
                                             'notificationInputTest', method], env=env,
                                            capture_output=True, text=True, timeout=2)
                    return json.loads(result.stdout) if result.returncode == 0 and result.stdout.strip() else None

                def state():
                    return ipc('state')

                initial = wait_for(lambda: (s := state()) and s['banners'] and s['banners'][0]['ready'] and s,
                                   'Banner did not settle')
                def nested_window():
                    clients = subprocess.check_output(['/usr/bin/xprop', '-root', '_NET_CLIENT_LIST'], text=True)
                    for candidate in re.findall(r'0x[0-9a-fA-F]+', clients):
                        title = subprocess.check_output(['/usr/bin/xprop', '-id', candidate, '_NET_WM_NAME'], text=True)
                        if 'wlroots - X11-1' in title:
                            return candidate
                    return None

                window = wait_for(nested_window, 'No private compositor window')

                def move(x, y):
                    subprocess.run(['/usr/bin/xdotool', 'mousemove', '--window', window, str(round(x)), str(round(y))], check=True)

                def inside(rect, bottom=False):
                    move(rect['x'] + rect['width'] / 2, rect['y'] + (rect['height'] - 3 if bottom else rect['height'] / 2))

                def click():
                    subprocess.run(['/usr/bin/xdotool', 'click', '1'], check=True)

                def control(card, name):
                    return next(c['bounds'] for c in card['controls'] if c['name'] == name)

                def banner(title):
                    return next(b for b in state()['banners'] if b['title'] == title)

                first = initial['banners'][0]
                # Start inside the bottom of the settled, still-collapsed card.
                inside(first['bounds'], bottom=True)
                time.sleep(.35)
                expanded = banner('Single notification')
                assert expanded['cards'][0]['hovered'] and expanded['bounds']['height'] > first['bounds']['height'], expanded
                inside(control(expanded['cards'][0], 'Reply'))
                time.sleep(.2)
                assert banner('Single notification')['cards'][0]['hovered'], 'Action row lost hover'
                click()
                wait_for(lambda: banner('Single notification')['cards'][0]['composing'], 'Bottom Reply button did not work')
                time.sleep(.3)
                inside(control(banner('Single notification')['cards'][0], 'Cancel'))
                time.sleep(.2)
                assert state()['frozen'], 'Reply footer lost group hover'
                click()
                wait_for(lambda: state()['replying'] == 0, 'Reply footer Cancel did not work')
                # Shrinking past the pointer can consume the hovered banner.
                move(200, 700)
                wait_for(lambda: not state()['banners'], 'Leaving the banner did not consume it')
                assert state()['clicks'] == 0 and state()['activations'] == 0, state()

                ipc('populate')
                wait_for(lambda: len(state()['banners']) == 2 and all(b['ready'] for b in state()['banners']),
                         'Grouped banners did not settle')
                group = banner('Grouped notification')
                inside(control(group['cards'][0], 'notificationGroupToggle'))
                click()
                wait_for(lambda: banner('Grouped notification')['unfold'] == 1, 'Group did not expand')
                inside(banner('Grouped notification')['cards'][1]['bounds'])
                time.sleep(.35)
                lower = banner('Grouped notification')['cards'][1]
                inside(control(lower, 'Archive conversation'))
                time.sleep(.2)
                assert banner('Grouped notification')['cards'][1]['hovered'], 'Lower group member lost hover'
                click()
                wait_for(lambda: state()['actions'] == 1, 'Lower group member action did not work')
                time.sleep(.4)
                neighbor = banner('Neighbor')
                inside(neighbor['bounds'])
                time.sleep(.35)
                inside(control(banner('Neighbor')['cards'][0], 'Archive conversation'))
                time.sleep(.2)
                click()
                wait_for(lambda: state()['actions'] == 2, 'Reflowed neighbor action did not work')
                assert state()['clicks'] == 0, 'A banner click reached the underlying app'
                # Empty overlay space must still pass input to the app below.
                move(200, 700)
                click()
                wait_for(lambda: state()['clicks'] == 1, 'Empty overlay space swallowed a click')
                print('NOTIFICATION INPUT PASS: collapsed bottom, expanded actions, reply footer, lower group member, neighbor reflow, click-through', flush=True)
            except Exception:
                print((root / 'gui.log').read_text(), flush=True)
                raise
            finally:
                if shell is not None:
                    shell.terminate()
                    shell.wait(timeout=5)
                compositor.terminate()
                compositor.wait(timeout=5)


if __name__ == '__main__':
    main()
