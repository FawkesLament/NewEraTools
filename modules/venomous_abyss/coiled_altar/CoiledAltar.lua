local _, ns = ...
local Internals = ns.Modules.Internals("CoiledAltar")
local Util = ns.Util

-- Stable AddonCheck provider id; version is owned by AddonCheck, not this snapshot.
local ADDON_CHECK_MODULE_ID = "CoiledAltar"

-- The Coiled Altar, the seventh boss of The Venomous Abyss.
-- There is no module-wide enable. Each reminder keeps its own saved settings.
local SCALE_MIN = 0.7
local SCALE_MAX = 1.5
local SCALE_STEP = 0.05
local NUMBER_FONT_SIZE = 14
local NUMBER_FONT_SIZE_MIN = 8
local NUMBER_FONT_SIZE_MAX = 24
local NUMBER_FONT_SIZE_STEP = 1
local NAME_FONT_SIZE = 11
local NAME_FONT_SIZE_MIN = 8
local NAME_FONT_SIZE_MAX = 20
local NAME_FONT_SIZE_STEP = 1
local OFFSET_MIN = -100
local OFFSET_MAX = 100
local OFFSET_STEP = 1
local SIDE_TOP = "top"
local SIDE_BOTTOM = "bottom"

---@class CoiledAltarNameplateHint
---@field enabled boolean
---@field side "top"|"bottom"
---@field scale number
---@field numberFontSize number
---@field nameFontSize number
---@field offsetX number
---@field offsetY number

---@class CoiledAltarMechanicReminder
---@field interrupt boolean
---@field ghostChase boolean
---@field orbCarryOdd boolean
---@field orbCarryEven boolean

---@class CoiledAltarSettings
---@field nameplateHint CoiledAltarNameplateHint
---@field mechanicReminder CoiledAltarMechanicReminder
---@field assignments CoiledAltarInterruptAssignments
---@field markedChain CoiledAltarInterruptChainId

---@class CoiledAltar: Module
---@field db CoiledAltarSettings
---@field OnInterruptAssignmentsChanged fun(self: CoiledAltar)|nil  Defined by the assignment editor.
---@field OnInterruptStateChanged fun(self: CoiledAltar)|nil  Defined by the UI; encounter HUD consumers refresh.
---@field OnNameplateHintChanged fun(self: CoiledAltar)|nil  Defined by the UI; nameplate preview button enabled or blocked.
---@field OnNameplateHintPreviewChanged fun(self: CoiledAltar)|nil  Defined by the UI; nameplate indicators shown or hidden.
---@field OnNameplateHintAppearanceChanged fun(self: CoiledAltar)|nil  Defined by the UI; visible indicators restyled.
---@field OnNameplateHintShow fun(self: CoiledAltar, unit: string, number: integer, playerName: string, classFile: string|nil)|nil
---@field OnNameplateHintHide fun(self: CoiledAltar, unit: string)|nil
---@field OnNameplateHintCleared fun(self: CoiledAltar)|nil
---@field OnNameplateHintApply fun(self: CoiledAltar, views: table<string, CoiledAltarNameplateIndicatorView>)|nil
local CoiledAltar = ns.Modules.New("CoiledAltar", {
    defaults = {
        mechanicReminder = {
            -- When true, the interrupt callout and status HUD are shown.
            interrupt = true,
            -- When true, a matched ENCOUNTER_WARNING shows the ghost-chase Callout.
            ghostChase = false,
            -- When true, odd-wave orb-carry reminders are shown.
            orbCarryOdd = false,
            -- When true, even-wave orb-carry reminders are shown.
            orbCarryEven = false,
        },
        nameplateHint = {
            -- When true, interrupt assignments are shown on nameplates.
            enabled = false,
            side = SIDE_BOTTOM,
            scale = 1,
            numberFontSize = NUMBER_FONT_SIZE,
            nameFontSize = NAME_FONT_SIZE,
            offsetX = 0,
            offsetY = 0,
        },
        -- Encounter-wide interrupt chains. Sanitized to six slots per chain in OnInit.
        assignments = {},
        -- Raid-marked shadows belong to this interrupt chain; the unmarked pair is the other.
        markedChain = "MELEE",
    },
})

