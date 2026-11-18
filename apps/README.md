# Locally built desktop applications

`./apps/manage install all` is included in `_scripts/load`. It clones the exact
commits in `sources.json`, builds them, and installs the results. Branch names
are recorded for context; setup never follows a moving branch or modifies the
working clones under `~/Projects`.

| App | Source and installation |
| --- | --- |
| Papers | `Chipi-Chapa-Corp/papers`, document-tabs branch. Build a user Flatpak with the pinned dependency manifest. Install it from `papers-local`, then remove the system Flathub copy without deleting application data. |
| Bazecor | `Chipi-Chapa-Corp/Bazecor`, keys-configuration-qol branch. Build a user Flatpak bundle with Electron Forge and the native Wayland startup fix. Import the existing profile on first install and archive the old AppImage setup. |
| OpenLogi | `Chipi-Chapa-Corp/OpenLogi`, branch `feat/gesture-repeat-with-sensitivity`: upstream PRs #2022 and #1245 adopted, plus configurable repeat distance submitted upstream as [#2551](https://github.com/AprilNEA/OpenLogi/pull/2551). Build CLI, desktop and agent together with Rust 1.99.0. Install a versioned directory and enable the agent for graphical sessions. Preserve and back up the existing configuration and mappings. |
| wl-screenrec | Upstream v0.3.1. Build an RPM in the pinned Fedora 45 container against FFmpeg 9. Install through rpm-ostree if that package version is not already installed; a staged RPM takes effect at the next normal reboot. |

Builds run in the development Toolbox (`dev`, or `DOTFILES_BUILD_CONTAINER` when
invoked from the host). The container recipe includes native build dependencies;
Papers uses the user Flatpak SDK, installed from Flathub when needed. wl-screenrec
uses its own Fedora 45 Podman build image. Host device rules may require normal
administrator authentication. LogiOps must remain stopped/masked when OpenLogi
owns the mouse; the OpenLogi device-rule installer masks its old service.

```sh
./apps/manage build papers
./apps/manage install bazecor
./apps/manage install openlogi
./apps/manage build wl-screenrec
./apps/manage check all
```

Sources, build output and installation records live under
`~/.local/state/dotfiles/apps/`. OpenLogi's reusable Cargo target directory is
`~/.cache/dotfiles-build/openlogi/target`. Updating a source requires editing its
full commit in `sources.json`; changing Papers dependencies also requires editing
`papers.json`. Builds are cached by source and recipe. Modified build sources are
preserved and reported instead of reset.

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
