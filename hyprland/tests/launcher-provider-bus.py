#!/usr/bin/env python3
"""Run the actual worker against a fake Nautilus on the private test bus."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
import time
from gi.repository import Gio, GLib

if 'agent-desktops' not in os.environ.get('XDG_RUNTIME_DIR', ''):
    raise SystemExit('Use the isolated-gui helper')

xml = '''<node><interface name="org.gnome.Shell.SearchProvider2">
<method name="GetInitialResultSet"><arg type="as" direction="in"/><arg type="as" direction="out"/></method>
<method name="GetResultMetas"><arg type="as" direction="in"/><arg type="aa{sv}" direction="out"/></method>
</interface></node>'''
loop = GLib.MainLoop()
bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
name = Gio.bus_own_name_on_connection(bus, 'org.gnome.Nautilus', Gio.BusNameOwnerFlags.NONE, None, None)
with tempfile.TemporaryDirectory(prefix='launcher-bus-') as temporary:
    root = Path(temporary)
    invoice = root / 'Invoice fixture.pdf'
    invoice.write_text('Fixture, not a personal document')
    calls = []
    def method(connection, sender, path, interface, method, args, invocation):
        calls.append((method, args.unpack()))
        if method == 'GetInitialResultSet':
            invocation.return_value(GLib.Variant('(as)', ([invoice.as_uri()],)))
        else:
            invocation.return_value(GLib.Variant('(aa{sv})', ([{'id': GLib.Variant('s', invoice.as_uri()),
                'name': GLib.Variant('s', invoice.name), 'description': GLib.Variant('s', 'Private fixture')}],)))
    obj = bus.register_object('/org/gnome/Nautilus/SearchProvider', Gio.DBusNodeInfo.new_for_xml(xml).interfaces[0], method, None, None)
    thread = threading.Thread(target=loop.run, daemon=True)
    thread.start()
    # Clipboard actions use a test executable; they never touch either desktop.
    fake_bin = root / 'bin'; fake_bin.mkdir()
    copy = fake_bin / 'wl-copy'
    copy.write_text('#!/usr/bin/python3\nimport pathlib,sys\npathlib.Path(' + repr(str(root / 'copied')) + ').write_text(sys.argv[-1])\n')
    copy.chmod(0o700)
    env = dict(os.environ, XDG_STATE_HOME=str(root/'state'), PATH=str(fake_bin)+':'+os.environ['PATH'])
    worker = subprocess.Popen([os.environ['DOTFILES_DESKTOP_BINARY'], 'launcher'], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env=env)
    try:
        assert json.loads(worker.stdout.readline())['ready']
        worker.stdin.write(json.dumps({'id': 1, 'query': 'files invoice'})+'\n');worker.stdin.flush()
        messages = [json.loads(worker.stdout.readline()), json.loads(worker.stdout.readline())]
        result = next(m['results'][0] for m in messages if m['section']=='files')
        assert result['path'] == str(invoice), messages
        worker.stdin.write(json.dumps({'op': 'action', 'resultId': result['id'], 'action': 'copy'})+'\n');worker.stdin.flush()
        assert json.loads(worker.stdout.readline())['message'] == 'Copied'
        assert (root/'copied').read_text() == str(invoice)
        worker.stdin.write(json.dumps({'op': 'action', 'resultId': result['id'], 'action': 'favorite'})+'\n');worker.stdin.flush()
        assert json.loads(worker.stdout.readline())['favorite']
        worker.stdin.write(json.dumps({'id': 2, 'query': ''})+'\n');worker.stdin.flush()
        messages = [json.loads(worker.stdout.readline()), json.loads(worker.stdout.readline())]
        assert next(m for m in messages if m['section']=='quick')['results'][0]['favorite']
        print('PROVIDER BUS PASS: actual JSON worker, GNOME D-Bus calls, copy, favorites and recents', flush=True)
    finally:
        worker.stdin.close()
        worker.wait(timeout=15)
        loop.quit()
        bus.unregister_object(obj)
        Gio.bus_unown_name(name)