CoiledAltar.SCALE_MIN = SCALE_MIN
CoiledAltar.SCALE_MAX = SCALE_MAX
CoiledAltar.SCALE_STEP = SCALE_STEP
CoiledAltar.NUMBER_FONT_SIZE_MIN = NUMBER_FONT_SIZE_MIN
CoiledAltar.NUMBER_FONT_SIZE_MAX = NUMBER_FONT_SIZE_MAX
CoiledAltar.NUMBER_FONT_SIZE_STEP = NUMBER_FONT_SIZE_STEP
CoiledAltar.NAME_FONT_SIZE_MIN = NAME_FONT_SIZE_MIN
CoiledAltar.NAME_FONT_SIZE_MAX = NAME_FONT_SIZE_MAX
CoiledAltar.NAME_FONT_SIZE_STEP = NAME_FONT_SIZE_STEP
CoiledAltar.OFFSET_MIN = OFFSET_MIN
CoiledAltar.OFFSET_MAX = OFFSET_MAX
CoiledAltar.OFFSET_STEP = OFFSET_STEP
CoiledAltar.SIDE_TOP = SIDE_TOP
CoiledAltar.SIDE_BOTTOM = SIDE_BOTTOM
CoiledAltar.ADDON_CHECK_MODULE_ID = ADDON_CHECK_MODULE_ID
-- Raid leader is commander for interrupt assignments; everyone else is a member.
ns.RaidRole.Attach(CoiledAltar)

-- Session-only; the settings toggle does not show indicators until the player starts a preview.
local nameplateHintPreviewing = false

local function NotifyNameplateHintChanged()
    if CoiledAltar.OnNameplateHintChanged then
        CoiledAltar:OnNameplateHintChanged()
    end
end

local function NotifyNameplateHintPreviewChanged()
    if CoiledAltar.OnNameplateHintPreviewChanged then
        CoiledAltar:OnNameplateHintPreviewChanged()
    end
end

local function NotifyNameplateHintAppearanceChanged()
    if CoiledAltar.OnNameplateHintAppearanceChanged then
        CoiledAltar:OnNameplateHintAppearanceChanged()
    end
end

local function IsSide(side)
    return side == SIDE_TOP or side == SIDE_BOTTOM
end

---@param settings any
---@return CoiledAltarNameplateHint
local function SanitizeNameplateHint(settings)
    if type(settings) ~= "table" then
        return {
            enabled = settings == true,
            side = SIDE_BOTTOM,
            scale = 1,
            numberFontSize = NUMBER_FONT_SIZE,
            nameFontSize = NAME_FONT_SIZE,
            offsetX = 0,
            offsetY = 0,
        }
    end
    settings.enabled = settings.enabled == true
    if not IsSide(settings.side) then
        settings.side = SIDE_BOTTOM
    end
    settings.scale = Util.Snap(tonumber(settings.scale) or 1, SCALE_MIN, SCALE_MAX, SCALE_STEP)
    settings.numberFontSize = Util.Snap(
        tonumber(settings.numberFontSize) or NUMBER_FONT_SIZE,
        NUMBER_FONT_SIZE_MIN,
        NUMBER_FONT_SIZE_MAX,
        NUMBER_FONT_SIZE_STEP
    )
    settings.nameFontSize = Util.Snap(
        tonumber(settings.nameFontSize) or NAME_FONT_SIZE,
        NAME_FONT_SIZE_MIN,
        NAME_FONT_SIZE_MAX,
        NAME_FONT_SIZE_STEP
    )
    settings.offsetX = Util.Snap(tonumber(settings.offsetX) or 0, OFFSET_MIN, OFFSET_MAX, OFFSET_STEP)
    settings.offsetY = Util.Snap(tonumber(settings.offsetY) or 0, OFFSET_MIN, OFFSET_MAX, OFFSET_STEP)
    return settings
end

---@param settings any
---@return CoiledAltarMechanicReminder
local function SanitizeMechanicReminder(settings)
    if type(settings) ~= "table" then
        return { interrupt = true, ghostChase = false, orbCarryOdd = false, orbCarryEven = false }
    end
    settings.enabled = nil
    settings.interrupt = settings.interrupt == true
    settings.ghostChase = settings.ghostChase == true
    settings.orbCarryOdd = settings.orbCarryOdd == true
    settings.orbCarryEven = settings.orbCarryEven == true
    return settings
