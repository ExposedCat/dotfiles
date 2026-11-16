#!/usr/bin/env python3
"""Real key press/release regression test; run through the isolated-gui helper."""
import json
import ctypes
import os
from pathlib import Path
import subprocess
import tempfile
import time

assert 'agent-desktops' in os.environ.get('XDG_RUNTIME_DIR', ''), 'Use isolated-gui'
SOURCE = Path(__file__).resolve().parents[1] / 'config/tools'
QML = Path(__file__).with_suffix('.qml')


def wait_for(check, message, timeout=8):
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        result = check()
        if result:
            return result
        time.sleep(.04)
    raise AssertionError(message)


class PhysicalKeyboard:
    """XTest keycodes without xdotool's keysym-to-Latin-layout translation."""
    def __init__(self):
        subprocess.run(['/usr/bin/setxkbmap', '-layout', 'us,ru,ara', '-option', '',
                        '-option', 'lv3:ralt_switch'], check=True)
        self.x11 = ctypes.CDLL('libX11.so.6')
        self.xtst = ctypes.CDLL('libXtst.so.6')
        self.x11.XOpenDisplay.argtypes = [ctypes.c_char_p]
        self.x11.XOpenDisplay.restype = ctypes.c_void_p
        self.x11.XkbLockGroup.argtypes = [ctypes.c_void_p, ctypes.c_uint, ctypes.c_uint]
        self.x11.XSync.argtypes = [ctypes.c_void_p, ctypes.c_int]
        self.xtst.XTestFakeKeyEvent.argtypes = [ctypes.c_void_p, ctypes.c_uint, ctypes.c_int, ctypes.c_ulong]
        self.display = self.x11.XOpenDisplay(None)
        assert self.display, 'No private X11 keyboard connection'

    def group(self, index):
        assert self.x11.XkbLockGroup(self.display, 0x0100, index), 'Cannot set private XKB group'
        self.x11.XSync(self.display, False)

    def key(self, code, down):
        assert self.xtst.XTestFakeKeyEvent(self.display, code, down, 0), 'Cannot send private physical key'
        self.x11.XSync(self.display, False)


