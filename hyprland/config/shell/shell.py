#!/usr/bin/env python3
"""One-shot session details and explicit desktop shell actions."""

import argparse
import json
import os
import subprocess
from pathlib import Path


POWER_COMMANDS = {
    "lock": ["/usr/bin/systemd-run", "--user", "--collect", "--quiet",
             "--unit=dotfiles-hyprland-lock", "--property=PartOf=graphical-session.target",
             "/usr/bin/hyprlock", "--no-fade-in"],
    "logout": ["/usr/bin/uwsm", "stop"],
    "suspend": ["/usr/bin/systemctl", "suspend"],
    "reboot": ["/usr/bin/systemctl", "reboot"],
    "poweroff": ["/usr/bin/systemctl", "poweroff"],
}


def session_info():
    """Read the initial keyboard once; Hyprland events handle later changes."""
    try:
        devices = json.loads(subprocess.check_output(["hyprctl", "devices", "-j"], text=True, timeout=2))
        keyboard = next((k for k in devices.get("keyboards", []) if k.get("main")), {})
        return dict(layout=keyboard.get("active_keymap", "English (US)"), keyboard=keyboard.get("name", ""))
    except (OSError, ValueError, subprocess.SubprocessError):
        return dict(layout="English (US)", keyboard="")


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
    actions.add_parser("session-info")
    actions.add_parser("ethernet")
    actions.add_parser("speed-test")
    actions.add_parser("stats-watch")
    actions.add_parser("brightness-list")
    brightness = actions.add_parser("brightness-set")
    brightness.add_argument("output")
    brightness.add_argument("level", type=float)
    actions.add_parser("power").add_argument("choice", choices=tuple(POWER_COMMANDS))
    args = parser.parse_args()
    if args.action == "session-info":
        print(json.dumps(session_info()))
    elif args.action == "stats-watch":
        from system_stats import watch as watch_stats
        watch_stats()
    elif args.action == "brightness-list":
        from brightness import listing
        print(json.dumps(listing()))
    elif args.action == "brightness-set":
        from brightness import set_level
        print(json.dumps(set_level(args.output, args.level)))
    elif args.action == "speed-test":
        from internet_speed import run_cli
        raise SystemExit(run_cli())
    elif args.action == "ethernet":
        print(json.dumps(ethernet_status()))
    else:
        subprocess.run(POWER_COMMANDS[args.choice], check=True)


if __name__ == "__main__":
    main()
