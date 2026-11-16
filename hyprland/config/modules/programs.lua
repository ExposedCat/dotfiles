-- Keep shell quoting in one place for paths used by command keybindings.
local function quote(value)
    return "'" .. value:gsub("'", "'\\''") .. "'"
end
local configHome = os.getenv("XDG_CONFIG_HOME") or (os.getenv("HOME") .. "/.config")
local helper = quote(configHome .. "/hypr/bin/dotfiles-desktop") .. " desktop"
return {
    terminal = "uwsm app -- ptyxis --new-window",
    fileManager = "uwsm app -- nautilus --new-window",
    menu = helper .. " launcher",
    helper = helper,
    capture = quote(configHome .. "/hypr/bin/dotfiles-desktop") .. " capture",
}
