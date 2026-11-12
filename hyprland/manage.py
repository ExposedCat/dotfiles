#!/usr/bin/env python3
"""Install and restore the Hyprland configuration without restarting the session."""

import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile


SOURCE = Path(__file__).resolve().parent / "config"
TARGET = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "hypr"
BACKUPS = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state")) / "dotfiles/hyprland/backups"


def run(*args, env=None):
    result = subprocess.run(args, env=env, text=True, capture_output=True, timeout=30)
    if result.returncode:
        raise RuntimeError(f"{' '.join(args)} failed:\n{result.stdout}{result.stderr}")
    return result.stdout


def verify(directory):
    # --verify-config parses only; it does not create a compositor or windows.
    # Keep even its diagnostic sockets and logs away from the working session.
    with tempfile.TemporaryDirectory(prefix="hyprland-verify-") as runtime:
        env = os.environ.copy()
        for name in ("DISPLAY", "WAYLAND_DISPLAY", "WAYLAND_SOCKET",
                     "HYPRLAND_INSTANCE_SIGNATURE", "DBUS_SESSION_BUS_ADDRESS"):
            env.pop(name, None)
        env["XDG_RUNTIME_DIR"] = runtime
        output = run("Hyprland", "--verify-config", "-c", str(directory / "hyprland.lua"), env=env)
        # Check the result text as well as the exit status.
        if "config ok" not in output:
            raise RuntimeError(f"Configuration validation failed:\n{output}")


def reload_session():
    if not os.environ.get("HYPRLAND_INSTANCE_SIGNATURE"):
        return
    run("hyprctl", "reload")
    errors = run("hyprctl", "configerrors").strip()
    if errors:
        raise RuntimeError(f"Live configuration errors:\n{errors}")


def snapshot(kind):
    BACKUPS.mkdir(parents=True, exist_ok=True, mode=0o700)
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S.%fZ")
    backup = BACKUPS / stamp
    backup.mkdir(mode=0o700)
    if TARGET.exists():
        shutil.copytree(TARGET, backup / "hypr", symlinks=True)
    (backup / "metadata.json").write_text(json.dumps({"kind": kind, "present": TARGET.exists()}) + "\n")
    print(f"Backup: {backup}", flush=True)
    return backup


def apply(staged):
    # Both paths are siblings on the same filesystem. Keep the original until
    # installation and the live reload succeed, then remove only that old copy.
    previous = Path(tempfile.mkdtemp(prefix=".hypr-previous-", dir=TARGET.parent))
    previous.rmdir()
    had_target = TARGET.exists()
    installed = False
    try:
        if had_target:
            TARGET.rename(previous)
        if staged is not None:
            staged.rename(TARGET)
        installed = True
        reload_session()
    except Exception:
        if installed and TARGET.exists():
            shutil.rmtree(TARGET)
        if previous.exists():
            previous.rename(TARGET)
        if installed:
            try:
                reload_session()
            except Exception as error:
                print(f"Original files restored; reload needs attention: {error}")
        raise
    else:
        if previous.exists():
            shutil.rmtree(previous)


def differences():
    return [str(path.relative_to(SOURCE)) for path in sorted(SOURCE.rglob("*.lua"))
            if not (TARGET / path.relative_to(SOURCE)).is_file()
            or path.read_bytes() != (TARGET / path.relative_to(SOURCE)).read_bytes()]


def install():
    verify(SOURCE)
    if TARGET.exists() and not differences():
        print("Hyprland configuration already matches the repository.")
        return
    TARGET.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".hypr-install-", dir=TARGET.parent) as temporary:
        staged = Path(temporary) / "hypr"
        if TARGET.exists():
            shutil.copytree(TARGET, staged, symlinks=True)
        else:
            staged.mkdir()
        for source in sorted(SOURCE.rglob("*.lua")):
            destination = staged / source.relative_to(SOURCE)
            # Refuse linked parents so an overlay cannot write outside staging.
            if any(parent.is_symlink() for parent in destination.parents if parent != staged.parent):
                raise RuntimeError(f"Linked configuration directory: {destination.parent}")
            destination.parent.mkdir(parents=True, exist_ok=True)
            if destination.is_symlink():
                destination.unlink()
            shutil.copy2(source, destination)
        verify(staged)
        snapshot("install")
        apply(staged)
    print("Hyprland configuration installed and validated.")


def rollback(backup_id):
    candidates = []
    if BACKUPS.exists():
        for path in sorted(BACKUPS.iterdir()):
            metadata = path / "metadata.json"
            if metadata.is_file() and json.loads(metadata.read_text())["kind"] == "install":
                candidates.append(path)
    if backup_id:
        backup = BACKUPS / backup_id
        if backup.parent != BACKUPS or not (backup / "metadata.json").is_file():
            raise RuntimeError("Choose a backup ID printed by the backups command.")
    elif candidates:
        backup = candidates[-1]
    else:
        raise RuntimeError("No pre-install backup is available.")
    present = json.loads((backup / "metadata.json").read_text())["present"]
    if not present and os.environ.get("HYPRLAND_INSTANCE_SIGNATURE"):
        raise RuntimeError("This backup predates any config; restore it outside the running session.")
    TARGET.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".hypr-restore-", dir=TARGET.parent) as temporary:
        staged = Path(temporary) / "hypr" if present else None
        if present:
            shutil.copytree(backup / "hypr", staged, symlinks=True)
            verify(staged)
        snapshot("rollback")
        apply(staged)
    print(f"Restored backup: {backup.name}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("install", "check", "rollback", "backups"))
    parser.add_argument("backup_id", nargs="?")
    args = parser.parse_args()
    if args.backup_id and args.action != "rollback":
        parser.error("Only rollback accepts a backup ID.")
    if TARGET.is_symlink():
        raise RuntimeError(f"{TARGET} is a symlink; use a regular configuration directory.")
    # Serialize installs, checks, and restores from this helper.
    import fcntl
    BACKUPS.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    with (BACKUPS.parent / "manage.lock").open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        if args.action == "install":
            install()
        elif args.action == "rollback":
            rollback(args.backup_id)
        elif args.action == "backups":
            for path in sorted(BACKUPS.glob("*/metadata.json")):
                print(path.parent.name, json.loads(path.read_text())["kind"])
        else:
            verify(SOURCE)
            changed = differences()
            if changed:
                raise RuntimeError("Installed files differ: " + ", ".join(changed))
            verify(TARGET)
            if os.environ.get("HYPRLAND_INSTANCE_SIGNATURE"):
                errors = run("hyprctl", "configerrors").strip()
                if errors:
                    raise RuntimeError(errors)
            print("Repository and installed configuration match; validation passed.")


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError, subprocess.SubprocessError) as error:
        raise SystemExit(str(error))
