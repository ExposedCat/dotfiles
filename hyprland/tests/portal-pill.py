"""Exercise real pill expansion and portal responses on an isolated compositor."""
import json
import os
from pathlib import Path
import subprocess
import sys
import time

if not os.environ.get('ISOLATED_GUI_SESSION'):
    raise SystemExit('Run through isolated-gui; this check starts a nested desktop.')

ROOT = Path(__file__).parents[1] / 'config'
sys.path.insert(0, str(ROOT / 'portals'))
from native import Dialog, share_result

runtime = Path(os.environ['XDG_RUNTIME_DIR'])
directory = runtime.parent / 'pill-integration'
directory.mkdir(exist_ok=True)
(directory / 'fixture.json').write_text('{}')
(directory / 'sway.conf').write_text('output * mode 1200x800\nseat * hide_cursor 10000\n')
env = dict(os.environ, WLR_BACKENDS='x11', WLR_RENDERER='pixman', WLR_LIBINPUT_NO_DEVICES='1')


def wait_for(check, message, timeout=10):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        value = check()
        if value:
            return value
        time.sleep(.025)
    raise AssertionError(message)


with (directory / 'sway.log').open('w') as sway_log, (directory / 'shell.log').open('w') as shell_log:
    compositor = subprocess.Popen(['/usr/bin/sway', '--unsupported-gpu', '-c', str(directory / 'sway.conf')],
                                  env=env, stdout=sway_log, stderr=sway_log)
    shell = dialog = None
    try:
        wayland = wait_for(lambda: next((p for p in runtime.glob('wayland-*') if p.is_socket()), None), 'No private Wayland display')
        env.update(QT_QPA_PLATFORM='wayland', WAYLAND_DISPLAY=wayland.name,
                   DOTFILES_SHELL_FIXTURE=str(directory / 'fixture.json'), DOTFILES_SHELL_SOURCE=str(ROOT / 'shell'),
                   XDG_STATE_HOME=str(directory / 'state'), XDG_CACHE_HOME=str(directory / 'cache'),
                   XDG_CONFIG_HOME=str(directory / 'config'))
        production = bool(os.environ.get('DOTFILES_PORTAL_PRODUCTION_ROOT'))
        fixture = ROOT / 'shell/shell.qml' if production else Path(__file__).with_suffix('.qml')
        shell = subprocess.Popen(['/usr/bin/quickshell', '--no-color', '--path', str(fixture)],
                                 env=env, stdout=shell_log, stderr=shell_log)

        def ipc(method, *arguments):
            result = subprocess.run(['/usr/bin/quickshell', 'ipc', '--path', str(fixture), 'call',
                                     'shell' if production else 'portalPillTest', method, *map(str, arguments)],
                                    env=env, text=True, capture_output=True, timeout=3)
            if result.returncode:
                return None
            return json.loads(result.stdout) if result.stdout.strip() else True

        def state():
            return ipc('status' if production else 'state') or {}

        wait_for(lambda: (state().get('fixture') if production else state().get('height') == 40)
                 and (runtime / 'dotfiles-portal-shell.sock').is_socket(), 'Shell did not become ready')
        data = {'kind': 'apps', 'filename': 'fixture.pdf', 'apps': [
            {'id': 'alpha', 'name': 'Alpha Document', 'description': 'View documents', 'icon': ''},
            {'id': 'beta', 'name': 'Beta Editor', 'description': 'Edit documents', 'icon': ''}]}

        if production:
            for request in [data, {'kind': 'access', 'title': 'Allow fixture access?', 'choices': []},
                            {'kind': 'share', 'outputs': [], 'windows': [], 'workspaces': []}]:
                dialog = Dialog(request)
                wait_for(lambda: state().get('panel') == 'portal', 'Production shell did not open the portal pane')
                time.sleep(.4)
                ipc('toggle', 'launcher')
                wait_for(lambda: dialog.process.poll() == 0, 'Production shell did not cancel the portal')
                assert dialog.result() == {'response': 1}, dialog.result()
                dialog.close(); dialog = None
                ipc('toggle', 'launcher')
                time.sleep(.3)
            print('PASS: production shell loads application, permission and sharing portals and completes cancellation', flush=True)
            raise SystemExit(0)

        def present():
            current = Dialog(data)
            wait_for(lambda: state().get('panel') == 'portal' and state().get('height') == 428, 'Pill did not expand')
            return current

        dialog = present()
        assert state()['opening'] >= 2, state()
        if os.environ.get('DOTFILES_PORTAL_PREVIEW'):
            print('PREVIEW READY: chooser is expanded in the pill; press Escape to finish', flush=True)
            while dialog.process.poll() is None:
                time.sleep(.05)
            assert dialog.result() == {'response': 1}, dialog.result()
            wait_for(lambda: state().get('height') == 40, 'Preview did not collapse')
            assert state()['closing'] >= 2, state()
            print('PASS: native Escape cancelled the pill and completed the closing animation', flush=True)
            raise SystemExit(0)
        ipc('filter', 'Beta')
        wait_for(lambda: state().get('results') == 1, 'Pill search did not filter the choices')
        ipc('cancel')
        wait_for(lambda: dialog.process.poll() == 0, 'Cancelled request did not finish')
        assert dialog.result() == {'response': 1}, dialog.result()
        wait_for(lambda: state().get('height') == 40, 'Pill did not collapse')
        assert state()['closing'] >= 2, state()
        dialog.close(); dialog = None
        print('PASS: chooser morphs from and back into the existing pill; cancel responds once', flush=True)

        dialog = present()
        wait_for(lambda: state().get('results') == 2, 'New chooser retained the previous search')
        updated = dict(data, apps=[{'id': 'gamma', 'name': 'Gamma Reader', 'description': '', 'icon': ''}])
        dialog.update(updated)
        wait_for(lambda: state().get('apps', [{}])[0].get('id') == 'gamma', 'Updated choices did not reach pill')
        time.sleep(.1)
        ipc('accept', 0)
        wait_for(lambda: dialog.process.poll() == 0, 'Choice did not finish')
        assert dialog.result() == {'response': 0, 'choice': 'gamma'}, dialog.result()
        dialog.close(); dialog = None
        print('PASS: updated choices and acceptance return the selected application', flush=True)

        dialog = present()
        dialog.close(); dialog = None
        wait_for(lambda: not state().get('active') and state().get('height') == 40, 'Frontend close left the chooser open')
        print('PASS: a disconnected frontend cancels the pill without an orphan dialog', flush=True)

        permission = json.loads((Path(__file__).parent / 'portal-fixtures/access.json').read_text())
        permission.pop('fixture')
        for allow in (False, True):
            dialog = Dialog(permission)
            wait_for(lambda: state().get('kind') == 'access' and state().get('width') == 440
                     and state().get('height') == round(state().get('desiredHeight', 0)), 'Permission pill did not settle')
            ipc('permission', str(allow).lower())
            wait_for(lambda: dialog.process.poll() == 0, 'Permission response did not finish')
            expected = {'response': 0, 'choices': {'remember': 'true'}} if allow else {'response': 1}
            assert dialog.result() == expected, dialog.result()
            dialog.close(); dialog = None
            wait_for(lambda: state().get('height') == 40, 'Permission pill did not collapse')
        print('PASS: permission pill preserves deny, allow and choice responses', flush=True)

        sharing = json.loads((Path(__file__).parent / 'portal-fixtures/share.json').read_text())
        sharing.pop('fixture')
        groups = [sharing[key] for key in ('outputs', 'windows', 'workspaces')]
        for tab, identity, region in [('window', 'window:21', False), ('workspace', 'workspace-id:1', False),
                                      ('screen', 'screen:DP-3', True)]:
            dialog = Dialog(sharing)
            # Enable synthetic preview pixels only after exercising real routing.
            dialog.update(dict(sharing, fixture=True))
            wait_for(lambda: state().get('kind') == 'share' and state().get('width') == 680
                     and state().get('height') == round(state().get('desiredHeight', 0)), 'Sharing pill did not settle')
            assert not state()['canAccept'], 'Sharing accepted without a selected source'
            ipc('share', tab, identity, str(region).lower())
            wait_for(lambda: state().get('canAccept') and state().get('height') == round(state().get('desiredHeight', 0)),
                     'Sharing selection/region did not become ready')
            ipc('submit')
            wait_for(lambda: dialog.process.poll() == 0, 'Sharing response did not finish')
            expected = '[SELECTION]r/' + ('region:DP-3@10,20,320,180' if region else identity)
            assert share_result(dialog.result(), groups) == expected, dialog.result()
            dialog.close(); dialog = None
            wait_for(lambda: state().get('height') == 40, 'Sharing pill did not collapse')
        print('PASS: sharing pill preserves window, workspace, remember and monitor region selections', flush=True)

        ipc('fullscreen', 'true')
        dialog = present()
        assert state()['idleHidden'] and not state()['hidden'], state()
        ipc('cancel')
        wait_for(lambda: dialog.process.poll() == 0, 'Hidden-pill cancellation did not finish')
        assert dialog.result() == {'response': 1}
        dialog.close(); dialog = None
        print('PASS: chooser remains usable when fullscreen hides the idle pill', flush=True)
    finally:
        if sys.exc_info()[0] not in (None, SystemExit) and shell is not None:
            print("Last pill state:", state(), flush=True)
        if dialog is not None:
            dialog.close()
        if shell is not None:
            shell.terminate(); shell.wait(timeout=5)
        compositor.terminate(); compositor.wait(timeout=5)
