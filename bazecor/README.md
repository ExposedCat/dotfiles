# Bazecor Flatpak

`./apps/manage install bazecor` builds the pinned fork as a user Flatpak
and installs its application-menu entry. The bundle stays under
`~/.local/state/dotfiles/apps/bazecor/` and points to Flathub for its runtime.
The build applies [the Flatpak patch](flatpak.patch) to a temporary checkout.
The Flatpak uses software rendering and shows the main window after the
renderer mounts the UI. It then requests a repaint for Wayland startup.

The installer checks `/etc/udev/rules.d/60-dygma.rules` and requests
administrator authentication if the rule needs to be installed or updated.
The Flatpak uses the host rule to access the keyboard and can read and write
backups in `~/Dygma`.

On first install, the installer copies the existing Bazecor profile into
`~/.var/app/com.dygma.bazecor/config/Bazecor`. It archives the AppImage,
old menu entry and icon, Python wrapper, and extraction cache under
`~/.local/state/dotfiles/apps/bazecor/appimage-*/`.

The original Wayland startup issue is tracked in
[Dygmalab/Bazecor#1064](https://github.com/Dygmalab/Bazecor/issues/1064).
