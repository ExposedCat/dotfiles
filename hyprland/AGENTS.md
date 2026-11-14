# Hyprland workflow

After completing Hyprland or Quickshell configuration changes, apply them to the
user's current session with `./hyprland/manage install` from the repository root.
The user has requested this as the default; do not leave installation as a manual
follow-up or ask for confirmation each time. Check live configuration errors and
shell service health after applying.

The agent terminal may inherit GNOME settings even while Hyprland is running.
In that case, obtain the Hyprland session variables from the running
`dotfiles-hyprland-shell.service` environment, verify its instance signature
against `hyprctl instances -j`, and explicitly reload that session. The installer
skips its live reload when `HYPRLAND_INSTANCE_SIGNATURE` is absent.

Keep agent-owned GUI tests and automation on the isolated desktop as instructed
by the repository's GUI isolation policy.
