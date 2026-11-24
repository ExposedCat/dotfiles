#!/usr/bin/env python3
"""Exercise clipboard ownership on a private compositor through isolated-gui.

Pass the compiled dotfiles-desktop executable as the only argument. Requires
container-local sway, wl-copy and wl-paste. No real session clipboard is used.
"""

import base64
import contextlib
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time


def main():
    if not os.environ.get("ISOLATED_GUI_SESSION"):
        raise SystemExit("Run through the isolated-gui helper")
    binary = str(Path(sys.argv[1]).resolve(strict=True))
    directory = Path(tempfile.mkdtemp(
        prefix="clipboard-regression-",
        dir=Path.home() / ".cache/agent-desktops",
    ))
    print(f"Test logs: {directory}", flush=True)
    runtime = directory / "runtime"
    runtime.mkdir(mode=0o700)
    config = directory / "sway.conf"
    config.write_text("output * mode 800x600\nxwayland disable\n")
    env = dict(os.environ, XDG_RUNTIME_DIR=str(runtime),
               XDG_STATE_HOME=str(directory / "state"),
               XDG_CONFIG_HOME=str(directory / "config"),
               XDG_CACHE_HOME=str(directory / "cache"),
               WLR_BACKENDS="headless", WLR_RENDERER="pixman",
               WLR_LIBINPUT_NO_DEVICES="1")

    def wait(check, label):
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            value = check()
            if value:
                return value
            time.sleep(0.025)
        raise AssertionError(label)

    with contextlib.ExitStack() as stack:
        def start(args, input_data=None):
            log = stack.enter_context((directory / f"process-{len(processes)}.log").open("wb"))
            process = subprocess.Popen(args, env=env,
                                       stdin=subprocess.PIPE if input_data is not None else subprocess.DEVNULL,
                                       stdout=log, stderr=log)
            processes.append(process)

            def stop():
                if process.poll() is None:
                    process.send_signal(signal.SIGCONT)
                    process.terminate()
                    process.wait(timeout=5)

            stack.callback(stop)
            if input_data is not None:
                process.stdin.write(input_data)
                process.stdin.close()
            return process

        def run(args, check=True):
            return subprocess.run(args, env=env, capture_output=True,
                                  timeout=4, check=check)

        def desktop(*args):
            return run([binary, "desktop", *args]).stdout

        def history():
            return json.loads(desktop("clipboard-list"))

        def read(mime="text/plain"):
            result = run(["/usr/bin/wl-paste", "--no-newline", "--type", mime], False)
            return result.stdout if result.returncode == 0 else None

        def marker():
            return b"application/x-dotfiles-clipboard-history;owner=" in run(
                ["/usr/bin/wl-paste", "--list-types"], False).stdout

        def copy(value, mime="text/plain", sensitive=False):
            args = ["/usr/bin/wl-copy", "--foreground", "--type", mime]
            if sensitive:
                args.append("--sensitive")
            data = value.encode() if isinstance(value, str) else value
            owner = start(args, data)
            wait(lambda: read(mime) == data, "source did not become owner")
            return owner

        def close(owner):
            owner.terminate()
            owner.wait(timeout=4)

        processes = []
        compositor = start(["/usr/bin/sway", "--unsupported-gpu", "-c", str(config)])
        display = wait(lambda: next((p for p in runtime.glob("wayland-*") if p.is_socket()), None),
                       "private compositor did not start")
        assert compositor.poll() is None
        env["WAYLAND_DISPLAY"] = display.name
        watcher = start([binary, "desktop", "clipboard-watch"])
        time.sleep(0.2)
        assert watcher.poll() is None
        assert read() is None, "empty startup unexpectedly restored history"

        for mime, value in [
            ("text/plain", "clipboard survives source exit 🐈"),
            ("text/html", '<p><b>Rich copy</b><img src="https://example.invalid/image.png"></p>'),
            ("text/uri-list", "file:///tmp/clipboard-fixture.txt\r\n"),
            ("image/png", base64.b64decode(
                "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aD1sAAAAASUVORK5CYII=")),
        ]:
            before = len(history())
            owner = copy(value, mime)
            wait(lambda: len(history()) == before + 1, f"history missing {mime}")
            close(owner)
            wait(marker, f"source exit did not preserve {mime}")
            expected = value.encode() if isinstance(value, str) else value
            assert read(mime) == expected, f"restored {mime} changed bytes"
            assert read(mime) == expected, "second paste failed"
            assert len(history()) == before + 1, "restoration duplicated history"

        run(["/usr/bin/wl-copy", "--clear"])
        time.sleep(0.15)
        assert read("image/png") is None, "clearing restored clipboard resurrected it"
        close(watcher)
        watcher = start([binary, "desktop", "clipboard-watch"])
        time.sleep(0.2)
        assert watcher.poll() is None
        assert read() is None, "restart resurrected an older history entry"

        owner = copy("old queued selection")
        wait(lambda: any(e.get("preview") == "old queued selection" for e in history()), "old history")
        watcher.send_signal(signal.SIGSTOP)
        close(owner)
        newer = copy("newer wins")
        watcher.send_signal(signal.SIGCONT)
        wait(lambda: any(e.get("preview") == "newer wins" for e in history()), "newer history")
        assert read() == b"newer wins", "queued clear overwrote newer selection"
        close(newer)
        wait(marker, "newer copy not persisted")
        assert read() == b"newer wins"

        owner = copy("before secret")
        wait(lambda: any(e.get("preview") == "before secret" for e in history()), "pre-secret history")
        secret = copy("secret fixture", sensitive=True)
        close(owner)
        time.sleep(0.15)
        close(secret)
        time.sleep(0.15)
        assert read() is None, "secret or stale predecessor was restored"
        assert not any(e.get("preview") == "secret fixture" for e in history())

        owner = copy("before unsupported")
        wait(lambda: any(e.get("preview") == "before unsupported" for e in history()), "unsupported history")
        unsupported = copy("custom fixture", "application/x-dotfiles-test")
        close(owner)
        time.sleep(0.15)
        close(unsupported)
        time.sleep(0.15)
        assert read() is None, "unsupported selection restored stale predecessor"

        replay = start([binary, "desktop", "clipboard-serve", str(history()[0]["id"])])
        wait(marker, "history replay did not become owner")
        time.sleep(0.15)
        close(replay)
        time.sleep(0.15)
        assert read() is None, "history replay restored an unrelated predecessor"

        owner = copy("clear history while source lives")
        wait(lambda: any(e.get("preview") == "clear history while source lives" for e in history()), "clear history")
        desktop("clipboard-clear")
        close(owner)
        wait(marker, "clearing history discarded active clipboard")
        assert read() == b"clear history while source lives"
        assert history() == [], "preservation repopulated cleared history"
        assert watcher.poll() is None, "watcher exited"
        print("PASS: source exit, formats, repeated paste, queued replacement, sensitive/unsupported "
              "copies, history replay and history clearing", flush=True)


if __name__ == "__main__":
    main()
