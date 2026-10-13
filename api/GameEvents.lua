local _, ns = ...

local GameEvents = {}
ns.Api.GameEvents = GameEvents

local frame
---@type table<string, { handler: fun(...), unit: string|nil }[]>
local handlers = {}

local function EnsureFrame()
    if frame then
        return
    end
    frame = CreateFrame("Frame")
    frame:SetScript("OnEvent", function(_, event, ...)
        local list = handlers[event]
        if not list then
            return
        end
        -- Snapshot in case a handler unsubscribes mid-dispatch.
        local snapshot = {}
        for i = 1, #list do
            snapshot[i] = list[i]
        end
        for i = 1, #snapshot do
            snapshot[i].handler(...)
        end
    end)
end

---Rebuilds RegisterEvent / RegisterUnitEvent after handlers change.
---@param event string
local function RefreshRegistration(event)
    local list = handlers[event]
    if not list or #list == 0 then
        handlers[event] = nil
        if frame then
            frame:UnregisterEvent(event)
        end
        return
    end

    local units = {}
    local seen = {}
    local hasUnit = false
    for _, entry in ipairs(list) do
        if entry.unit then
            hasUnit = true
            if not seen[entry.unit] then
                seen[entry.unit] = true
                table.insert(units, entry.unit)
            end
        end
    end

    EnsureFrame()
    frame:UnregisterEvent(event)
    if hasUnit then
        frame:RegisterUnitEvent(event, unpack(units))
    else
        frame:RegisterEvent(event)
    end
end

---@param event string
---@param handler fun(...)
---@param unit string|nil
---@return fun()  Unsubscribe; safe to call more than once.
local function AddHandler(event, handler, unit)
    EnsureFrame()
    handlers[event] = handlers[event] or {}
    local entry = { handler = handler, unit = unit }
    table.insert(handlers[event], entry)
    RefreshRegistration(event)

    local removed = false
    return function()
        if removed then
            return
        end
        removed = true
        local list = handlers[event]
        if not list then
            return
        end
        for index, candidate in ipairs(list) do
            if candidate == entry then
                table.remove(list, index)
                break
            end
        end
        RefreshRegistration(event)
    end
end

---For use inside api/ only; other layers subscribe through api functions such as Group.OnChanged.
---@param event string  A WoW event name, e.g. "GROUP_ROSTER_UPDATE".
---@param handler fun(...)  Receives the event payload.
---@return fun()  Unsubscribe.
function GameEvents.Listen(event, handler)
    return AddHandler(event, handler, nil)
end

---Like Listen, but scopes a UNIT_* event to one unit token via RegisterUnitEvent.
---@param event string
---@param unit string
---@param handler fun(...)
---@return fun()  Unsubscribe.
function GameEvents.ListenUnit(event, unit, handler)
    assert(type(unit) == "string" and unit ~= "", "GameEvents.ListenUnit requires a unit")
    return AddHandler(event, handler, unit)
end
