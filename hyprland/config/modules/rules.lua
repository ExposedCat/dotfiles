-- Window rules inherited from the packaged configuration.
-- Capture and recording masks must appear immediately, with no layer fade.
hl.layer_rule({
    name = "instant-capture-overlays",
    match = { namespace = "^dotfiles-(capture|record-shade|record-status)$" },
    no_anim = true,
})

hl.window_rule({
    name = "app-launcher",
    match = { class = "org.quickshell", title = "Applications" },
    float = true,
    center = true,
})

hl.window_rule({
    name = "clipboard-picker",
    match = { class = "org.quickshell", title = "Clipboard history" },
    float = true,
    center = true,
})

local suppressMaximizeRule = hl.window_rule({
    -- Ignore maximize requests from all apps. You'll probably like this.
    name  = "suppress-maximize-events",
    match = { class = ".*" },

    suppress_event = "maximize",
})
-- suppressMaximizeRule:set_enabled(false)

hl.window_rule({
    -- Fix some dragging issues with XWayland
    name  = "fix-xwayland-drags",
    match = {
        class      = "^$",
        title      = "^$",
        xwayland   = true,
        float      = true,
        fullscreen = false,
        pin        = false,
    },

    no_focus = true,
})

-- Layer rules also return a handle.
-- local overlayLayerRule = hl.layer_rule({
--     name  = "no-anim-overlay",
--     match = { namespace = "^my-overlay$" },
--     no_anim = true,
-- })
-- overlayLayerRule:set_enabled(false)
