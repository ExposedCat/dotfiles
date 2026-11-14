-- Observe Super without consuming it, so existing shortcuts keep working.
-- Input keycodes use XKB numbering (evdev + 8), independent of EN/RU layout.
local down, super, used, hidden = {}, nil, false, false
local pending = nil
local pressedAt, generation = 0, 0
local holdDelay = 200
local function send(action, timestamp)
    -- Socket2 preserves order and does not spawn a process per transition.
    hl.dispatch(hl.dsp.event("dotfiles-pill," .. action .. "," .. tostring(timestamp or pressedAt)))
end
local function cancel()
    if super then used = true end
end
local function open(panel)
    if super then cancel(); pending = panel
    else send(panel) end
end
hl.on("input.keyboard.key", function(code, time, state)
    if state == 2 then return end
    if state == 1 then
        if down[code] then return end
        down[code] = true
        if code == 133 or code == 134 then
            if super then cancel(); return end
            super, used, hidden, pressedAt, pending = code, false, false, time, nil
            for key in pairs(down) do if key ~= code then used = true end end
            generation = generation + 1
            local current = generation
            hl.timer(function()
                if current == generation and super and (hl.is_key_down(133) or hl.is_key_down(134)) then
                    hidden = true
                    send("hide")
                end
            end, {timeout = holdDelay, type = "oneshot"})
        else cancel() end
    else
        down[code] = nil
        if code ~= super then return end
        if down[133] or down[134] then super = down[133] and 133 or 134; return end
        generation = generation + 1
        local duration = (time - pressedAt) % 4294967296
        if pending then send(pending, time)
        elseif not used and duration < holdDelay then send("tap", time)
        else send("show", time) end
        super, used, hidden, pending = nil, false, false, nil
    end
end)
hl.on("config.unload", function()
    if hidden then send("show", (pressedAt + 1) % 4294967296) end
end)
return { cancel = cancel, open = open }
