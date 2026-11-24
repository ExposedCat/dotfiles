#!/usr/bin/env python3
"""Open live pill views, file choosers, and the system authentication prompt."""
import argparse
import json
import os
from pathlib import Path
import shlex
import socket
import subprocess
import sys
import tempfile
import threading
import time
import uuid

SAMPLES = Path(__file__).resolve().parent / 'samples'


def desktop_environment():
    if os.environ.get('ISOLATED_GUI_SESSION'):
        return
    if Path('/run/.containerenv').exists():
        os.execvp('distrobox-host-exec', ['distrobox-host-exec', '/usr/bin/python3', '-B', str(Path(__file__).resolve()), *sys.argv[1:]])
    pid = subprocess.check_output(['systemctl', '--user', 'show', 'dotfiles-hyprland-shell.service', '-p', 'MainPID', '--value'], text=True).strip()
    values = dict(part.split('=', 1) for part in Path(f'/proc/{pid}/environ').read_text().split('\0') if '=' in part)
    instances = json.loads(subprocess.check_output(['hyprctl', 'instances', '-j'], text=True))
    if not any(item['instance'] == values.get('HYPRLAND_INSTANCE_SIGNATURE') for item in instances):
        raise RuntimeError('The shell does not belong to a running Hyprland session')
    for key in ('HYPRLAND_INSTANCE_SIGNATURE', 'WAYLAND_DISPLAY', 'DISPLAY', 'XDG_RUNTIME_DIR', 'DBUS_SESSION_BUS_ADDRESS'):
        if key in values:
            os.environ[key] = values[key]
    os.environ['GDK_BACKEND'] = 'wayland'


