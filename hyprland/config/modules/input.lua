-- Keyboard, mouse, and touchpad settings.
hl.config({
    input = {
        kb_layout  = "us,ru",
        kb_variant = "",
        kb_model   = "",
        -- Caps switches layouts; Shift+Caps toggles normal Caps Lock.
        kb_options = "grp:caps_toggle",
        kb_rules   = "",

        -- Hover and scroll follow the pointer; keyboard focus changes on click.
        follow_mouse = 2,
        float_switch_override_focus = 0,

        sensitivity = 0, -- -1.0 - 1.0, 0 means no modification.

        touchpad = {
            natural_scroll = false,
        },
    },
})

hl.gesture({
    fingers = 3,
    direction = "horizontal",
    action = "workspace"
})
