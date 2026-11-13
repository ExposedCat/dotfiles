#!/usr/bin/env python3
"""Session status events and explicit power-menu actions for the desktop shell."""

import argparse
import json
import os
import subprocess
from pathlib import Path


RECORD_UNIT = "dotfiles-hyprland-record.service"
POWER_COMMANDS = {
    "lock": ["/usr/bin/systemd-run", "--user", "--collect", "--quiet",
             "--unit=dotfiles-hyprland-lock", "--property=PartOf=graphical-session.target",
             "/usr/bin/hyprlock", "--no-fade-in"],
    "logout": ["/usr/bin/uwsm", "stop"],
    "suspend": ["/usr/bin/systemctl", "suspend"],
    "reboot": ["/usr/bin/systemctl", "reboot"],
    "poweroff": ["/usr/bin/systemctl", "poweroff"],
}


def watch():
    from gi.repository import Gio, GLib
    bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
    service = "org.freedesktop.systemd1"
    manager = "/org/freedesktop/systemd1"
    unit_path = manager + "/unit/dotfiles_2dhyprland_2drecord_2eservice"

    def send(**data):
        print(json.dumps(data), flush=True)

    def update(*unused):
        try:
            state = bus.call_sync(service, unit_path, "org.freedesktop.DBus.Properties", "Get",
                                  GLib.Variant("(ss)", ("org.freedesktop.systemd1.Unit", "ActiveState")),
                                  None, Gio.DBusCallFlags.NONE, 1500, None).unpack()[0]
            send(recording=state in ("active", "activating", "deactivating"))
        except GLib.Error:
            send(recording=False)

    try:
        devices = json.loads(subprocess.check_output(["hyprctl", "devices", "-j"], text=True))
        keyboard = next((k for k in devices.get("keyboards", []) if k.get("main")), {})
        send(layout=keyboard.get("active_keymap", "English (US)"), keyboard=keyboard.get("name", ""),
             username=os.environ.get("USER", ""), uid=os.getuid())
    except (OSError, ValueError, subprocess.SubprocessError):
        pass
    bus.signal_subscribe(service, "org.freedesktop.DBus.Properties", "PropertiesChanged", unit_path,
                         "org.freedesktop.systemd1.Unit", Gio.DBusSignalFlags.NONE, update)
    for signal in ("UnitNew", "UnitRemoved"):
        bus.signal_subscribe(service, service + ".Manager", signal, manager, RECORD_UNIT,
                             Gio.DBusSignalFlags.NONE, update)
    bus.call_sync(service, manager, service + ".Manager", "Subscribe", None, None,
                  Gio.DBusCallFlags.NONE, 1500, None)
    update()
    GLib.MainLoop().run()


def ethernet_status():
    """Read NetworkManager state and the negotiated Ethernet link speed."""
    try:
        result = subprocess.run(
            ["/usr/bin/nmcli", "-t", "--escape", "no", "-f", "DEVICE,TYPE,STATE", "device", "status"],
            check=True, capture_output=True, text=True, timeout=3,
            env={**os.environ, "LC_ALL": "C"},
        )
        devices = []
        for line in result.stdout.splitlines():
            name, kind, state = line.split(":", 2)
            if kind != "ethernet":
                continue
            try:
                speed = max(0, int((Path("/sys/class/net") / name / "speed").read_text()))
            except (OSError, ValueError):
                speed = 0
            is_connected = state.startswith("connected")
            label = "Connected" if is_connected else {
                "disconnected": "Disconnected", "unavailable": "Cable unplugged",
                "unmanaged": "Unmanaged",
            }.get(state, state.capitalize())
            devices.append({"name": name, "state": label, "speed": speed if is_connected else 0,
                            "connected": is_connected})
        return {"devices": devices, "unavailable": False}
    except (OSError, ValueError, subprocess.SubprocessError):
        return {"devices": [], "unavailable": True}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    actions = parser.add_subparsers(dest="action", required=True)
    actions.add_parser("watch")
    actions.add_parser("ethernet")
    actions.add_parser("speed-test")
    actions.add_parser("power").add_argument("choice", choices=tuple(POWER_COMMANDS))
    args = parser.parse_args()
    if args.action == "watch":
        watch()
    elif args.action == "speed-test":
        from internet_speed import run_cli
        raise SystemExit(run_cli())
    elif args.action == "ethernet":
        print(json.dumps(ethernet_status()))
    else:
        subprocess.run(POWER_COMMANDS[args.choice], check=True)


if __name__ == "__main__":
    main()
