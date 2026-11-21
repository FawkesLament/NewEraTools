-- Schedules Guillotine soak Callouts from P1/P3 clocks: 10s before each soak deadline.
local _, ns = ...
local Internals = ns.Modules.Internals("CoiledAltar")
local CalloutManager = ns.CalloutManager
local Timer = ns.Api.Timer
local L = ns.L

local CoiledAltar = ns.Modules.Get("CoiledAltar")

local CALLOUT_SOURCE = "CoiledAltarSoak"
local PHASE_P1 = "P1"
local PHASE_P2 = "P2"
local PHASE_P3 = "P3"

local CAST_DEADLINE = 3.5
local REMINDER_LEAD = 10

---@alias CoiledAltarSoakKind "p1First"|"p1Second"|"p3First"|"p3Second"|"p3Third"

---@class CoiledAltarSoakOccurrence
---@field kind CoiledAltarSoakKind
---@field castAt number

---@type table<string, CoiledAltarSoakOccurrence[]>
local PHASE_CASTS = {
    [PHASE_P1] = {
        { kind = "p1First", castAt = 43.0 },
        { kind = "p1Second", castAt = 128.0 },
    },
    [PHASE_P3] = {
        { kind = "p3First", castAt = 16.64 },
        { kind = "p3Second", castAt = 81.1 },
        { kind = "p3Third", castAt = 181.1 },
    },
}

---@type CalloutManagerHandle|nil
local presented = nil
---@type CoiledAltarSoakKind|nil
local presentedKind = nil
---@type ResourceScope|nil
local reminderScope = nil

local function HidePresented()
    if presented then
        presented:Dismiss()
        presented = nil
    end
    presentedKind = nil
end

---@param kind CoiledAltarSoakKind|nil
function Internals.HideSoakCallout(kind)
    if kind ~= nil and presentedKind ~= kind then
        return
    end
    HidePresented()
end

---@param kind CoiledAltarSoakKind
---@return boolean
local function IsKindEnabled(kind)
    if kind == "p1First" then
        return CoiledAltar:IsSoakP1FirstReminderEnabled()
    end
    if kind == "p1Second" then
        return CoiledAltar:IsSoakP1SecondReminderEnabled()
    end
    if kind == "p3First" then
        return CoiledAltar:IsSoakP3FirstReminderEnabled()
    end
    if kind == "p3Second" then
        return CoiledAltar:IsSoakP3SecondReminderEnabled()
    end
    return CoiledAltar:IsSoakP3ThirdReminderEnabled()
end

local function ResetReminderScope()
    if reminderScope then
        reminderScope:Dispose()
    end
    reminderScope = ns.ResourceScope.New()
end

local function CancelScheduledReminders()
    ResetReminderScope()
    HidePresented()
end

---@param kind CoiledAltarSoakKind
---@param deadline number
local function ShowReminder(kind, deadline)
    if not IsKindEnabled(kind) then
        return
    end
    HidePresented()
    presentedKind = kind
    presented = CalloutManager.Show({
        source = CALLOUT_SOURCE,
        text = L.COILED_ALTAR_SOAK_CALLOUT,
        expiresAt = deadline,
        appendTimer = true,
    })
end

---@param phase CoiledAltarPhase
---@param phaseStart number
local function SchedulePhase(phase, phaseStart)
    local occurrences = PHASE_CASTS[phase]
    if not occurrences or not reminderScope then
        return
    end
    local now = Timer.GetTime()
    for index = 1, #occurrences do
        local occurrence = occurrences[index]
        local deadline = phaseStart + occurrence.castAt + CAST_DEADLINE
        if deadline > now then
            local delay = deadline - REMINDER_LEAD - now
            if delay <= 0 then
                ShowReminder(occurrence.kind, deadline)
            else
                local kind = occurrence.kind
                reminderScope:After(delay, function()
                    ShowReminder(kind, deadline)
                end)
            end
        end
    end
end

---@param phase CoiledAltarPhase
---@param at number
local function OnPhaseChanged(phase, at)
    if phase == PHASE_P2 then
        CancelScheduledReminders()
        return
    end
    if phase == PHASE_P3 then
        CancelScheduledReminders()
        SchedulePhase(PHASE_P3, at)
    end
end

---Owns this pull's phase-change hook and scheduled soak reminders until `scope` is disposed.
---@param scope ResourceScope
function Internals.StartSoak(scope)
    CancelScheduledReminders()
    scope:Subscribe(Internals.PhaseDetector.OnChanged, OnPhaseChanged)
    local phase = Internals.PhaseDetector.GetPhase()
    local phaseStart = Internals.PhaseDetector.GetPhaseStartTime()
    if phase == PHASE_P1 and phaseStart ~= nil then
        SchedulePhase(PHASE_P1, phaseStart)
    end
    scope:Add(function()
        CancelScheduledReminders()
        reminderScope = nil
    end)
end
