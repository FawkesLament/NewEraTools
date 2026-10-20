local _, ns = ...
local Position = ns.Position

-- Shared on-screen anchor for callout messages. Features read and write this one saved position.

---@class CalloutAnchor
---@field point string
---@field relativePoint string
---@field x number
---@field y number

local CalloutPosition = {}
ns.CalloutPosition = CalloutPosition

---@type CalloutAnchor|nil
local savedPosition

---@return CalloutAnchor
local function FactoryPosition()
    return { point = "CENTER", relativePoint = "CENTER", x = 0, y = 160 }
end

---Factory anchor. A new table, so callers can store it without aliasing the saved one.
---@return CalloutAnchor
function CalloutPosition.DefaultPosition()
    return FactoryPosition()
end

---Points later reads and writes at `saved.calloutPosition`, filling the factory anchor when needed.
---@param saved table
function CalloutPosition.Bind(saved)
    local position = saved.calloutPosition
    if not Position.IsValid(position) then
        position = FactoryPosition()
        saved.calloutPosition = position
    end
    savedPosition = position
end

---@return CalloutAnchor
function CalloutPosition.GetPosition()
    return assert(savedPosition, "Callout position is not loaded")
end

---@param position CalloutAnchor
function CalloutPosition.SetPosition(position)
    assert(savedPosition, "Callout position is not loaded")
    assert(Position.IsValid(position), "Bad callout position")
    savedPosition.point = position.point
    savedPosition.relativePoint = position.relativePoint
    savedPosition.x = position.x
    savedPosition.y = position.y
end

ns.Modules.BeforeInit(function(saved)
    CalloutPosition.Bind(saved)
end)
