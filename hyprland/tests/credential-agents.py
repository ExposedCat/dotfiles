"""Real agent protocol + pill checks on the isolated desktop and fake system bus."""
import json
import os
from pathlib import Path
import subprocess
import threading
import time

import gi
gi.require_version('Gio', '2.0')
from gi.repository import Gio, GLib

if not os.environ.get('ISOLATED_GUI_SESSION'):
    raise SystemExit('Run through isolated-gui; this test creates a nested compositor.')

ROOT = Path(__file__).resolve().parents[1]
runtime = Path(os.environ['XDG_RUNTIME_DIR'])
work = runtime.parent / 'credential-fixtures'
work.mkdir(exist_ok=True)
(work / 'fixture.json').write_text('{}')
(work / 'sway.conf').write_text('output * mode 1280x800\noutput * bg #171411 solid_color\nseat * hide_cursor 10000\n')
binary = os.environ['DOTFILES_DESKTOP_BINARY']
env = dict(os.environ, DBUS_SYSTEM_BUS_ADDRESS=os.environ['DBUS_SESSION_BUS_ADDRESS'],
           WLR_BACKENDS='x11', WLR_RENDERER='pixman', WLR_LIBINPUT_NO_DEVICES='1',
           DOTFILES_SHELL_FIXTURE=str(work / 'fixture.json'), DOTFILES_SHELL_SOURCE=str(ROOT / 'config/shell'),
           DOTFILES_HYPR_ROOT=str(ROOT / 'config'), XDG_STATE_HOME=str(work / 'state'),
           XDG_CACHE_HOME=str(work / 'cache'), XDG_CONFIG_HOME=str(work / 'config'))

def wait(check, message, timeout=12):
    until = time.monotonic() + timeout
    while time.monotonic() < until:
        value = check()
        if value:
            return value
        time.sleep(.025)
    raise AssertionError(message)

bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
for name in ('org.bluez', 'org.freedesktop.NetworkManager'):
    bus.call_sync('org.freedesktop.DBus', '/org/freedesktop/DBus', 'org.freedesktop.DBus',
                  'RequestName', GLib.Variant('(su)', (name, 0)), None, 0, 2000, None)
agents = {}
def manager(connection, sender, path, interface, method, params, call):
    if method in ('RegisterAgent', 'RegisterWithCapabilities'):
        agents['bt' if method == 'RegisterAgent' else 'nm'] = sender
    call.return_value(None)

for path, xml in [('/org/bluez', '''<node><interface name="org.bluez.AgentManager1">
 <method name="RegisterAgent"><arg type="o" direction="in"/><arg type="s" direction="in"/></method>
 <method name="RequestDefaultAgent"><arg type="o" direction="in"/></method></interface></node>'''),
 ('/org/freedesktop/NetworkManager/AgentManager', '''<node><interface name="org.freedesktop.NetworkManager.AgentManager">
 <method name="RegisterWithCapabilities"><arg type="s" direction="in"/><arg type="u" direction="in"/></method></interface></node>''')]:
    bus.register_object(path, Gio.DBusNodeInfo.new_for_xml(xml).interfaces[0], manager, None, None)
device = '/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF'
bus.register_object(device, Gio.DBusNodeInfo.new_for_xml('''<node><interface name="org.bluez.Device1">
 <property name="Alias" type="s" access="read"/><method name="CancelPairing"/></interface></node>''').interfaces[0],
                    lambda *args: args[-1].return_value(None), lambda *args: GLib.Variant('s', 'Keychron K2'), None)
loop = GLib.MainLoop()
threading.Thread(target=loop.run, daemon=True).start()

def request(group, method, params, connection=bus):
    result = {}
    def completed(conn, response):
        try:
            result['value'] = conn.call_finish(response)
        except GLib.Error as error:
            result['error'] = error
        result['done'] = True
    connection.call(agents[group], '/org/dotfiles/BluetoothAgent' if group == 'bt' else '/org/freedesktop/NetworkManager/SecretAgent',
                    'org.bluez.Agent1' if group == 'bt' else 'org.freedesktop.NetworkManager.SecretAgent',
                    method, params, None, Gio.DBusCallFlags.NONE, 20000, None, completed)
    return result

def network(section, name, extra, hints=()):
    config = {'connection': {'id': GLib.Variant('s', name), 'uuid': GLib.Variant('s', 'fixture-not-a-real-profile')}, section: extra}
    return GLib.Variant('(a{sa{sv}}osasu)', (config, '/org/freedesktop/NetworkManager/Settings/99999', section, hints, 3))

