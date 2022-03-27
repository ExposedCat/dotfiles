<h1 align="center">
  <p>ExposedCat's dotfiles</p>
</h1>

### zsh/.zshrc
#### Description
ZSH shell config:
1. Colors
2. ZSH settings
3. Plugins
4. Java PATH variables
5. Aliases for git, dnf and other utilites
#### Usage
Download file to `~`:  
```
wget https://raw.githubusercontent.com/ExposedCat/dotfiles/main/zsh/.zshrc 
mv .zshrc ~
```

### zsh/.p10k.zsh
#### Description
Powerlevel 10K ZSH theme config
#### Usage
Download file to `~`:  
```
wget https://raw.githubusercontent.com/ExposedCat/dotfiles/main/zsh/.p10k.zsh
mv .p10k.zsh ~
```

### flameshot/flameshot.ini
#### Description
Flameshot configuration
#### Usage
Download file to `~/.config`:  
```
wget https://raw.githubusercontent.com/ExposedCat/dotfiles/main/flameshot/flameshot.ini
mv flameshot.ini ~/.config/flameshot
```

### neofetch/neofetch.conf
#### Description
Neofetch configuration
#### Usage
Download file to `~/.config/neofetch`:  
```
wget https://raw.githubusercontent.com/ExposedCat/dotfiles/main/neofetch/neofetch.conf
mv neofetch.conf ~/.config/neofetch/config.conf
```

### logiops/logid.cfg
#### Description
Logiops driver configuration:
1. Smartshift
2. HiRes scroll
3. Volume control (gesture button ↑ ↓)
4. Brightness control (gesture button ← →)
5. Play/Pause (gesture button click)
6. Switch workspaces (side forward/backward buttons)
7. `Super` button emulation to open overview or app list (DPI button click)
#### Usage
Download file to `/etc`:  
```
wget https://raw.githubusercontent.com/ExposedCat/dotfiles/main/logiops/logid.cfg
sudo mv logid.cfg /etc
```

### os/evdev.xml
#### Description
Uppercase layout indicator names:
1. Russian (ru → RU)
2. English (en → EN)
#### Usage
Download file to `/usr/share/X11/xkb/rules`:  
```
wget https://raw.githubusercontent.com/ExposedCat/stunning-gnome-de/main/os/evdev.xml
sudo mv evdev.xml /usr/share/X11/xkb/rules
```

### vscode/settings.json
#### Description
VSCode extensions, look, editor and general settings
#### Usage
Download file to `~/.config/Code/User`:  
```
wget https://raw.githubusercontent.com/ExposedCat/dotfiles/main/vscode/settings.json
mv settings.json ~/.config/Code/User
```

### vscode/tasks.json
#### Description
VSCode tasks to compile & run/debug C/C++ files
#### Usage
Download file to `~/.config/Code/User`:  
```
wget https://raw.githubusercontent.com/ExposedCat/dotfiles/main/vscode/tasks.json
mv tasks.json ~/.config/Code/User
```