local _, ns = ...
local Internals = ns.Modules.Internals("CoiledAltar")
local Util = ns.Util

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

---@class CoiledAltarSettings
---@field nameplateHint CoiledAltarNameplateHint
---@field assignments CoiledAltarInterruptAssignments

---@class CoiledAltar: Module
---@field db CoiledAltarSettings
---@field OnInterruptAssignmentsChanged fun(self: CoiledAltar)|nil  Defined by the assignment editor.
---@field OnNameplateHintChanged fun(self: CoiledAltar)|nil  Defined by the UI; nameplate preview button enabled or blocked.
---@field OnNameplateHintPreviewChanged fun(self: CoiledAltar)|nil  Defined by the UI; nameplate indicators shown or hidden.
---@field OnNameplateHintAppearanceChanged fun(self: CoiledAltar)|nil  Defined by the UI; visible indicators restyled.
---@field OnNameplateHintShow fun(self: CoiledAltar, unit: string, number: integer, playerName: string, classFile: string|nil)|nil
---@field OnNameplateHintHide fun(self: CoiledAltar, unit: string)|nil
---@field OnNameplateHintCleared fun(self: CoiledAltar)|nil
local CoiledAltar = ns.Modules.New("CoiledAltar", {
    defaults = {
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

function CoiledAltar:OnInit()
    self.db.nameplateHint = SanitizeNameplateHint(self.db.nameplateHint)
    self.db.assignments = Internals.InterruptAssignments.SanitizeSaved(self.db.assignments)
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
