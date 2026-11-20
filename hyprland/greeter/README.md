# Quickshell login screen

The greeter reuses the desktop's `PillTheme` and `PillBackground` components.
Its dedicated Hyprland config blurs the wallpaper behind the painted area of
the sign-in panel. Quickshell sends authentication requests to greetd and
launches the packaged UWSM Hyprland session after successful authentication.

For deployment, keep the relative layout of `greeter.qml`, `greeter/`, and
`config/shell/` in a system-owned directory readable by the greetd account. The shared files are
`PillTheme.qml`, `ShellTheme.qml`, `PillBackground.qml`, `ShellIcon.qml`, and
the icons used by the greeter. Use `greeter/start` as the greetd greeter
command. It requires the socket that greetd supplies.

- `DOTFILES_GREETER_WALLPAPER` is a wallpaper file readable before login.
- `DOTFILES_GREETER_USER` presets the account. An empty value opens the username field.
- `DOTFILES_GREETER_OUTPUT` selects the screen for the sign-in panel. The first available screen is the default.
