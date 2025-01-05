<h1 align="center">
  <p>ExposedCat's dotfiles</p>
</h1>

<h2 align="center">
  <p>Zsh shell</p>
</h2>

<h3 align="center">
  <p>Description</p>
</h3>

1. ZSH settings
2. Plugins
3. Java PATH variables
4. Aliases for git, dnf and other utilites
5. Move to trash

<h3 align="center">
  <p>Usage</p>
</h3>

1. Install [Oh My Zsh](https://ohmyz.sh/)
2. Install [syntax highlighting plugin](https://github.com/zsh-users/zsh-syntax-highlighting/blob/master/INSTALL.md)
3. Download config to the home directory
```
wget -O ~/.zshrc https://raw.githubusercontent.com/ExposedCat/dotfiles/main/zsh/.zshrc
```

<h2 align="center">
  <p>FireArc <sup>BETA</sup></p>
</h2>

<h3 align="center">
  <p>Description</p>
</h3>

FireArc is a Firefox theme that brings Arc Browser UI without extensions

<h3 align="center">
  <p>Usage</p>
</h3>

1. Go to `about:config` in Firefox
2. Set `sidebar.revamp` to `true`
3. Set `sidebar.verticalTabs` to `true`
4. Set `toolkit.legacyUserProfileCustomizations.stylesheets` to `true`
5. Open "Configure Sidebar" at the bottom. Disable everything, select "Open on Click", select Right positioning
6. Go to the `about:support` in Firefox and copy path under `Profile Directory`. If you use Flatpak, the base path will be `~/.var/app/org.mozilla.firefox/.mozilla/firefox/`
7. Download configs (replace your `PATH_FROM_STEP_1`):
```
wget -O PATH_FROM_STEP_1 https://raw.githubusercontent.com/ExposedCat/dotfiles/main/firefox/arclike.css
wget -O PATH_FROM_STEP_1 https://raw.githubusercontent.com/ExposedCat/dotfiles/main/firefox/userChrome.css
```
8. Restart Firefox

<h2 align="center">
  <p>Fastfetch</p>
</h2>

<h3 align="center">
  <p>Description</p>
</h3>

Fastfetch is CLI tool to display PC info

<h3 align="center">
  <p>Usage</p>
</h3>

1. Download config to `~/.config/fastfetch`
```
wget -O ~/.config/fastfetch/config.jsonc https://raw.githubusercontent.com/ExposedCat/dotfiles/main/fastfetch/config.jsonc
```
2. Download Bongo Cat ASCII to `~/.config/fastfetch`
```
wget -O ~/.config/fastfetch/bongo.txt https://raw.githubusercontent.com/ExposedCat/dotfiles/main/fastfetch/bongo.txt
```

<h2 align="center">
  <p>Logiops</p>
</h2>

<h3 align="center">
  <p>Description</p>
</h3>

Logiops is a driver for Logitech™ mice configuration. Config includes:
1. Smartshift
2. HiRes scroll
3. Volume control (gesture button ↑ ↓)
4. Brightness control (gesture button ← →)
5. Play/Pause (gesture button click)
6. Switch workspaces (side forward/backward buttons)
7. `Super` button emulation to open overview or app list (DPI button click)

<h3 align="center">
  <p>Usage</p>
</h3>

Download file to `/etc`:
```
sudo wget -O /etc/logid.cfg https://raw.githubusercontent.com/ExposedCat/dotfiles/main/logiops/logid.cfg
```

<h2 align="center">
  <p>Uppercase layouts</p>
</h2>

<h3 align="center">
  <p>Description</p>
</h3>

Use uppercase layout indicator names:
1. English (en → EN)
2. Ukrainian (uk → UK)
2. Russian (ru → RU)
\* Please open an issue if you want other languages support
<h3 align="center">
  <p>Usage</p>
</h3>

Download file to `/usr/share/X11/xkb/rules`:
```
sudo wget -O /usr/share/X11/xkb/rules/evdev.xml https://raw.githubusercontent.com/ExposedCat/dotfiles/main/os/evdev.xml
```

<h2 align="center">
  <p>Visual Studio Code</p>
</h2>

<h3 align="center">
  <p>Description</p>
</h3>

Visual Studio Code is a free open-source* code editor built for web development

*Microsoft provides builds with telemetry. Consider using VSCodium for builds from sources

<h3 align="center">
  <p>Usage</p>
</h3>

1. Download [Visual Studio Code](https://code.visualstudio.com/download)
2. Download config to `~/.config/Code/User`:
```
wget -O ~/.config/Code/User/settings.json https://raw.githubusercontent.com/ExposedCat/dotfiles/main/vscode/settings.json
```

<h2 align="center">
  <p>VS Code - C++ Tasks</p>
</h2>

<h3 align="center">
  <p>Description</p>
</h3>

Visual Studio Code tasks to compile and run/debug C/C++ files

<h3 align="center">
  <p>Usage</p>
</h3>

1. Download [Visual Studio Code](https://code.visualstudio.com/download)
2. Download config to `~/.config/Code/User`:
```
wget -O ~/.config/Code/User/tasks.json https://raw.githubusercontent.com/ExposedCat/dotfiles/main/vscode/tasks.json
```
<h2 align="center">
  <p>SystemD - Startup script</p>
</h2>

<h3 align="center">
  <p>Description</p>
</h3>

Runs `~/.startup.bash` on system startup. Script in repo includes:
1. Rights for ASUS ScreenPad+ brightness controls (requires [kernel module](https://github.com/Plippo/asus-wmi-screenpad) by [Plippo](https://github.com/Plippo))
2. Setting ASUS ScreenPad+ brightness to maximum (requires [screenpad tool](https://github.com/Plippo/screenpad-tools) by [Plippo](https://github.com/Plippo) + see prev. paragraph)
3. Stop charging laptops battery on 80%

<h3 align="center">
  <p>Usage</p>
</h3>

1. Download service to `/etc/systemd/system`:
```
wget -O /etc/systemd/system/startup.service https://raw.githubusercontent.com/ExposedCat/dotfiles/main/services/startup/startup.service
```
2. Replace all `$USER` with your username in `/etc/systemd/system/startup.service`
2. Download script to the home directory:
```
wget -O ~ https://raw.githubusercontent.com/ExposedCat/dotfiles/main/services/startup/.startup.bash
```
<h2 align="center">
  <p>GNOME Terminal config</p>
</h2>

<h3 align="center">
  <p>Description</p>
</h3>

Monokai profile for GNOME Terminal

<h3 align="center">
  <p>Usage</p>
</h3>

0. [Install monospace Nerd font](https://github.com/ExposedCat/stunning-gnome-de/tree/lo-fi#assetsjetbrainsmonospacettf) for text icons in terminal
1. Download file:
```
wget https://raw.githubusercontent.com/ExposedCat/dotfiles/gnome-terminal/terminal.conf
```
2. Load configuration:
```
dconf load /org/gnome/terminal/ < ./terminal.conf
```
3. \[Optional] Remove config:
```
rm terminal.conf
```
