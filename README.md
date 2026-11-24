# Dotfiles

Fedora Atomic workstation with a Hyprland and UWSM session, a Quickshell desktop,
and a Fedora `dev` Distrobox. The [package list](hyprland-packages.md) covers
host dependencies. The monitor and audio configuration is specific to this PC.

## Setup

Create the development container from the host if it does not exist:

```bash
./containers/dev/create
```

Run `./_scripts/load` to apply the desktop configuration, local app builds,
preferences, and host services. It applies Hyprland before the portal backend
and configures greetd last. Use `./_scripts/load --skip-auto-login` if you are
keeping GDM or have not booted into a deployment with greetd installed yet.

`./_scripts/dump` captures selected installed settings back into the checkout.
It stages all sources before updating files. Review `git diff` afterward.
Hyprland's source configuration is edited directly in `hyprland/config/`.

## Hyprland

```bash
./hyprland/manage install
./hyprland/manage check
./xdg-desktop-portal/manage install
./xdg-desktop-portal/manage check
```

**Install replaces `~/.config/hypr/`** with the managed configuration and native
helper, carrying forward the portal's generated `xdph.conf`. It validates the
staged configuration and restores the previous directory if the live reload
fails. The installer keeps the ten most recent full snapshots in
`~/.local/state/dotfiles/hyprland/backups/`.

```bash
./hyprland/manage backups
./hyprland/manage rollback           # Latest pre-install snapshot
./hyprland/manage rollback BACKUP_ID # Specific snapshot
```

The live reload uses the Hyprland session environment. Run the commands from
that session when applying changes to a running desktop.

| Shortcut | Action |
| --- | --- |
| `Super+Space` | Launcher |
| `Super+Return` | Ptyxis terminal |
| `Super+N` | Notification center |
| `Super+Shift+V` | Clipboard history |
| `Super+L` | Lock |
| `Print` / `Alt+Print` | Region / window screenshot |
| `Ctrl+Shift+Alt+R` | Screen recording |
| `Super+0` | Pick a screen color |

See the [full keybindings](hyprland/config/modules/keybindings.lua) and
[native helpers](hyprland/native/README.md). The portal uses Nautilus for file
selection and the custom Quickshell picker for sharing. Finish any active
portal requests or screen sharing before reinstalling it.

To share a region, select a monitor, enable **Region**, and click **Share**.
Drag on that monitor using the screenshot selector. Press any key except
Escape or click **Share** to confirm. Escape cancels the request.

## Auto-login and keyring

On the host, layer `greetd` and `greetd-selinux` with rpm-ostree and boot into
that deployment. Run `./services/login/manage install` and reboot to activate
Hyprland auto-login. After logout, greetd shows a text login prompt. Use
`./services/login/manage check` to verify the setup, or `revert` to select GDM
for the next boot.

For automatic oo7 keyring unlocking, run `./services/secrets/manage seal` and
enter the login keyring password. Run it again if that password changes.
`./services/secrets/manage check` verifies the oo7 and GNOME Online Accounts
service setup.

## Other entry points

| Path | Purpose |
| --- | --- |
| [App builds](apps/README.md) | Pinned Bazecor, OpenLogi, and `wl-screenrec` builds. The loader also sets Dokument as the PDF viewer. |
| [Ptyxis](ptyxis/manage) | Ptyxis preferences, Fish in the `dev` container, font fallback, and the default terminal for applications that use XDG terminal selection. |
| [Sleep](services/sleep/manage) | Deep sleep, wake diagnostics, and Logi Bolt wake rules. |
| [mDNS](services/mdns/manage) | Resolve `.local` hostnames. Use `check` to verify. |
| [Dev container](containers/dev/Containerfile) | Build dependencies and Fish. Rerun `containers/dev/setup-host-commands` inside `dev` if a package update replaces the Flatpak or `xdg-open` forwarding. |
| [Claude and Codex setup](claude/install) | Install repo skills and share the same skill directory between agents. |

Build output, local snapshots, and preview artifacts stay outside this checkout.
Use the [isolated GUI skill](codex/skills/isolated-gui/SKILL.md) for GUI checks.
