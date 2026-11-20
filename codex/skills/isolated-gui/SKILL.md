---
name: isolated-gui
description: Run Linux GUI applications and diagnostics on a private virtual desktop without covering the user's windows or taking their keyboard and mouse. Use for agent-owned GTK/WebKit tests, desktop-app testing, screenshots, and GUI automation while the user works on the same machine.
---

# Isolated GUI

This user requires agent-owned GUI work to stay off their working desktop. Use this skill for every test or diagnostic that creates windows, including ignored GTK/WebKit tests. Prefer non-GUI APIs when they exercise the required behavior. Explicit requests to control an existing user application or browser tab remain scoped to that application.

Use the helper in `scripts/desktop.py`: it creates a named Xvfb display, Openbox window manager, private Xauthority cookie, and private D-Bus session. It wraps the server and every application, input, and capture command in a Bubblewrap mount namespace with a per-session `/tmp`, removes inherited Wayland and desktop-session settings, and forces toolkits to use private X11. Xvfb has both TCP and Linux abstract socket listeners disabled. It does not open a viewer, listen on a network port, or create a system service. A stopped or unhealthy session is an error: repair or restart it; never fall back to the user's display.

## Mandatory socket protection

- For agent-owned GUI work, start display servers only through this helper.
  Never run bare `Xvfb`, `Xorg`, `Xwayland`, or `xvfb-run`, including for a quick
  check or a reproduction. Do not copy an older helper into a temporary script.
- Never use Xvfb `-displayfd`, `-nolock`, or a low display number. A container,
  private D-Bus session, or different `DISPLAY` alone does not protect the desktop.
- Do not expose host X11 sockets inside the private `/tmp`, override its mount,
  export the environment for use outside the helper, or escape to the host using
  a forwarding command, `nsenter`, or a shell wrapper.
- The helper must verify its private mount before starting Xvfb. Symlinked or
  shared temporary/socket directories are errors. If verification fails, stop;
  fix the helper rather than weakening isolation or launching a server manually.
- Never delete, rename, replace, or "clean up" host `/tmp/.X11-unix/*` or
  `/tmp/.X*-lock` during tests. Report missing or changed host endpoints and stop
  GUI work; desktop repair is a separate task, not test cleanup.

## This machine

The development environment is the Fedora Toolbx container named `dev`, with shared home `/var/home/kitkat`. Run the helper inside that container. In the current Codex shell:

```bash
desktop="/usr/bin/python3 /var/home/kitkat/.codex/skills/isolated-gui/scripts/desktop.py"
```

From a host shell, enter the same container:

```bash
desktop="podman exec --user kitkat dev /usr/bin/python3 /var/home/kitkat/.codex/skills/isolated-gui/scripts/desktop.py"
```

From a Flatpak sandbox that provides `flatpak-spawn`, prepend `flatpak-spawn --host` to that host command. These entry commands depend on the caller's environment; the container-local command is the verified path. Set the `desktop` variable in each shell tool call; shell variables do not persist between calls. Keep screenshots and exchanged artifacts in shared home, preferably `~/.cache/agent-desktops`, rather than relying on `/tmp`, which is private inside helper commands.

Some `/usr/local/bin` commands here forward to the host through `distrobox-host-exec`, including `dbus-run-session`. The helper uses container-local display services and rejects a directly launched host-forwarding executable. Do not bypass this by wrapping host commands in a shell. Use native container application binaries for these sessions.

## Start and launch

```bash
$desktop --session brevlada-check start --size 1600x1000
$desktop --session brevlada-check launch --cwd /absolute/project -- /absolute/path/to/gui-diagnostic
$desktop --session brevlada-check run --cwd /absolute/project --timeout 90 -- /absolute/path/to/finite-test
```

Always supply the intended absolute working directory. Arguments after `--` run directly, without a shell. `launch` returns the PID and log immediately. `run` waits for the exit code and cleans up remaining processes in that application's owned group; a timeout returns 124. Both write application output to the reported log.

`start` is idempotent for a healthy session and reports its existing size and renderer. Stop and start again to change them. Give concurrent tasks distinct names when they need independent focus or pointer control.

Software rendering is the default (`GSK_RENDERER=cairo`, `LIBGL_ALWAYS_SOFTWARE=1`, WebKit DMA-BUF disabled). Use `start --render native` for a test that needs native rendering, then verify the application's renderer log. Xvfb alone does not prove GPU acceleration. Do not claim performance or production theme fidelity from the software session: settings are in memory, accessibility integration is disabled, and the private bus has no desktop service activation directories. Notification, portal, autostart, or GNOME Shell integration needs a separate nested desktop or controlled test environment; do not test it through the user's session bus.

Pass application-specific variables explicitly:

```bash
$desktop --session brevlada-check run --cwd /var/home/kitkat/Projects/Gnome/brevlada --env LD_LIBRARY_PATH=/var/home/kitkat/Projects/Gnome/brevlada/.native/usr/lib64 --timeout 90 -- /absolute/path/to/gui-diagnostic
```