end

---@param chainId any
---@return CoiledAltarInterruptChainId
local function SanitizeMarkedChain(chainId)
    if Internals.InterruptAssignments.IsChain(chainId) then
        return chainId
    end
    return Internals.InterruptAssignments.MELEE
end

function CoiledAltar:OnInit()
    self.db.mechanicReminder = SanitizeMechanicReminder(self.db.mechanicReminder)
    self.db.interruptReminder = nil
    self.db.nameplateHint = SanitizeNameplateHint(self.db.nameplateHint)
    self.db.assignments = Internals.InterruptAssignments.SanitizeSaved(self.db.assignments)
    self.db.markedChain = SanitizeMarkedChain(self.db.markedChain)
    -- Raid members must answer config checks; register regardless of UI, role, or encounter.
    ns.AddonCheck.Register(ADDON_CHECK_MODULE_ID, function()
        return CoiledAltar:GetAddonCheckConfig()
    end)
end

---Adopts interrupt-assignment publications from the raid. Called from OnEnable.
function CoiledAltar:ListenForInterruptSync()
    Internals.InterruptSync.Listen()
end

---@return CoiledAltarInterruptChainId
function CoiledAltar:GetMarkedChain()
    return SanitizeMarkedChain(self.db.markedChain)
end

---Raid-marked shadows' interrupt chain. Display code should read Internals.MarkedChain.
---@return CoiledAltarInterruptChainId
function Internals.MarkedChain()
    return CoiledAltar:GetMarkedChain()
end

---@param chainId CoiledAltarInterruptChainId
---@return boolean changed
function CoiledAltar:SetMarkedChain(chainId)
    local Assignments = Internals.InterruptAssignments
    assert(Assignments.IsChain(chainId), "Bad marked chain")
    if self.db.markedChain == chainId then
        return false
    end
    self.db.markedChain = chainId
    Internals.NotifyEncounterState()
    return true
end

---@return boolean
function CoiledAltar:IsInterruptReminderEnabled()
    return self.db.mechanicReminder.interrupt == true
end

---@param enabled boolean
function CoiledAltar:SetInterruptReminderEnabled(enabled)
    enabled = enabled == true
    if self.db.mechanicReminder.interrupt == enabled then
        return
    end
    self.db.mechanicReminder.interrupt = enabled
    Internals.NotifyEncounterState()
end

---@return boolean
function CoiledAltar:IsGhostChaseReminderEnabled()
    return self.db.mechanicReminder.ghostChase == true
end

---@param enabled boolean
function CoiledAltar:SetGhostChaseReminderEnabled(enabled)
    enabled = enabled == true
    if self.db.mechanicReminder.ghostChase == enabled then
        return
    end
    self.db.mechanicReminder.ghostChase = enabled
    if not enabled then
        Internals.HideGhostChaseCallout()
    end
end

---@return boolean
function CoiledAltar:IsOrbCarryOddReminderEnabled()
    return self.db.mechanicReminder.orbCarryOdd == true
end

---@param enabled boolean
function CoiledAltar:SetOrbCarryOddReminderEnabled(enabled)
    enabled = enabled == true
    if self.db.mechanicReminder.orbCarryOdd == enabled then
        return
    end
    self.db.mechanicReminder.orbCarryOdd = enabled
    if not enabled then
        Internals.HideOrbCarryCallout("odd")
    end
end

---@return boolean
function CoiledAltar:IsOrbCarryEvenReminderEnabled()
    return self.db.mechanicReminder.orbCarryEven == true
end

---@param enabled boolean
function CoiledAltar:SetOrbCarryEvenReminderEnabled(enabled)
    enabled = enabled == true
    if self.db.mechanicReminder.orbCarryEven == enabled then
        return
    end
    self.db.mechanicReminder.orbCarryEven = enabled
    if not enabled then
        Internals.HideOrbCarryCallout("even")
    end
end

---@return InterruptRotationTrackerAnchor
function CoiledAltar:GetInterruptRotationTrackerPosition()
    return ns.InterruptRotationTrackerAnchor.GetPosition()
end

---@param position InterruptRotationTrackerAnchor
function CoiledAltar:SetInterruptRotationTrackerPosition(position)
    ns.InterruptRotationTrackerAnchor.SetPosition(position)
