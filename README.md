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
