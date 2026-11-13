#!/usr/bin/env python3
"""Install the desktop's portal routing, custom dialogs, and sharing picker."""
import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import re
import shutil
import subprocess

SOURCE = Path(__file__).resolve().parent
CONFIG = Path(os.environ.get('XDG_CONFIG_HOME', Path.home() / '.config'))
DATA = Path(os.environ.get('XDG_DATA_HOME', Path.home() / '.local/share'))
STATE = Path(os.environ.get('XDG_STATE_HOME', Path.home() / '.local/state')) / 'dotfiles/xdg-desktop-portal'
HYPR = CONFIG / 'hypr'
SERVICE = 'dotfiles-portal.service'
BUS = 'org.freedesktop.impl.portal.desktop.dotfiles'
RULE = '''-- BEGIN dotfiles-portals
hl.window_rule({
    name = "desktop-portal-dialogs",
    match = { class = "org.quickshell", title = "^Desktop portal:.*$" },
    float = true,
    center = true,
    no_anim = true,
})
-- END dotfiles-portals'''


def run(*args):
    result = subprocess.run(args, text=True, capture_output=True, timeout=30)
    if result.returncode:
        raise RuntimeError(f"{' '.join(args)}: {result.stdout}{result.stderr}")
    return result.stdout


def managed_block(text, block, marker):
    start, end = f'BEGIN {marker}', f'END {marker}'
    pattern = rf'(?m)^[^\n]*{re.escape(start)}\n.*?^[^\n]*{re.escape(end)}[^\n]*'
    if start in text:
        if end not in text:
            raise RuntimeError(f'Incomplete managed block: {marker}')
        return re.sub(pattern, lambda match: block, text, flags=re.S)
    return text.rstrip() + '\n\n' + block + '\n'


def contents(path):
    return path.read_text() if path.exists() else ''


def payloads():
    result = {}
    for path in sorted((SOURCE.parent / 'hyprland/config/portals').iterdir()):
        if path.is_file() and (path.suffix in ('.qml', '.py') or path.name == 'share-picker'):
            result[HYPR / 'portals' / path.name] = (path.read_bytes(), 0o755 if path.name == 'share-picker' else 0o644)
    result[HYPR / 'portal.qml'] = ((SOURCE.parent / 'hyprland/config/portal.qml').read_bytes(), 0o644)
    result[CONFIG / 'xdg-desktop-portal/hyprland-portals.conf'] = ((SOURCE / 'hyprland-portals.conf').read_bytes(), 0o644)
    result[DATA / 'xdg-desktop-portal/portals/dotfiles.portal'] = ((SOURCE / 'dotfiles.portal').read_bytes(), 0o644)
    command = f'/usr/bin/python3 "{HYPR / "portals/backend.py"}"'
    unit = f'''[Unit]
Description=Desktop portal dialogs
PartOf=graphical-session.target
After=graphical-session.target

[Service]
Type=dbus
BusName={BUS}
ExecStart={command}
Restart=on-failure
Slice=session.slice
'''
    activation = f'''[D-BUS Service]
Name={BUS}
Exec={command}
SystemdService={SERVICE}
'''
    result[CONFIG / 'systemd/user' / SERVICE] = (unit.encode(), 0o644)
    result[DATA / 'dbus-1/services' / (BUS + '.service')] = (activation.encode(), 0o644)
    xdph = HYPR / 'xdph.conf'
    block = f'''# BEGIN dotfiles-share-picker
screencopy {{
    custom_picker_binary = {HYPR / 'portals/share-picker'}
}}
# END dotfiles-share-picker'''
    result[xdph] = (managed_block(contents(xdph), block, 'dotfiles-share-picker').encode(), 0o644)
    rules = HYPR / 'modules/rules.lua'
    if not rules.is_file():
        raise RuntimeError('Install the Hyprland dotfiles before the portal dialogs.')
    result[rules] = (managed_block(contents(rules), RULE, 'dotfiles-portals').encode(), 0o644)
    return result


def check_backend():
    run('systemctl', '--user', 'start', 'xdg-desktop-portal-gnome.service')
    for bus, interface in [('org.freedesktop.impl.portal.desktop.gnome', 'FileChooser'), (BUS, 'AppChooser'), (BUS, 'Access')]:
        run('busctl', '--user', 'introspect', bus, '/org/freedesktop/portal/desktop', 'org.freedesktop.impl.portal.' + interface)


