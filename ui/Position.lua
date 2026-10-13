local _, ns = ...

local Position = {}
ns.Position = Position

---Whether `position` is a saved floating-window / bar anchor table.
---@param position any
---@return boolean
function Position.IsValid(position)
    return type(position) == "table"
        and type(position.point) == "string"
        and type(position.relativePoint) == "string"
        and type(position.x) == "number"
        and type(position.y) == "number"
end
