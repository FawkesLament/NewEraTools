local _, ns = ...
local Internals = ns.Modules.Internals("Ulatek")

-- Ulatek, the eighth boss of The Venomous Abyss.
-- There is no module-wide enable. Each reminder keeps its own saved settings.

---@class UlatekMechanicReminder
---@field eggDeadline boolean
---@field causticWaves boolean
---@field wretchAoe boolean

---@class UlatekSettings
---@field mechanicReminder UlatekMechanicReminder
---@field cornerMarkers table<integer, WorldMarker>

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
    },
})

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
