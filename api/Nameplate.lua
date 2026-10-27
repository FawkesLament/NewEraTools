local _, ns = ...

local Nameplate = {}
ns.Api.Nameplate = Nameplate

---A secret value throws on comparison, including `value == ""`. Check this before any other use.
---@param value any
---@return boolean
local function IsSecret(value)
    return issecretvalue and issecretvalue(value)
end

---@param frame any
---@return boolean
local function FrameIsForbidden(frame)
    if type(frame) ~= "table" or type(frame.IsForbidden) ~= "function" then
        return false
    end
    local ok, forbidden = pcall(frame.IsForbidden, frame)
    return ok and forbidden == true
end

---Blizzard nameplate frame for `unit`, or nil when that plate is not shown.
---Secret nameplate tokens are passed through; comparing them would throw.
---@param unit any
---@return Frame|nil
function Nameplate.GetFrame(unit)
    if not IsSecret(unit) and (type(unit) ~= "string" or unit == "") then
        return nil
    end
    return C_NamePlate.GetNamePlateForUnit(unit)
end

---Whether `unit` is a plain Blizzard nameplate token (`nameplate1`, …). Secret tokens fail closed.
---@param unit any
---@return boolean
function Nameplate.IsUnitToken(unit)
    if IsSecret(unit) or type(unit) ~= "string" or unit == "" then
        return false
    end
    return unit:match("^nameplate%d+$") ~= nil
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

---Whether this nameplate (or its unit frame) is forbidden. Forbidden plates must not be touched.
---@param frame any
---@return boolean
function Nameplate.IsForbidden(frame)
    if type(frame) ~= "table" then
        return true
    end
    if FrameIsForbidden(frame) then
        return true
    end
    return FrameIsForbidden(frame.UnitFrame)
end

---Click host for a nameplate overlay. Blizzard's `UnitFrame` owns Midnight's C++
---HitTestFrame. Plater hides that frame and remaps hit-testing onto
---`unitFrame.hitTestFrame` (often LOW / UIParent), so overlays must cover Plater's
---host or they sit on a hidden WORLD frame and never receive clicks.
---@param frame any
---@return Frame|nil
function Nameplate.GetHost(frame)
    if type(frame) ~= "table" then
        return nil
    end
    local platerUnitFrame = frame.unitFrame
    if type(platerUnitFrame) == "table" and (frame.Plater or platerUnitFrame.Plater) then
        local hitTest = platerUnitFrame.hitTestFrame
        if type(hitTest) == "table" then
            return hitTest
        end
        return platerUnitFrame
    end
    local unitFrame = frame.UnitFrame
    if type(unitFrame) == "table" then
        return unitFrame
    end
    return frame
end

---Unit token for a nameplate frame. May be a secret value; do not compare it.
---@param frame any
---@return any
function Nameplate.GetUnit(frame)
    if type(frame) ~= "table" then
        return nil
    end
    local unit = frame.namePlateUnitToken
    if IsSecret(unit) then
        return unit
    end
    if type(unit) == "string" and unit ~= "" then
        return unit
    end
    if type(frame.GetUnit) == "function" then
        local ok, value = pcall(frame.GetUnit, frame)
        if ok and (IsSecret(value) or (type(value) == "string" and value ~= "")) then
            return value
        end
    end
    return nil
end

---Whether the player can attack the unit on this nameplate. Secret tokens are probed
---without comparing them. Nil/secret attack results fail closed.
---@param frame any
---@return boolean
function Nameplate.UnitCanAttack(frame)
    local unit = Nameplate.GetUnit(frame)
    if not IsSecret(unit) and (type(unit) ~= "string" or unit == "") then
        return false
    end
    local ok, value = pcall(UnitCanAttack, "player", unit)
    if not ok or IsSecret(value) then
        return false
    end
    return value == true or value == 1
end

---Invokes `handler(frame)` for every currently visible Blizzard nameplate, including
---plates whose unit token is secret or missing. Use this for click overlays.
---@param handler fun(frame: Frame)
function Nameplate.ForEachPlate(handler)
    local plates = C_NamePlate.GetNamePlates()
    if type(plates) ~= "table" then
        return
    end
    for i = 1, #plates do
        local frame = plates[i]
        if type(frame) == "table" then
            handler(frame)
        end
    end
end

---Invokes `handler(unit, frame)` for every currently visible Blizzard nameplate
---with a plain unit token. Secret tokens are skipped so callers can compare `unit`.
---@param handler fun(unit: string, frame: Frame)
function Nameplate.ForEachVisible(handler)
    local plates = C_NamePlate.GetNamePlates()
    if type(plates) ~= "table" then
        return
    end
    for i = 1, #plates do
        local frame = plates[i]
        local unit = frame and frame.namePlateUnitToken
        if not IsSecret(unit) and type(unit) == "string" and unit ~= "" then
            handler(unit, frame)
        end
    end
end
