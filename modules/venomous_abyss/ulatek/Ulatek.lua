local _, ns = ...
local Internals = ns.Modules.Internals("Ulatek")
local Util = ns.Util

-- Same range as the Sszorak arena map and the main panel scale control.
local PAD_SCALE_MIN = 0.8
local PAD_SCALE_MAX = 1.5
local PAD_SCALE_STEP = 0.05

-- Ulatek, the eighth boss of The Venomous Abyss.
-- There is no module-wide enable. Each reminder keeps its own saved settings.

---@class UlatekMechanicReminder
---@field eggDeadline boolean
---@field causticWaves boolean
---@field wretchAoe boolean

---@class UlatekPadPosition
---@field point string  e.g. "CENTER".
---@field relativePoint string
---@field x number
---@field y number

---@class UlatekSettings
---@field mechanicReminder UlatekMechanicReminder
---@field cornerMarkers table<integer, WorldMarker>
---@field tacticalPadPosition UlatekPadPosition
---@field tacticalPadScale number

---@class Ulatek: Module
---@field db UlatekSettings
---@field OnCornerMarkersChanged fun(self: Ulatek)|nil  Defined by the UI; called after the assignment changes.
local Ulatek = ns.Modules.New("Ulatek", {
    defaults = {
        mechanicReminder = {
            -- When true, the egg-deadline reminder is shown.
            eggDeadline = false,
            -- When true, the caustic-waves reminder is shown.
            causticWaves = false,
            -- When true, the Wretch AoE reminder is shown.
            wretchAoe = false,
        },
        ---@type table<integer, WorldMarker>  Corner index to marker; every vertex is marked.
        cornerMarkers = {
            [1] = "STAR",
            [2] = "CIRCLE",
            [3] = "DIAMOND",
            [4] = "TRIANGLE",
            [5] = "MOON",
            [6] = "SQUARE",
            [7] = "CROSS",
            [8] = "SKULL",
        },
        -- Unset factory default (center). The window places this at 80% of max X, y = 0.
        ---@type UlatekPadPosition
        tacticalPadPosition = { point = "CENTER", relativePoint = "CENTER", x = 0, y = 0 },
        -- Scale of the floating tactical pad.
        tacticalPadScale = 1,
    },
})

Ulatek.PAD_SCALE_MIN = PAD_SCALE_MIN
Ulatek.PAD_SCALE_MAX = PAD_SCALE_MAX
Ulatek.PAD_SCALE_STEP = PAD_SCALE_STEP

ns.RaidRole.Attach(Ulatek)

---@param settings any
---@return UlatekMechanicReminder
local function SanitizeMechanicReminder(settings)
    if type(settings) ~= "table" then
        return {
            eggDeadline = false,
            causticWaves = false,
            wretchAoe = false,
        }
    end
    settings.eggDeadline = settings.eggDeadline == true
    settings.causticWaves = settings.causticWaves == true
    settings.wretchAoe = settings.wretchAoe == true
    settings.addSoak = nil
    return settings
end

---@param key string
---@return boolean
local function ReminderEnabled(key)
    return Ulatek.db.mechanicReminder[key] == true
end

---@param key string
---@param enabled boolean
local function SetReminderEnabled(key, enabled)
    enabled = enabled == true
    if Ulatek.db.mechanicReminder[key] == enabled then
        return
    end
    Ulatek.db.mechanicReminder[key] = enabled
    if not enabled then
        Internals.HideMechanicCallout(key)
    end
end

function Ulatek:OnInit()
    self.db.mechanicReminder = SanitizeMechanicReminder(self.db.mechanicReminder)
    self:RepairCornerMarkers()
    if not ns.Position.IsValid(self.db.tacticalPadPosition) then
        self.db.tacticalPadPosition = { point = "CENTER", relativePoint = "CENTER", x = 0, y = 0 }
    end
    self.db.tacticalPadScale =
        Util.Snap(tonumber(self.db.tacticalPadScale) or 1, PAD_SCALE_MIN, PAD_SCALE_MAX, PAD_SCALE_STEP)
end

---@return boolean
function Ulatek:IsEggDeadlineReminderEnabled()
    return ReminderEnabled("eggDeadline")
end

---@param enabled boolean
function Ulatek:SetEggDeadlineReminderEnabled(enabled)
    SetReminderEnabled("eggDeadline", enabled)
end

---@return boolean
function Ulatek:IsCausticWavesReminderEnabled()
    return ReminderEnabled("causticWaves")
end

---@param enabled boolean
function Ulatek:SetCausticWavesReminderEnabled(enabled)
    SetReminderEnabled("causticWaves", enabled)
end

---@return boolean
function Ulatek:IsWretchAoeReminderEnabled()
    return ReminderEnabled("wretchAoe")
end

---@param enabled boolean
function Ulatek:SetWretchAoeReminderEnabled(enabled)
    SetReminderEnabled("wretchAoe", enabled)
end

---@return UlatekPadPosition
function Ulatek:GetTacticalPadPosition()
    return self.db.tacticalPadPosition
end

---@param position UlatekPadPosition
function Ulatek:SetTacticalPadPosition(position)
    assert(ns.Position.IsValid(position), "Bad position")
    local saved = self.db.tacticalPadPosition
    saved.point, saved.relativePoint = position.point, position.relativePoint
    saved.x, saved.y = position.x, position.y
end

---@return number
function Ulatek:GetTacticalPadScale()
    return Util.Snap(self.db.tacticalPadScale, PAD_SCALE_MIN, PAD_SCALE_MAX, PAD_SCALE_STEP)
end

---@param scale number
function Ulatek:SetTacticalPadScale(scale)
    assert(type(scale) == "number", "Bad scale")
    self.db.tacticalPadScale = Util.Snap(scale, PAD_SCALE_MIN, PAD_SCALE_MAX, PAD_SCALE_STEP)
end
