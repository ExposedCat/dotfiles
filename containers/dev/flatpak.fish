# Keep build tools on the container's native Flatpak while terminal commands
# manage the desktop host's applications. Autoloading also covers open shells.
function flatpak --description 'Use host Flatpak interactively in Distrobox'
    if status is-interactive; and test -f /run/.containerenv
        command /usr/bin/distrobox-host-exec /usr/bin/flatpak $argv
    else
        command /usr/bin/flatpak $argv
    end
end
