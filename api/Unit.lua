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
---Whether `unit` currently exists. Secret results fail closed.
---@param unit string
---@return boolean
function Unit.Exists(unit)
    if type(unit) ~= "string" or unit == "" then
        return false
    end
    if issecret and issecret(unit) then
        return false
    end
    local exists = UnitExists(unit)
    if issecret and issecret(exists) then
        return false
    end
    return exists == true or exists == 1
end

---Plain boolean from UnitCanAssist. Nil when the call failed or the value is secret.
---@param ok boolean
---@param canAssist any
---@return boolean|nil
local function ReadCanAssist(ok, canAssist)
    if not ok or (issecret and issecret(canAssist)) then
        return nil
    end
    if canAssist == true or canAssist == 1 then
        return true
    end
    if canAssist == false or canAssist == 0 then
        return false
    end
    return nil
end

---Whether the player can assist `unit`, ignoring temporary immune and uninteractable flags.
---Matches AuraContainer's includeSpellIDs reaction test. Nil when the unit is missing or the
---result is secret — callers must treat nil as "not safe to filter".
---@param unit string
---@return boolean|nil
function Unit.CanPlayerAssist(unit)
    if not Unit.Exists(unit) then
        return nil
    end
    -- true, true: still assistable while immune or uninteractable (vehicle, CC, teleport).
    -- That form can come back secret while the two-argument call is a plain boolean; a secret
    -- result must not hide a hostile target that the plain call can still classify.
    local parsed = ReadCanAssist(pcall(UnitCanAssist, "player", unit, true, true))
    if parsed ~= nil then
        return parsed
    end
    return ReadCanAssist(pcall(UnitCanAssist, "player", unit))
end

---@param unit string  A unit token, e.g. "player" or "raid3".
---@return string|nil
function Unit.GetGUID(unit)
    if type(unit) ~= "string" or unit == "" or (issecret and issecret(unit)) then
        return nil
    end
    local guid = UnitGUID(unit)
    -- A secret GUID cannot be compared. Callers rescan the token instead of throwing.
    if type(guid) ~= "string" or guid == "" or (issecret and issecret(guid)) then
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
