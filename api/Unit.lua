local _, ns = ...

local Unit = {}
ns.Api.Unit = Unit

local HAS_CLASS_COLOR_API = C_ClassColor ~= nil and C_ClassColor.GetClassColor ~= nil
local HAS_UNIT_CLASS_BASE = UnitClassBase ~= nil

local classColors = {}

---Roster names omit the realm for same-realm players; this adds it so saved keys stay unique.
---@param name string
---@return string  "Name-Realm".
function Unit.GetFullName(name)
    if name:find("-", 1, true) then
        return name
    end
    return name .. "-" .. (GetNormalizedRealmName() or "")
end

---Unit GUID when the client knows it (e.g. "Player-…"); nil when unavailable.
---@param unit string  A unit token, e.g. "player" or "raid3".
---@return string|nil
function Unit.GetGUID(unit)
    if type(unit) ~= "string" or unit == "" then
        return nil
    end
    local guid = UnitGUID(unit)
    if type(guid) ~= "string" or guid == "" then
        return nil
    end
    return guid
end

---@param unit string  A unit token, e.g. "raid3".
---@return string|nil  Class file name, e.g. "WARRIOR".
function Unit.GetClassFile(unit)
    local _, classFile = UnitClass(unit)
    if (not classFile or classFile == "") and HAS_UNIT_CLASS_BASE then
        classFile = UnitClassBase(unit)
    end
    if classFile == "" then
        return nil
    end
    return classFile
end

---Returns one shared table per class; callers must not modify it.
---@param classFile string|nil
---@return { r: number, g: number, b: number }|nil
function Unit.GetClassColor(classFile)
    if not classFile then
        return nil
    end
    local cached = classColors[classFile]
    if cached then
        return cached
    end
    local color = HAS_CLASS_COLOR_API and C_ClassColor.GetClassColor(classFile)
    color = color or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile])
    if not color then
        return nil
    end
    cached = { r = color.r, g = color.g, b = color.b }
    classColors[classFile] = cached
    return cached
end