def refresh():
    run('systemctl', '--user', 'daemon-reload')
    run('systemctl', '--user', 'restart', SERVICE)
    check_backend()
    run('systemctl', '--user', 'restart', 'xdg-desktop-portal-hyprland.service')
    run('systemctl', '--user', 'restart', 'xdg-desktop-portal.service')
    if os.environ.get('HYPRLAND_INSTANCE_SIGNATURE'):
        run('hyprctl', 'reload')
        errors = run('hyprctl', 'configerrors').strip()
        if errors:
            raise RuntimeError(errors)


def install():
    for binary in ('quickshell', 'nautilus', 'busctl'):
        if not shutil.which(binary):
            raise RuntimeError(f'Missing dependency: {binary}')
    if not (HYPR / 'shell/ShellTheme.qml').is_file():
        raise RuntimeError('The desktop shell theme must be installed first.')
    files = payloads()
    changed = {p: item for p, item in files.items() if not p.is_file() or p.read_bytes() != item[0] or p.stat().st_mode & 0o777 != item[1]}
    if not changed:
        check_backend()
        print('Portal dialogs and routing already match.')
        return
    tree = run('busctl', '--user', 'tree', '--list', 'org.freedesktop.impl.portal.desktop.hyprland')
    if '/org/freedesktop/portal/desktop/session/' in tree:
        raise RuntimeError('A portal session is active. Finish screen sharing or input capture before installing.')
    backup = STATE / datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S.%fZ')
    backup.mkdir(parents=True, mode=0o700)
    metadata = []
    for i, path in enumerate(changed):
        if path.is_symlink() or any(p.is_symlink() for p in path.parents if p != Path.home()):
            raise RuntimeError(f'Refusing linked target: {path}')
        saved = backup / str(i)
        present = path.exists()
        if present:
            shutil.copy2(path, saved)
        metadata.append({'target': str(path), 'saved': str(i), 'present': present})
    (backup / 'files.json').write_text(json.dumps(metadata, indent=2) + '\n')
    try:
        for path, (content, mode) in changed.items():
            path.parent.mkdir(parents=True, exist_ok=True)
            stage = path.with_name('.' + path.name + '.portal-install')
            stage.write_bytes(content)
            stage.chmod(mode)
            stage.replace(path)
        refresh()
    except Exception:
        for entry in metadata:
            path = Path(entry['target'])
            if entry['present']:
                shutil.copy2(backup / entry['saved'], path)
            else:
                path.unlink(missing_ok=True)
        run('systemctl', '--user', 'daemon-reload')
        subprocess.run(['systemctl', '--user', 'stop', SERVICE], capture_output=True, timeout=10)
        subprocess.run(['systemctl', '--user', 'restart', 'xdg-desktop-portal-hyprland.service'], capture_output=True, timeout=30)
        subprocess.run(['systemctl', '--user', 'restart', 'xdg-desktop-portal.service'], capture_output=True, timeout=30)
        if os.environ.get('HYPRLAND_INSTANCE_SIGNATURE'):
            subprocess.run(['hyprctl', 'reload'], capture_output=True, timeout=10)
        raise
    print(f'Installed Open With, permission dialogs, and sharing picker. Backup: {backup}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('install', 'check', 'dump'))
    args = parser.parse_args()
    STATE.mkdir(parents=True, exist_ok=True)
    import fcntl
    with (STATE / 'manage.lock').open('w') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        if args.action == 'install':
            install()
        elif args.action == 'check':
            changed = [str(p) for p, (content, mode) in payloads().items() if not p.is_file() or p.read_bytes() != content or p.stat().st_mode & 0o777 != mode]
            if changed:
                raise RuntimeError('Installed files differ: ' + ', '.join(changed))
            check_backend()
            run('systemctl', '--user', 'is-active', 'xdg-desktop-portal.service', SERVICE)
            print('Custom portals, file chooser, and sharing configuration verified.')
        else:
            shutil.copy2(CONFIG / 'xdg-desktop-portal/hyprland-portals.conf', SOURCE / 'hyprland-portals.conf')


if __name__ == '__main__':
    try:
        main()
    except (OSError, RuntimeError, subprocess.SubprocessError) as error:
        raise SystemExit(str(error))
