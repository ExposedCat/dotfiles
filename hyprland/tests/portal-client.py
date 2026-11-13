"""Interactive protocol check; run ONLY through the isolated-gui helper."""
import os
from pathlib import Path
import subprocess
import sys
import time
from gi.repository import Gio, GLib

if not os.environ.get('ISOLATED_GUI_SESSION'):
    raise SystemExit('Run through isolated-gui; this check opens dialogs.')
ROOT = Path(__file__).parents[1] / 'config/portals'
sys.path.insert(0, str(ROOT))
import backend

bus = Gio.bus_get_sync(Gio.BusType.SESSION)
# Simulate the trusted frontend, rather than bypassing production authorization.
bus.call_sync('org.freedesktop.DBus', '/org/freedesktop/DBus', 'org.freedesktop.DBus', 'RequestName',
              GLib.Variant('(su)', ('org.freedesktop.portal.Desktop', 4)), None,
              Gio.DBusCallFlags.NONE, 1000, None)
service = subprocess.Popen(['/usr/bin/python3', str(ROOT / 'backend.py')])
loop = GLib.MainLoop()
errors = []
handle = '/org/freedesktop/portal/desktop/request/test/dialog'
phase = 0


def call(interface, method, params, callback):
    def done(connection, result):
        try:
            callback(connection.call_finish(result).unpack())
        except Exception as error:
            errors.append(error)
            loop.quit()
    bus.call(backend.NAME, backend.PATH, backend.PREFIX + interface, method, params,
             None, Gio.DBusCallFlags.NONE, 180000, None, done)


def app_done(reply):
    assert reply == (0, {'choice': 'org.mozilla.firefox'}), reply
    print('PASS: application response. Next: allow the permission prompt.', flush=True)
    options = {'choices': GLib.Variant('a(ssa(ss)s)', [('remember', 'Remember my decision', [], 'false')])}
    call('Access', 'AccessDialog', GLib.Variant('(osssssa{sv})', (handle, 'com.chipichapa.sele', '',
         'Allow microphone access?', 'Sele would like to use your microphone.', 'Only allow this if you trust the application.', options)), access_done)


def access_done(reply):
    assert reply == (0, {'choices': [('remember', 'false')]}), reply
    print('PASS: permission response. Testing frontend cancellation…', flush=True)
    call('AppChooser', 'ChooseApplication', GLib.Variant('(ossasa{sv})', (handle, '', '', ['org.mozilla.firefox'], {})), cancel_done)
    GLib.timeout_add(750, cancel)


def cancel():
    bus.call(backend.NAME, handle, backend.PREFIX + 'Request', 'Close', None, None,
             Gio.DBusCallFlags.NONE, 2000, None, None)
    return False


def cancel_done(reply):
    assert reply == (2, {}), reply
    print('PASS: frontend Close cancels request and closes UI.', flush=True)
    # A malformed request path must not leave an orphan chooser process.
    call('AppChooser', 'ChooseApplication', GLib.Variant('(ossasa{sv})', (handle, '', '', ['before'], {})), update_cancel_done)
    GLib.timeout_add(500, update_choices)


def update_choices():
    bus.call_sync(backend.NAME, backend.PATH, backend.PREFIX + 'AppChooser', 'UpdateChoices',
                  GLib.Variant('(oas)', (handle, ['after'])), None, Gio.DBusCallFlags.NONE, 2000, None)
    files = list(Path(os.environ['XDG_RUNTIME_DIR']).glob('dotfiles-portal-*/request.json'))
    import json
    assert any(json.loads(path.read_text()).get('apps', [{}])[0].get('id') == 'after' for path in files), files
    cancel()
    return False


def update_cancel_done(reply):
    assert reply == (2, {}), reply
    print('PASS: UpdateChoices replaces choices on the pending request.', flush=True)
    loop.quit()


try:
    for attempt in range(50):
        try:
            bus.call_sync(backend.NAME, backend.PATH, 'org.freedesktop.DBus.Introspectable', 'Introspect', None, None,
                          Gio.DBusCallFlags.NO_AUTO_START, 500, None)
            break
        except GLib.Error:
            time.sleep(0.1)
    else:
        raise RuntimeError('Backend did not start')
    foreign = Gio.DBusConnection.new_for_address_sync(os.environ['DBUS_SESSION_BUS_ADDRESS'],
                  Gio.DBusConnectionFlags.AUTHENTICATION_CLIENT | Gio.DBusConnectionFlags.MESSAGE_BUS_CONNECTION, None, None)
    try:
        foreign.call_sync(backend.NAME, backend.PATH, backend.PREFIX + 'AppChooser', 'ChooseApplication',
                          GLib.Variant('(ossasa{sv})', (handle, '', '', [], {})), None, Gio.DBusCallFlags.NONE, 2000, None)
    except GLib.Error as error:
        assert 'AccessDenied' in str(error), error
        print('PASS: untrusted direct caller rejected.', flush=True)
    else:
        raise AssertionError('Untrusted caller was allowed')
    foreign.close_sync(None)
    print('READY: select Firefox and press Open.', flush=True)
    call('AppChooser', 'ChooseApplication', GLib.Variant('(ossasa{sv})', (handle, 'com.chipichapa.sele', '',
         ['org.mozilla.firefox', 'org.gnome.Nautilus'], {'filename': GLib.Variant('s', 'Project brief.html')})), app_done)
    loop.run()
    if errors:
        raise errors[0]
    print('PASS: D-Bus AppChooser, Access, Close, and UpdateChoices integration.', flush=True)
finally:
    service.terminate()
    service.wait(timeout=5)
