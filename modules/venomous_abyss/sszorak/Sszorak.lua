local _, ns = ...
local Group = ns.Api.Group

-- Saved callout-mode ids. Implementations register against these from communication/.
local CALLOUT_MODE_NORMAL = "normal"
local CALLOUT_MODE_JAILBREAK = "jailbreak"
-- Raid role: raid leader is commander (macros / sync UI); everyone else is a member.
local RAID_ROLE_MEMBER = "member"
local RAID_ROLE_COMMANDER = "commander"
-- Stable AddonCheck provider id; version is owned by AddonCheck, not this snapshot.
local ADDON_CHECK_MODULE_ID = "Sszorak"

---Where the map window sits, as an anchor on the screen.
---@class MapPosition
---@field point string  e.g. "TOPLEFT".
---@field relativePoint string
---@field x number
---@field y number

-- Mythic Sszorak, the fifth boss of The Venomous Abyss.
---@class Sszorak: Module
---@field OnEdgeMarkersChanged fun(self: Sszorak)|nil  Defined by the UI; called after the assignment changes.
---@field OnEncounterChanged fun(self: Sszorak)|nil  Defined by the UI; called when this boss fight starts or ends.
---@field OnPositionsChanged fun(self: Sszorak)|nil  Defined by the UI; called when the animated dots move.
---@field OnMapAnimationStarted fun(self: Sszorak)|nil  Defined by the UI; pull/test timeline began.
---@field OnMapAnimationStopped fun(self: Sszorak)|nil  Defined by the UI; pull/test timeline ended.
---@field OnRaidLeaderMessagesChanged fun(self: Sszorak)|nil  Defined by the UI; saved callouts changed.
---@field OnCalloutChanged fun(self: Sszorak)|nil  Defined by the UI; on-screen callout text was shown or cleared.
local Sszorak = ns.Modules.New("Sszorak", {
    defaults = {
        ---@type table<integer, WorldMarker>  Edge index to marker; the entrance and exit have none.
        edgeMarkers = {
            [2] = "STAR",
            [3] = "CIRCLE",
            [4] = "DIAMOND",
            [6] = "TRIANGLE",
            [7] = "MOON",
            [8] = "SQUARE",
        },
        -- When true, the map window opens automatically for this boss fight.
        mapEnabled = true,
        -- Player's side of the room: "left" (group A) or "right" (group B). Independent of map rotation.
        playerSide = "left",
        -- Degrees to turn the floating arena map, counterclockwise. Independent of the player's side.
        mapRotation = 0,
        -- Scale of the floating arena map window.
        mapScale = 1,
        ---@type MapPosition
        mapPosition = { point = "CENTER", relativePoint = "CENTER", x = 0, y = 0 },
        ---@type MapPosition  On-screen raid callout text.
        calloutPosition = { point = "CENTER", relativePoint = "CENTER", x = 0, y = 160 },
        -- Shows RL markers as-is, or jailbreak decrypt/retarget (see CALLOUT_MODE_*).
        calloutMode = CALLOUT_MODE_NORMAL,
    },
})

Sszorak.CALLOUT_MODE_NORMAL = CALLOUT_MODE_NORMAL
Sszorak.CALLOUT_MODE_JAILBREAK = CALLOUT_MODE_JAILBREAK
Sszorak.RAID_ROLE_MEMBER = RAID_ROLE_MEMBER
Sszorak.RAID_ROLE_COMMANDER = RAID_ROLE_COMMANDER
Sszorak.ADDON_CHECK_MODULE_ID = ADDON_CHECK_MODULE_ID

---Raid leader is commander (edge-click macros / sync UI); everyone else is a member.
---@return string
function Sszorak:GetRaidRole()
    if Group.IsPlayerRaidLeader() then
        return RAID_ROLE_COMMANDER
    end
    return RAID_ROLE_MEMBER
end

---@return boolean
function Sszorak:IsRaidCommander()
    return self:GetRaidRole() == RAID_ROLE_COMMANDER
end

function Sszorak:OnInit()
    -- Later files add these repair steps. OnInit runs after every file has loaded.
    self:RepairEdgeMarkers()
    self:RepairMapSettings()
    self:RepairCalloutMode()
    -- Raid members must answer config checks; register regardless of UI, role, or encounter.
    ns.AddonCheck.Register(ADDON_CHECK_MODULE_ID, function()
        return Sszorak:GetAddonCheckConfig()
    end)
end
