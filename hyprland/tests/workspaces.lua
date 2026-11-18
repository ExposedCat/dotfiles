-- Run by test_workspaces.py with a real Lua runtime and a fake compositor.
local module_path = ...
local hooks, timers, state, monitors, applied, dispatched, animations, active_window, carry_timer
local getenv = os.getenv
os.getenv = function(key)
    if key == "WAYLAND_DISPLAY" then return "workspace-test" end
    return getenv(key)
end

local function emit(event, ...)
    if hooks[event] then hooks[event](...) end
end

local function activate(workspace)
    local previous = workspace.monitor.active_workspace
    if previous then previous.visible = false end
    if active_window.pinned and active_window.workspace == previous then
        active_window.workspace = workspace
    end
    workspace.visible = true
    workspace.monitor.active_workspace = workspace
    emit("workspace.active", workspace)
end

local function add(id, monitor, windows, visible, special)
    local workspace = {
        id = id, name = tostring(id), monitor = monitor, windows = windows or 0,
        visible = visible or false, special = special or false,
    }
    table.insert(state, workspace)
    if visible then monitor.active_workspace = workspace end
    return workspace
end

local function settle()
    for _ = 1, 30 do
        if #timers == 0 then return end
        local callbacks = timers
        timers = {}
        for _, callback in ipairs(callbacks) do callback() end
        -- Apply rules after Lua returns, like Hyprland's property refresher.
        for id, rule in pairs(applied) do
            local workspace
            for _, candidate in ipairs(state) do
                if candidate.id == id then workspace = candidate end
            end
            if rule.enabled and rule.persistent and not workspace then
                workspace = add(id, rule.monitor)
                emit("workspace.created")
            end
            if workspace then workspace.persistent = rule.enabled and rule.persistent end
        end
        for i = #state, 1, -1 do
            local workspace = state[i]
            if workspace.windows == 0 and not workspace.visible
                and not workspace.persistent and not workspace.special then
                table.remove(state, i)
                emit("workspace.removed")
            end
        end
    end
    error("workspace policy did not settle")
end

local function setup()
    hooks, timers, state, applied, dispatched = {}, {}, {}, {}, {}
    animations = {}
    carry_timer = nil
    monitors = {
        { name = "DP-1", enabled = true, x = 0, mode = { width = 1600 } },
        { name = "HDMI-1", enabled = true, x = 1600, mode = { width = 1600 } },
    }
    hl = {
        animation = function(spec) animations[spec.leaf] = spec.style end,
        on = function(event, callback) hooks[event] = callback end,
        timer = function(callback, spec)
            if spec.timeout == 30 then
                table.insert(timers, callback)
                return
            end
            local timer = { timeout = spec.timeout, enabled = true }
            function timer:set_enabled(enabled) self.enabled = enabled end
            function timer:set_timeout(timeout) self.timeout = timeout end
            function timer:fire() if self.enabled then callback() end end
            carry_timer = timer
            return timer
        end,
        get_monitors = function() return monitors end,
        get_workspaces = function() return state end,
        get_active_monitor = function() return monitors.focused or monitors[1] end,
        get_active_window = function() return active_window end,
        workspace_rule = function(spec)
            local rule = { persistent = spec.persistent, enabled = true }
            for _, monitor in ipairs(monitors) do
                if monitor.name == spec.monitor then rule.monitor = monitor end
            end
            function rule:set_enabled(enabled) self.enabled = enabled end
            applied[tonumber(spec.workspace)] = rule
            return rule
        end,
        dispatch = function(command)
            table.insert(dispatched, command)
            command.style = animations.workspacesIn
            assert(animations.workspacesOut == command.style, "the entry and exit slides must match")
            if command.action ~= "move" then
                assert(command.style == "slide", "ordinary workspace switches must use the full slide")
            end
            if command.action == "renumber" then
                local target
                for _, workspace in ipairs(state) do
                    assert(workspace.id ~= command.id, "renumbering must not collide with another workspace")
                    if workspace.id == command.from then target = workspace end
                end
                assert(target, "renumbering must keep the existing workspace object")
                target.id, target.name = command.id, tostring(command.id)
                emit("workspace.renamed")
            elseif command.action == "pin" then
                assert(command.window.floating, "only floating windows can be pinned")
                command.window.pinned = command.enable
            elseif command.action == "float" then
                command.window.floating = command.enable
                command.window.pinned = false
                if command.enable then
                    command.window.at = { x = 100, y = 100 }
                    command.window.size = { x = 500, y = 400 }
                end
            elseif command.action == "position" then
                command.window.at = { x = command.x, y = command.y }
            elseif command.action == "resize" then
                command.window.size = { x = command.x, y = command.y }
            elseif command.action == "focus" or command.action == "move" then
                for _, workspace in ipairs(state) do
                    if workspace.id == command.id then
                        if command.action == "move" then
                            command.window.workspace = workspace
                            command.pinned = command.window.pinned
                        end
                        if command.follow ~= false then activate(workspace) end
                        break
                    end
                end
            end
        end,
        dsp = {
            workspace = { change_id = function(spec) return { action = "renumber", from = spec.workspace, id = spec.id } end },
            focus = function(spec) return { action = "focus", id = spec.workspace } end,
            window = {
                move = function(spec)
                    return { action = spec.workspace and "move" or "position", id = spec.workspace,
                             window = spec.window, follow = spec.follow, x = spec.x, y = spec.y }
                end,
                float = function(spec) return { action = "float", window = spec.window, enable = spec.action == "set" } end,
                pin = function(spec) return { action = "pin", window = spec.window, enable = spec.action == "set" } end,
                resize = function(spec) return { action = "resize", window = spec.window, x = spec.x, y = spec.y } end,
            },
        },
    }
    active_window = { at = { x = 0, y = 0 }, size = { x = 1200, y = 800 }, fullscreen = 0,
                      mapped = true, monitor = monitors[1], workspace = add(1, monitors[1], 2, true) }
    add(2, monitors[2], 3, true)
    local policy = assert(loadfile(module_path))()
    emit("config.reloaded")
    settle()
    for _, command in ipairs(dispatched) do
        assert(command.action == "renumber", "setup must not switch focus or move windows")
    end
    dispatched = {}
    return policy
