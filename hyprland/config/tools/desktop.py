#!/usr/bin/env python3
"""Small desktop actions built on the installed Wayland tools and D-Bus APIs."""

import argparse
import fcntl
import json
import os
from pathlib import Path
import subprocess
import sys
import time


ROOT = Path(__file__).resolve().parent.parent
STATE = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state")) / "dotfiles/hyprland"
PREFIX = "dotfiles-hyprland-"
BACKGROUND = ("clipboard-text", "clipboard-image", "shell", "capture", "idle")


def run(*args, **kwargs):
    return subprocess.run(args, check=True, **kwargs)


def active(name):
    return subprocess.run(["systemctl", "--user", "is-active", "--quiet", PREFIX + name],
                          stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0


def service(name, command, restart=True):
    if active(name):
        return
    args = ["systemd-run", "--user", "--quiet", "--collect", "--unit=" + PREFIX + name,
            "--property=PartOf=graphical-session.target", "--property=After=graphical-session.target",
            "--property=Requisite=graphical-session.target", "--property=UMask=0077"]
    # UWSM keeps login-specific variables out of the global activation environment.
    # Pass them and the live display explicitly to this session's services.
    for key in ("WAYLAND_DISPLAY", "HYPRLAND_INSTANCE_SIGNATURE", "XDG_CURRENT_DESKTOP",
                "XDG_SESSION_ID", "XDG_SEAT", "XDG_VTNR", "XDG_CACHE_HOME"):
        if key in os.environ:
            args.append("--setenv=" + key + "=" + os.environ[key])
    args += ["--setenv=XDG_CONFIG_HOME=" + os.environ.get("XDG_CONFIG_HOME", str(ROOT.parent)),
             "--setenv=XDG_STATE_HOME=" + os.environ.get("XDG_STATE_HOME", str(Path.home() / ".local/state"))]
    if restart:
        args += ["--property=Restart=on-failure", "--property=RestartSec=2"]
    run(*args, "--", *command)


def session_start(refresh=False):
    if "Hyprland" not in os.environ.get("XDG_CURRENT_DESKTOP", "").split(":"):
        raise RuntimeError("Desktop services must be started inside the Hyprland session.")
    runtime = Path(os.environ["XDG_RUNTIME_DIR"])
    with (runtime / "dotfiles-hyprland-services.lock").open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        for kind in ("text", "image"):
            service("clipboard-" + kind,
                    ["/usr/bin/wl-paste", "--type", kind, "--watch", "/usr/bin/cliphist", "store"])
        # Automatic locking is deliberately disabled, including old verified installs.
        if active("idle"):
            run("systemctl", "--user", "stop", PREFIX + "idle")
        STATE.mkdir(parents=True, exist_ok=True, mode=0o700)
        if (ROOT / "shell/shell.qml").is_file():
            if refresh and active("shell"):
                run("systemctl", "--user", "restart", PREFIX + "shell")
            else:
                service("shell", ["/usr/bin/quickshell", "--no-duplicate", "--path", str(ROOT / "shell/shell.qml")])
            wait_shell()
        elif active("shell"):
            run("systemctl", "--user", "stop", PREFIX + "shell")
        if (ROOT / "tools/capture-daemon.qml").is_file():
            if refresh and active("capture"):
                run("systemctl", "--user", "restart", PREFIX + "capture")
            else:
                service("capture", ["/usr/bin/quickshell", "--no-duplicate", "--path", str(ROOT / "tools/capture-daemon.qml")])
            wait_shell("tools/capture-daemon.qml", "capture", "ready")
        elif active("capture"):
            run("systemctl", "--user", "stop", PREFIX + "capture")


def wait_shell(config="shell/shell.qml", target="shell", field="polkit"):
    # A systemd start job can succeed before QML finishes loading. Make a failed
    # shell load fail the installer too, so its normal rollback can restore it.
    command = ["/usr/bin/quickshell", "ipc", "--path", str(ROOT / config), "call", target, "status"]
    for attempt in range(30):
        try:
            result = subprocess.run(command, capture_output=True, text=True, timeout=1)
            status = json.loads(result.stdout)
            if result.returncode == 0 and isinstance(status, dict) and field in status and (field != "ready" or status[field] is True):
                return
        except (ValueError, subprocess.TimeoutExpired):
            pass
        time.sleep(0.1)
    raise RuntimeError("Desktop shell did not become ready; inspect journalctl --user -u dotfiles-hyprland-shell.")


def clipboard_list():
    result = subprocess.run(["cliphist", "list"], capture_output=True, text=True)
    # A new database does not exist until the first selection is stored.
    if result.returncode and "no such file" not in result.stderr.lower():
        raise RuntimeError(result.stderr.strip() or "Cannot read clipboard history.")
    entries = []
    for line in result.stdout.splitlines():
        identity, separator, preview = line.partition("\t")
        if separator and identity.isdecimal():
            entries.append({"id": identity, "preview": preview})
    print(json.dumps(entries))


def clipboard_copy(identity):
    if not identity.isdecimal():
        raise RuntimeError("Clipboard entry IDs must be numbers.")
    # Preserve bytes exactly, including images, tabs, and trailing newlines.
    content = run("cliphist", "decode", input=identity.encode(), capture_output=True).stdout
    run("wl-copy", input=content)


def applications():
    from gi.repository import Gio, GioUnix
    entries = []
    for app in Gio.AppInfo.get_all():
        if not app.should_show() or not isinstance(app, GioUnix.DesktopAppInfo):
            continue
        icon = app.get_icon()
        entries.append({"id": app.get_id(), "name": app.get_display_name(),
                        "description": app.get_description() or "",
                        "keywords": list(app.get_keywords() or []),
                        "icon": icon.to_string() if icon else ""})
    print(json.dumps(sorted(entries, key=lambda app: app["name"].casefold())))


def launch_app(identity):
    from gi.repository import GioUnix
    app = GioUnix.DesktopAppInfo.new(identity)
    if app is None or not app.should_show():
        raise RuntimeError("This application is no longer available.")
    # Let UWSM process the desktop entry, including Terminal and field codes.
    run("uwsm", "app", "--", app.get_filename())


def media(method):
    from gi.repository import Gio, GLib
    bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)

    def call(name, interface, action, parameters=None):
        return bus.call_sync(name, "/org/mpris/MediaPlayer2", interface, action,
                             parameters, None, Gio.DBusCallFlags.NONE, 1500, None)

    names = bus.call_sync("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus",
                          "ListNames", None, None, Gio.DBusCallFlags.NONE, 1500, None).unpack()[0]
    players = []
    for name in sorted(n for n in names if n.startswith("org.mpris.MediaPlayer2.")):
        try:
            status = call(name, "org.freedesktop.DBus.Properties", "Get",
                          GLib.Variant("(ss)", ("org.mpris.MediaPlayer2.Player", "PlaybackStatus"))).unpack()[0]
            players.append((0 if status == "Playing" else 1, name))
        except GLib.Error:
            continue
    for _, name in sorted(players):
        try:
            call(name, "org.mpris.MediaPlayer2.Player", method)
            return
        except GLib.Error:
            continue


