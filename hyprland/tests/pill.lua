-- Real Lua, fake compositor: never touches the user's keyboard or session.
local module_path = ...
local hooks, commands, timers, physical = {}, {}, {}, {}
hl = {
    on = function(event, callback) hooks[event] = callback end,
    timer = function(callback, spec)
        assert(spec.timeout == 200 and spec.type == "oneshot")
        table.insert(timers, callback)
    end,
    is_key_down = function(code) return physical[code] or false end,
    dispatch = function(command) table.insert(commands, command) end,
    dsp = { event = function(command) return command end },
}
local pill = assert(loadfile(module_path))()
local now = 1000
local function key(code, state, elapsed)
    now = now + (elapsed or 10)
    if state ~= 2 then physical[code] = state == 1 end
    hooks["input.keyboard.key"](code, now, state)
end
local function settle()
    local callbacks = timers; timers = {}
    for _, callback in ipairs(callbacks) do callback() end
end
local function hold()
    now = now + 210
    settle()
end
local function expect(...)
    local wanted = {...}
    assert(#commands == #wanted, "unexpected command count: " .. table.concat(commands, ", "))
    for i, action in ipairs(wanted) do
        assert(commands[i]:match("^dotfiles%-pill," .. action .. ",%d+$"), commands[i])
    end
    commands = {}
end
-- Tapping either key opens the launcher with no transient hide, even when a
-- timer from the completed tap expires later.
for _, code in ipairs({133, 134}) do
    key(code, 1); expect()
    key(code, 0); expect("tap")
    settle(); expect()
end
-- Only a sustained hold hides. Release restores through the same event stream.
key(133, 1); expect()
hold(); expect("hide")
key(133, 2); expect()
key(133, 0); expect("show")
-- Releasing Super before the other shortcut key must still restore.
key(133, 1); key(36, 1); hold(); expect("hide")
key(133, 0); expect("show")
key(36, 0); expect()
-- Quick keyboard and mouse shortcuts must not flash the pill or launch search.
key(50, 1); key(133, 1); expect()
key(133, 0); key(50, 0); settle(); expect("show")
key(133, 1); pill.cancel(); pill.cancel(); expect()
key(133, 0); settle(); expect("show")
-- With both Super keys held, only the final release restores.
key(133, 1); key(134, 1); hold(); expect("hide")
key(133, 0); expect()
key(134, 0); expect("show")
-- A timer from a previous tap cannot hide the next short tap.
key(133, 1); key(133, 0); key(133, 1); key(133, 0)
settle(); expect("tap", "tap")
-- A delayed hold timer cannot run after release.
key(133, 1); key(133, 0, 400); settle(); expect("show")
-- The compositor's actual key state prevents hiding after a lost release.
key(133, 1); physical[133] = false; settle(); expect()
key(133, 0, 400); expect("show")
-- Reloading while hidden restores the existing shell.
key(133, 1); hold(); expect("hide")
hooks["config.unload"](); expect("show")
key(133, 0); expect("show")
for _, panel in ipairs({"launcher", "power", "notifications"}) do
    key(133, 1); key(27, 1); pill.open(panel); expect()
    key(27, 0); key(133, 0); settle(); expect(panel)
end
print("Pill taps without flashes, sustained holds, ordered restoration, chords, both keys, and stale timers passed")
