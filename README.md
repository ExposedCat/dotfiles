<h1 align="center">
  <p>ExposedCat's dotfiles</p>
</h1>

### configs/.zshrc
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
wget https://raw.githubusercontent.com/ExposedCat/dotfiles/main/configs/.zshrc 
mv .zshrc ~
```

### configs/.p10k.zsh
#### Description
Powerlevel 10K ZSH theme config
#### Usage
Download file to `~`:  
```
wget https://raw.githubusercontent.com/ExposedCat/dotfiles/main/configs/.p10k.zsh
mv .p10k.zsh ~
```

### configs/flameshot.ini
#### Description
Flameshot configuration
#### Usage
Download file to `~/.config`:  
```
wget https://raw.githubusercontent.com/ExposedCat/dotfiles/main/configs/flameshot.ini
mv flameshot.ini ~/.config/flameshot
```

### configs/neofetch.conf
#### Description
Neofetch configuration
#### Usage
Download file to `~/.config/neofetch`:  
```
wget https://raw.githubusercontent.com/ExposedCat/dotfiles/main/configs/neofetch.conf
mv neofetch.conf ~/.config/neofetch/config.conf
```

### configs/logid.cfg
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
wget https://raw.githubusercontent.com/ExposedCat/dotfiles/main/configs/logid.cfg
sudo mv logid.cfg /etc
```

### configs/evdev.xml
#### Description
Uppercase layout indicator names:
1. Russian (ru → RU)
2. English (en → EN)
#### Usage
Download file to `/usr/share/X11/xkb/rules`:  
```
wget https://raw.githubusercontent.com/ExposedCat/stunning-gnome-de/main/configs/evdev.xml
sudo mv evdev.xml /usr/share/X11/xkb/rules
```
