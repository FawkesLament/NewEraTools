local _, ns = ...
local Position = ns.Position

-- Shared on-screen anchor for interrupt rotation trackers. Features read and write this one saved position.

---@class InterruptRotationTrackerAnchor
---@field point string
---@field relativePoint string
---@field x number
---@field y number

local InterruptRotationTrackerAnchor = {}
ns.InterruptRotationTrackerAnchor = InterruptRotationTrackerAnchor

---@type InterruptRotationTrackerAnchor|nil
local savedPosition

---@return InterruptRotationTrackerAnchor
local function FactoryPosition()
    return { point = "CENTER", relativePoint = "CENTER", x = 0, y = 80 }
end

---Factory anchor. A new table, so callers can store it without aliasing the saved one.
---@return InterruptRotationTrackerAnchor
function InterruptRotationTrackerAnchor.DefaultPosition()
    return FactoryPosition()
end

---Points later reads and writes at `saved.interruptRotationTrackerPosition`, filling the factory anchor when needed.
---@param saved table
function InterruptRotationTrackerAnchor.Bind(saved)
    local position = saved.interruptRotationTrackerPosition
    if not Position.IsValid(position) then
        position = FactoryPosition()
        saved.interruptRotationTrackerPosition = position
    end
    savedPosition = position
end

---@return InterruptRotationTrackerAnchor
function InterruptRotationTrackerAnchor.GetPosition()
    return assert(savedPosition, "Interrupt rotation tracker anchor is not loaded")
end

---@param position InterruptRotationTrackerAnchor
function InterruptRotationTrackerAnchor.SetPosition(position)
    assert(savedPosition, "Interrupt rotation tracker anchor is not loaded")
    assert(Position.IsValid(position), "Bad interrupt rotation tracker anchor")
    savedPosition.point = position.point
    savedPosition.relativePoint = position.relativePoint
    savedPosition.x = position.x
    savedPosition.y = position.y
end

ns.Modules.BeforeInit(function(saved)
    InterruptRotationTrackerAnchor.Bind(saved)
end)
