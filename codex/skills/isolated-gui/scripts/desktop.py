import argparse
import json
import os
from pathlib import Path
import re
import shlex
import subprocess
import sys
import time

from runtime import Session, alive, binary


def command_arguments(values):
    values = values[1:] if values and values[0] == "--" else values
    if not values:
        raise RuntimeError("Supply a command after --")
    return values


def status(session):
    state = session.state
    if not state:
        return {"session": session.name, "running": False, "directory": str(session.path)}
    return {"session": session.name, "running": all(alive(state["services"].get(name, {"pid": 0, "start": ""})) for name in ["display", "bus", "wm"]),
            "display": state["display"], "size": state["size"], "render": state["render"], "directory": str(session.path),
            "apps": [{"pid": record["pid"], "running": alive(record), "log": record["log"]} for record in state["apps"]]}


def main():
    parser = argparse.ArgumentParser(description="Run agent-owned GUIs on a private Xvfb/Openbox desktop")
    parser.add_argument("--session", required=True)
    subparsers = parser.add_subparsers(dest="operation", required=True)
    start = subparsers.add_parser("start")
    start.add_argument("--size", default="1600x1000")
    start.add_argument("--render", choices=["software", "native"], default="software")
    for name in ["status", "env", "windows"]:
        subparsers.add_parser(name)
    for name in ["run", "launch"]:
        launch = subparsers.add_parser(name)
        launch.add_argument("--cwd", required=True)
        launch.add_argument("--env", action="append", default=[])
        if name == "run":
            launch.add_argument("--timeout", type=float, default=120)
        launch.add_argument("command", nargs=argparse.REMAINDER)
    screenshot = subparsers.add_parser("screenshot")
    screenshot.add_argument("--window")
    screenshot.add_argument("path")
    inputs = subparsers.add_parser("input")
    inputs.add_argument("command", nargs=argparse.REMAINDER)
    stop = subparsers.add_parser("stop")
    stop.add_argument("--app", type=int)
    args = parser.parse_args()
    with Session(args.session) as session:
        if args.operation == "start":
            if not re.fullmatch(r"[1-9][0-9]{1,4}x[1-9][0-9]{1,4}", args.size):
                raise RuntimeError("Use a size such as 1600x1000")
            session.start(args.size, args.render)
            print(json.dumps(status(session), indent=2))
            return 0
        if args.operation == "status":
            print(json.dumps(status(session), indent=2))
            return 0
        if args.operation == "stop":
            session.stop(args.app)
            print(json.dumps(status(session), indent=2))
            return 0
        session.ready()
        env = session.environment(getattr(args, "env", None))
        if args.operation == "env":
            removed = sorted(set(os.environ) - set(env))
            if removed:
                print("unset " + " ".join(removed))
            for key, value in sorted(env.items()):
                if os.environ.get(key) != value:
                    print("export " + key + "=" + shlex.quote(value))
            return 0
        if args.operation == "windows":
            clients = subprocess.run([binary("xprop"), "-root", "_NET_CLIENT_LIST"], env=env, check=True, capture_output=True, text=True)
            for window in re.findall(r"0x[0-9a-fA-F]+", clients.stdout):
                title = subprocess.run([binary("xprop"), "-id", window, "_NET_WM_NAME", "WM_NAME"], env=env, check=True, capture_output=True, text=True)
                print(window + " " + title.stdout.strip().replace("\n", "; "))
            return 0
        if args.operation == "input":
            return subprocess.run([binary("xdotool"), *command_arguments(args.command)], env=env, timeout=20).returncode
        if args.operation == "screenshot":
            path = Path(args.path).expanduser().absolute()
            path.parent.mkdir(parents=True, exist_ok=True)
            subprocess.run([binary("import"), "-display", env["DISPLAY"], "-window", args.window or "root", str(path)], env=env, check=True, timeout=20)
            print(str(path))
            return 0
        cwd = Path(args.cwd).expanduser()
        if not cwd.is_absolute() or not cwd.is_dir():
            raise RuntimeError("Supply an existing absolute --cwd directory")
        command = command_arguments(args.command)
        log = f"app-{time.time_ns()}.log"
        process, record = session.spawn(command, env, log, str(cwd))
        session.state["apps"].append(record)
        session.save()
        print(json.dumps({"pid": process.pid, "log": record["log"], "display": env["DISPLAY"]}), flush=True)
        if args.operation == "launch":
            return 0
        session.unlock()
        try:
            result = process.wait(timeout=args.timeout)
        except subprocess.TimeoutExpired:
            result = 124
        except KeyboardInterrupt:
            result = 130
        finally:
            with Session(args.session) as cleanup:
                if cleanup.state and any(app["pid"] == process.pid for app in cleanup.state["apps"]):
                    cleanup.stop(process.pid)
        print(json.dumps({"exit_code": result, "log": record["log"]}), flush=True)
        return result


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (RuntimeError, OSError, subprocess.SubprocessError) as error:
        print(f"isolated-gui: {error}", file=sys.stderr)
        sys.exit(1)
