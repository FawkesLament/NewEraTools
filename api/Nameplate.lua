local _, ns = ...

local Nameplate = {}
ns.Api.Nameplate = Nameplate

---Blizzard nameplate frame for `unit`, or nil when that plate is not shown.
---@param unit string
---@return Frame|nil
function Nameplate.GetFrame(unit)
    if type(unit) ~= "string" or unit == "" then
        return nil
    end
    return C_NamePlate.GetNamePlateForUnit(unit)
end

---Calls `handler(unit, frame)` when a Blizzard nameplate is shown for `unit`.
---@param handler fun(unit: string, frame: Frame)
---@return fun()  Unsubscribe.
function Nameplate.OnAdded(handler)
    return ns.Api.GameEvents.Listen("NAME_PLATE_UNIT_ADDED", function(unit)
        local frame = Nameplate.GetFrame(unit)
        if frame then
            handler(unit, frame)
        end
    end)
end

---Calls `handler(unit)` when that unit's nameplate is hidden or recycled.
---@param handler fun(unit: string)
---@return fun()  Unsubscribe.
function Nameplate.OnRemoved(handler)
    return ns.Api.GameEvents.Listen("NAME_PLATE_UNIT_REMOVED", handler)
end

---Invokes `handler(unit, frame)` for every currently visible Blizzard nameplate.
---@param handler fun(unit: string, frame: Frame)
function Nameplate.ForEachVisible(handler)
    local plates = C_NamePlate.GetNamePlates()
    if type(plates) ~= "table" then
        return
    end
    for i = 1, #plates do
        local frame = plates[i]
        local unit = frame and frame.namePlateUnitToken
        if type(unit) == "string" and unit ~= "" then
            handler(unit, frame)
        end
    end
end
