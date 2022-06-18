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
  <p>Powerlevel 10K</p>
</h2>

<h3 align="center">
  <p>Description</p>
</h3>

Powerlevel 10K is a theme for ZSH shell

<h3 align="center">
  <p>Usage</p>
</h3>

Download config to the home directory
```
wget -O ~/.p10k.zsh https://raw.githubusercontent.com/ExposedCat/dotfiles/main/zsh/.p10k.zsh
```

<h2 align="center">
  <p>Flameshot</p>
</h2>

<h3 align="center">
  <p>Description</p>
</h3>

Flameshot is a nice screenshot tool

<h3 align="center">
  <p>Usage</p>
</h3>

1. Download config to the `~/.config/flameshot`:  
```
wget -O ~/.config/flameshot/flameshot.ini  https://raw.githubusercontent.com/ExposedCat/dotfiles/main/flameshot/flameshot.ini
```
2. Edit `savePath` option in `~/.config/flameshot/flameshot.ini`

<h2 align="center">
  <p>Neofetch</p>
</h2>

<h3 align="center">
  <p>Description</p>
</h3>

Neofetch is CLI image info display tool

<h3 align="center">
  <p>Usage</p>
</h3>

1. Download config to `~/.config/neofetch`  
```
wget -O ~/.config/neofetch/config.conf https://raw.githubusercontent.com/ExposedCat/dotfiles/main/neofetch/neofetch.conf
```
2. Download Bongo Cat ASCII to `~/.config/neofetch` 
```
wget -O ~/.config/neofetch/bongo.txt https://raw.githubusercontent.com/ExposedCat/dotfiles/main/neofetch/bongo.txt
```
3. Add alias to execute neofetch with custom ASCII (done in ZSH shell config in this repo)
```
alias neofetch="neofetch --ascii ~/.config/neofetch/bongo.txt"
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
  <p>Layout flags</p>
</h2>

<h3 align="center">
  <p>Description</p>
</h3>

Set flags as layout indicator names:
1. Russian (ru → 🇺🇦)
2. English (en → 🇨🇿)  
\* Please open an issue if you want other languages support
<h3 align="center">
  <p>Usage</p>
</h3>

Download file to `/usr/share/X11/xkb/rules`:  
```
sudo wget -O /usr/share/X11/xkb/rules/evdev.xml https://raw.githubusercontent.com/ExposedCat/stunning-gnome-de/main/os/evdev.xml
```

<h2 align="center">
  <p>Visual Studio Code</p>
</h2>

<h3 align="center">
  <p>Description</p>
</h3>

Visual Studio Code is free open-source code editor built for web development

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
wget -O ~/.config/Code/User/settings.json https://raw.githubusercontent.com/ExposedCat/dotfiles/main/vscode/tasks.json
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