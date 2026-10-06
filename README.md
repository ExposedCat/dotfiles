<h1 align="center">
  <p>ExposedCat's dotfiles</p>
</h1>

<h2 align="center">
  <p>Fish shell</p>
</h2>

Fish configuration snippets stored in `fish/`:

1. Base shell settings
2. Catppuccin-inspired colors
3. Custom key bindings
4. App helper functions
5. Starship prompt setup
6. Volta PATH setup

<h3 align="center">
  <p>Usage</p>
</h3>

Copy the configs to `/etc/fish/conf.d`:

```bash
sudo wget -O /etc/fish/conf.d/config.fish https://raw.githubusercontent.com/ExposedCat/dotfiles/main/fish/config.fish
sudo wget -O /etc/fish/conf.d/colors.fish https://raw.githubusercontent.com/ExposedCat/dotfiles/main/fish/colors.fish
sudo wget -O /etc/fish/conf.d/keys.fish https://raw.githubusercontent.com/ExposedCat/dotfiles/main/fish/keys.fish
sudo wget -O /etc/fish/conf.d/apps.fish https://raw.githubusercontent.com/ExposedCat/dotfiles/main/fish/apps.fish
sudo wget -O /etc/fish/conf.d/starship.fish https://raw.githubusercontent.com/ExposedCat/dotfiles/main/fish/starship.fish
sudo wget -O /etc/fish/conf.d/volta.fish https://raw.githubusercontent.com/ExposedCat/dotfiles/main/fish/volta.fish
```

<h2 align="center">
  <p>Fastfetch</p>
</h2>

Fastfetch is a CLI tool to display PC info. This repo includes:

1. `config.jsonc` with the main module layout
2. `bongo.txt` ASCII art logo

<h3 align="center">
  <p>Usage</p>
</h3>

1. Create config directory if needed:

```bash
mkdir -p ~/.config/fastfetch
```

2. Download config:

```bash
wget -O ~/.config/fastfetch/config.jsonc https://raw.githubusercontent.com/ExposedCat/dotfiles/main/fastfetch/config.jsonc
wget -O ~/.config/fastfetch/bongo.txt https://raw.githubusercontent.com/ExposedCat/dotfiles/main/fastfetch/bongo.txt
```

<h2 align="center">
  <p>Logiops</p>
</h2>

Logiops is a driver for Logitech mice configuration. Config includes:

1. SmartShift
2. HiRes scroll
3. Volume control on gesture up/down
4. Brightness control on gesture left/right
5. Play/Pause on gesture click
6. Workspace switching on side forward/backward buttons
7. `Super` button emulation on DPI button click

<h3 align="center">
  <p>Usage</p>
</h3>

Copy the config file to `/etc`:

```bash
sudo wget -O /etc/logid.cfg https://raw.githubusercontent.com/ExposedCat/dotfiles/main/logiops/logid.cfg
```

Copy the resume fix script to `/etc/systemd/system-sleep/after-resume`:

```bash
sudo wget -O /etc/systemd/system-sleep/after-resume https://raw.githubusercontent.com/ExposedCat/dotfiles/main/logiops/resume-fix
sudo chmod +x /etc/systemd/system-sleep/after-resume
```

<h2 align="center">
  <p>System sleep</p>
</h2>

`services/sleep/` restricts normal systemd suspend to deep (S3) sleep using
`SuspendState=mem` and `MemorySleepMode=deep`. If that attempt fails, systemd
stops instead of trying the `freeze` / `s2idle` fallback. Requires systemd 256+
and hardware with deep sleep support; this is the configuration for the
TUF GAMING B650-PLUS desktop with AMD graphics.

On October 6, 2026, a pending wake event interrupted deep sleep. Both GPUs
recovered from that attempt, but the immediate `s2idle` fallback was rejected
by the integrated GPU and left the dedicated Radeon wedged. The original wake
device was not recorded. This configuration removes that fallback; it does not
guarantee recovery from every possible GPU or firmware fault.

The suspend service also enables kernel power-management debug messages and
records wake IRQ information, wake-source counters, suspend statistics, interrupt
mapping, and USB / ACPI wake settings before and after each attempt. Diagnostics
are saved in the system journal, time-limited to five seconds per hook, and
cannot block sleep on failure. Kernel PM debug messages remain enabled until
reboot (or until `/sys/power/pm_debug_messages` is set back to `0`).

<h3 align="center">
  <p>Usage</p>
</h3>

From the repository root:

```bash
./services/sleep/manage install
```

The helper installs the two configuration files under `/etc/systemd/` and the
executable under `/usr/local/sbin/`, restores SELinux labels when available, and
reloads systemd. It takes effect on the next sleep attempt without rebooting.
When run from Distrobox, it executes on the host and requests administrator
authentication there. Installation does not trigger sleep.

`_scripts/load` includes this installation. `_scripts/dump` calls
`./services/sleep/manage dump` to save the installed host files back to the repo.

After the next sleep attempt, inspect these logs on the host (use `-b -1`
instead of `-b` if you have rebooted since the attempt):

