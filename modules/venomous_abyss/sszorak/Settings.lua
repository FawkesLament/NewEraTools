local _, ns = ...
local L = ns.L
local Util = ns.Util

local Sszorak = ns.Modules.Get("Sszorak")

-- Same range as the main panel scale control.
local MAP_SCALE_MIN = 0.8
local MAP_SCALE_MAX = 1.5
local MAP_SCALE_STEP = 0.05
-- Full circle, in degrees. 0 leaves the entrance on the right; 360 matches 0.
local MAP_ROTATION_MIN = 0
local MAP_ROTATION_MAX = 360
local MAP_ROTATION_STEP = 45
-- Saved player side and AddonCheck snapshot values. Left is group A; right is group B.
local SIDE_LEFT = "left"
local SIDE_RIGHT = "right"

Sszorak.MAP_SCALE_MIN = MAP_SCALE_MIN
Sszorak.MAP_SCALE_MAX = MAP_SCALE_MAX
Sszorak.MAP_SCALE_STEP = MAP_SCALE_STEP
Sszorak.MAP_ROTATION_MIN = MAP_ROTATION_MIN
Sszorak.MAP_ROTATION_MAX = MAP_ROTATION_MAX
Sszorak.MAP_ROTATION_STEP = MAP_ROTATION_STEP
Sszorak.SIDE_LEFT = SIDE_LEFT
Sszorak.SIDE_RIGHT = SIDE_RIGHT

---Snaps a saved scale and rotation into range. Called from OnInit.
function Sszorak:RepairMapSettings()
    self.db.mapScale = Util.Snap(self.db.mapScale, MAP_SCALE_MIN, MAP_SCALE_MAX, MAP_SCALE_STEP)
    self.db.mapRotation = Util.Snap(self.db.mapRotation, MAP_ROTATION_MIN, MAP_ROTATION_MAX, MAP_ROTATION_STEP)
end

---@return boolean  Whether the map opens automatically at the Sszorak altar.
function Sszorak:IsMapEnabled()
    return self.db.mapEnabled == true
end

---@param enabled boolean
function Sszorak:SetMapEnabled(enabled)
    self.db.mapEnabled = enabled == true
end

---@return "left"|"right"
function Sszorak:GetPlayerSide()
    return self.db.playerSide
end

---@param side "left"|"right"
function Sszorak:SetPlayerSide(side)
    assert(side == SIDE_LEFT or side == SIDE_RIGHT, "Bad side")
    self.db.playerSide = side
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

---@return number  Degrees counterclockwise, from 0 through 360.
function Sszorak:GetMapRotation()
    return Util.Snap(self.db.mapRotation, MAP_ROTATION_MIN, MAP_ROTATION_MAX, MAP_ROTATION_STEP)
end

---@param degrees number
function Sszorak:SetMapRotation(degrees)
    assert(type(degrees) == "number", "Bad rotation")
    self.db.mapRotation = Util.Snap(degrees, MAP_ROTATION_MIN, MAP_ROTATION_MAX, MAP_ROTATION_STEP)
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

---@return CalloutAnchor
function Sszorak:GetCalloutPosition()
    return ns.CalloutAnchor.GetPosition()
end

---@param position CalloutAnchor
function Sszorak:SetCalloutPosition(position)
    ns.CalloutAnchor.SetPosition(position)
end

---Group assignment isn't implemented yet; the left/right setting chooses the group.
---@return SszorakGroup
function Sszorak:GetPlayerGroup()
    return self:GetPlayerSide() == SIDE_RIGHT and "B" or "A"
end

---@class SszorakAddonCheckConfig
---@field enabled boolean  Feature On/Off (`mapEnabled`).
---@field side "left"|"right"  The saved player side.
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
    local side = self.db.playerSide
    if side ~= SIDE_LEFT and side ~= SIDE_RIGHT then
        error("Sszorak AddonCheck: invalid playerSide")
    end
    local mode = ResolveAddonCheckMode()
    return {
        enabled = mapEnabled,
        side = side,
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
