-- A standalone compositor for the greetd account.
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = "auto" })

hl.config({
    animations = { enabled = false },
    decoration = {
        blur = { enabled = true, size = 12, passes = 3, vibrancy = 0.1696 },
    },
    misc = { disable_hyprland_logo = true, force_default_wallpaper = 0 },
    xwayland = { enabled = false },
})

hl.layer_rule({
    name = "greeter-pill-glass",
    match = { namespace = "^dotfiles-greeter-login$" },
    blur = true,
    ignore_alpha = 0.2,
    no_anim = true,
})

hl.on("hyprland.start", function()
    hl.exec_cmd([[
        quickshell --path "$DOTFILES_GREETER_DIR/../greeter.qml"
        hyprctl dispatch 'hl.dsp.exit()'
    ]])
end)