def brightness(direction):
    monitors = json.loads(run("hyprctl", "monitors", "-j", capture_output=True, text=True).stdout)
    monitor = next(m for m in monitors if m["focused"])
    serial = monitor["serial"]
    if not serial:
        raise RuntimeError("Focused monitor has no serial for DDC selection.")
    # Do not queue up slow DDC writes when a mouse gesture repeats rapidly.
    with (Path(os.environ["XDG_RUNTIME_DIR"]) / "dotfiles-monitor-brightness.lock").open("w") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return
        run("ddcutil", "--sn", serial, "--noverify", "setvcp", "10",
            "+" if direction == "up" else "-", "5", timeout=5)
        result = run("ddcutil", "--sn", serial, "--terse", "getvcp", "10",
                     capture_output=True, text=True, timeout=5)
        # Continuous VCP terse output: VCP 10 C <current> <maximum>.
        values = next((line.split()[3:] for line in result.stdout.splitlines()
                       if line.split()[:3] == ["VCP", "10", "C"]), [])
        if len(values) != 2 or not all(value.isdecimal() for value in values):
            raise RuntimeError("Cannot read the monitor's brightness level.")
        current, maximum = map(int, values)
        if maximum <= 0 or not 0 <= current <= maximum:
            raise RuntimeError("Monitor returned an invalid brightness level.")
        # Brightness still works if the shell is absent or restarting.
        try:
            run("quickshell", "ipc", "--path", str(ROOT / "shell/shell.qml"),
                "call", "shell", "brightness", monitor["name"], str(current), str(maximum),
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=2)
        except (OSError, subprocess.SubprocessError):
            pass


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    actions = parser.add_subparsers(dest="action", required=True)
    for name in ("clipboard", "clipboard-list", "launcher", "apps-list", "record", "lock", "session-stop"):
        actions.add_parser(name)
    actions.add_parser("shell").add_argument("panel", choices=("notifications", "power", "connections", "ethernet", "bluetooth"))
    actions.add_parser("clipboard-copy").add_argument("id")
    actions.add_parser("screenshot").add_argument("mode", choices=("region", "window"))
    actions.add_parser("app-launch").add_argument("id")
    actions.add_parser("media").add_argument("method", choices=("PlayPause", "Next", "Previous"))
    actions.add_parser("brightness").add_argument("direction", choices=("up", "down"))
    actions.add_parser("session-start").add_argument("--refresh", action="store_true")
    args = parser.parse_args()
    os.umask(0o077)
    if args.action == "clipboard":
        os.execvp("quickshell", ["quickshell", "--no-duplicate", "--path", str(ROOT / "tools/clipboard.qml")])
    elif args.action == "clipboard-list":
        clipboard_list()
    elif args.action == "clipboard-copy":
        clipboard_copy(args.id)
    elif args.action == "launcher":
        os.execvp("quickshell", ["quickshell", "--no-duplicate", "--path", str(ROOT / "tools/launcher.qml")])
    elif args.action == "apps-list":
        applications()
    elif args.action == "app-launch":
        launch_app(args.id)
    elif args.action == "screenshot":
        os.execv(sys.executable, [sys.executable, str(ROOT / "tools/capture.py"), "select", args.mode])
    elif args.action == "record":
        os.execv(sys.executable, [sys.executable, str(ROOT / "tools/capture.py"), "select", "record"])
    elif args.action == "media":
        media(args.method)
    elif args.action == "brightness":
        brightness(args.direction)
    elif args.action == "lock":
        service("lock", ["/usr/bin/hyprlock", "--no-fade-in"], restart=False)
    elif args.action == "shell":
        run("quickshell", "ipc", "--path", str(ROOT / "shell/shell.qml"), "call", "shell", "toggle", args.panel)
    elif args.action == "session-start":
        session_start(args.refresh)
    elif args.action == "session-stop":
        subprocess.run(["systemctl", "--user", "stop", *[PREFIX + name + ".service" for name in BACKGROUND]],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError, subprocess.SubprocessError) as error:
        print(str(error), file=sys.stderr)
        raise SystemExit(1)
