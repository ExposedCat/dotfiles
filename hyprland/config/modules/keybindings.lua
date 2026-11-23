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
hl.bind(mainMod .. " + CTRL + SHIFT + F", function() pill.open("visibility") end)
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

-- Keyboard workspace shortcuts, scoped to the focused monitor.
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

-- OpenLogi can send a wheel event from a side button. Hyprland keeps its
-- window drag active on wheel events, but ends it on key or button events.
local openLogiDevices = { "ol-action-injector", "ol-action-injector-1" }
local wheelSwitchPending = false
local grabbedWindow

local function windowBeingDragged()
    -- A tiled window becomes floating once the native move drag starts.
    if grabbedWindow and grabbedWindow.mapped and grabbedWindow.floating then
        return grabbedWindow
    end
end

for direction, wheel in pairs({ [-1] = "mouse_up", [1] = "mouse_down" }) do
    local function switchWorkspace()
        pill.cancel()
        workspaces.step(direction)
    end

    local function moveWorkspace(window)
        local cursor = hl.get_cursor_pos()
        pill.cancel()
        workspaces.step(direction, true, window)
        -- Moving and following a window can warp the cursor to its center.
        local current = hl.get_cursor_pos()
        if cursor and current and (cursor.x ~= current.x or cursor.y ~= current.y) then
            hl.dispatch(hl.dsp.cursor.move(cursor))
        end
    end

    local function switchWithWheel()
        if wheelSwitchPending then return end
        wheelSwitchPending = true
        hl.timer(function() wheelSwitchPending = false end, { timeout = 300, type = "oneshot" })
        local window = windowBeingDragged()
        if window then
            moveWorkspace(window)
        else
            switchWorkspace()
        end
    end

    hl.bind(mainMod .. " + " .. wheel, switchWithWheel, { device = { inclusive = false, list = openLogiDevices } })
    hl.bind(wheel, switchWorkspace, { device = { list = openLogiDevices } })
    hl.bind("SHIFT + " .. wheel, moveWorkspace, { device = { list = openLogiDevices } })
    hl.bind(mainMod .. " + " .. wheel, function()
        moveWorkspace(windowBeingDragged())
    end, { device = { list = openLogiDevices } })
end

-- Move/resize windows with mainMod + LMB/RMB and dragging
local function bindWindowMouse(button, action, movesWindow)
    local dragging, forwarded = false, false
    hl.bind(mainMod .. " + " .. button, function()
        -- The native dispatcher calls this binding again on release.
        if dragging then
            dragging = false
            grabbedWindow = nil
            hl.dispatch(action)
            return
        end
        pill.cancel()
        forwarded = pill.fullscreenPeekAtCursor()
        if forwarded then return { pass_event = true } end

        dragging = true
        local result = hl.dispatch(action)
        grabbedWindow = movesWindow and result.ok and not result.pass_event and hl.get_active_window() or nil
    end, { mouse = true })

    -- Replay short windowed clicks without Super. A press already delivered to
    -- the fullscreen overlay gets its physical release, even if Super is up.
    local press = hl.dsp.send_key_state({ mods = "", key = button, state = "down" })
    local release = hl.dsp.send_key_state({ mods = "", key = button, state = "up" })
    hl.bind(mainMod .. " + " .. button, function()
        if forwarded then return end
        hl.dispatch(press)
        hl.dispatch(release)
    end, { click = true, non_consuming = true })
end
bindWindowMouse("mouse:272", hl.dsp.window.drag(), true)
bindWindowMouse("mouse:273", hl.dsp.window.resize(), false)
hl.on("input.keyboard.key", function() grabbedWindow = nil end)

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
