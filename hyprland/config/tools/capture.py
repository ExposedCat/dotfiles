#!/usr/bin/env python3
"""Frozen selection/annotation UI, with grim images and wl-screenrec recordings."""

import argparse
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime
import fcntl
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time


HERE = Path(__file__).resolve().parent
RECORD_UNIT = "dotfiles-hyprland-record.service"
CAPTURE_UNIT = "dotfiles-hyprland-capture.service"


def run(*args, **kwargs):
    return subprocess.run(args, check=True, **kwargs)


def recording():
    return subprocess.run(["systemctl", "--user", "is-active", "--quiet", RECORD_UNIT],
                          stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0


def output_path(kind):
    result = subprocess.run(["xdg-user-dir", "PICTURES" if kind == "image" else "VIDEOS"],
                            capture_output=True, text=True)
    base = Path(result.stdout.strip()) if result.returncode == 0 and result.stdout.strip() else Path.home() / ("Pictures" if kind == "image" else "Videos")
    directory = base / ("Screenshots" if kind == "image" else "Recordings")
    directory.mkdir(parents=True, exist_ok=True)
    return directory / (datetime.now().strftime("capture-%Y%m%d-%H%M%S-%f") + (".png" if kind == "image" else ".mp4"))


def window_selection(window, outputs):
    if not window or "at" not in window or "size" not in window:
        raise RuntimeError("There is no active window to capture.")
    x, y = window["at"]
    width, height = window["size"]
    def intersection(output):
        left, top = max(x, output["x"]), max(y, output["y"])
        right = min(x + width, output["x"] + output["width"])
        bottom = min(y + height, output["y"] + output["height"])
        return max(0, right - left) * max(0, bottom - top)
    monitor = max(outputs, key=intersection)
    left, top = max(x, monitor["x"]), max(y, monitor["y"])
    right = min(x + width, monitor["x"] + monitor["width"])
    bottom = min(y + height, monitor["y"] + monitor["height"])
    if right <= left or bottom <= top:
        raise RuntimeError("The active window is outside the visible displays.")
    return {"monitor": monitor["name"], "x": left - monitor["x"], "y": top - monitor["y"],
            "width": right - left, "height": bottom - top}


def capture_outputs(monitors, directory):
    outputs, jobs = [], []
    # Capture both cursor variants in the same frame batch. Raw pixmaps avoid
    # PNG compression on the shortcut's latency-sensitive startup path.
    with ThreadPoolExecutor(max_workers=4) as pool:
        for i, monitor in enumerate(monitors):
            if monitor.get("disabled"):
                continue
            scale = monitor["scale"]
            width, height = monitor["width"], monitor["height"]
            if monitor.get("transform", 0) % 2:
                width, height = height, width
            plain, cursor = directory / f"screen-{i}.ppm", directory / f"screen-{i}-cursor.ppm"
            jobs.append(pool.submit(run, "grim", "-t", "ppm", "-o", monitor["name"], str(plain)))
            jobs.append(pool.submit(run, "grim", "-t", "ppm", "-c", "-o", monitor["name"], str(cursor)))
            outputs.append({"name": monitor["name"], "x": monitor["x"], "y": monitor["y"],
                            "width": width / scale, "height": height / scale,
                            "scale": scale, "focused": monitor["focused"],
                            "plain": plain.as_uri(), "cursor": cursor.as_uri()})
        for job in jobs:
            job.result()
    return outputs


def select(mode):
    if mode == "record" and recording():
        run("systemctl", "--user", "stop", RECORD_UNIT)
        return
    runtime = Path(os.environ["XDG_RUNTIME_DIR"])
    with (runtime / "dotfiles-capture.lock").open("w") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return
        monitors = json.loads(run("hyprctl", "monitors", "-j", capture_output=True, text=True).stdout)
        window = json.loads(run("hyprctl", "activewindow", "-j", capture_output=True, text=True).stdout) if mode == "window" else None
        with tempfile.TemporaryDirectory(prefix="dotfiles-capture-", dir=runtime) as temporary:
            directory = Path(temporary)
            outputs = capture_outputs(monitors, directory)
            if not outputs:
                raise RuntimeError("No active displays are available.")
            data = {"mode": mode, "outputs": outputs, "render": str(directory / "render.png"),
                    "selection": window_selection(window, outputs) if mode == "window" else None}
            (directory / "session.json").write_text(json.dumps(data))
            if open_warm_capture(directory):
                return
            env = os.environ.copy()
            env["DOTFILES_CAPTURE_SESSION"] = str(directory)
            run("quickshell", "--path", str(HERE / "capture.qml"), env=env)


def open_warm_capture(directory):
    """Use the already-loaded Qt UI; retain a cold fallback outside the session."""
    pid_result = subprocess.run(["systemctl", "--user", "show", CAPTURE_UNIT, "--property=MainPID", "--value"],
                                capture_output=True, text=True)
    pid_text = pid_result.stdout.strip()
    if pid_result.returncode or not pid_text.isdecimal() or int(pid_text) <= 0:
        return False
    pid = int(pid_text)
    result = subprocess.run(["quickshell", "ipc", "--path", str(HERE / "capture-daemon.qml"),
                             "call", "capture", "open", str(directory)], capture_output=True, text=True, timeout=2)
    if result.returncode or result.stdout.strip() != "true":
        return False
    polls = 0
    while not (directory / "result.json").is_file():
        try:
            os.kill(pid, 0)
        except ProcessLookupError as error:
            raise RuntimeError("The capture UI stopped before finishing.") from error
        time.sleep(0.025)
        polls += 1
        if polls % 40 == 0:
            state = subprocess.run(["quickshell", "ipc", "--path", str(HERE / "capture-daemon.qml"),
                                    "call", "capture", "status"], capture_output=True, text=True, timeout=2)
            try:
                if state.returncode == 0 and json.loads(state.stdout).get("active") is False:
                    return True
            except ValueError:
                pass
    return True


def session():
    directory = Path(os.environ["DOTFILES_CAPTURE_SESSION"]).resolve()
    return directory, json.loads((directory / "session.json").read_text())


def export_image():
    directory, data = session()
    source = Path(data["render"])
    if source.parent != directory or not source.is_file():
        raise RuntimeError("The selected image could not be rendered.")
    image = source.read_bytes()
    if not image.startswith(b"\x89PNG\r\n\x1a\n"):
        raise RuntimeError("The rendered image is not a PNG.")
    output = output_path("image")
    output.write_bytes(image)
    run("wl-copy", "--type", "image/png", input=image)
    print(output)


def record_area(monitor_name, x, y, width, height, cursor):
    _, data = session()
    monitor = next(output for output in data["outputs"] if output["name"] == monitor_name)
    x, y = max(0, x), max(0, y)
    # Video encoders commonly require even dimensions. Keep the result inside
    # the selected output; image captures preserve their exact dimensions.
    width = min(width, int(monitor["width"]) - x) // 2 * 2
    height = min(height, int(monitor["height"]) - y) // 2 * 2
    if width < 2 or height < 2:
        raise RuntimeError("Select a larger recording area.")
    geometry = f'{int(monitor["x"]) + x},{int(monitor["y"]) + y} {width}x{height}'
    output = output_path("video")
    command = ["systemd-run", "--user", "--wait", "--collect", "--quiet", "--unit=" + RECORD_UNIT,
               "--property=PartOf=graphical-session.target", "--property=KillSignal=SIGINT",
               "--property=TimeoutStopSec=15", "--property=SuccessExitStatus=SIGINT", "--property=UMask=0077"]
    for key in ("WAYLAND_DISPLAY", "HYPRLAND_INSTANCE_SIGNATURE", "XDG_CURRENT_DESKTOP"):
        if key in os.environ:
            command.append("--setenv=" + key + "=" + os.environ[key])
    command += ["--", "/usr/bin/wl-screenrec", "--geometry", geometry,
                "--filename", str(output), "--max-fps", "60"]
    if not cursor:
        command.append("--no-cursor")
    run(*command)
    if not output.is_file() or output.stat().st_size == 0:
        raise RuntimeError("The recorder did not produce a video. Check its user-service journal.")
    print(output)


def main():
    os.umask(0o077)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--session", type=Path, help="Capture session directory for the persistent UI")
    actions = parser.add_subparsers(dest="action", required=True)
    actions.add_parser("select").add_argument("mode", choices=("region", "window", "record"))
    for name in ("info", "export", "stop"):
        actions.add_parser(name)
    record = actions.add_parser("record")
    record.add_argument("monitor")
    for name in ("x", "y", "width", "height"):
        record.add_argument(name, type=int)
    record.add_argument("cursor", choices=("yes", "no"))
    args = parser.parse_args()
    if args.session is not None:
        os.environ["DOTFILES_CAPTURE_SESSION"] = str(args.session)
    if args.action == "select":
        select(args.mode)
    elif args.action == "info":
        print(json.dumps(session()[1]))
    elif args.action == "export":
        export_image()
    elif args.action == "record":
        record_area(args.monitor, args.x, args.y, args.width, args.height, args.cursor == "yes")
    else:
        run("systemctl", "--user", "stop", RECORD_UNIT)


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError, subprocess.SubprocessError, KeyError, ValueError, StopIteration) as error:
        print(str(error), file=sys.stderr)
        raise SystemExit(1)
