#!/usr/bin/env python3
"""Frozen selection/annotation UI, with grim images and wl-screenrec recordings."""

import argparse
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime
import fcntl
import json
import os
from pathlib import Path
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
import time
from urllib.parse import unquote, urlparse


HERE = Path(__file__).resolve().parent
RECORD_UNIT = "dotfiles-hyprland-record.service"
CAPTURE_UNIT = "dotfiles-hyprland-capture.service"


def preferences_path():
    return Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state")) / "dotfiles/hyprland/capture.json"


def load_preferences():
    try:
        value = json.loads(preferences_path().read_text())
        return value if isinstance(value, dict) else {}
    except (OSError, ValueError):
        return {}


def save_preferences(value):
    path = preferences_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(mode="w", dir=path.parent, delete=False) as stream:
        temporary = Path(stream.name)
        json.dump(value, stream)
    try:
        temporary.replace(path)
    finally:
        temporary.unlink(missing_ok=True)


def intersection(rect, output):
    left, top = max(rect["x"], output["x"]), max(rect["y"], output["y"])
    right = min(rect["x"] + rect["width"], output["x"] + output["width"])
    bottom = min(rect["y"] + rect["height"], output["y"] + output["height"])
    return {"x": left, "y": top, "width": max(0, right - left), "height": max(0, bottom - top)}


def selected_outputs(rect, outputs):
    return [(output, part) for output in outputs
            if (part := intersection(rect, output))["width"] > 0 and part["height"] > 0]


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
    parts = selected_outputs({"x": x, "y": y, "width": width, "height": height}, outputs)
    if not parts:
        raise RuntimeError("The active window is outside the visible displays.")
    left = min(part["x"] for _, part in parts)
    top = min(part["y"] for _, part in parts)
    right = max(part["x"] + part["width"] for _, part in parts)
    bottom = max(part["y"] + part["height"] for _, part in parts)
    return {"x": left, "y": top,
            "width": right - left, "height": bottom - top}