end

local function ids(policy, monitor)
    local result = {}
    for _, workspace in ipairs(policy.list(monitor)) do table.insert(result, workspace.id) end
    return table.concat(result, ",")
end

local function edges(policy, monitor, count)
    local list = policy.list(monitor)
    assert(#list == count, "unexpected number of workspaces: " .. ids(policy, monitor))
    assert(list[1].windows == 0 and list[#list].windows == 0, "both edges must be empty")
    for index = 2, #list do assert(list[index-1].id < list[index].id, "visual order and slide direction must agree") end
    return table.unpack(list)
end

local policy = setup()
assert(ids(policy, monitors[1]) == "1,3,4")
assert(ids(policy, monitors[2]) == "2,5,6")
assert(state[1] == monitors[1].active_workspace and state[1].windows == 2, "initialization must preserve the focused workspace object and its windows")
local left, middle, right = edges(policy, monitors[1], 3)
edges(policy, monitors[2], 3)
policy.step(-1)
assert(dispatched[#dispatched].id == left.id, "previous must reach the left edge")
activate(middle)
policy.step(1)
assert(dispatched[#dispatched].id == right.id, "next must reach the right edge")
active_window.fullscreen = 1
policy.select(1, true)
assert(dispatched[#dispatched].id == left.id and dispatched[#dispatched].action == "move"
       and dispatched[#dispatched].window == active_window and dispatched[#dispatched].style == "slide 25%")
activate(middle)
active_window.at.x = 1510
active_window.size.x = 200
policy.step(1, true)
assert(dispatched[#dispatched].id == right.id and dispatched[#dispatched].action == "move"
       and dispatched[#dispatched].style == "slide 1%", "narrow visible area should limit slide travel")
assert(animations.workspacesIn == "slide" and animations.workspacesOut == "slide")
local dispatch = hl.dispatch
hl.dispatch = function() error("move failed") end
local ok = pcall(policy.step, -1, true)
assert(not ok and animations.workspacesIn == "slide" and animations.workspacesOut == "slide",
       "a failed move must restore the slide")
hl.dispatch = dispatch
monitors.focused = monitors[2]
policy.step(1)
assert(dispatched[#dispatched].id == policy.list(monitors[2])[3].id, "switching must stay on the focused monitor")
local count = #dispatched
policy.select(10)
monitors[2].active_workspace = policy.list(monitors[2])[1]
policy.step(-1)
monitors[2].active_workspace = policy.list(monitors[2])[3]
policy.step(1)
assert(#dispatched == count, "navigation must stop at both edges")

policy = setup()
left, middle, right = edges(policy, monitors[1], 3)
policy.step(1, true)
assert(active_window.workspace == right and active_window.floating and active_window.pinned)
assert(active_window.at.x == 0 and active_window.at.y == 0
       and active_window.size.x == 1200 and active_window.size.y == 800,
       "a tiled window must keep its geometry while pinned")
assert(dispatched[#dispatched].style == "slide" and dispatched[#dispatched].pinned,
       "a pinned move must use the full slide")
local timer = carry_timer
policy.step(-1, true)
assert(carry_timer == timer and active_window.workspace == middle and active_window.pinned,
       "reversing must keep the same window pinned and restart the timer")
timer:fire()
assert(active_window.workspace == middle and not active_window.pinned and not active_window.floating)

active_window.floating = true
local get_active_window = hl.get_active_window
hl.get_active_window = function() error("drag transfers must use the grabbed window") end
policy.step(-1, true, active_window)
hl.get_active_window = get_active_window
assert(active_window.workspace == left and active_window.pinned)
activate(middle) -- A workspace switch started elsewhere carries pins with it.
assert(carry_timer.timeout == 1)
carry_timer:fire()
assert(active_window.workspace == left and not active_window.pinned and active_window.floating,
       "an external workspace switch must leave the window in its intended destination")

policy.select(3, true)
assert(active_window.pinned)
emit("config.unload")
assert(active_window.workspace == right and not active_window.pinned and active_window.floating
       and not carry_timer.enabled, "reload must clear temporary pins")

policy = setup()
left, middle, right = edges(policy, monitors[1], 3)
active_window.floating = true
policy.step(-1, true)
active_window.floating, active_window.pinned = false, false -- Native drag release can retile early.
local before_release_cleanup = #dispatched
carry_timer:fire()
assert(active_window.workspace == left and #dispatched == before_release_cleanup,
       "cleanup must accept a window already retiled by the compositor")

policy = setup()
left, middle, right = edges(policy, monitors[1], 3)
local other = ids(policy, monitors[2])
middle.visible = false
left.visible = true
monitors[1].active_workspace = left
emit("workspace.active", left)
settle()
edges(policy, monitors[1], 3)
left.windows = 1
emit("window.open")
emit("window.move_to_workspace")
assert(#timers == 1, "related lifecycle events should coalesce")
settle()
edges(policy, monitors[1], 4)
assert(policy.list(monitors[1])[2] == left and policy.list(monitors[1])[3] == middle,
       "prepending must keep occupied objects in order")
assert(monitors[1].active_workspace == left and left.visible, "making room must retain focus")
assert(ids(policy, monitors[2]) == other, "making room must not renumber another monitor")
left.visible = false
right.visible = true
monitors[1].active_workspace = right
emit("workspace.active", right)
settle()
edges(policy, monitors[1], 4)
right.windows = 1
emit("window.open")
settle()
edges(policy, monitors[1], 5)
middle.windows = 0
emit("window.close")
settle()
edges(policy, monitors[1], 4)
left.windows = 0
emit("window.close")
settle()
edges(policy, monitors[1], 3)
right.windows = 0
emit("window.close")
settle()
assert(#policy.list(monitors[1]) == 1 and policy.list(monitors[1])[1] == right,
       "an empty monitor must keep only its visible workspace")
assert(ids(policy, monitors[2]) == other, "other monitors must remain unchanged")
right.windows = 1
emit("window.open")
settle()
edges(policy, monitors[1], 3)

policy = setup()
local special = add(-99, monitors[1], 1, false, true)
monitors[2].enabled = false
for _, workspace in ipairs(state) do
    if workspace.monitor == monitors[2] then
        workspace.monitor = monitors[1]
        workspace.visible = false
    end
end
emit("monitor.removed")
settle()
edges(policy, monitors[1], 4)
assert(#policy.list(monitors[2]) == 0)
local found = false
for _, workspace in ipairs(state) do if workspace == special then found = true end end
assert(found, "scratchpads must remain unmanaged")

-- Reloads must preserve order without moving/focusing/renumbering anything.
local before, dispatched_before = ids(policy, monitors[1]), #dispatched
policy = assert(loadfile(module_path))()
emit("config.reloaded")
settle()
assert(ids(policy, monitors[1]) == before)
assert(#dispatched == dispatched_before)

-- Empty and mirrored outputs must not acquire duplicate or unmanaged edges.
policy = setup()
state = {}
for _, monitor in ipairs(monitors) do monitor.active_workspace = nil end
emit("workspace.removed")
settle()
assert(#policy.list(monitors[1]) == 1 and #policy.list(monitors[2]) == 1)
monitors[2].is_mirror = true
emit("monitor.added")
settle()
assert(#policy.list(monitors[2]) == 0)
print("Workspace lifecycle, monitor isolation, pinned window transfers, reversals, early release, hotplug, and reload passed")
