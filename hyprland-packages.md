# Hyprland desktop packages

- hyprland
- hyprland-guiutils
- uwsm
- quickshell (0.3.2+; bar, notifications/history, Polkit, volume OSD, power menu)
- hyprlock
- hypridle (optional, unused; automatic locking is disabled)
- polkit
- ptyxis
- nautilus
- udisks2
- gvfs and gvfs-fuse (removable-media automount and file-manager volume discovery)
- gvfs-mtp, gvfs-gphoto2, gvfs-afc (phones and cameras)
- qalculate (launcher currencies, units, and advanced calculations)
- ibus (installed emoji/Unicode catalogs and native IBus API for launcher characters)
- xdg-user-dirs (screenshot directory)
- ddcutil (external-monitor brightness)
- qt6-qtwayland
- qt6-qtsvg
- MacTahoe-blue (reuse existing application icons)
- adwaita-icon-theme (folders, Places, and file types)
- hicolor-icon-theme (fallback)
- Lucide SVG assets (small shell controls and indicators)
- xdg-desktop-portal
- xdg-desktop-portal-hyprland
- xdg-desktop-portal-gtk
- xdg-desktop-portal-gnome (modern Nautilus file chooser)
- pipewire
- pipewire-utils (`pw-cli` for stopping screen sharing from the pill)
- pipewire-pulseaudio
- pulseaudio-utils (pactl, recording audio source discovery)
- wireplumber
- NetworkManager
- NetworkManager-wifi
- bluez
- upower
- tuned-ppd
- grim
- wl-screenrec
- ffmpeg (VA-API decode, scale/overlay and H.264/HEVC encode; libx264 for recording composition recovery)
- wl-clipboard
- cliphist
- gnome-online-accounts
- evolution-data-server (selected GNOME calendars and today's events)
- libgweather4 (saved GNOME Clocks locations)
- libsecret
- oo7-daemon
- pam_oo7

Custom desktop and portal helpers are Rust executables built from `hyprland/native/`.
Build dependencies live in the `dev` container: Rust 1.92+, a C compiler,
pkg-config, and GLib/GIO development headers. Python and PyGObject are needed
only for the repository’s isolated GUI and D-Bus test harnesses.