end

---@return boolean
function CoiledAltar:IsNameplateHintEnabled()
    return self.db.nameplateHint.enabled == true
end

---@param enabled boolean
function CoiledAltar:SetNameplateHintEnabled(enabled)
    enabled = enabled == true
    if self.db.nameplateHint.enabled == enabled then
        return
    end
    self.db.nameplateHint.enabled = enabled
    if not enabled then
        self:SetNameplateHintPreviewing(false)
    end
    NotifyNameplateHintChanged()
    Internals.SyncNameplateIndicators()
end

---@return boolean
function CoiledAltar:IsNameplateHintPreviewing()
    return nameplateHintPreviewing == true
end

---@param enabled boolean
function CoiledAltar:SetNameplateHintPreviewing(enabled)
    enabled = enabled == true and self:IsNameplateHintEnabled()
    if nameplateHintPreviewing == enabled then
        return
    end
    nameplateHintPreviewing = enabled
    NotifyNameplateHintPreviewChanged()
end

---@return "top"|"bottom"
function CoiledAltar:GetNameplateHintSide()
    local side = self.db.nameplateHint.side
    if IsSide(side) then
        return side
    end
    return SIDE_BOTTOM
end

---@param side "top"|"bottom"
function CoiledAltar:SetNameplateHintSide(side)
    assert(IsSide(side), "Bad nameplate hint side")
    if self.db.nameplateHint.side == side then
        return
    end
    self.db.nameplateHint.side = side
    NotifyNameplateHintAppearanceChanged()
end

---@return number
function CoiledAltar:GetNameplateHintScale()
    return self.db.nameplateHint.scale
end

---@param scale number
function CoiledAltar:SetNameplateHintScale(scale)
    assert(type(scale) == "number", "Bad scale")
    scale = Util.Snap(scale, SCALE_MIN, SCALE_MAX, SCALE_STEP)
    if self.db.nameplateHint.scale == scale then
        return
    end
    self.db.nameplateHint.scale = scale
    NotifyNameplateHintAppearanceChanged()
end

---@return number
function CoiledAltar:GetNameplateHintNumberFontSize()
    return self.db.nameplateHint.numberFontSize
end

---@param size number
function CoiledAltar:SetNameplateHintNumberFontSize(size)
    size = Util.Snap(size, NUMBER_FONT_SIZE_MIN, NUMBER_FONT_SIZE_MAX, NUMBER_FONT_SIZE_STEP)
    if self.db.nameplateHint.numberFontSize == size then
        return
    end
    self.db.nameplateHint.numberFontSize = size
    NotifyNameplateHintAppearanceChanged()
end

---@return number
function CoiledAltar:GetNameplateHintNameFontSize()
    return self.db.nameplateHint.nameFontSize
end

---@param size number
function CoiledAltar:SetNameplateHintNameFontSize(size)
    size = Util.Snap(size, NAME_FONT_SIZE_MIN, NAME_FONT_SIZE_MAX, NAME_FONT_SIZE_STEP)
    if self.db.nameplateHint.nameFontSize == size then
        return
    end
    self.db.nameplateHint.nameFontSize = size
    NotifyNameplateHintAppearanceChanged()
end

---@return number
function CoiledAltar:GetNameplateHintOffsetX()
    return self.db.nameplateHint.offsetX
end

---@param offset number
function CoiledAltar:SetNameplateHintOffsetX(offset)
    offset = Util.Snap(offset, OFFSET_MIN, OFFSET_MAX, OFFSET_STEP)
    if self.db.nameplateHint.offsetX == offset then
        return
    end
    self.db.nameplateHint.offsetX = offset
    NotifyNameplateHintAppearanceChanged()
end

---@return number
function CoiledAltar:GetNameplateHintOffsetY()
    return self.db.nameplateHint.offsetY
end

---@param offset number
function CoiledAltar:SetNameplateHintOffsetY(offset)
    offset = Util.Snap(offset, OFFSET_MIN, OFFSET_MAX, OFFSET_STEP)
    if self.db.nameplateHint.offsetY == offset then
        return
    end
    self.db.nameplateHint.offsetY = offset
    NotifyNameplateHintAppearanceChanged()
end
