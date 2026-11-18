# Bazecor Flatpak

`./apps/manage build bazecor` uses the pinned fork's unmodified Electron Forge
recipe. The bundle stays under `~/.local/state/dotfiles/apps/bazecor/` and points
to Flathub for its runtime. The recipe exports a menu entry. Its logo stays
inside the bundle, so desktop launchers may display their default icon.

`./apps/manage install bazecor` installs the bundle as a user Flatpak.

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
