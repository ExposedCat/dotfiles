## Logitech advanced mice setup

1. Install <a href="https://github.com/PixlOne/logiops">logiops</a> driver
2. Run `sudo logid list` to find out your device name (for ex. `Wireless Mouse MX Master 3`)
3. Download `logid` config:  
   `sudo wget -d /etc https://raw.githubusercontent.com/ExposedCat/sightly-linux/main/logid.cfg`
4. Change your device name in `logid` config:  
   `sudo vim /etc/logid.cfg`
5. Install <a href="https://wiki.archlinux.org/title/IMWheel">IMWheel</a>
6. Download `IMWheel` config:  
   `wget -d ~ https://raw.githubusercontent.com/ExposedCat/sightly-linux/main/.imwheelrc`
7. Download `IMWheel` autostart service:  
   `wget -d ~/.config/systemd/user https://raw.githubusercontent.com/ExposedCat/sightly-linux/main/imwheel.service`
8. Enable and run `logid` daemon:  
   `sudo systemctl enable --now logid`
9. Enable and run `IMWheel` autostart service:  
   `systemctl --user enable --now imwheel`
