import fcntl
import json
import os
from pathlib import Path
import re
import secrets
import selectors
import shutil
import signal
import struct
import subprocess
import time
from xml.sax.saxutils import escape


def binary(name):
    for directory in ["/usr/bin", "/bin", *os.environ.get("PATH", "").split(os.pathsep)]:
        path = Path(directory) / name
        if path.is_file() and os.access(path, os.X_OK) and path.resolve().name != "distrobox-host-exec":
            return str(path)
    raise RuntimeError(f"Missing container-local executable: {name}")


def identity(pid):
    try:
        fields = Path(f"/proc/{pid}/stat").read_text().rsplit(")", 1)[1].split()
        return {"pid": pid, "start": fields[19], "group": int(fields[2]), "alive": fields[0] != "Z"}
    except (FileNotFoundError, ProcessLookupError):
        return None


def alive(record):
    current = identity(record["pid"])
    return current is not None and current["alive"] and current["start"] == record["start"]


def namespace():
    return {name: os.readlink(f"/proc/self/ns/{name}") for name in ["pid", "mnt"]}


class Session:
    def __init__(self, name):
        if not re.fullmatch(r"[a-z0-9][a-z0-9_-]{0,63}", name):
            raise RuntimeError("Use a short session name containing lowercase letters, numbers, hyphens or underscores")
        self.name = name
        self.path = Path.home() / ".cache" / "agent-desktops" / name
        self.path.mkdir(parents=True, exist_ok=True, mode=0o700)
        self.path.chmod(0o700)
        self.state_path = self.path / "state.json"
        self.state = None

    def __enter__(self):
        self.lock = (self.path / "lock").open("a")
        fcntl.flock(self.lock, fcntl.LOCK_EX)
        if self.state_path.exists():
            self.state = json.loads(self.state_path.read_text())
            if self.state["namespace"] != namespace():
                raise RuntimeError("This session belongs to a different container; enter its original container")
            if self.state["boot"] != Path("/proc/sys/kernel/random/boot_id").read_text().strip():
                self.state = None
        return self

    def __exit__(self, *_):
        if self.lock:
            self.lock.close()

    def unlock(self):
        self.lock.close()
        self.lock = None

    def save(self):
        temporary = self.path / "state.new"
        temporary.write_text(json.dumps(self.state, indent=2) + "\n")
        temporary.chmod(0o600)
        temporary.replace(self.state_path)

    def environment(self, additions=None):
        env = os.environ.copy()
        for key in ["DISPLAY", "WAYLAND_DISPLAY", "WAYLAND_SOCKET", "XAUTHORITY", "XAUTHLOCALHOSTNAME",
                    "DBUS_SESSION_BUS_ADDRESS", "DBUS_STARTER_ADDRESS", "DBUS_STARTER_BUS_TYPE",
                    "SESSION_MANAGER", "DESKTOP_STARTUP_ID", "XDG_ACTIVATION_TOKEN", "SWAYSOCK",
                    "HYPRLAND_INSTANCE_SIGNATURE", "MIR_SOCKET", "PULSE_SERVER", "PIPEWIRE_REMOTE"]:
            env.pop(key, None)
        env.update({
            "DISPLAY": self.state["display"], "XAUTHORITY": self.state["authority"],
            "DBUS_SESSION_BUS_ADDRESS": self.state["bus"], "XDG_RUNTIME_DIR": str(self.path / "runtime"),
            "XDG_SESSION_TYPE": "x11", "XDG_CURRENT_DESKTOP": "Openbox", "XDG_SESSION_DESKTOP": "openbox",
            "GDK_BACKEND": "x11", "QT_QPA_PLATFORM": "xcb", "CLUTTER_BACKEND": "x11",
            "SDL_VIDEODRIVER": "x11", "SDL_VIDEO_DRIVER": "x11", "MOZ_ENABLE_WAYLAND": "0",
            "GTK_A11Y": "none", "NO_AT_BRIDGE": "1", "GSETTINGS_BACKEND": "memory", "GIO_USE_VFS": "local",
            "ISOLATED_GUI_SESSION": self.state["token"],
        })
        if self.state["render"] == "software":
            env.update({"GSK_RENDERER": "cairo", "LIBGL_ALWAYS_SOFTWARE": "1", "WEBKIT_DISABLE_DMABUF_RENDERER": "1"})
        protected = {"DISPLAY", "WAYLAND_DISPLAY", "WAYLAND_SOCKET", "XAUTHORITY", "DBUS_SESSION_BUS_ADDRESS", "DBUS_STARTER_ADDRESS", "DBUS_STARTER_BUS_TYPE", "XDG_RUNTIME_DIR", "ISOLATED_GUI_SESSION", "GDK_BACKEND", "QT_QPA_PLATFORM", "SDL_VIDEODRIVER", "SDL_VIDEO_DRIVER", "CLUTTER_BACKEND", "GSETTINGS_BACKEND", "GIO_USE_VFS"}
        for value in additions or []:
            key, separator, data = value.partition("=")
            if not separator or not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", key) or key in protected:
                raise RuntimeError(f"Invalid or isolation-critical environment override: {key}")
            env[key] = data
        return env

    def spawn(self, command, env, log, cwd=None, pass_fds=()):
        executable = shutil.which(command[0], path=env.get("PATH"))
        if executable and Path(executable).resolve().name == "distrobox-host-exec":
            raise RuntimeError("Host-forwarding commands are unsupported; use the container-local application binary")
        with (self.path / log).open("ab") as output:
            process = subprocess.Popen(command, cwd=cwd, env=env, stdin=subprocess.DEVNULL,
                                       stdout=output, stderr=subprocess.STDOUT, start_new_session=True, pass_fds=pass_fds)
        record = identity(process.pid)
        record.update({"command": command, "log": str(self.path / log)})
        return process, record

    def read_line(self, descriptor, process):
        with selectors.DefaultSelector() as selector:
            selector.register(descriptor, selectors.EVENT_READ)
            if not selector.select(8):
                raise RuntimeError("Private display/session bus did not become ready; inspect its log")
            value = os.read(descriptor, 4096).decode().strip()
            if not value or process.poll() is not None:
                raise RuntimeError("Private display/session bus exited during startup; inspect its log")
            return value

    def authority(self, display, cookie):
        values = [b"", display.encode(), b"MIT-MAGIC-COOKIE-1", cookie]
        data = struct.pack("!H", 65535) + b"".join(struct.pack("!H", len(value)) + value for value in values)
        path = Path(self.state["authority"])
        path.write_bytes(data)
        path.chmod(0o600)

    def start(self, size, render):
        for name in ["Xvfb", "dbus-daemon", "openbox", "xdpyinfo", "xprop", "xdotool", "import"]:
            binary(name)
        if self.state and all(alive(self.state["services"].get(name, {"pid": 0, "start": ""})) for name in ["display", "bus", "wm"]):
            self.ready()
            return
        if self.state:
            self.stop()
        runtime = self.path / "runtime"
        runtime.mkdir(mode=0o700, exist_ok=True)
        runtime.chmod(0o700)
        (runtime / "bus").unlink(missing_ok=True)
        self.state = {"name": self.name, "namespace": namespace(), "boot": Path("/proc/sys/kernel/random/boot_id").read_text().strip(),
                      "display": "", "bus": "", "authority": str(self.path / "Xauthority"), "render": render,
                      "size": size, "token": secrets.token_hex(16), "services": {}, "apps": []}
        self.save()
        cookie = secrets.token_bytes(16)
        self.authority("0", cookie)
        try:
            read_fd, write_fd = os.pipe()
            try:
                process, record = self.spawn([binary("Xvfb"), "-displayfd", str(write_fd), "-screen", "0", size + "x24", "-nolisten", "tcp", "-auth", self.state["authority"]], os.environ.copy(), "xvfb.log", pass_fds=(write_fd,))
                self.state["services"]["display"] = record
                self.save()
                os.close(write_fd)
                write_fd = None
                self.state["display"] = ":" + self.read_line(read_fd, process)
            finally:
                os.close(read_fd)
                if write_fd is not None:
                    os.close(write_fd)
            self.authority(self.state["display"][1:], cookie)
            config = self.path / "dbus.conf"
            config.write_text('<busconfig><type>session</type><listen>unix:path=' + escape(str(runtime / "bus")) + '</listen><auth>EXTERNAL</auth><policy context="default"><allow own="*"/><allow send_destination="*"/><allow receive_sender="*"/></policy></busconfig>\n')
            read_fd, write_fd = os.pipe()
            try:
                process, record = self.spawn([binary("dbus-daemon"), "--config-file=" + str(config), "--nofork", "--print-address=" + str(write_fd)], os.environ.copy(), "dbus.log", pass_fds=(write_fd,))
                self.state["services"]["bus"] = record
                self.save()
                os.close(write_fd)
                write_fd = None
                self.state["bus"] = self.read_line(read_fd, process)
            finally:
                os.close(read_fd)
                if write_fd is not None:
                    os.close(write_fd)
            _, record = self.spawn([binary("openbox"), "--sm-disable"], self.environment(), "openbox.log")
            self.state["services"]["wm"] = record
            self.save()
            self.ready()
        except BaseException:
            self.stop()
            raise

    def ready(self):
        if not self.state or not all(alive(self.state["services"].get(name, {"pid": 0, "start": ""})) for name in ["display", "bus", "wm"]):
            raise RuntimeError("Private session is stopped or unhealthy; restart it before GUI work")
        subprocess.run([binary("xdpyinfo")], env=self.environment(), check=True, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, timeout=5)
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            value = subprocess.run([binary("xprop"), "-root", "_NET_SUPPORTING_WM_CHECK"], env=self.environment(), capture_output=True, text=True, timeout=2)
            if "window id" in value.stdout:
                return
            time.sleep(0.05)
        raise RuntimeError("Openbox did not initialize on the private display; inspect openbox.log")

    def owns_group(self, record):
        if alive(record):
            return True
        token = ("ISOLATED_GUI_SESSION=" + self.state["token"]).encode()
        for entry in Path("/proc").glob("[0-9]*"):
            current = identity(int(entry.name))
            if current and current["alive"] and current["group"] == record["group"]:
                try:
                    if token in (entry / "environ").read_bytes().split(b"\0"):
                        return True
                except (PermissionError, ProcessLookupError, FileNotFoundError):
                    continue
        return False

    def terminate(self, record):
        if not self.owns_group(record):
            return
        try:
            os.killpg(record["group"], signal.SIGTERM)
            deadline = time.monotonic() + 2
            while time.monotonic() < deadline and self.owns_group(record):
                time.sleep(0.05)
            if self.owns_group(record):
                os.killpg(record["group"], signal.SIGKILL)
        except ProcessLookupError:
            pass

    def stop(self, app=None):
        if not self.state:
            return
        if app is not None:
            records = [record for record in self.state["apps"] if record["pid"] == app]
            if not records:
                raise RuntimeError("That PID was not launched by this session")
        else:
            records = [*reversed(self.state["apps"]), *reversed(list(self.state["services"].values()))]
        for record in records:
            self.terminate(record)
        if app is None:
            self.state["services"] = {}
        self.state["apps"] = [record for record in self.state["apps"] if record not in records]
        self.save()
