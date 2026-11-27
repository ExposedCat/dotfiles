# Desktop applications

The locally built apps section of [`_scripts/load`](../_scripts/load) pins and
installs the three packages below. Source checkouts live under
`${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/apps`.

| App | Source and installation |
| --- | --- |
| Bazecor | `Chipi-Chapa-Corp/Bazecor`, keys-configuration-qol branch. Build a user Flatpak bundle with the fork's Electron Forge recipe. See [Bazecor Flatpak](#bazecor-flatpak) for device access and profile migration. |
| OpenLogi | `Chipi-Chapa-Corp/OpenLogi`, branch `feat/gesture-repeat-with-sensitivity`: upstream PRs #2022 and #1245 adopted, plus configurable repeat distance submitted upstream as [#2551](https://github.com/AprilNEA/OpenLogi/pull/2551). Build CLI, desktop and agent together with Rust 1.99.0. Install a versioned directory and use the upstream systemd user unit with the local executable path and graphical session lifecycle. |
| wl-screenrec | Upstream v0.3.1. Build an RPM in the pinned Fedora 45 container against FFmpeg 9. Install through rpm-ostree if that package version is not already installed; a staged RPM takes effect at the next normal reboot. |

Builds run in the development Toolbox (`dev`, or `DOTFILES_BUILD_CONTAINER` when
invoked from the host). The container recipe includes native build dependencies.
wl-screenrec uses its own [Fedora 45 RPM recipe](wl-screenrec). Update the
expected RPM version or release in `_scripts/load` when changing that recipe.
Setting up OpenLogi's device rules can require administrator authentication.

## OpenLogi settings

OpenLogi's sensitivity and axis bias default to upstream behavior. Its repeat
distance defaults to 600 raw movement units. The hold gate, first-swipe travel
and repeat spacing are independent controls. This PC's mouse uses these fields
in its existing `[devices."..."]` table:

```toml
gesture_hold = 0
gesture_sensitivity = 100
gesture_axis_bias = 0
gesture_repeat_distance = 20
```

This removes the time gate and sets both initial travel and subsequent repeat
spacing to 20 raw units. Setup preserves existing device settings on subsequent
runs. Capture logs include `gesture_repeat_distance` to verify the runtime value.

## Bazecor Flatpak

The installer caches the bundle by source commit under
`${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/apps/bazecor/`.
The bundle points to Flathub for its runtime.

Bazecor checks for `/etc/udev/rules.d/60-dygma.rules` on startup and prompts
if it needs to install the rule. If the Flatpak cannot install it, Bazecor
shows the command to run on the host. The Flatpak uses the host rule to
access the keyboard and can read and write backups in `~/Dygma`.

On first install, the installer copies the existing Bazecor profile into
`~/.var/app/com.dygma.bazecor/config/Bazecor`. It archives the AppImage,
old menu entry and icon, Python wrapper, and extraction cache in an
`appimage-*/` directory alongside the cached bundle.

The original Wayland startup issue is tracked in
[Dygmalab/Bazecor#1064](https://github.com/Dygmalab/Bazecor/issues/1064).
