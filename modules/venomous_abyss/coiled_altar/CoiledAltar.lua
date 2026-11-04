local _, ns = ...
local Internals = ns.Modules.Internals("CoiledAltar")
local Player = ns.Api.Player
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

---@class CoiledAltarMechanicReminder
---@field enabled boolean
---@field interrupt boolean

---@class CoiledAltarSettings
---@field nameplateHint CoiledAltarNameplateHint
---@field mechanicReminder CoiledAltarMechanicReminder
---@field assignments CoiledAltarInterruptAssignments

---@class CoiledAltar: Module
---@field db CoiledAltarSettings
---@field OnInterruptAssignmentsChanged fun(self: CoiledAltar)|nil  Defined by the assignment editor.
---@field OnInterruptStateChanged fun(self: CoiledAltar)|nil  Defined by UI consumers; encounter interrupt state is ready.
---@field OnNameplateHintChanged fun(self: CoiledAltar)|nil  Defined by the UI; nameplate preview button enabled or blocked.
---@field OnNameplateHintPreviewChanged fun(self: CoiledAltar)|nil  Defined by the UI; nameplate indicators shown or hidden.
---@field OnNameplateHintAppearanceChanged fun(self: CoiledAltar)|nil  Defined by the UI; visible indicators restyled.
---@field OnNameplateHintShow fun(self: CoiledAltar, unit: string, number: integer, playerName: string, classFile: string|nil)|nil
---@field OnNameplateHintHide fun(self: CoiledAltar, unit: string)|nil
---@field OnNameplateHintCleared fun(self: CoiledAltar)|nil
local CoiledAltar = ns.Modules.New("CoiledAltar", {
    defaults = {
        mechanicReminder = {
            enabled = false,
            -- When true, the interrupt callout and status HUD are shown.
            interrupt = false,
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
CoiledAltar.INTERRUPT_CALLOUT_DURATION = 10

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
        return { enabled = settings == true, interrupt = false }
    end
    settings.enabled = settings.enabled == true
    settings.interrupt = settings.interrupt == true
    return settings
end

function CoiledAltar:OnInit()
    self.db.mechanicReminder = SanitizeMechanicReminder(self.db.mechanicReminder)
    self.db.interruptReminder = nil
    self.db.nameplateHint = SanitizeNameplateHint(self.db.nameplateHint)
    self.db.assignments = Internals.InterruptAssignments.SanitizeSaved(self.db.assignments)
end

---@return boolean
function CoiledAltar:IsMechanicReminderEnabled()
    return self.db.mechanicReminder.enabled == true
end

---@param enabled boolean
function CoiledAltar:SetMechanicReminderEnabled(enabled)
    enabled = enabled == true
    if self.db.mechanicReminder.enabled == enabled then
        return
    end
    self.db.mechanicReminder.enabled = enabled
    if self.OnInterruptStateChanged then
        self:OnInterruptStateChanged()
    end
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
    if self.OnInterruptStateChanged then
        self:OnInterruptStateChanged()
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

---@param state CoiledAltarInterruptState
---@param object CoiledAltarShadow|nil
---@return CoiledAltarShadow|nil
local function LiveShadow(state, object)
    if not object then
        return nil
    end
    for index = 1, #state.list do
        if state.list[index] == object then
            return object
        end
    end
    return nil
end

---@param indices integer[]
---@return integer[]
local function CopyIndices(indices)
    local copy = {}
    for index = 1, #indices do
        copy[index] = indices[index]
    end
    return copy
end

---@class CoiledAltarInterruptAssignment
---@field chainId CoiledAltarInterruptChainId
---@field indices integer[]

---@class CoiledAltarRotationTrackerView
---@field mode "hidden"|"normal"|"pending"
---@field chainId CoiledAltarInterruptChainId|nil
---@field indices integer[]|nil
---@field kicks integer|nil
---@field casting boolean|nil

---Read-only RotationTracker view for the local player's assignment.
---@param state CoiledAltarInterruptState|nil
---@param assignment CoiledAltarInterruptAssignment|nil
---@return CoiledAltarRotationTrackerView
function Internals.ResolveRotationTrackerView(state, assignment)
    if not state or state.disposed or not state.curWave then
        return { mode = "hidden" }
    end
    if type(assignment) ~= "table" or type(assignment.indices) ~= "table" or #assignment.indices == 0 then
        return { mode = "hidden" }
    end
    local Assignments = Internals.InterruptAssignments
    local chainId = assignment.chainId
    if not Assignments.IsChain(chainId) then
        return { mode = "hidden" }
    end
    local wave = state.curWave
    if type(wave) ~= "table" or type(wave.members) ~= "table" then
        return { mode = "hidden" }
    end
    local memberCount = #wave.members
    if memberCount ~= 1 and memberCount ~= 2 then
        return { mode = "hidden" }
    end

    local firstMelee, secondMelee = Internals.InterruptTracker.GetPossibleWorlds(wave)
    local candidates = {}
    local function Consider(index)
        local shadow = wave.members[index]
        if shadow then
            candidates[#candidates + 1] = shadow
        end
    end
    if chainId == Assignments.MELEE then
        if firstMelee then
            Consider(1)
        end
        if secondMelee then
            Consider(2)
        end
    else
        if firstMelee then
            Consider(2)
        end
        if secondMelee then
            Consider(1)
        end
    end
    if #candidates == 0 then
        return { mode = "hidden" }
    end

    local indices = CopyIndices(assignment.indices)
    if #candidates == 1 then
        local shadow = candidates[1]
        if not LiveShadow(state, shadow) then
            return { mode = "hidden" }
        end
        return {
            mode = "normal",
            chainId = chainId,
            indices = indices,
            kicks = shadow.kicks,
            casting = shadow.casting == true,
        }
    end

    local kicks = candidates[1].kicks
    for index = 2, #candidates do
        if candidates[index].kicks ~= kicks then
            return {
                mode = "pending",
                chainId = chainId,
                indices = indices,
            }
        end
    end
    return {
        mode = "normal",
        chainId = chainId,
        indices = indices,
        kicks = kicks,
        casting = false,
    }
end

---@param indices integer[]
---@return integer
local function ConsecutiveEnd(indices)
    local last = indices[1]
    for index = 2, #indices do
        if indices[index] ~= last + 1 then
            break
        end
        last = indices[index]
    end
    return last
end

---@class CoiledAltarInterruptStatus
---@field chainId CoiledAltarInterruptChainId
---@field indices integer[]
---@field index integer
---@field indexEnd integer
---@field kicks integer|nil
---@field pending boolean
---@field chainLength integer
---@field casting boolean

---Local player's interrupt HUD snapshot for the current wave, or nil when it cannot be shown.
---@return CoiledAltarInterruptStatus|nil
function CoiledAltar:GetInterruptStatus()
    local Assignments = Internals.InterruptAssignments
    local chainId, indices = Assignments.PlayerPositions(self.db.assignments, Player.GetFullName())
    local assignment
    if chainId and #indices > 0 then
        assignment = { chainId = chainId, indices = indices }
    end
    local view = Internals.ResolveRotationTrackerView(Internals.InterruptTracker.Get(), assignment)
    if view.mode == "hidden" then
        return nil
    end
    return {
        chainId = view.chainId,
        indices = view.indices,
        index = view.indices[1],
        indexEnd = ConsecutiveEnd(view.indices),
        kicks = view.kicks,
        pending = view.mode == "pending",
        chainLength = Assignments.SLOT_COUNT,
        casting = view.casting == true,
    }
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