def frozen_image(outputs, rect, cursor=False):
    """Composite logical desktop coordinates, including mixed scales and gaps."""
    from PIL import Image
    parts = selected_outputs(rect, outputs)
    scale = max(output.get("scale", 1) for output, _ in parts)
    canvas = Image.new("RGB", (round(rect["width"] * scale), round(rect["height"] * scale)))
    for output, part in parts:
        source = unquote(urlparse(output["cursor" if cursor else "plain"]).path)
        with Image.open(source) as image:
            sx, sy = image.width / output["width"], image.height / output["height"]
            crop = image.crop((round((part["x"] - output["x"]) * sx), round((part["y"] - output["y"]) * sy),
                               round((part["x"] + part["width"] - output["x"]) * sx),
                               round((part["y"] + part["height"] - output["y"]) * sy)))
            crop = crop.resize((round(part["width"] * scale), round(part["height"] * scale)), Image.Resampling.LANCZOS)
            canvas.paste(crop, (round((part["x"] - rect["x"]) * scale), round((part["y"] - rect["y"]) * scale)))
    return canvas


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
        subprocess.run(["quickshell", "ipc", "--path", str(HERE / "capture-daemon.qml"),
                        "call", "capture", "recordingStopped"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
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
            preferences = load_preferences()
            if mode == "window":
                image = frozen_image(outputs, window_selection(window, outputs), bool(preferences.get("cursor", False)))
                output = output_path("image")
                image.save(output, format="PNG")
                run("wl-copy", "--type", "image/png", input=output.read_bytes())
                return
            data = {"mode": mode, "outputs": outputs, "render": str(directory / "render.png"),
                    "selection": None, "preferences": preferences}
            (directory / "session.json").write_text(json.dumps(data))
            if open_warm_capture(directory):
                return
            env = os.environ.copy()
            env["DOTFILES_CAPTURE_SESSION"] = str(directory)
            run("quickshell", "--path", str(HERE / "capture.qml"), env=env)


def request_warm_capture(directory):
    """Contact the worker without starting a systemctl/Qt IPC client pair."""
    with socket.socket(socket.AF_UNIX) as client:
        client.settimeout(2)
        try:
            client.connect(str(Path(os.environ["XDG_RUNTIME_DIR"]) / "dotfiles-capture.sock"))
        except (FileNotFoundError, ConnectionRefusedError):
            return None
        # Once sent, a failed reply is ambiguous: do not launch a second UI.
        client.sendall((json.dumps({"action": "open", "directory": str(directory)}) + "\n").encode())
        with client.makefile("rb") as stream:
            reply = stream.readline(65536)
        if not reply.endswith(b"\n"):
            raise RuntimeError("The capture UI disconnected before acknowledging the session.")
        return json.loads(reply)


def open_warm_capture(directory):
    """Use the already-loaded Qt UI; retain a cold fallback outside the session."""
    reply = request_warm_capture(directory)
    if reply is not None:
        if not reply.get("accepted"):
            raise RuntimeError("The capture UI is already busy.")
        pid = int(reply["pid"])
        if pid <= 0:
            raise RuntimeError("The capture UI returned an invalid process ID.")
    else:
        return open_legacy_capture(directory)
    wait_warm_capture(directory, pid)
    return True


def open_legacy_capture(directory):
    """Support an older worker until the configuration has been reloaded."""
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
    wait_warm_capture(directory, pid)
    return True


def wait_warm_capture(directory, pid):
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
                    return
            except ValueError:
                pass


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
    directory, data = session()
    if monitor_name != "desktop":
        monitor = next(output for output in data["outputs"] if output["name"] == monitor_name)
        width, height = min(width, int(monitor["width"]) - x), min(height, int(monitor["height"]) - y)
        x, y = int(monitor["x"]) + x, int(monitor["y"]) + y
    width, height = width // 2 * 2, height // 2 * 2
    if width < 2 or height < 2:
        raise RuntimeError("Select a larger recording area.")
    rect = {"x": x, "y": y, "width": width, "height": height}
    parts = selected_outputs(rect, data["outputs"])
    if not parts:
        raise RuntimeError("The recording area is outside the visible displays.")
    geometry = f'{x},{y} {width}x{height}'
    output = output_path("video")
    command = ["systemd-run", "--user", "--wait", "--collect", "--quiet", "--unit=" + RECORD_UNIT,
               "--property=PartOf=graphical-session.target", "--property=KillSignal=SIGINT",
               "--property=TimeoutStopSec=300", "--property=KillMode=mixed",
               "--property=SuccessExitStatus=SIGINT", "--property=UMask=0077"]
    for key in ("WAYLAND_DISPLAY", "HYPRLAND_INSTANCE_SIGNATURE", "XDG_CURRENT_DESKTOP"):
        if key in os.environ:
            command.append("--setenv=" + key + "=" + os.environ[key])
    if len(parts) == 1 and parts[0][1] == rect:
        command += ["--", "/usr/bin/wl-screenrec", "--geometry", geometry,
                    "--filename", str(output), "--max-fps", "60"]
        if not cursor:
            command.append("--no-cursor")
    else:
        command += ["--", sys.executable, str(HERE / "capture.py"), "--session", str(directory),
                    "record-worker", json.dumps(rect), "yes" if cursor else "no", str(output)]
    run(*command)
    if not output.is_file() or output.stat().st_size == 0:
        raise RuntimeError("The recorder did not produce a video. Check its user-service journal.")
    print(output)


def compose_recordings(clips, rect, output):
    """Put independently captured outputs on one correctly positioned timeline."""
    scale = max(clip["output"].get("scale", 1) for clip in clips)
    width, height = round(rect["width"] * scale) // 2 * 2, round(rect["height"] * scale) // 2 * 2
    command = ["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-filter_complex_threads", "1"]
    filters = [f"color=c=black:s={width}x{height}:r=60[base]"]
    duration = 0
    for i, clip in enumerate(clips):
        command += ["-i", str(clip["path"])]
        metadata = json.loads(run("ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries",
                                  "stream=width,height:format=duration", "-of", "json", str(clip["path"]),
                                  capture_output=True, text=True).stdout)
        stream, source = metadata["streams"][0], clip["output"]
        part = intersection(rect, source)
        sx, sy = stream["width"] / source["width"], stream["height"] / source["height"]
        left, top = round((part["x"] - source["x"]) * sx), round((part["y"] - source["y"]) * sy)
        w = min(stream["width"], round((part["x"] + part["width"] - source["x"]) * sx)) - left
        h = min(stream["height"], round((part["y"] + part["height"] - source["y"]) * sy)) - top
        tw, th = max(1, round(part["width"] * scale)), max(1, round(part["height"] * scale))
        offset = clip.get("offset", 0)
        filters.append(f"[{i}:v]crop={w}:{h}:{left}:{top}:exact=1,scale={tw}:{th},setsar=1,setpts=PTS-STARTPTS+{offset}/TB[s{i}]")
        previous = "base" if i == 0 else f"v{i-1}"
        dx, dy = round((part["x"] - rect["x"]) * scale), round((part["y"] - rect["y"]) * scale)
        filters.append(f"[{previous}][s{i}]overlay={dx}:{dy}:eof_action=pass:repeatlast=0:format=rgb[v{i}]")
        duration = max(duration, float(metadata["format"]["duration"]) + offset)
    command += ["-filter_complex", ";".join(filters), "-map", f"[v{len(clips)-1}]", "-t", str(duration),
                "-an", "-c:v", "libx264", "-preset", "veryfast", "-crf", "18", "-pix_fmt", "yuv420p",
                "-movflags", "+faststart", str(output)]
    run(*command)


def record_worker(rect, cursor, output):
    _, data = session()
    parts = selected_outputs(rect, data["outputs"])
    if not parts:
        raise RuntimeError("The recording area is outside the visible displays.")
    output = Path(output)
    directory = Path(tempfile.mkdtemp(prefix=output.stem + "-parts-", dir=output.parent))
    processes, clips = [], []
    stopping = False
    def stop(*_):
        nonlocal stopping
        stopping = True
        for process in processes:
            if process.poll() is None:
                process.send_signal(signal.SIGINT)
    previous = {sig: signal.signal(sig, stop) for sig in (signal.SIGINT, signal.SIGTERM)}
    started = time.monotonic()
    try:
        for i, (monitor, _) in enumerate(parts):
            if stopping:
                break
            path = directory / f"output-{i}.mkv"
            command = ["/usr/bin/wl-screenrec", "--output", monitor["name"], "--filename", str(path), "--max-fps", "60"]
            if not cursor:
                command.append("--no-cursor")
            offset = time.monotonic() - started
            processes.append(subprocess.Popen(command))
            clips.append({"path": path, "output": monitor, "offset": offset})
        while not stopping:
            if any(process.poll() is not None for process in processes):
                raise RuntimeError("A display recorder stopped unexpectedly.")
            time.sleep(.05)
        stop()  # Also covers a stop signal arriving while a child was spawning.
        for process in processes:
            process.wait(timeout=15)
        if not clips or any(not clip["path"].is_file() or not clip["path"].stat().st_size for clip in clips):
            raise RuntimeError("A display recorder produced no video.")
        compose_recordings(clips, rect, output)
        shutil.rmtree(directory)
    except BaseException:
        print(f"Uncombined display recordings are retained in {directory}", file=sys.stderr)
        raise
    finally:
        stop()
        for process in processes:
            try:
                process.wait(timeout=15)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
        for sig, handler in previous.items():
            signal.signal(sig, handler)


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
    worker = actions.add_parser("record-worker")
    worker.add_argument("rect", type=json.loads)
    worker.add_argument("cursor", choices=("yes", "no"))
    worker.add_argument("output", type=Path)
    actions.add_parser("preferences").add_argument("value", type=json.loads)
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
    elif args.action == "record-worker":
        record_worker(args.rect, args.cursor == "yes", args.output)
    elif args.action == "preferences":
        save_preferences(args.value)
    else:
        run("systemctl", "--user", "stop", RECORD_UNIT)


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError, subprocess.SubprocessError, KeyError, ValueError, StopIteration) as error:
        print(str(error), file=sys.stderr)
        raise SystemExit(1)
