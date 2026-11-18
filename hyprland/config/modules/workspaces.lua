-- Independent, dynamic workspace lists. Hyprland collects hidden empty
-- workspaces itself; each monitor keeps an empty workspace at both ends.
local M = {}
local rules = {}
local pending = false

hl.animation({ leaf = "workspaces", enabled = true, speed = 2.2, bezier = "easeInOutCubic", style = "slide" })

local function setWorkspaceSlide(style)
    for _, leaf in ipairs({ "workspacesIn", "workspacesOut" }) do
        hl.animation({ leaf = leaf, enabled = true, speed = 2.2, bezier = "easeInOutCubic", style = style })
    end
end

setWorkspaceSlide("slide")

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
    local function allocate(preferred, direction)
        local id = preferred
        while id > 0 and used[id] do id = id + direction end
        if id <= 0 then
            id = 1
            while used[id] do id = id + 1 end
        end
        used[id] = true
        return id
    end
    local function make_room(workspaces)
        -- Numbered IDs must stay positive. Shift only this monitor's prefix
        -- into the next free ID, backwards, preserving objects and slide order.
        local hole = workspaces[1].id
        while used[hole] do hole = hole + 1 end
        for index = #workspaces, 1, -1 do
            local workspace = workspaces[index]
            local id = workspace.id
            if id < hole then
                if rules[id] then
                    rules[id].rule:set_enabled(false)
                    rules[id] = nil
                end
                hl.dispatch(hl.dsp.workspace.change_id({ workspace = id, id = hole }))
                used[hole], used[id] = true, nil
                hole = id
            end
        end
    end
    for _, monitor in ipairs(hl.get_monitors()) do
        if monitor.enabled and not monitor.is_mirror then
            local workspaces = M.list(monitor)
            local occupied, visible
            for _, workspace in ipairs(workspaces) do
                if workspace.windows > 0 then occupied = true end
                if workspace.visible then visible = workspace end
            end
            local first, last = workspaces[1], workspaces[#workspaces]
            local head, tail
            if occupied then
                head, tail = first.id, last.id
                if first.windows > 0 then
                    local available = first.id - 1
                    while available > 0 and used[available] do available = available - 1 end
                    if available == 0 then make_room(workspaces) end
                    head = allocate(first.id - 1, -1)
                    desired[head] = { monitor = monitor.name, persistent = true }
                end
                tail = last.id
                if last.windows > 0 then
                    tail = allocate(last.id + 1, 1)
                    desired[tail] = { monitor = monitor.name, persistent = true }
                end
            else
                -- An entirely empty monitor needs one workspace, not two.
                head = (visible or first or {}).id or allocate(1, 1)
                tail = head
                if not first then desired[head] = { monitor = monitor.name, persistent = true } end
            end
            for _, workspace in ipairs(workspaces) do
                desired[workspace.id] = {
                    monitor = monitor.name, persistent = workspace.id == head or workspace.id == tail,
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
            if previous then previous.rule:set_enabled(false) end
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
        local window = hl.get_active_window()
        if not window then return end
        local monitor = workspace.monitor
        local width = monitor.mode.width
        local x = window.at.x - monitor.x
        local visible = math.max(0, math.min(width, x + window.size.x) - math.max(0, x))
        -- Hyprland slides the carried window in with the destination. Limit
        -- the travel to a fraction of the window's visible width.
        local percent = math.max(1, math.min(25, math.floor(100 * visible / (3 * width))))
        local dispatch = hl.dsp.window.move({ workspace = workspace.id, window = window })
        setWorkspaceSlide(string.format("slide %d%%", percent))
        local ok, result = pcall(hl.dispatch, dispatch)
        setWorkspaceSlide("slide")
        if not ok then error(result, 0) end
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
