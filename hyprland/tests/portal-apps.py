"""Exercise launcher-style application choices and cancellation on a private bus."""
import os
from pathlib import Path
import subprocess
import sys
from gi.repository import Gio, GLib

if not os.environ.get('ISOLATED_GUI_SESSION'):
    raise SystemExit('Run through isolated-gui; this check creates chooser windows.')

ROOT = Path(__file__).parents[1] / 'config/portals'
sys.path.insert(0, str(ROOT))
import native as backend

applications = Path(os.environ['XDG_DATA_HOME']) / 'applications'
applications.mkdir(parents=True, exist_ok=True)
for identity, name in [('Alpha', 'Alpha Document'), ('Beta', 'Beta Editor'), ('Gamma', 'Gamma Reader')]:
    (applications / f'org.example.{identity}.desktop').write_text(
        f'[Desktop Entry]\nType=Application\nName={name}\nExec=/usr/bin/true %U\n')

bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
bus.call_sync('org.freedesktop.DBus', '/org/freedesktop/DBus', 'org.freedesktop.DBus', 'RequestName',
              GLib.Variant('(su)', ('org.freedesktop.portal.Desktop', 4)), None,
              Gio.DBusCallFlags.NONE, 2000, None)
service = subprocess.Popen([str(backend.BINARY), 'portal', 'backend'])
loop = GLib.MainLoop()
failure = []
phase = 0
waiting = False
cases = [(1, {}), (1, {}), (0, {'choice': 'org.example.Beta'}),
         (0, {'choice': 'org.example.Gamma'}), (1, {})]


def input(*args):
    subprocess.run(['/usr/bin/xdotool', *args], check=True, timeout=5)


def later(callback, delay=200):
    def wrapped():
        try:
            callback()
        except Exception as error:
            failure.append(error)
            loop.quit()
        return False
    GLib.timeout_add(delay, wrapped)


def finished(connection, result):
    global phase, waiting
    try:
        reply = connection.call_finish(result).unpack()
        assert waiting, 'Chooser accepted a query with no matches'
        assert reply == cases[phase], (phase, reply)
        print(f'PASS: chooser case {phase}: {reply}', flush=True)
        phase += 1
        if phase == len(cases):
            loop.quit()
        else:
            later(request)
    except Exception as error:
        failure.append(error)
        loop.quit()


def no_matches():
    global waiting
    assert phase == 4
    waiting = True
    input('key', 'Escape')


def drive():
    global waiting
    found = subprocess.run(['/usr/bin/xdotool', 'search', '--onlyvisible', '--name',
                            '^Desktop portal: Open With$'], text=True, capture_output=True)
    if not found.stdout.strip():
        later(drive, 100)
        return
    window = found.stdout.splitlines()[-1]
    input('windowactivate', '--sync', window)
    if phase == 0:
        input('key', 'Escape')
    elif phase == 1:
        input('type', '--clearmodifiers', 'beta')
        later(lambda: input('key', 'Escape'))
    elif phase == 2:
        input('key', 'Down', 'Return')
    elif phase == 3:
        input('type', '--clearmodifiers', 'gamma')
        later(lambda: input('key', 'Return'))
    else:
        input('type', '--clearmodifiers', 'no-such-application')
        def enter():
            global waiting
            waiting = False
            input('key', 'Return')
            later(no_matches, 400)
        later(enter)


def request():
    global waiting
    waiting = True
    handle = f'/org/freedesktop/portal/desktop/request/test/chooser{phase}'
    options = {'filename': GLib.Variant('s', 'fixture.pdf')}
    bus.call(backend.NAME, backend.PATH, backend.PREFIX + 'AppChooser', 'ChooseApplication',
             GLib.Variant('(ossasa{sv})', (handle, '', '',
                          ['org.example.Alpha', 'org.example.Beta', 'org.example.Gamma'], options)),
             None, Gio.DBusCallFlags.NONE, 20000, None, finished)
    later(drive)


def start():
    try:
        bus.call_sync(backend.NAME, backend.PATH, 'org.freedesktop.DBus.Introspectable', 'Introspect',
                      None, None, Gio.DBusCallFlags.NO_AUTO_START, 500, None)
    except GLib.Error:
        later(start, 100)
        return
    request()


def timeout():
    failure.append(RuntimeError('Application chooser check timed out'))
    loop.quit()
    return False


try:
    later(start, 100)
    GLib.timeout_add(25000, timeout)
    loop.run()
    if failure:
        raise failure[0]
    assert phase == len(cases)
    print('PASS: Escape cancels empty/filtered/unmatched queries; arrows and Enter choose apps.', flush=True)
finally:
    service.terminate()
    service.wait(timeout=5)