keyboard = PhysicalKeyboard()
with tempfile.TemporaryDirectory(prefix='capture-input-', dir=os.environ['XDG_RUNTIME_DIR']) as temporary:
    root = Path(temporary)
    runtime = Path(os.environ['XDG_RUNTIME_DIR'])
    (root / 'sway.conf').write_text('output * mode 1280x800\nseat * hide_cursor 10000\n'
                                  'input type:keyboard xkb_layout "us,ru,ara"\n'
                                  'input type:keyboard xkb_options "lv3:ralt_switch"\n')
    env = dict(os.environ, WLR_BACKENDS='x11', WLR_RENDERER='pixman', WLR_LIBINPUT_NO_DEVICES='1')
    with (root / 'sway.log').open('w') as compositor_log, (root / 'qml.log').open('w') as qml_log:
        compositor = subprocess.Popen(['/usr/bin/sway', '--unsupported-gpu', '--config', str(root/'sway.conf')],
                                      env=env, stdout=compositor_log, stderr=compositor_log)
        shell = cold = None
        try:
            socket = wait_for(lambda: next((p for p in runtime.glob('wayland-*') if p.is_socket()), None),
                              'No private Wayland display')
            env.update(QT_QPA_PLATFORM='wayland', WAYLAND_DISPLAY=socket.name,
                       SWAYSOCK=str(wait_for(lambda: next(runtime.glob('sway-ipc.*.sock'), None), 'No private Sway IPC')),
                       DOTFILES_CAPTURE_SOURCE=str(SOURCE), DOTFILES_CAPTURE_SESSION=str(root),
                       DOTFILES_CAPTURE_TEST_CONFIG=str(QML),
                       DOTFILES_SHELL_FIXTURE=str(root/'empty.json'),
                       XDG_STATE_HOME=str(root/'state'), XDG_CACHE_HOME=str(root/'cache'),
                       XDG_CONFIG_HOME=str(root/'config'))
            (root/'empty.json').write_text('{}')
            # Delay only preference writes to prove the cold process waits for
            # persistence instead of killing its helper as soon as it hides.
            (root/'bin').mkdir()
            wrapper = root/'bin/dotfiles-desktop'
            native = os.environ['DOTFILES_DESKTOP_BINARY']
            wrapper.write_text('#!/usr/bin/python3\nimport os,sys,time\nif "preferences" in sys.argv: time.sleep(0.5)\nos.execv(' + repr(native) + ', [' + repr(native) + ']+sys.argv[1:])\n')
            wrapper.chmod(0o755)
            env['DOTFILES_DESKTOP_BINARY'] = str(wrapper)
            env['PATH'] = str(root/'bin') + os.pathsep + env['PATH']
            (root/'config').mkdir()
            (root/'pictures').mkdir()
            (root/'config/user-dirs.dirs').write_text(f'XDG_PICTURES_DIR="{root}/pictures"\n')
            image = root/'screen.ppm'
            image.write_bytes(b'P6\n1280 800\n255\n' + b'\x60\x90\xc0' * (1280*800))
            (root/'session.json').write_text(json.dumps({'mode': 'region', 'render': str(root/'render.png'),
                'selection': {'monitor': 'X11-1', 'x': 100, 'y': 100, 'width': 320, 'height': 200},
                'outputs': [{'name': 'X11-1', 'x': 0, 'y': 0, 'width': 1280, 'height': 800,
                             'scale': 1, 'focused': True, 'plain': image.as_uri(), 'cursor': image.as_uri()}]}))
            shell = subprocess.Popen(['/usr/bin/quickshell', '--path', str(QML)], env=env,
                                     stdout=qml_log, stderr=qml_log)

            def ipc(method):
                result = subprocess.run(['/usr/bin/quickshell', 'ipc', '--path', str(QML), 'call',
                                         'captureInputTest', method], env=env, capture_output=True, text=True, timeout=2)
                return json.loads(result.stdout) if result.returncode == 0 and result.stdout.strip() else None

            def state():
                return ipc('state')

            def key(action, name):
                subprocess.run(['/usr/bin/xdotool', action, name], check=True)

            def files():
                return sorted((root/'pictures/Screenshots').glob('*.png'))

            def poison_clipboard():
                subprocess.run(['/usr/bin/wl-copy', '--type', 'text/plain'], input=b'before capture', env=env, check=True)

            def verify_export(previous):
                saved = files()
                assert len(saved) == previous + 1, ('Export repeated or missing', saved)
                image = saved[-1].read_bytes()
                assert image.startswith(b'\x89PNG\r\n\x1a\n'), 'Saved image is not PNG'
                clipboard = subprocess.check_output(['/usr/bin/wl-paste', '--type', 'image/png', '--no-newline'], env=env, timeout=3)
                assert clipboard == image, 'Clipboard image differs from saved screenshot'

            def layout(index):
                keyboard.group(index)
                subprocess.run(['/usr/bin/swaymsg', 'input', 'type:keyboard', 'xkb_switch_layout', str(index)],
                               env=env, check=True, capture_output=True)
                def switched():
                    inputs = json.loads(subprocess.check_output(['/usr/bin/swaymsg', '-t', 'get_inputs', '-r'], env=env))
                    keyboards = [device for device in inputs if device['type'] == 'keyboard']
                    return keyboards and all(device['xkb_active_layout_index'] == index for device in keyboards)
                wait_for(switched, 'Private keyboard layout did not change')

            wait_for(lambda: state() and state()['observerFocused'], 'Observer did not receive initial focus')
            wait_for(lambda: state()['idleSurfaces'], 'Idle surfaces are not ready and input-free')
            ipc('watchSurfaceSizes')
            subprocess.run(['/usr/bin/xdotool', 'mousemove', '640', '400', 'click', '1'], check=True)
            wait_for(lambda: state()['clicks'] == 1, 'Idle surfaces intercepted a click')
            export_keys = (['Escape'], ['Return'], ['Control_L', 'c'], ['a'], ['space'], ['z'],
                           ['Control_L', 'z'], ['Tab'], ['Left'], ['F6'],
                           ['Shift_L'], ['Control_L'], ['Alt_L'], ['Super_L'], ['Alt_R'])
            for keys in export_keys:
                previous = len(files())
                poison_clipboard()
                assert ipc('open') is True, state()
                wait_for(lambda: state()['active'] and not state()['observerFocused'], 'Overlay did not take focus')
                assert state()['resizeEvents'] == [], ('Opening resized the warm surface', state())
                time.sleep(.15)
                for name in keys:
                    key('keydown', name)
                time.sleep(.7)  # Include auto-repeat and fast export completion.
                held = state()
                assert held['active'], (keys, 'Overlay released input while keys were still held', held)
                assert held['events'] == [], (keys, 'Key press escaped to underlying window', held)
                for name in reversed(keys):
                    key('keyup', name)
                    if len(keys) > 1 and name != keys[0]:
                        time.sleep(.15)
                        assert state()['active'], 'Overlay closed before modifier release'
                wait_for(lambda: not state()['active'] and state()['observerFocused'], 'Overlay did not dismiss after release')
                wait_for(lambda: state()['idleSurfaces'], 'Dismissed surfaces still cover the desktop')
                assert state()['resizeEvents'] == [], ('Closing resized the warm surface', state())
                time.sleep(.15)
                assert state()['events'] == [], (keys, 'Key release escaped to underlying window', state())
                if keys == ['Escape']:
                    assert len(files()) == previous, 'Escape exported a screenshot'
                else:
                    verify_export(previous)
            assert len(files()) == len(export_keys) - 1, 'Export was repeated or failed'

            # Alt/Shift/Ctrl can predate the overlay, e.g. Alt+Print.
            key('keydown', 'Shift_L'); time.sleep(.1)
            assert ipc('open') is True, state()
            wait_for(lambda: not state()['observerFocused'], 'Overlay did not take focus')
            key('keydown', 'Escape'); key('keyup', 'Escape'); time.sleep(.15)
            assert state()['active'], 'Previously held modifier was released to the observer'
            key('keyup', 'Shift_L')
            wait_for(lambda: not state()['active'] and state()['observerFocused'], 'Modifier release did not dismiss')
            assert state()['events'] == [], state()

            # Feed physical X11 keys to the nested compositor's actual layouts,
            # then verify the non-Latin symbols reached Qt and copied/saved once.
            for index, low, high in ((1, 0x0400, 0x0500), (2, 0x0600, 0x0700)):
                layout(index)
                previous = len(files())
                poison_clipboard()
                assert ipc('open') is True, state()
                wait_for(lambda: state()['active'] and state()['sceneFocused'], 'Non-Latin overlay did not take focus')
                keyboard.key(38, True)  # Physical A position: Cyrillic ф / Arabic ش.
                time.sleep(.3)
                held = state()
                assert held['active'] and any(low <= value < high for value in held['heldKeys'].values()), held
                assert any(identity.startswith('scan:') for identity in held['heldKeys']), held
                if index == 1:
                    layout(2)  # Release the same physical key with a different symbol.
                keyboard.key(38, False)
                wait_for(lambda: not state()['active'] and state()['observerFocused'], 'Non-Latin key release left selector open')
                assert state()['events'] == [], state()
                verify_export(previous)

                # Exceptions keep their meaning in each layout and never export.
                layout(index)
                previous = len(files())
                assert ipc('open') is True, state()
                wait_for(lambda: state()['active'] and state()['sceneFocused'], 'Exception overlay did not take focus')
                for code in (22, 119):  # Backspace and Delete in every layout.
                    ipc('paintAcross')
                    assert len(state()['strokes']) == 1, state()
                    keyboard.key(code, True); keyboard.key(code, False)
                    wait_for(lambda: state()['strokes'] == [], 'Undo exception failed')
                    assert state()['active'] and not state()['exporting'], state()
                keyboard.key(9, True); keyboard.key(9, False)
                wait_for(lambda: not state()['active'] and state()['observerFocused'], 'Non-Latin Escape failed')
                assert len(files()) == previous and state()['events'] == [], state()
            layout(0)

            # Text editing keeps its own Return/Ctrl+C behavior; held Escape
            # cancels just the label, without repeating into whole-session cancel.
            assert ipc('open') is True, state()
            wait_for(lambda: not state()['observerFocused'], 'Overlay did not take focus')
            assert ipc('edit') is True
            subprocess.run(['/usr/bin/xdotool', 'type', 'label'], check=True)
            assert state()['text'] == 'label', state()
            key('keydown', 'Escape'); time.sleep(.7); key('keyup', 'Escape')
            assert state()['active'] and not state()['editing'], 'Label cancel dismissed the entire overlay'
            assert ipc('edit') is True
            subprocess.run(['/usr/bin/xdotool', 'type', 'label'], check=True)
            subprocess.run(['/usr/bin/xdotool', 'key', 'ctrl+a', 'ctrl+c'], check=True)
            assert state()['active'] and state()['editing'] and not state()['exporting'], 'Text copy exported the image'
            key('keydown', 'Return'); key('keyup', 'Return'); time.sleep(.1)
            assert state()['active'] and state()['strokes'][0]['text'] == 'label', state()
            subprocess.run(['/usr/bin/xdotool', 'key', 'BackSpace'], check=True)
            assert state()['strokes'] == [], 'Backspace undo stopped working'
            key('keydown', 'Escape'); key('keyup', 'Escape')
            wait_for(lambda: not state()['active'] and state()['observerFocused'], 'Overlay did not dismiss')
            assert state()['events'] == [], state()

            # An IPC cancellation can close an unfinished label. Reusing the
            # surface must start with clean editing state and keyboard focus.
            assert ipc('open') is True, state()
            wait_for(lambda: not state()['observerFocused'], 'Overlay did not take focus')
            assert ipc('edit') is True
            subprocess.run(['/usr/bin/xdotool', 'type', 'discarded'], check=True)
            subprocess.run(['/usr/bin/quickshell', 'ipc', '--path', str(QML), 'call', 'capture', 'cancel'],
                           env=env, check=True)
            wait_for(lambda: not state()['active'] and state()['observerFocused'], 'IPC cancel did not restore focus')
            assert ipc('open') is True, state()
            wait_for(lambda: state()['sceneFocused'] and not state()['observerFocused'], 'Reused surface did not take focus')
            assert not state()['editing'] and state()['text'] == '', state()
            key('keydown', 'Escape'); key('keyup', 'Escape')
            wait_for(lambda: not state()['active'] and state()['observerFocused'], 'Reused surface did not dismiss')
            assert state()['events'] == [], state()

            # Recording must also keep the selector mapped while Enter is held.
            # Cancel before release, so no recorder or system service is started.
            assert ipc('openRecord') is True
            wait_for(lambda: not state()['observerFocused'], 'Overlay did not take focus')
            key('keydown', 'Return'); time.sleep(.3)
            assert state()['active'] and state()['recordPending'] and not state()['recording'], state()
            key('keydown', 'Escape'); key('keyup', 'Escape')
            assert state()['active'], 'Pending recording released a held Return'
            key('keyup', 'Return')
            wait_for(lambda: not state()['active'] and state()['observerFocused'], 'Pending recording did not cancel')
            assert state()['events'] == [], state()

            # The cold fallback is a separate application from the observer.
            cold = subprocess.Popen(['/usr/bin/quickshell', '--path', str(SOURCE/'capture.qml')],
                                    env=env, stdout=qml_log, stderr=qml_log)
            wait_for(lambda: not state()['observerFocused'], 'Cold overlay did not take focus')
            key('keydown', 'Escape'); time.sleep(.7)
            assert cold.poll() is None and not state()['observerFocused'], 'Cold overlay exited with Escape held'
            key('keyup', 'Escape')
            assert cold.wait(timeout=5) == 0
            wait_for(lambda: state()['observerFocused'], 'Cold fallback did not restore focus')
            assert state()['events'] == [], state()

            # Fast cold export must survive its slower preference writer.
            cold_data = json.loads((root/'session.json').read_text())
            cold_data['selection']['x'] = 180
            (root/'session.json').write_text(json.dumps(cold_data))
            cold = subprocess.Popen(['/usr/bin/quickshell', '--path', str(SOURCE/'capture.qml')],
                                    env=env, stdout=qml_log, stderr=qml_log)
            wait_for(lambda: not state()['observerFocused'], 'Cold export did not take focus')
            time.sleep(.15)
            key('keydown', 'Return'); key('keyup', 'Return')
            assert cold.wait(timeout=5) == 0
            saved = json.loads((root/'state/dotfiles/hyprland/capture.json').read_text())
            assert saved['region']['x'] == 180, saved
            wait_for(lambda: state()['observerFocused'], 'Cold export did not restore focus')
            assert state()['events'] == [], state()

            for gesture in ('Escape', 'Return'):
                if gesture == 'Return':
                    ipc('useLegacyHandoff')
                assert ipc('launcher') is True
                wait_for(lambda: state()['panel'] == 'launcher' and state()['wantsGrab'], 'Launcher did not open')
                time.sleep(.35)  # Let the opening animation and Loader activation finish.
                if gesture == 'Escape':
                    ipc('connectHandoff')
                    wait_for(lambda: state()['handoffReady'], 'Direct shell handoff did not connect')
                ipc('query')
                wait_for(lambda: state()['query'] == 'te', 'Launcher query was not set')
                ipc('choose')
                before = state()
                assert before['query'] == 'te' and before['selected'], before
                assert ipc('open') is True, state()
                wait_for(lambda: state()['active'] and state()['captureActive'], 'Capture did not suspend shell dismissal')
                ipc('loseFocus')  # The Hyprland focus-grab cleared callback.
                during = state()
                assert during['panel'] == 'launcher' and not during['wantsGrab'], during
                key('keydown', gesture); time.sleep(.3); key('keyup', gesture)
                wait_for(lambda: not state()['active'] and not state()['captureActive'], 'Capture handoff did not finish')
                time.sleep(.15)
                after = state()
                assert after['panel'] == 'launcher' and after['query'] == before['query'], after
                assert after['selected'] == before['selected'] and after['wantsGrab'], after
                ipc('loseFocus')
                assert state()['panel'] == '', 'Ordinary focus-loss dismissal was not restored'
            print('CAPTURE INPUT PASS: copy/save for letters, Ctrl+Z, modifiers, navigation/function keys, Cyrillic/Arabic, layout change while held, Escape/Backspace/Delete exceptions, repeats, text editing, warm/cold, recording, launcher/query/selection preservation and normal dismissal')
        except Exception:
            print("Capture check state:", locals().get("keys"), state(), flush=True)
            print((root/'qml.log').read_text())
            print((root/'sway.log').read_text()[-2000:])
            raise
        finally:
            for name in ('Escape', 'Return', 'a', 'c', 'z', 'Control_L', 'Shift_L', 'Alt_L', 'Alt_R', 'Super_L', 'Tab', 'Left', 'F6', 'BackSpace', 'Delete'):
                subprocess.run(['/usr/bin/xdotool', 'keyup', name], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            if cold and cold.poll() is None:
                cold.terminate(); cold.wait(timeout=5)
            if shell:
                shell.terminate(); shell.wait(timeout=5)
            compositor.terminate(); compositor.wait(timeout=5)
