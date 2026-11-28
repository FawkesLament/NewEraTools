local _, ns = ...
local Internals = ns.Modules.Internals("Ulatek")
local L = ns.L
local CalloutManager = ns.CalloutManager
local Encounter = ns.Api.Encounter
local Timer = ns.Api.Timer

local Ulatek = ns.Modules.Get("Ulatek")
local Timeline = Internals.Timeline

-- Ulatek in The Venomous Abyss.
local ENCOUNTER_ID = 3492
local CALLOUT_SOURCE = "Ulatek"

Ulatek.ENCOUNTER_ID = ENCOUNTER_ID

---@type table<UlatekMechanicId, CalloutManagerHandle>
local handles = {}

---@param mechanicId UlatekMechanicId
---@return boolean
local function IsMechanicEnabled(mechanicId)
    if mechanicId == Timeline.CAUSTIC_WAVES then
        return Ulatek:IsCausticWavesReminderEnabled()
    end
    if mechanicId == Timeline.EGG_DEADLINE then
        return Ulatek:IsEggDeadlineReminderEnabled()
    end
    return Ulatek:IsWretchAoeReminderEnabled()
end

---@param mechanicId UlatekMechanicId
---@return string
local function CalloutText(mechanicId)
    if mechanicId == Timeline.CAUSTIC_WAVES then
        return L.ULATEK_CAUSTIC_WAVES_CALLOUT
    end
    if mechanicId == Timeline.EGG_DEADLINE then
        return L.ULATEK_EGG_DEADLINE_CALLOUT
    end
    return L.ULATEK_WRETCH_AOE_CALLOUT
end

---@param mechanicId UlatekMechanicId
function Internals.HideMechanicCallout(mechanicId)
    local handle = handles[mechanicId]
    handles[mechanicId] = nil
    if handle then
        handle:Dismiss()
    end
end

local function ClearCallouts()
    handles = {}
    CalloutManager.ClearSource(CALLOUT_SOURCE)
end

---@param mechanicId UlatekMechanicId
---@param expiresAt number
local function ShowCallout(mechanicId, expiresAt)
    if not IsMechanicEnabled(mechanicId) then
        return
    end
    handles[mechanicId] = CalloutManager.Show({
        source = CALLOUT_SOURCE,
        key = CALLOUT_SOURCE .. ":" .. mechanicId,
        text = CalloutText(mechanicId),
        expiresAt = expiresAt,
        appendTimer = true,
    })
end

---Owns this pull's scheduled mechanic callouts until `scope` is disposed.
---@param scope ResourceScope
---@param difficultyID number
function Internals.StartAlerts(scope, difficultyID)
    local schedule = Timeline.GetSchedule(difficultyID)
    if not schedule then
        return
    end
    local pullStart = Timer.GetTime()
    local now = pullStart
    ---Captures per-hit values so Lua 5.1 closures do not share loop locals.
    ---@param mechanicId UlatekMechanicId
    ---@param delay number
    ---@param expiresAt number
    local function ScheduleShow(mechanicId, delay, expiresAt)
        if delay <= 0 then
            ShowCallout(mechanicId, expiresAt)
            return
        end
        scope:After(delay, function()
            ShowCallout(mechanicId, expiresAt)
        end)
    end
    for _, mechanicId in ipairs(Timeline.MECHANICS) do
        local mechanic = schedule[mechanicId]
        for index = 1, #mechanic.hits do
            local expiresAt = pullStart + mechanic.hits[index]
            if expiresAt > now then
                ScheduleShow(mechanicId, expiresAt - mechanic.leadTime - now, expiresAt)
            end
        end
    end
    scope:Add(ClearCallouts)
end

---Starts watching this boss fight. Called from OnEnable.
function Ulatek:ListenForEncounter()
    Encounter.WhileIn(ENCOUNTER_ID, function(difficultyID, scope)
        Internals.StartAlerts(scope, difficultyID)
    end)
end
