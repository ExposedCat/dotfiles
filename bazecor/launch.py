#!/usr/bin/env python3
"""Launch Bazecor on Wayland with its initial hidden-window deadlock corrected."""

import argparse
from datetime import datetime, timezone
import fcntl
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile


IMAGE = Path.home() / "AppImages/bazecor.appimage"
CACHE = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "dotfiles/bazecor"
STATE = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state")) / "dotfiles/bazecor"
HIDDEN = 'show:!1,backgroundColor:"#2e2c29"'
VISIBLE = 'show:!0,backgroundColor:"#2e2c29"'


def prepare(image=IMAGE, cache=CACHE):
    if not image.is_file() or not os.access(image, os.X_OK):
        raise RuntimeError(f"Bazecor AppImage is missing or not executable: {image}")
    with image.open("rb") as stream:
        digest = hashlib.file_digest(stream, "sha256").hexdigest()
    cache.mkdir(parents=True, exist_ok=True)
    destination = cache / ("wayland-v1-" + digest[:20])
    with (cache / "prepare.lock").open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        if not (destination / "ready").is_file():
            with tempfile.TemporaryDirectory(prefix=".prepare-", dir=cache) as temporary:
                staging = Path(temporary)
                with (staging / "extract.log").open("w") as log:
                    subprocess.run([str(image), "--appimage-extract"], cwd=staging,
                                   stdout=log, stderr=subprocess.STDOUT, check=True)
                root = staging / "squashfs-root"
                main = root / "usr/lib/bazecor/resources/app/.webpack/main/index.js"
                source = main.read_text()
                if source.count(HIDDEN) != 1:
                    raise RuntimeError("This Bazecor version needs its Wayland startup workaround reviewed.")
                # A hidden BrowserWindow can wait indefinitely for ready-to-show
                # on Wayland. Map the main window at creation so it can paint.
                main.write_text(source.replace(HIDDEN, VISIBLE))
                if not (root / "AppRun").is_file():
                    raise RuntimeError("The extracted Bazecor application is incomplete.")
                (root / "ready").write_text(digest + "\n")
                if destination.exists():
                    shutil.rmtree(destination)
                root.rename(destination)
    return destination


def install():
    prepare()
    applications = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share")) / "applications"
    desktop = applications / "bazecor.desktop"
    if not desktop.is_file():
        raise RuntimeError(f"Install the Bazecor desktop entry first: {desktop}")
    launcher = Path.home() / ".local/libexec/dotfiles-bazecor.py"
    command = f'Exec=/usr/bin/python3 "{launcher}" run %U'
    original = desktop.read_text()
    lines = original.splitlines()
    if sum(line.startswith("Exec=") for line in lines) != 1:
        raise RuntimeError("The Bazecor desktop entry needs its Exec line reviewed.")
    if command not in lines:
        STATE.mkdir(parents=True, exist_ok=True)
        stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S.%fZ")
        shutil.copy2(desktop, STATE / f"bazecor-{stamp}.desktop")
    launcher.parent.mkdir(parents=True, exist_ok=True)
    if Path(__file__).resolve() != launcher.resolve():
        shutil.copy2(__file__, launcher)
    launcher.chmod(0o755)
    desktop.write_text("\n".join(command if line.startswith("Exec=") else line for line in lines) + "\n")
    if shutil.which("update-desktop-database"):
        subprocess.run(["update-desktop-database", str(applications)], check=True)
    print(f"Installed Bazecor native Wayland launcher: {desktop}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("install", "prepare", "run"))
    parser.add_argument("args", nargs=argparse.REMAINDER)
    options = parser.parse_args()
    if options.action == "install":
        install()
        return
    if options.action == "run":
        STATE.mkdir(parents=True, exist_ok=True, mode=0o700)
        log = STATE / "startup.log"
        if log.exists() and log.stat().st_size > 2_000_000:
            log.replace(STATE / "startup.previous.log")
        descriptor = os.open(log, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
        os.dup2(descriptor, 1)
        os.dup2(descriptor, 2)
        os.close(descriptor)
        print(f"\nBazecor Wayland launch {datetime.now(timezone.utc).isoformat()}", flush=True)
    root = prepare()
    if options.action == "prepare":
        print(root)
        return
    env = os.environ.copy()
    env.update(APPIMAGE=str(IMAGE), APPDIR=str(root), DESKTOPINTEGRATION="1")
    os.execve(root / "AppRun", [str(root / "AppRun"), "--ozone-platform=wayland", *options.args], env)


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError, subprocess.SubprocessError) as error:
        print(f"Bazecor launch failed: {error}", file=sys.stderr)
        sys.exit(1)
