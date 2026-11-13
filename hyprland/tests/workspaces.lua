-- Run by test_workspaces.py with a real Lua runtime and a fake compositor.
local module_path = ...
local hooks, timers, state, monitors, applied, dispatched
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
        id = id, monitor = monitor, windows = windows or 0,
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
    monitors = {
        { name = "DP-1", enabled = true },
        { name = "HDMI-1", enabled = true },
    }
    hl = {
        on = function(event, callback) hooks[event] = callback end,
        timer = function(callback) table.insert(timers, callback) end,
        get_monitors = function() return monitors end,
        get_workspaces = function() return state end,
        get_active_monitor = function() return monitors.focused or monitors[1] end,
        workspace_rule = function(spec)
            local rule = { persistent = spec.persistent, enabled = true }
            for _, monitor in ipairs(monitors) do
                if monitor.name == spec.monitor then rule.monitor = monitor end
            end
            function rule:set_enabled(enabled) self.enabled = enabled end
            applied[tonumber(spec.workspace)] = rule
            return rule
        end,
        dispatch = function(command) table.insert(dispatched, command) end,
        dsp = {
            focus = function(spec) return { action = "focus", id = spec.workspace } end,
            window = { move = function(spec) return { action = "move", id = spec.workspace } end },
        },
    }
    add(1, monitors[1], 2, true)
    add(2, monitors[2], 3, true)
    local policy = assert(loadfile(module_path))()
    emit("config.reloaded")
    settle()
    return policy
end

local function ids(policy, monitor)
    local result = {}
    for _, workspace in ipairs(policy.list(monitor)) do table.insert(result, workspace.id) end
    return table.concat(result, ",")
end

local policy = setup()
assert(ids(policy, monitors[1]) == "1,3")
assert(ids(policy, monitors[2]) == "2,4")
assert(#dispatched == 0, "initialization must not change focus or move windows")
policy.step(1)
assert(dispatched[#dispatched].id == 3)
monitors.focused = monitors[2]
policy.step(1)
assert(dispatched[#dispatched].id == 4, "switching must stay on the focused monitor")
policy.select(2, true)
assert(dispatched[#dispatched].id == 4 and dispatched[#dispatched].action == "move")
local count = #dispatched
policy.select(10)
policy.step(-1)
assert(#dispatched == count, "out-of-range navigation must stop at the edge")

policy = setup()
local first = state[1]
local tail = policy.list(monitors[1])[2]
first.visible = false
tail.visible = true
monitors[1].active_workspace = tail
emit("workspace.active")
settle()
assert(ids(policy, monitors[1]) == "1,3", "viewing the empty tail must not spawn endless empty workspaces")
tail.windows = 1
emit("window.open")
emit("window.move_to_workspace")
assert(#timers == 1, "related lifecycle events should coalesce")
settle()
assert(ids(policy, monitors[1]) == "1,3,5", "using the tail must append a new empty workspace")
first.windows = 0
emit("window.close")
settle()
assert(ids(policy, monitors[1]) == "3,5", "a hidden empty workspace must disappear")
tail.windows = 0
emit("window.close")
settle()
assert(ids(policy, monitors[1]) == "3,5", "a visible empty workspace must survive")
tail.visible = false
policy.list(monitors[1])[2].visible = true
monitors[1].active_workspace = policy.list(monitors[1])[2]
emit("workspace.active")
settle()
assert(ids(policy, monitors[1]) == "5", "the former visible empty workspace must disappear after leaving it")
assert(ids(policy, monitors[2]) == "2,4", "other monitors must remain unchanged")

policy = setup()
add(-99, monitors[1], 1, false, true)
monitors[2].enabled = false
for _, workspace in ipairs(state) do
    if workspace.monitor == monitors[2] then
        workspace.monitor = monitors[1]
        workspace.visible = false
    end
end
emit("monitor.removed")
settle()
assert(ids(policy, monitors[1]) == "1,2,4", "hotplug should retain migrated windows and just one empty tail")
assert(#policy.list(monitors[2]) == 0)
assert(state[#state].special, "scratchpads must remain unmanaged")

-- A reload rebuilds rule state without changing the workspace list or focus.
local before = ids(policy, monitors[1])
policy = assert(loadfile(module_path))()
emit("config.reloaded")
settle()
assert(ids(policy, monitors[1]) == before)
assert(#dispatched == 0)
print("Workspace lifecycle, monitor isolation, shortcuts, hotplug, and reload passed")
