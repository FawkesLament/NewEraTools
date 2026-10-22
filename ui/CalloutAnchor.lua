local _, ns = ...
local Position = ns.Position

-- Shared on-screen anchor for callout messages. Features read and write this one saved position.

---@class CalloutAnchor
---@field point string
---@field relativePoint string
---@field x number
---@field y number

local CalloutAnchor = {}
ns.CalloutAnchor = CalloutAnchor

---@type CalloutAnchor|nil
local savedPosition

---@return CalloutAnchor
local function FactoryPosition()
    return { point = "CENTER", relativePoint = "CENTER", x = 0, y = 160 }
end

---Factory anchor. A new table, so callers can store it without aliasing the saved one.
---@return CalloutAnchor
function CalloutAnchor.DefaultPosition()
    return FactoryPosition()
end

---Points later reads and writes at `saved.calloutPosition`, filling the factory anchor when needed.
---@param saved table
function CalloutAnchor.Bind(saved)
    local position = saved.calloutPosition
    if not Position.IsValid(position) then
        position = FactoryPosition()
        saved.calloutPosition = position
    end
    savedPosition = position
end

---@return CalloutAnchor
function CalloutAnchor.GetPosition()
    return assert(savedPosition, "Callout anchor is not loaded")
end

---@param position CalloutAnchor
function CalloutAnchor.SetPosition(position)
    assert(savedPosition, "Callout anchor is not loaded")
    assert(Position.IsValid(position), "Bad callout anchor")
    savedPosition.point = position.point
    savedPosition.relativePoint = position.relativePoint
    savedPosition.x = position.x
    savedPosition.y = position.y
end

ns.Modules.BeforeInit(function(saved)
    CalloutAnchor.Bind(saved)
end)
