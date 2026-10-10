local _, ns = ...

local GameEvents = {}
ns.Api.GameEvents = GameEvents

local frame
local handlers = {}

local function OnEvent(_, event, ...)
    for _, handler in ipairs(handlers[event]) do
        handler(...)
    end
end

---For use inside api/ only; other layers subscribe through api functions such as Group.OnChanged.
---@param event string  A WoW event name, e.g. "GROUP_ROSTER_UPDATE".
---@param handler fun(...)  Receives the event payload.
function GameEvents.Listen(event, handler)
    if not frame then
        frame = CreateFrame("Frame")
        frame:SetScript("OnEvent", OnEvent)
    end
    if not handlers[event] then
        handlers[event] = {}
        frame:RegisterEvent(event)
    end
    table.insert(handlers[event], handler)
end
