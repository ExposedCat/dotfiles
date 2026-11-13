"""Shared data and transport for the desktop's portal dialogs (no GTK UI)."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parent


def atomic_json(path, data):
    path = Path(path)
    temporary = path.with_suffix('.tmp')
    temporary.write_text(json.dumps(data, ensure_ascii=True))
    temporary.replace(path)


def label(text):
    # Portal button labels may contain GTK mnemonic underscores.
    return str(text).replace('__', '\0').replace('_', '').replace('\0', '_')


def app_metadata(identity):
    from gi.repository import Gio, GioUnix
    desktop_id = identity if identity.endswith('.desktop') else identity + '.desktop'
    try:
        app = GioUnix.DesktopAppInfo.new(desktop_id) if identity else None
    except TypeError:  # PyGObject raises when a desktop entry no longer exists.
        app = None
    if app is None:
        return {'id': identity, 'name': identity or 'Application', 'icon': '', 'description': ''}
    icon = app.get_icon()
    icon_name = ''
    if isinstance(icon, Gio.ThemedIcon):
        icon_name = next(iter(icon.get_names()), '')
    elif isinstance(icon, Gio.FileIcon):
        icon_name = icon.get_file().get_path() or ''
    return {'id': desktop_id.removesuffix('.desktop'), 'name': app.get_display_name(),
            'icon': icon_name, 'description': app.get_description() or ''}


def app_choices(identities):
    # The frontend supplies eligible apps. Preserve those IDs in the response.
    result = []
    for identity in dict.fromkeys(identities):
        row = app_metadata(identity)
        row['id'] = identity
        result.append(row)
    return result


class Dialog:
    def __init__(self, data):
        runtime = os.environ.get('XDG_RUNTIME_DIR')
        self.temporary = tempfile.TemporaryDirectory(prefix='dotfiles-portal-', dir=runtime)
        self.directory = Path(self.temporary.name)
        self.update(data)
        env = os.environ.copy()
        env['DOTFILES_PORTAL_REQUEST'] = str(self.directory)
        if data.get('activationToken'):
            env['XDG_ACTIVATION_TOKEN'] = data['activationToken']
        self.process = subprocess.Popen(['/usr/bin/quickshell', '--no-color', '--path', str(ROOT.parent / 'portal.qml')],
                                        env=env, stdout=sys.stderr)

    def update(self, data):
        atomic_json(self.directory / 'request.json', data)

    def result(self):
        try:
            result = json.loads((self.directory / 'response.json').read_text())
            return result if isinstance(result, dict) else {'response': 2}
        except (OSError, ValueError):
            return {'response': 2}

    def close(self):
        if self.process.poll() is None:
            self.process.terminate()
            try:
                self.process.wait(timeout=2)
            except subprocess.TimeoutExpired:
                self.process.kill()
                self.process.wait()
        self.temporary.cleanup()


class Fields:
    """Parse XDPH's byte-length-prefixed names without splitting their contents."""
    def __init__(self, value):
        self.data = value.encode('utf-8')

    def until(self, separator):
        field, found, rest = self.data.partition(separator.encode())
        if not found:
            raise ValueError('Truncated source list')
        self.data = rest
        return field.decode('utf-8')

    def name(self):
        size = int(self.until(':'))
        if size < 0 or size > len(self.data):
            raise ValueError('Invalid name length')
        name, self.data = self.data[:size], self.data[size:]
        return name.decode('utf-8')

    def consume(self, marker):
        marker = marker.encode()
        if not self.data.startswith(marker):
            raise ValueError('Invalid source separator')
        self.data = self.data[len(marker):]


