#! /bin/bash

# Allow to modify brightness of ScreenPad
sudo chmod a+w '/sys/class/leds/asus::screenpad/brightness'
# Set  maximal brightness of ScreenPad
screenpad 9
# Limit battery charge to 80%
echo 81 | sudo tee -a /sys/class/power_supply/BAT0/charge_control_end_threshold
