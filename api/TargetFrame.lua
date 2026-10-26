local _, ns = ...

local TargetFrame = {}
ns.Api.TargetFrame = TargetFrame

-- EllesmereUIUnitFrames Engine.SpawnUnitFrame("target", ...) creates this
-- SecureUnitButtonTemplate button. It is the click receiver (RegisterForClicks
-- AnyUp). Player/Focus/ToT use different names and must not be bound.
local ELLESMERE_ADDON = "EllesmereUIUnitFrames"
local ELLESMERE_TARGET_NAME = "EllesmereUIUnitFrames_Target"

---@param frame any
---@return boolean
local function IsForbidden(frame)
    if type(frame) ~= "table" or type(frame.IsForbidden) ~= "function" then
        return false
    end
    local ok, forbidden = pcall(frame.IsForbidden, frame)
    return ok and forbidden == true
end

---@param frame any
---@return string|nil
local function FrameName(frame)
    if type(frame) ~= "table" or type(frame.GetName) ~= "function" then
        return nil
    end
    local ok, name = pcall(frame.GetName, frame)
    if ok and type(name) == "string" then
        return name
    end
    return nil
end

---@param frame any
---@return string|nil
local function UnitAttribute(frame)
    if type(frame) ~= "table" or type(frame.GetAttribute) ~= "function" then
        return nil
    end
    local ok, unit = pcall(frame.GetAttribute, frame, "unit")
    if ok and type(unit) == "string" then
        return unit
    end
    return nil
end

---@return boolean
local function IsEllesmereUnitFramesLoaded()
    if type(C_AddOns) ~= "table" or type(C_AddOns.IsAddOnLoaded) ~= "function" then
        return false
    end
    local ok, loaded = pcall(C_AddOns.IsAddOnLoaded, ELLESMERE_ADDON)
    return ok and loaded == true
end

---@param frame any
---@param expectedName string
---@return boolean
local function IsUsableNamedFrame(frame, expectedName)
    if type(frame) ~= "table" or IsForbidden(frame) then
        return false
    end
    local name = FrameName(frame)
    if name ~= nil and name ~= expectedName then
        return false
    end
    return true
end

---@return Frame|nil
local function GetBlizzardFrame()
    local frame = _G.TargetFrame
    if not IsUsableNamedFrame(frame, "TargetFrame") then
        return nil
    end
    return frame
end

---The EllesmereUI Target Frame button, when that addon is loaded and has spawned it.
---@return Frame|nil
local function GetEllesmereFrame()
    if not IsEllesmereUnitFramesLoaded() then
        return nil
    end
    local frame = _G[ELLESMERE_TARGET_NAME]
    if not IsUsableNamedFrame(frame, ELLESMERE_TARGET_NAME) then
        return nil
    end
    local unit = UnitAttribute(frame)
    if unit ~= nil and unit ~= "target" then
        return nil
    end
    return frame
end

---The clickable Target Frame: EllesmereUI's unit button when that frame exists, otherwise Blizzard's.
---@return Frame|nil
function TargetFrame.GetFrame()
    return GetEllesmereFrame() or GetBlizzardFrame()
end

---Runs `callback` when the Target Frame may have appeared or been replaced (EUI load, login, reload).
---@param callback fun()
function TargetFrame.OnReady(callback)
    local function notify()
        callback()
    end
    ns.Api.GameEvents.Listen("ADDON_LOADED", function(loadedName)
        if loadedName == ELLESMERE_ADDON then
            notify()
            ns.Api.Timer.After(0, notify)
        end
    end)
    ns.Api.GameEvents.Listen("PLAYER_LOGIN", notify)
    ns.Api.GameEvents.Listen("PLAYER_ENTERING_WORLD", notify)
end
