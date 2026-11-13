-- Application windows and shell layers.
-- BEGIN dotfiles-portals
hl.window_rule({
    name = "desktop-portal-dialogs",
    match = { class = "org.quickshell", title = "^Desktop portal:.*$" },
    float = true,
    center = true,
    no_anim = true,
})
-- END dotfiles-portals
hl.layer_rule({
    name = "static-screen-corners",
    match = { namespace = "^dotfiles-screen-corners$" },
    no_anim = true,
})

-- Capture and recording masks must appear immediately, with no layer fade.
hl.layer_rule({
    name = "instant-capture-overlays",
    match = { namespace = "^dotfiles-(capture(-warmup)?|record-shade|record-status)$" },
    no_anim = true,
})

-- The banner items own their horizontal entrance/exit motion.
hl.layer_rule({
    name = "notification-banner-motion",
    match = { namespace = "^dotfiles-notifications$" },
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

local telegramClass = "^(org\\.telegram\\.desktop|telegram-desktop|TelegramDesktop)$"
local telegramViewer = "^(Media viewer|Просмотр медиа)$"

hl.window_rule({
    -- Keep ordinary app maximize requests from disrupting the tiled layout.
    -- Telegram's media viewer has its own fullscreen policy below.
    name  = "suppress-maximize-events",
    match = { class = "negative:" .. telegramClass },
    suppress_event = "maximize",
})
hl.window_rule({
    name = "suppress-telegram-main-maximize",
    match = { class = telegramClass, title = "negative:" .. telegramViewer },
    suppress_event = "maximize",
})

hl.window_rule({
    name = "telegram-media-viewer",
    match = { class = telegramClass, title = telegramViewer },
    float = true,
    -- Telegram clears its windowed-mode flag on a maximized configure, but not
    -- on a forced fullscreen configure. That flag disables click-to-close.
    -- Keep the monitor covered while giving Telegram its normal preview state.
    fullscreen_state = "2 1",
    sync_fullscreen = false,
    no_anim = true,
    -- Open fullscreen immediately, without a floating-size or pop-in transition.
    -- Ignore Qt's remembered output and maximize requests on the way to fullscreen.
    suppress_event = "maximize fullscreenoutput",
})

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
