-- Independent, dynamic workspace lists. Hyprland collects hidden empty
-- workspaces itself; only each monitor's trailing empty workspace is persistent.
local M = {}
local rules = {}
local pending = false

function M.list(monitor)
    local result = {}
    if not monitor then return result end
    for _, workspace in ipairs(hl.get_workspaces()) do
        if workspace.id and workspace.id > 0 and workspace.monitor
            and workspace.monitor.name == monitor.name and not workspace.special then
            table.insert(result, workspace)
        end
    end
    table.sort(result, function(a, b) return a.id < b.id end)
    return result
end

local function reconcile()
    local used, desired = {}, {}
    for _, workspace in ipairs(hl.get_workspaces()) do
        if workspace.id then used[workspace.id] = true end
    end
    for _, monitor in ipairs(hl.get_monitors()) do
        if monitor.enabled and not monitor.is_mirror then
            local workspaces = M.list(monitor)
            local last = workspaces[#workspaces]
            local tail
            if last and last.windows == 0 then
                tail = last.id
            else
                tail = last and last.id + 1 or 1
                while used[tail] do tail = tail + 1 end
                used[tail] = true
                desired[tail] = { monitor = monitor.name, persistent = true }
            end
            for _, workspace in ipairs(workspaces) do
                desired[workspace.id] = {
                    monitor = monitor.name, persistent = workspace.id == tail,
                }
            end
        end
    end
    for id, previous in pairs(rules) do
        if not desired[id] and previous.enabled then
            previous.rule:set_enabled(false)
            previous.enabled = false
        end
    end
    for id, spec in pairs(desired) do
        local previous = rules[id]
        if not previous or previous.monitor ~= spec.monitor
            or previous.persistent ~= spec.persistent then
            spec.rule = hl.workspace_rule({
                workspace = tostring(id), monitor = spec.monitor,
                persistent = spec.persistent,
            })
            spec.enabled = true
            rules[id] = spec
        elseif not previous.enabled then
            previous.rule:set_enabled(true)
            previous.enabled = true
        end
    end
end

local function schedule()
    if pending then return end
    -- --verify-config emits config.reloaded without starting a Wayland server
    -- or event loop. Creating a timer there crashes Hyprland 0.57.
    if not os.getenv("WAYLAND_DISPLAY") then return end
    pending = true
    -- Window-close/move events can fire before the window count is updated.
    -- Coalesce them and let Hyprland finish its lifecycle/animation work first.
    hl.timer(function()
        pending = false
        reconcile()
    end, { timeout = 30, type = "oneshot" })
end

local function target(workspace, move)
    if not workspace then return end
    if move then
        hl.dispatch(hl.dsp.window.move({ workspace = workspace.id }))
    else
        hl.dispatch(hl.dsp.focus({ workspace = workspace.id }))
    end
end

function M.step(direction, move)
    local monitor = hl.get_active_monitor()
    if not monitor or not monitor.active_workspace then return end
    local workspaces = M.list(monitor)
    for index, workspace in ipairs(workspaces) do
        if workspace.id == monitor.active_workspace.id then
            target(workspaces[index + direction], move)
            return
        end
    end
end

function M.select(index, move)
    target(M.list(hl.get_active_monitor())[index], move)
end

for _, event in ipairs({
    "hyprland.start", "config.reloaded", "monitor.added", "monitor.removed",
    "workspace.created", "workspace.removed", "workspace.active",
    "workspace.move_to_monitor", "window.open", "window.close",
    "window.destroy", "window.move_to_workspace",
}) do
    hl.on(event, schedule)
end

return M