```bash
journalctl -b -u systemd-suspend.service
journalctl -b -k -g 'PM:|Wakeup|wakeup|amdgpu'
```

To remove this configuration, run on the host:

```bash
sudo rm /etc/systemd/sleep.conf.d/90-deep-only.conf \
    /etc/systemd/system/systemd-suspend.service.d/90-wake-diagnostics.conf \
    /usr/local/sbin/sleep-wake-diagnostics
sudo systemctl daemon-reload
echo 0 | sudo tee /sys/power/pm_debug_messages
```

<h2 align="center">
  <p>Audio outputs (WirePlumber)</p>
</h2>

Custom ALSA profiles keep HDMI / DisplayPort 5 on the OMEN monitor as the
only output on the Navi GPU and make the RØDE PodMic USB input-only. The
PodMic microphone remains available. Alternate GPU outputs, PodMic playback
ports, and the Pro Audio profiles for these two devices are hidden.

The rule targets GPU `alsa_card.pci-0000_03_00.1` and PodMic
`alsa_card.usb-R__DE_R__DE_PodMic_USB_973F4E9B-00`. On another machine, adjust
the device matches and HDMI mapping using `wpctl status` and `wpctl inspect`.
Other audio devices are unaffected. This uses WirePlumber 0.5 configuration
and PipeWire's user ALSA profile directory (verified with PipeWire 1.6.9).

<h3 align="center">
  <p>Usage</p>
</h3>

From the repository root, install both profiles before the rule, then reload:

```bash
mkdir -p ~/.config/alsa-card-profile/mixer/profile-sets ~/.config/wireplumber/wireplumber.conf.d
cp ./alsa-card-profile/mixer/profile-sets/{omen-hdmi5-only,podmic-input-only}.conf ~/.config/alsa-card-profile/mixer/profile-sets/ &&
    cp ./wireplumber/wireplumber.conf.d/51-audio-output-cleanup.conf ~/.config/wireplumber/wireplumber.conf.d/ &&
    systemctl --user restart wireplumber
```

The profile filenames resolve from `~/.config/alsa-card-profile/mixer/profile-sets/`,
so the rule contains no username or absolute home path. `_scripts/load` installs
these files; `_scripts/dump` saves them and normalizes any absolute profile paths.

To restore the available output choices:

```bash
rm ~/.config/wireplumber/wireplumber.conf.d/51-audio-output-cleanup.conf
systemctl --user restart wireplumber
```

<h2 align="center">
  <p>Visual Studio Code</p>
</h2>

Visual Studio Code user settings for editor, terminal profiles, formatting, and
Git behavior.

<h3 align="center">
  <p>Usage</p>
</h3>

1. Create settings directory if needed:

```bash
mkdir -p ~/.config/Code/User
```

2. Download config:

```bash
wget -O ~/.config/Code/User/settings.json https://raw.githubusercontent.com/ExposedCat/dotfiles/main/vscode/settings.json
```

<h2 align="center">
  <p>SystemD - Startup script</p>
</h2>

Runs `~/.startup.bash` on system startup. Script in repo includes:

1. Permissions for ASUS ScreenPad brightness controls
2. Setting ScreenPad brightness to maximum
3. Limiting battery charge to 80%

<h3 align="center">
  <p>Usage</p>
</h3>

1. Copy service to `/etc/systemd/system`:

```bash
sudo wget -O /etc/systemd/system/startup.service https://raw.githubusercontent.com/ExposedCat/dotfiles/main/services/startup/startup.service
```

2. Replace all `$USER` values in `/etc/systemd/system/startup.service` with your
   username
3. Copy script to your home directory:

```bash
wget -O ~/.startup.bash https://raw.githubusercontent.com/ExposedCat/dotfiles/main/services/startup/.startup.bash
```

4. Enable the service:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now startup
```

<h2 align="center">
  <p>Dev Container</p>
</h2>

Fedora-based dev container setup with:

1. Fish shell
2. Starship prompt
3. Node.js
4. Fastfetch
5. Visual Studio Code
6. Codex CLI
7. Deno
8. Godot Steam editor

<h3 align="center">
  <p>Usage</p>
</h3>

Build and create the distrobox:

```bash
./containers/dev/create
```

<h2 align="center">
  <p>GNOME Dev Container</p>
</h2>

Fedora distrobox for GNOME Shell development with:

1. `systemd`
2. `gnome-shell`
3. `mutter-devel`
4. `gettext`
5. `dbus-daemon`
6. `gnome-extensions-app`

<h3 align="center">
  <p>Usage</p>
</h3>

Create the distrobox:

```bash
./containers/gnome-dev/create
```

<h2 align="center">
  <p>Ramalama</p>
</h2>

Local `ramalama` inference service with:

1. Podman Compose setup
2. Vulkan backend
3. Model/image overrides through `.env`
4. Persistent model storage volume

<h3 align="center">
  <p>Usage</p>
</h3>

1. Move into the container directory:

```bash
cd containers/ramalama
```

2. Start the service:

```bash
podman compose up -d
```

3. Adjust `containers/ramalama/.env` if you want a different model or image
