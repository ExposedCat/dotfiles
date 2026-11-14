-- Everyday controls. Super+V remains the existing floating-window shortcut.
local programs = require("modules.programs")
local terminal = programs.terminal
local fileManager = programs.fileManager
local helper = programs.helper
local capture = programs.capture
local workspaces = require("modules.workspaces")
local pill = require("modules.pill")

local mainMod = "SUPER" -- Sets "Windows" key as main modifier

-- Example binds, see https://wiki.hypr.land/configuring/core/binds/ for more
hl.bind(mainMod .. " + Return", hl.dsp.exec_cmd(terminal))
hl.bind(mainMod .. " + Q", hl.dsp.window.close())
hl.bind(mainMod .. " + F", hl.dsp.window.fullscreen({ action = "toggle", mode = "fullscreen" }))
hl.bind(mainMod .. " + M", function() pill.open("power") end)
hl.bind(mainMod .. " + N", function() pill.open("notifications") end)
hl.bind(mainMod .. " + E", hl.dsp.exec_cmd(fileManager))
hl.bind(mainMod .. " + V", hl.dsp.window.float({ action = "toggle" }))
hl.bind(mainMod .. " + R", function() pill.open("launcher") end)
hl.bind(mainMod .. " + space", function() pill.open("launcher") end)
hl.bind(mainMod .. " + L", hl.dsp.exec_cmd(helper .. " lock"))
hl.bind(mainMod .. " + SHIFT + V", hl.dsp.exec_cmd(helper .. " clipboard"))
hl.bind("Print", hl.dsp.exec_cmd(capture .. " select region"))
hl.bind("ALT + Print", hl.dsp.exec_cmd(capture .. " select window"))
hl.bind("CTRL + SHIFT + ALT + R", hl.dsp.exec_cmd(capture .. " select record"))
hl.bind(mainMod .. " + P", hl.dsp.window.pseudo())
hl.bind(mainMod .. " + J", hl.dsp.layout("togglesplit"))    -- dwindle only

-- Move focus with mainMod + arrow keys
hl.bind(mainMod .. " + left",  hl.dsp.focus({ direction = "left" }))
hl.bind(mainMod .. " + right", hl.dsp.focus({ direction = "right" }))
hl.bind(mainMod .. " + up",    hl.dsp.focus({ direction = "up" }))
hl.bind(mainMod .. " + down",  hl.dsp.focus({ direction = "down" }))

-- GNOME shortcuts, scoped to the focused monitor. Logitech side buttons
-- emit Ctrl+Alt+Left/Right as well.
hl.bind("SUPER + Page_Up", function() workspaces.step(-1) end)
hl.bind("SUPER + Page_Down", function() workspaces.step(1) end)
hl.bind("CTRL + ALT + left", function() workspaces.step(-1) end)
hl.bind("CTRL + ALT + right", function() workspaces.step(1) end)
hl.bind("SUPER + SHIFT + Page_Up", function() workspaces.step(-1, true) end)
hl.bind("SUPER + SHIFT + Page_Down", function() workspaces.step(1, true) end)
hl.bind("CTRL + ALT + SHIFT + left", function() workspaces.step(-1, true) end)
hl.bind("CTRL + ALT + SHIFT + right", function() workspaces.step(1, true) end)

-- Switch workspaces with mainMod + [0-9]
-- Move active window to a workspace with mainMod + SHIFT + [0-9]
for i = 1, 10 do
    local key = i % 10 -- 10 maps to key 0
    hl.bind(mainMod .. " + " .. key, function() workspaces.select(i) end)
    hl.bind(mainMod .. " + SHIFT + " .. key, function() workspaces.select(i, true) end)
end

-- Example special workspace (scratchpad)
hl.bind(mainMod .. " + S",         hl.dsp.workspace.toggle_special("magic"))
hl.bind(mainMod .. " + SHIFT + S", hl.dsp.window.move({ workspace = "special:magic" }))

-- Scroll through existing workspaces with mainMod + scroll
hl.bind(mainMod .. " + mouse_down", function() pill.cancel(); workspaces.step(1) end)
hl.bind(mainMod .. " + mouse_up", function() pill.cancel(); workspaces.step(-1) end)

-- Move/resize windows with mainMod + LMB/RMB and dragging
hl.bind(mainMod .. " + mouse:272", function() pill.cancel(); hl.dispatch(hl.dsp.window.drag()) end, { mouse = true })
hl.bind(mainMod .. " + mouse:273", function() pill.cancel(); hl.dispatch(hl.dsp.window.resize()) end, { mouse = true })
-- A release within drag_threshold is an ordinary app click, without Super.
-- Send both states here: click binds run after the physical button is released.
for _, button in ipairs({ "mouse:272", "mouse:273" }) do
    local press = hl.dsp.send_key_state({ mods = "", key = button, state = "down" })
    local release = hl.dsp.send_key_state({ mods = "", key = button, state = "up" })
    hl.bind(mainMod .. " + " .. button, function()
        hl.dispatch(press)
        hl.dispatch(release)
    end, { click = true })
end

-- Audio and external-monitor brightness (DDC/CI on the focused display).
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"), { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),      { locked = true, repeating = true })
hl.bind("XF86AudioMute",        hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),     { locked = true, repeating = true })
hl.bind("XF86AudioMicMute",     hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"),   { locked = true, repeating = true })
hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd(helper .. " brightness up"), { repeating = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd(helper .. " brightness down"), { repeating = true })

-- Standard MPRIS control; prefer a currently playing application.
hl.bind("XF86AudioNext", hl.dsp.exec_cmd(helper .. " media Next"), { locked = true })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd(helper .. " media PlayPause"), { locked = true })
hl.bind("XF86AudioPlay", hl.dsp.exec_cmd(helper .. " media PlayPause"), { locked = true })
hl.bind("XF86AudioPrev", hl.dsp.exec_cmd(helper .. " media Previous"), { locked = true })