logs = [(work / name).open('w') for name in ('sway.log', 'shell.log', 'agents.log')]
compositor = shell = backend = recorder = None
try:
    compositor = subprocess.Popen(['/usr/bin/sway', '--unsupported-gpu', '-c', str(work / 'sway.conf')], env=env, stdout=logs[0], stderr=logs[0])
    display = wait(lambda: next((p for p in runtime.glob('wayland-*') if p.is_socket()), None), 'No private Wayland socket')
    env.update(QT_QPA_PLATFORM='wayland', WAYLAND_DISPLAY=display.name)
    fixture = ROOT / 'tests/credentials.qml'
    shell = subprocess.Popen(['/usr/bin/quickshell', '--no-color', '--path', str(fixture)], env=env, stdout=logs[1], stderr=logs[1])
    def ipc(method, *args):
        result = subprocess.run(['/usr/bin/quickshell', 'ipc', '--path', str(fixture), 'call', 'credentialTest', method, *map(str, args)],
                                env=env, capture_output=True, text=True, timeout=3)
        if result.returncode:
            return {}
        return json.loads(result.stdout) if result.stdout.strip() else True
    def state():
        return ipc('state') or {}
    wait(lambda: state().get('height') == 40 and (runtime / 'dotfiles-credentials-shell.sock').is_socket(), 'Shell did not become ready')
    backend = subprocess.Popen([binary, 'desktop', 'agents', '--test-bus'], env=env, stdout=logs[2], stderr=logs[2])
    wait(lambda: len(agents) == 2, 'System agents did not register on the private bus')
    if os.environ.get('DOTFILES_CREDENTIAL_RECORD'):
        recorder = subprocess.Popen(['/usr/bin/ffmpeg', '-y', '-loglevel', 'error', '-f', 'x11grab', '-framerate', '24',
                                     '-video_size', '1280x800', '-i', os.environ['DISPLAY'], '-c:v', 'ffv1', str(work / 'pill-morph.mkv')], stdout=subprocess.DEVNULL, stderr=(work / 'recording.log').open('w'))
    def shown(kind, fields=0):
        wait(lambda: state().get('panel') == 'credentials' and state().get('kind') == kind and state().get('fields') == fields, 'Credential pill did not open')
        time.sleep(.45)
    def capture(name):
        subprocess.run(['/usr/bin/import', '-window', 'root', str(work / (name + '.png'))], check=True, env=env)
    def closed():
        wait(lambda: not state().get('active') and state().get('height') == 40, 'Credential pill did not collapse')
        time.sleep(.25)

    def pointer(control, click=False):
        point = ipc('controlPoint', control, 0)
        outer = subprocess.check_output(['/usr/bin/xdotool', 'getactivewindow'], env=env, text=True).strip()
        geometry = subprocess.check_output(['/usr/bin/xdotool', 'getwindowgeometry', '--shell', outer], env=env, text=True)
        geometry = dict(line.split('=', 1) for line in geometry.splitlines() if '=' in line)
        command = ['/usr/bin/xdotool', 'mousemove', str(round(point['x']) + int(geometry['X'])),
                   str(round(point['y']) + int(geometry['Y']))]
        subprocess.run(command + (['click', '1'] if click else []), env=env, check=True)

    def dock(name):
        expected = 'credential-' + name
        wait(lambda: state().get('ember') == expected and state().get('dock') == expected,
             'Orange indicator did not land on ' + expected + ': ' + str(state()))

    confirmation = request('bt', 'RequestConfirmation', GLib.Variant('(ou)', (device, 482916)))
    shown('bluetooth'); assert state()['code'] == '482916'
    assert state()['heading'] == 'Keychron K2' and state()['icon'] == 'bluetooth', state()
    capture('bluetooth')
    ipc('accept'); wait(lambda: confirmation.get('done'), 'Pairing response did not finish')
    assert 'error' not in confirmation, confirmation
    closed()
    print('PASS: Bluetooth confirmation uses the pill and returns the protocol response', flush=True)

    wifi = request('nm', 'GetSecrets', network('802-11-wireless-security', 'Home Wi-Fi', {'key-mgmt': GLib.Variant('s', 'wpa-psk')}))
    shown('network', 1)
    assert state()['heading'] == 'Connect to Home Wi-Fi' and state()['icon'] == 'wifi-lock' and not state()['body'], state()
    assert not state()['canAccept']
    capture('wifi-empty')
    pointer('input', click=True)
    subprocess.run(['/usr/bin/xdotool', 'type', '--clearmodifiers', '--delay', '8', 'fixture-password-4829'], env=env, check=True)
    assert state()['canAccept']
    dock('input-0')
    capture('wifi')
    frames = state()['emberFrames']
    pointer('visibility', click=True); dock('visibility-0')
    assert ipc('revealed', 0) is True
    pointer('visibility', click=True)
    assert ipc('revealed', 0) is False
    # Keyboard focus must win even when the pointer remains on the eye button.
    for key, target in [('Tab', 'cancel'), ('Tab', 'connect'), ('shift+Tab', 'cancel'),
                        ('shift+Tab', 'visibility-0'), ('shift+Tab', 'input-0')]:
        subprocess.run(['/usr/bin/xdotool', 'key', key], env=env, check=True)
        dock(target)
    for control, target in [('cancel', 'cancel'), ('connect', 'connect'),
                            ('visibility', 'visibility-0'), ('input', 'input-0')]:
        pointer(control); dock(target)
    assert state()['emberFrames'] > frames + 10
    capture('wifi')
    print('PASS: visibility icon toggles and orange indicator follows mouse and keyboard across all controls', flush=True)
    ipc('accept'); wait(lambda: wifi.get('done'), 'Wi-Fi response did not finish')
    assert 'error' not in wifi, wifi
    assert wifi['value'].unpack()[0]['802-11-wireless-security']['psk'] == 'fixture-password-4829'
    closed()
    print('PASS: masked Wi-Fi input returns the expected NetworkManager settings map', flush=True)

    vpn = request('nm', 'GetSecrets', network('vpn', 'Work VPN', {'service-type': GLib.Variant('s', 'org.example.VPN')}, ['password', 'otp']))
    shown('network', 2)
    assert state()['heading'] == 'Connect to Work VPN' and state()['icon'] == 'shield-lock' and not state()['body'], state()
    capture('vpn')
    ipc('fill', 0, 'fixture-vpn-password'); ipc('fill', 1, '123456'); ipc('accept')
    wait(lambda: vpn.get('done'), 'VPN response did not finish')
    assert 'error' not in vpn, vpn
    assert vpn['value'].unpack()[0]['vpn']['secrets']['otp'] == '123456'
    closed()
    print('PASS: VPN password/token fields return the nested VPN secret map', flush=True)

    cancelled = request('bt', 'RequestPinCode', GLib.Variant('(o)', (device,)))
    shown('bluetooth', 1); ipc('cancel')
    wait(lambda: cancelled.get('done'), 'Dismissed request did not return')
    assert 'error' in cancelled
    closed()

    cancelled = request('nm', 'GetSecrets', network('802-11-wireless-security', 'Cancelled Wi-Fi', {}))
    shown('network', 1)
    request('nm', 'CancelGetSecrets', GLib.Variant('(os)', ('/org/freedesktop/NetworkManager/Settings/99999', '802-11-wireless-security')))
    wait(lambda: cancelled.get('done'), 'Network cancellation did not return')
    assert 'error' in cancelled
    closed()
    print('PASS: Escape/panel dismissal and service cancellation clear inputs and finish pending calls', flush=True)

    other = Gio.DBusConnection.new_for_address_sync(os.environ['DBUS_SESSION_BUS_ADDRESS'],
                Gio.DBusConnectionFlags.AUTHENTICATION_CLIENT | Gio.DBusConnectionFlags.MESSAGE_BUS_CONNECTION, None, None)
    rejected = request('bt', 'RequestConfirmation', GLib.Variant('(ou)', (device, 111111)), other)
    wait(lambda: rejected.get('done'), 'Unauthorized caller did not return')
    assert 'error' in rejected and not state()['active']
    assert state()['opening'] > 1 and state()['closing'] > 1, state()
    displayed = request('bt', 'DisplayPasskey', GLib.Variant('(ouq)', (device, 123456, 0)))
    wait(lambda: displayed.get('done'), 'DisplayPasskey did not acknowledge')
    shown('bluetooth')
    updated = request('bt', 'DisplayPasskey', GLib.Variant('(ouq)', (device, 123456, 4)))
    wait(lambda: updated.get('done'), 'Passkey update did not acknowledge')
    bus.emit_signal(None, device, 'org.freedesktop.DBus.Properties', 'PropertiesChanged',
                    GLib.Variant('(sa{sv}as)', ('org.bluez.Device1', {'Paired': GLib.Variant('b', True)}, [])))
    closed()
    print('PASS: display-only passkeys close when pairing completes', flush=True)
    pending = request('bt', 'RequestConfirmation', GLib.Variant('(ou)', (device, 654321)))
    shown('bluetooth')
    backend.terminate(); backend.wait(timeout=5)
    closed()
    print('PASS: backend shutdown closes the pill without leaving a prompt', flush=True)
    for log in logs: log.flush()
    for path in work.glob('*.log'):
        assert 'fixture-password-4829' not in path.read_text() and 'fixture-vpn-password' not in path.read_text(), path
    print('PASS: caller authentication, real morph frames, and no secret values in logs', flush=True)
    print('PREVIEWS: ' + str(work), flush=True)
finally:
    if recorder:
        recorder.send_signal(2)
        try: recorder.wait(timeout=5)
        except subprocess.TimeoutExpired: recorder.kill(); recorder.wait()
    for child in (backend, shell, compositor):
        if child:
            child.terminate()
            try: child.wait(timeout=4)
            except subprocess.TimeoutExpired: child.kill(); child.wait()
    loop.quit()
    for log in logs: log.close()