class Preview:
    """Own only this gallery's pending request; never dismiss another client."""
    def __init__(self):
        self.cancelled = threading.Event()
        self.connection = None
        self.process = None

    def close(self):
        self.cancelled.set()
        if self.connection:
            try:
                self.connection.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
        if self.process and self.process.poll() is None:
            self.process.terminate()

    def exchange(self, endpoint, payload):
        runtime = Path(os.environ['XDG_RUNTIME_DIR'])
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as connection:
            self.connection = connection
            connection.settimeout(2)
            connection.connect(str(runtime / endpoint))
            connection.sendall((json.dumps(payload) + '\n').encode())
            connection.settimeout(.2)
            pending = b''
            accepted = False
            deadline = time.monotonic() + 300
            while not self.cancelled.is_set() and time.monotonic() < deadline:
                try:
                    chunk = connection.recv(4096)
                except socket.timeout:
                    continue
                if not chunk:
                    return 'Dismissed' if accepted else 'The shell closed the request'
                pending += chunk
                if len(pending) > 65536:
                    raise RuntimeError('Oversized shell response')
                while b'\n' in pending:
                    line, pending = pending.split(b'\n', 1)
                    reply = json.loads(line)
                    if reply.get('accepted') is False:
                        return 'The pill is busy. Dismiss its current prompt, then try again.'
                    if reply.get('accepted') is True:
                        accepted = True
                    if 'response' in reply:
                        # Secret values are intentionally neither retained nor logged.
                        return 'Preview completed' if reply['response'] == 0 else 'Dismissed'
                    if reply.get('done'):
                        return 'Preview closed'
                    if 'error' in reply:
                        raise RuntimeError('The shell rejected the preview request')
            return 'Dismissed' if self.cancelled.is_set() else 'Preview timed out'

    def credentials(self, kind):
        data = {'id': 'gallery-' + uuid.uuid4().hex, 'kind': 'bluetooth' if kind.startswith('bt-') else 'network', 'fields': [], 'rememberAllowed': False}
        if kind == 'bt-confirm':
            data.update(subtitle='Preview headphones', code='482916', confirmLabel='Pair')
        elif kind == 'bt-pin':
            data.update(subtitle='Preview keyboard', confirmLabel='Pair', fields=[{'key': 'pin', 'label': 'Pairing PIN', 'secret': False, 'maxLength': 16}])
        elif kind == 'bt-passkey':
            data.update(subtitle='Preview keyboard', code='482916', entered=3, displayOnly=True)
        elif kind == 'wifi':
            data.update(subtitle='Preview Wi-Fi', networkType='wifi', confirmLabel='Connect', fields=[{'key': 'password', 'label': 'Password', 'secret': True, 'minLength': 8, 'maxLength': 63}])
        elif kind == 'vpn':
            data.update(subtitle='Preview VPN', networkType='vpn', confirmLabel='Connect', fields=[{'key': 'password', 'label': 'Password', 'secret': True}, {'key': 'otp', 'label': 'One-time code', 'secret': True, 'validation': 'digits', 'minLength': 6, 'maxLength': 6}])
        return self.exchange('dotfiles-credentials-shell.sock', {'action': 'open', 'data': data})

    def portal(self, kind):
        data = json.loads((SAMPLES / f'{kind}.json').read_text())
        data['app'] = {'name': 'Prompt Gallery', 'id': 'org.dotfiles.PromptGallery'}
        # Connect directly to the live pill while preserving sample source previews.
        with tempfile.TemporaryDirectory(prefix='dotfiles-portal-', dir=os.environ['XDG_RUNTIME_DIR']) as directory:
            path = Path(directory) / 'request.json'
            path.write_text(json.dumps(data))
            path.chmod(0o600)
            if kind == 'share':
                config = Path(os.environ.get('XDG_CONFIG_HOME') or Path.home() / '.config')
                helper = os.environ.get('DOTFILES_DESKTOP_BINARY') or config / 'hypr/bin/dotfiles-desktop'
                self.process = subprocess.Popen(
                    [helper, 'portal', 'preview', path, '--in-pill'],
                    stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
                )
                if self.cancelled.is_set():
                    self.process.terminate()
                stdout, _ = self.process.communicate()
                if self.cancelled.is_set():
                    return 'Dismissed'
                if self.process.returncode:
                    return 'Could not open the screen sharing preview'
                return 'Preview completed' if json.loads(stdout)['response'] == 0 else 'Dismissed'
            try:
                return self.exchange('dotfiles-portal-shell.sock', {'action': 'open', 'directory': directory})
            finally:
                # Allow an in-flight response writer to finish after cancellation.
                if self.cancelled.is_set():
                    time.sleep(.35)

    def authenticate(self):
        if os.environ.get('ISOLATED_GUI_SESSION'):
            return 'Real authentication is disabled on the isolated test desktop'
        self.process = subprocess.Popen(['pkexec', '/usr/bin/true'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        result = self.process.wait()
        return 'Authorization completed (or already cached)' if result == 0 else 'Authentication dismissed'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--floating-launch', action='store_true', help=argparse.SUPPRESS)
    args = parser.parse_args()
    desktop_environment()
    if not os.environ.get('ISOLATED_GUI_SESSION') and not args.floating_launch:
        command = shlex.join(['/usr/bin/python3', '-B', str(Path(__file__).resolve()), '--floating-launch'])
        return subprocess.run(['hyprctl', 'dispatch', 'hl.dsp.exec_cmd(' + json.dumps(command) + ', {float=true, center=true})']).returncode
    import gi
    gi.require_version('Gtk', '4.0')
    gi.require_version('Adw', '1')
    from gi.repository import Adw, Gio, GLib, Gtk

    class Gallery(Adw.Application):
        def __init__(self):
            super().__init__(application_id='org.dotfiles.PromptGallery')
            self.current = None
            self.last = None
            self.queue = []
            self.generation = 0
            self.portal_request = None
            self.portal_subscription = None
            self.titles = {}
            self.shell_config = os.environ.get('DOTFILES_GALLERY_SHELL', str(Path.home() / '.config/hypr/shell/shell.qml'))
            self.connect('activate', self.activate)
            self.connect('shutdown', self.shutdown)

        def shell(self, method, *values):
            return subprocess.check_output(['/usr/bin/quickshell', 'ipc', '--path', self.shell_config, 'call', 'shell', method, *values], text=True, timeout=3).strip()

        def activate(self, _app):
            if hasattr(self, "window"):
                self.window.present()
                return
            self.window = Adw.ApplicationWindow(application=self, title='Prompt Gallery', default_width=560, default_height=770)
            layout = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
            toolbar = Adw.HeaderBar()
            toolbar.set_title_widget(Adw.WindowTitle(title='Prompt Gallery', subtitle='Pill prompts and desktop portals'))
            layout.append(toolbar)
            scroll = Gtk.ScrolledWindow(vexpand=True, hscrollbar_policy=Gtk.PolicyType.NEVER)
            page = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=20, margin_start=24, margin_end=24, margin_top=12, margin_bottom=24)
            intro = Gtk.Label(label='Screen sharing, permission, app, and credential previews use sample requests. Dismiss a prompt to replay it.', wrap=True, xalign=0)
            intro.add_css_class('dim-label')
            page.append(intro)
            actions = Gtk.Box(spacing=8, homogeneous=True)
            tour = Gtk.Button(label='Play all')
            tour.add_css_class('suggested-action')
            tour.connect('clicked', self.tour)
            replay = Gtk.Button(label='Replay last')
            replay.connect('clicked', lambda _button: self.trigger(self.last) if self.last else None)
            stop = Gtk.Button(label='Stop / dismiss')
            stop.connect('clicked', lambda _button: self.stop())
            for button in (tour, replay, stop):
                actions.append(button)
            page.append(actions)
            self.status = Gtk.Label(label='Ready. Choose any prompt below.', wrap=True, xalign=0, selectable=True)
            page.append(self.status)
            groups = [
                ('Authentication and credentials', [
                    ('auth', 'System authentication', 'Real authorization for a command that does nothing'),
                    ('bt-confirm', 'Bluetooth pairing', 'Confirm a matching six-digit code'),
                    ('bt-pin', 'Bluetooth PIN', 'Enter a pairing PIN'),
                    ('bt-passkey', 'Bluetooth passkey display', 'See the code and typing progress'),
                    ('wifi', 'Wi-Fi password', 'Masked input and visibility control'),
                    ('vpn', 'VPN credentials', 'Password and one-time code')]),
                ('Portals', [
                    ('apps', 'Open with', 'Application chooser in the pill'),
                    ('access', 'Permission request', 'Allow / deny and remembered choices'),
                    ('share', 'Screen sharing', 'Sample monitors, windows, workspaces, and regions'),
                    ('open-file', 'Open file', 'The real desktop file chooser'),
                    ('save-file', 'Save file', 'The real save chooser; no file is written')]),
                ('Pill menus', [
                    ('panel:launcher', 'Applications', 'Launcher and search'),
                    ('panel:notifications', 'Notifications', 'Your notification center'),
                    ('panel:bluetooth', 'Bluetooth devices', 'Your Bluetooth menu'),
                    ('panel:ethernet', 'Network', 'Your connection menu'),
                    ('panel:mixer', 'Sound', 'Your audio mixer'),
                    ('panel:media', 'Media', 'Your current player, when one is active'),
                    ('panel:system', 'System', 'Your system statistics'),
                    ('panel:power', 'Power', 'Power menu — dismiss without choosing an action')])]
            for title, entries in groups:
                group = Adw.PreferencesGroup(title=title)
                for key, title, subtitle in entries:
                    row = Adw.ActionRow(title=title, subtitle=subtitle)
                    button = Gtk.Button(label='Show', valign=Gtk.Align.CENTER)
                    button.update_property([Gtk.AccessibleProperty.LABEL], ['Show ' + title])
                    button.connect('clicked', lambda _button, key=key: self.trigger(key))
                    row.add_suffix(button)
                    row.set_activatable_widget(button)
                    group.add(row)
                    self.titles[key] = title
                page.append(group)
            scroll.set_child(page)
            layout.append(scroll)
            self.window.set_content(layout)
            self.window.present()

        def stop(self):
            self.queue.clear()
            self.generation += 1
            if self.current:
                self.current.close()
                self.current = None
            if self.portal_request:
                Gio.bus_get_sync(Gio.BusType.SESSION, None).call('org.freedesktop.portal.Desktop', self.portal_request, 'org.freedesktop.portal.Request', 'Close', None, None, Gio.DBusCallFlags.NONE, 2000, None, None)
                self.portal_request = None
            if self.portal_subscription:
                Gio.bus_get_sync(Gio.BusType.SESSION, None).signal_unsubscribe(self.portal_subscription)
                self.portal_subscription = None
            self.status.set_label('Stopped. Choose a prompt to open it again.')

        def shutdown(self, _app):
            self.stop()

        def tour(self, _button):
            self.stop()
            # Dismiss each view to advance; leave enough time to see the compact pill.
            self.queue = [key for key in self.titles if key != 'auth'] + ['auth']
            self.next_in_tour()

        def next_in_tour(self):
            if self.queue:
                key = self.queue.pop(0)
                self.trigger(key, tour=True)
            return False

        def trigger(self, key, tour=False):
            if not key:
                return
            if not tour:
                self.stop()
            self.last = key
            self.generation += 1
            generation = self.generation
            self.status.set_label('Opening ' + self.titles[key] + '…')
            def begin():
                if generation != self.generation:
                    return False
                if key in ('open-file', 'save-file'):
                    self.file_picker(key, generation)
                else:
                    request = Preview()
                    self.current = request
                    def work():
                        try:
                            if key == 'auth':
                                message = request.authenticate()
                            elif key in ('apps', 'access', 'share'):
                                message = request.portal(key)
                            elif key.startswith('panel:'):
                                panel = key.split(':', 1)[1]
                                self.shell('toggle', panel)
                                time.sleep(.4)
                                while not request.cancelled.is_set() and json.loads(self.shell('status')).get('panel') == panel:
                                    time.sleep(.2)
                                if request.cancelled.is_set() and json.loads(self.shell('status')).get('panel') == panel:
                                    self.shell('toggle', panel)
                                message = 'Menu closed'
                            else:
                                message = request.credentials(key)
                        except (OSError, ValueError, subprocess.SubprocessError, RuntimeError):
                            message = 'Could not open the prompt. Check that the Hyprland shell is running.'
                        GLib.idle_add(self.finished, generation, message)
                    threading.Thread(target=work, daemon=True).start()
                return False
            GLib.timeout_add(700, begin)

        def finished(self, generation, message):
            if generation != self.generation:
                return False
            self.current = None
            if any(word in message for word in ("busy", "Could not", "unavailable")):
                self.queue.clear()
            self.status.set_label(message + ('. Dismiss the next prompt to continue the tour.' if self.queue else '. Click again to replay.'))
            if self.queue:
                GLib.timeout_add(900, lambda: self.next_in_tour() if generation == self.generation else False)
            return False

        def file_picker(self, key, generation):
            bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
            token = 'gallery_' + uuid.uuid4().hex
            handle = '/org/freedesktop/portal/desktop/request/' + bus.get_unique_name()[1:].replace('.', '_') + '/' + token
            self.portal_request = handle
            def response(_bus, _sender, _path, _interface, _signal, parameters):
                if generation != self.generation:
                    return
                code, _results = parameters.unpack()
                bus.signal_unsubscribe(self.portal_subscription)
                self.portal_subscription = None
                self.portal_request = None
                self.finished(generation, 'File chooser completed' if code == 0 else 'File chooser dismissed')
            self.portal_subscription = bus.signal_subscribe('org.freedesktop.portal.Desktop', 'org.freedesktop.portal.Request', 'Response', handle, None, Gio.DBusSignalFlags.NONE, response)
            options = {'handle_token': GLib.Variant('s', token), 'modal': GLib.Variant('b', False)}
            if key == 'save-file':
                options['current_name'] = GLib.Variant('s', 'Preview.txt')
            def called(connection, result):
                try:
                    connection.call_finish(result)
                except GLib.Error:
                    if generation == self.generation:
                        bus.signal_unsubscribe(self.portal_subscription)
                        self.portal_subscription = None
                        self.portal_request = None
                        self.finished(generation, 'The desktop file chooser is unavailable')
            bus.call('org.freedesktop.portal.Desktop', '/org/freedesktop/portal/desktop', 'org.freedesktop.portal.FileChooser', 'SaveFile' if key == 'save-file' else 'OpenFile', GLib.Variant('(ssa{sv})', ('', 'Prompt Gallery — ' + ('Save file' if key == 'save-file' else 'Open file'), options)), None, Gio.DBusCallFlags.NONE, 10000, None, called)

    return Gallery().run([])


if __name__ == '__main__':
    raise SystemExit(main())
