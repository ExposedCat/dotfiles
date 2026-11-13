Bazecor 1.11.0 bundles Electron 34 and defaults to Xwayland. Its native Wayland
startup can also leave the main window hidden while waiting for `ready-to-show`.
The wrapper selects Wayland and makes the main window visible at creation.

Install after integrating `~/AppImages/bazecor.appimage` into the application menu:

```bash
python3 bazecor/launch.py install
```

This backs up the desktop entry under `~/.local/state/dotfiles/bazecor`, installs
the wrapper under `~/.local/libexec`, and prepares a cached extracted copy. The
original AppImage and keyboard configuration are preserved. The cache follows
the AppImage's content hash; an updated image is extracted again. Unknown startup
code produces an error so the patch can be reviewed for that version.
Startup output is saved to `~/.local/state/dotfiles/bazecor/startup.log` so a
failed menu launch has a readable error log.

The related upstream startup report is
[Dygmalab/Bazecor#1064](https://github.com/Dygmalab/Bazecor/issues/1064).
