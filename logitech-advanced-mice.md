## Logitech advanced mice setup

1. Install <a href="https://github.com/PixlOne/logiops">logiops</a> driver
2. Run `sudo logid list` to find out your device name (for ex. `Wireless Mouse MX Master 3`)
3. Download `logiops` config:  
   `sudo wget -d /etc https://raw.githubusercontent.com/ExposedCat/sightly-linux/main/configs/logid.cfg`
4. Change your device name in `logiops` config:  
   `sudo vim /etc/logid.cfg`
5. Install <a href="https://wiki.archlinux.org/title/IMWheel">IMWheel</a>
6. Download `IMWheel` config:  
   `wget -d ~ https://raw.githubusercontent.com/ExposedCat/sightly-linux/main/configs/.imwheelrc`
7. Enable and run `logiops` daemon:  
   `sudo systemctl enable --now logid`
8. Run IMWheel:  
   `imwheel`
   
P.S. You need to run `imwheel` at system startup. For X11 use <a href="https://github.com/ExposedCat/sightly-linux/blob/main/configs/imwheel.service">IMWheel startup systemd service</a>