def share_sources(env):
    outputs, windows, workspaces = [], [], []
    fields = Fields(env.get('XDPH_OUTPUT_SHARING_LIST', ''))
    while fields.data:
        name = fields.name()
        fields.consume(':')
        x, y, width = (int(fields.until(':')) for _ in range(3))
        height = int(fields.until(';'))
        if width > 0 and height > 0 and not any(c in name for c in '\r\n'):
            outputs.append({'id': 'screen:' + name, 'name': name, 'subtitle': f'{width} × {height}',
                            'output': name, 'x': x, 'y': y, 'width': width, 'height': height, 'kind': 'screen'})
    fields = Fields(env.get('XDPH_WINDOW_SHARING_LIST', ''))
    while fields.data:
        identity = fields.until('[HC>]')
        app = fields.until('[HT>]')
        title = fields.until('[HE>]')
        address = fields.until('[HA>]')
        if identity.isdecimal() and 0 < int(identity) <= 0xffffffff:
            windows.append({'id': 'window:' + identity, 'name': title or app, 'subtitle': app,
                            'appId': app, 'address': address, 'kind': 'window'})
    version3 = env.get('XDPH_WORKSPACE_SHARING_LIST_V3')
    fields = Fields(version3 if version3 is not None else env.get('XDPH_WORKSPACE_SHARING_LIST_V2', ''))
    while fields.data:
        if version3 is not None:
            identity = fields.until('[HN>]')
            name = fields.name()
            fields.consume('[HM>]')
            count = int(fields.until(':'))
            if not 0 <= count <= 128:
                raise ValueError('Invalid output count')
            monitors = [fields.name() for _ in range(count)]
            fields.consume('[HE>]')
        else:
            name = fields.name()
            fields.consume(':')
            identity = fields.until(';')
            monitors = []
        if identity.isdecimal() and 0 < int(identity) <= 0xffffffffffffffff:
            workspaces.append({'id': 'workspace-id:' + identity, 'name': 'Workspace ' + name,
                               'workspaceName': name, 'outputs': monitors,
                               'subtitle': ', '.join(monitors) or 'All windows in this workspace', 'kind': 'workspace'})
    return outputs, windows, workspaces


def workspace_previews(sources, clients=None, monitors=None):
    """Add window layouts to workspace cards; sharing still uses XDPH's IDs."""
    if clients is None or monitors is None:
        if not os.environ.get('HYPRLAND_INSTANCE_SIGNATURE'):
            return sources
        try:
            def query(kind):
                result = subprocess.run(['hyprctl', '-j', kind], capture_output=True, text=True, timeout=2, check=True)
                return json.loads(result.stdout)
            clients, monitors = query('clients'), query('monitors')
        except (OSError, ValueError, subprocess.SubprocessError):
            return sources
    for workspace in sources[2]:
        windows = [c for c in clients if c.get('mapped', True) and not c.get('hidden', False)
                   and c.get('workspace', {}).get('name') == workspace['workspaceName']]
        displays = [m for m in monitors if m.get('name') in workspace['outputs']]
        if not displays:
            displays = [m for m in monitors if m.get('id') in {c.get('monitor') for c in windows}]
        workspace['tiles'] = []
        if not displays:
            continue
        bounds = []
        for display in displays:
            scale = max(0.01, display.get('scale', 1))
            width, height = display['width'] / scale, display['height'] / scale
            if display.get('transform', 0) % 2:
                width, height = height, width
            bounds.append((display['x'], display['y'], display['x'] + width, display['y'] + height))
        left, top = min(b[0] for b in bounds), min(b[1] for b in bounds)
        width, height = max(b[2] for b in bounds) - left, max(b[3] for b in bounds) - top
        if width <= 0 or height <= 0:
            continue
        workspace['aspect'] = width / height
        for client in windows:
            x, y = client.get('at', [left, top])
            w, h = client.get('size', [0, 0])
            x1, y1 = max(0, (x - left) / width), max(0, (y - top) / height)
            x2, y2 = min(1, (x + w - left) / width), min(1, (y + h - top) / height)
            if x2 > x1 and y2 > y1:
                workspace['tiles'].append({'x': x1, 'y': y1, 'width': x2 - x1, 'height': y2 - y1,
                    'kind': 'window', 'appId': client.get('class', ''), 'name': client.get('title', '')})
    return sources


def share_result(result, sources):
    if result.get('response') != 0:
        return ''
    identity = result.get('choice')
    allowed = {row['id']: row for group in sources for row in group}
    if not isinstance(identity, str) or identity not in allowed:
        raise ValueError('Unrecognized sharing source')
    region = result.get('region')
    if region is not None:
        source = allowed[identity]
        if source['kind'] != 'screen' or len(region) != 4 or any(type(n) is not int for n in region):
            raise ValueError('Invalid sharing region')
        x, y, width, height = region
        if min(x, y) < 0 or min(width, height) < 1 or x + width > source['width'] or y + height > source['height']:
            raise ValueError('Sharing region outside monitor')
        if '@' in source['output']:
            raise ValueError('Unsupported monitor name for region sharing')
        identity = f"region:{source['output']}@{x},{y},{width},{height}"
    flags = 'r' if result.get('remember') is True else ''
    return f'[SELECTION]{flags}/{identity}'
