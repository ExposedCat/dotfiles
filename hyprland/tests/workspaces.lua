-- Run by test_workspaces.py with a real Lua runtime and a fake compositor.
local module_path = ...
local hooks, timers, state, monitors, applied, dispatched, animations, active_window
local getenv = os.getenv
os.getenv = function(key)
    if key == "WAYLAND_DISPLAY" then return "workspace-test" end
    return getenv(key)
end

local function emit(event)
    if hooks[event] then hooks[event]() end
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
    active_window = { at = { x = 0 }, size = { x = 1200 } }
    monitors = {
        { name = "DP-1", enabled = true, x = 0, mode = { width = 1600 } },
        { name = "HDMI-1", enabled = true, x = 1600, mode = { width = 1600 } },
    }
    hl = {
        animation = function(spec) animations[spec.leaf] = spec.style end,
        on = function(event, callback) hooks[event] = callback end,
        timer = function(callback) table.insert(timers, callback) end,
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
            end
        end,
        dsp = {
            workspace = { change_id = function(spec) return { action = "renumber", from = spec.workspace, id = spec.id } end },
            focus = function(spec) return { action = "focus", id = spec.workspace } end,
            window = { move = function(spec) return { action = "move", id = spec.workspace, window = spec.window } end },
        },
    }
    add(1, monitors[1], 2, true)
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
policy.step(1)
assert(dispatched[#dispatched].id == right.id, "next must reach the right edge")
policy.select(1, true)
assert(dispatched[#dispatched].id == left.id and dispatched[#dispatched].action == "move"
       and dispatched[#dispatched].window == active_window and dispatched[#dispatched].style == "slide 25%")
active_window.at.x = 1510
active_window.size.x = 200
policy.step(1, true)
assert(dispatched[#dispatched].id == right.id and dispatched[#dispatched].action == "move"
       and dispatched[#dispatched].style == "slide 1%", "narrow visible area should limit slide travel")
assert(animations.workspacesIn == "slide" and animations.workspacesOut == "slide")
local dispatch = hl.dispatch
hl.dispatch = function() error("move failed") end
local ok = pcall(policy.step, 1, true)
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
local other = ids(policy, monitors[2])
middle.visible = false
left.visible = true
monitors[1].active_workspace = left
emit("workspace.active")
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
emit("workspace.active")
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
print("Two-sided workspace lifecycle, empty-monitor collapse, stable workspace objects, monitor isolation, shortcuts, hotplug, and reload passed")