Display, bus, runtime, and toolkit backend overrides are rejected. Respect each repository's launch restrictions: when diagnostics are required, launch a diagnostic rather than the real application.

## Inspect and interact

```bash
$desktop --session brevlada-check windows
$desktop --session brevlada-check screenshot /var/home/kitkat/.cache/agent-desktops/brevlada-check/desktop.png
$desktop --session brevlada-check input -- windowactivate --sync WINDOW_ID
$desktop --session brevlada-check input -- mousemove 430 480 click 1
$desktop --session brevlada-check input -- key ctrl+a
$desktop --session brevlada-check input -- type --clearmodifiers 'test text'
$desktop --session brevlada-check input -- keydown w sleep 0.7 keyup w
```

Use a real window ID from `windows`, which prints IDs and titles. Inspect a screenshot with the local image-viewing tool before choosing coordinates. Coordinates refer to the full private desktop, including decorations. `screenshot --window WINDOW_ID PATH` captures just that window and has a different coordinate origin.

After input, inspect a fresh screenshot or application state to verify the result. Release held keys and mouse buttons even on failure. Keep all input and capture commands scoped through this helper. Never run bare `xdotool` or capture against the inherited `DISPLAY`; tools outside the wrapper cannot reach its private filesystem sockets; selecting a display number alone is insufficient.

`env` refuses to export a usable GUI environment: environment variables alone cannot enter the private mount namespace. Launch every external tool through `run` or `launch`; their child processes inherit the private `/tmp` automatically.

## Isolation boundaries and cleanup

The host and Toolbx can share `/tmp/.X11-unix` and the network namespace. Never
use Xvfb `-displayfd`: automatic selection disables the usual server lock and
probes from display 0; Unix listener creation can unlink an existing socket.
This risk also exists when the PID namespace is shared. The helper uses both
independent layers:

- Bubblewrap mounts a session-owned directory over `/tmp` for Xvfb and every GUI
  command. Server socket and lock creation/removal stays in that private directory.
- Explicit display numbers start at 100, under a shared allocation lock; occupied
  filesystem sockets, symlinks, PID locks, and abstract addresses are skipped.
  Xvfb's abstract listener is disabled, and a foreign abstract listener causes
  subsequent operations to fail closed.

Before starting, the helper records the identities of existing host X11 endpoints.
It also checks from inside Bubblewrap that `/tmp` and `/tmp/.X11-unix` have the
expected private directory identities and that the mount namespace differs from
the caller's, before any display server is launched.
It checks those identities before GUI work and after cleanup. It never repairs or
removes a foreign endpoint automatically. Legacy sessions without private mount
isolation must be stopped by name before reuse. A private D-Bus session or high
display number alone is insufficient. If Bubblewrap or another isolation step
fails, repair it; never run the GUI command outside the wrapper.

The display and input are private; home files, network access, hardware capacity, and application profiles are shared. Use fixtures and an application-specific temporary profile/data directory when necessary. Browsers and other singleton applications need their documented separate-profile option so they cannot forward requests to an existing user instance. Do not modify real mail/account data during diagnostics. Coordinate expensive GPU work and simultaneous imports of the same project.

```bash
$desktop --session brevlada-check status
$desktop --session brevlada-check stop --app APPLICATION_PID
$desktop --session brevlada-check stop
```

Prefer ordinary close/quit UI when an application needs to save work. `stop --app` accepts only a recorded application PID. `stop` terminates this session's application groups and display services, checking PID start times and owned group markers to avoid killing reused PIDs. It retains logs and screenshots. Stop sessions after testing. Never use broad `pkill`, remove other display sockets, stop another task's session, or kill/restart the user's application.

## Dependencies and verification

Required container-local tools: Python 3, `bwrap`, `Xvfb`, `openbox`, `xdpyinfo`, `xprop`, `xdotool`, ImageMagick `import`, and `dbus-daemon`. `xauth` is useful for inspecting cookies; the helper writes its own private Xauthority file. Missing executables are reported before startup.

Dependencies are installed in `dev`. If the container is rebuilt, install them in that container, never layer them onto the immutable host just for GUI testing:

```bash
podman exec --user root dev /usr/bin/dnf install -y bubblewrap xorg-x11-server-Xvfb xorg-x11-xauth xdpyinfo xprop xdotool openbox ImageMagick dbus-daemon
```

Verified on this machine: separate concurrent displays; private X11 authentication and D-Bus; GTK window screenshots; real typing and mouse click with visible result; Brevlada's GTK/WebKit viewer diagnostics; timeout and orphan-process cleanup; rejection of foreign application PIDs and backend overrides. Recheck the relevant visible behavior for each task. A working helper is not proof that an application test passed.

Validate actual GUI launch, input, and capture and preserve host socket identities
whenever the wrapper changes.
