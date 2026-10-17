local _, ns = ...
local L = ns.L
local Util = ns.Util

local Sszorak = ns.Modules.Get("Sszorak")

-- Same range as the main panel scale control.
local MAP_SCALE_MIN = 0.8
local MAP_SCALE_MAX = 1.5
local MAP_SCALE_STEP = 0.05
-- Arena side for AddonCheck snapshots (mapRotated false = left / group A, true = right / group B).
local SIDE_LEFT = "left"
local SIDE_RIGHT = "right"

Sszorak.MAP_SCALE_MIN = MAP_SCALE_MIN
Sszorak.MAP_SCALE_MAX = MAP_SCALE_MAX
Sszorak.MAP_SCALE_STEP = MAP_SCALE_STEP
Sszorak.SIDE_LEFT = SIDE_LEFT
Sszorak.SIDE_RIGHT = SIDE_RIGHT

---Snaps a saved scale into range. Called from OnInit.
function Sszorak:RepairMapSettings()
    self.db.mapScale = Util.Snap(self.db.mapScale, MAP_SCALE_MIN, MAP_SCALE_MAX, MAP_SCALE_STEP)
end

---@return boolean  Whether the map opens automatically during this boss fight.
function Sszorak:IsMapEnabled()
    return self.db.mapEnabled == true
end

---@param enabled boolean
function Sszorak:SetMapEnabled(enabled)
    self.db.mapEnabled = enabled == true
end

---@return boolean  Whether the map window is turned 180 degrees.
function Sszorak:IsMapRotated()
    return self.db.mapRotated == true
end

---@param rotated boolean
function Sszorak:SetMapRotated(rotated)
    self.db.mapRotated = rotated == true
end

---@return number
function Sszorak:GetMapScale()
    return Util.Snap(self.db.mapScale, MAP_SCALE_MIN, MAP_SCALE_MAX, MAP_SCALE_STEP)
end

---@param scale number
function Sszorak:SetMapScale(scale)
    assert(type(scale) == "number", "Bad scale")
    self.db.mapScale = Util.Snap(scale, MAP_SCALE_MIN, MAP_SCALE_MAX, MAP_SCALE_STEP)
end

---@return MapPosition
function Sszorak:GetMapPosition()
    return self.db.mapPosition
end

---@param position MapPosition
function Sszorak:SetMapPosition(position)
    assert(type(position.point) == "string" and type(position.relativePoint) == "string", "Bad anchor points")
    assert(type(position.x) == "number" and type(position.y) == "number", "Bad offsets")
    local saved = self.db.mapPosition
    saved.point, saved.relativePoint = position.point, position.relativePoint
    saved.x, saved.y = position.x, position.y
end

---@return MapPosition
function Sszorak:GetCalloutPosition()
    return self.db.calloutPosition
end

---@param position MapPosition
function Sszorak:SetCalloutPosition(position)
    assert(type(position.point) == "string" and type(position.relativePoint) == "string", "Bad anchor points")
    assert(type(position.x) == "number" and type(position.y) == "number", "Bad offsets")
    local saved = self.db.calloutPosition
    saved.point, saved.relativePoint = position.point, position.relativePoint
    saved.x, saved.y = position.x, position.y
end

---Group assignment isn't implemented yet; players rotate the map when they're in group B.
---@return SszorakGroup
function Sszorak:GetPlayerGroup()
    return self:IsMapRotated() and "B" or "A"
end

---@class SszorakAddonCheckConfig
---@field enabled boolean  Feature On/Off (`mapEnabled`).
---@field side "left"|"right"  From mapRotated: false → left, true → right.
---@field mode string  Registered callout mode, or normal when the saved mode is unavailable.

-- AddonCheck reads this snapshot more than once per check. Announce each missing mode once.
local announcedUnavailable = false
local announcedUnavailableMode

---Saved mode when that provider is registered. Otherwise normal, with one chat notice.
---Does not change the saved preference.
---@return string
local function ResolveAddonCheckMode()
    local mode = Sszorak.db.calloutMode
    if Sszorak.IsCalloutModeAvailable(mode) then
        return mode
    end
    if not announcedUnavailable or announcedUnavailableMode ~= mode then
        announcedUnavailable = true
        announcedUnavailableMode = mode
        Util.Print(string.format(L.SSZORAK_CALLOUT_MODE_UNAVAILABLE, tostring(mode)))
    end
    return Sszorak.CALLOUT_MODE_NORMAL
end

---Live AddonCheck snapshot. Reads current settings; does not mutate them.
---Invalid map values error so AddonCheck reports `provider_failed` instead of a fake default.
---@return SszorakAddonCheckConfig
function Sszorak:GetAddonCheckConfig()
    local mapEnabled = self.db.mapEnabled
    if type(mapEnabled) ~= "boolean" then
        error("Sszorak AddonCheck: invalid mapEnabled")
    end
    local mapRotated = self.db.mapRotated
    if type(mapRotated) ~= "boolean" then
        error("Sszorak AddonCheck: invalid mapRotated")
    end
    local mode = ResolveAddonCheckMode()
    return {
        enabled = mapEnabled,
        side = mapRotated and SIDE_RIGHT or SIDE_LEFT,
        mode = mode,
    }
end

---AddonCheck panel validator: column keys to highlight, or nil when ok.
---Flags disabled feature and marker-assignment mode that differs from the commander's snapshot.
---@param config any  Peer's AddonCheck config.
---@param localConfig any  Commander's snapshot from the check session.
---@return string[]|nil
function Sszorak.ValidateAddonCheckConfig(config, localConfig)
    local flagged = {}
    if type(config) ~= "table" or config.enabled ~= true then
        flagged[#flagged + 1] = "enabled"
    end
    if
        type(config) == "table"
        and type(localConfig) == "table"
        and config.mode ~= nil
        and localConfig.mode ~= nil
        and config.mode ~= localConfig.mode
    then
        flagged[#flagged + 1] = "mode"
    end
    if #flagged == 0 then
        return nil
    end
    return flagged
end
