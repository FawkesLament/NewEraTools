-- Matches Sever timeline events to odd/even orb-carry waves and shows a timed Callout.
local _, ns = ...
local Internals = ns.Modules.Internals("CoiledAltar")
local CalloutManager = ns.CalloutManager
local EncounterTimeline = ns.Api.EncounterTimeline
local Timer = ns.Api.Timer
local L = ns.L

local CoiledAltar = ns.Modules.Get("CoiledAltar")

local CALLOUT_SOURCE = "CoiledAltarOrbCarry"
local PHASE_P1 = "P1"
local PHASE_P2 = "P2"
local PHASE_I2 = "I2"
local PHASE_P3 = "P3"

local P1_ODD_DURATION = 20
local P1_EVEN_DURATION = 17
local DURATION_TOLERANCE = 0.05
local P3_DURATION_MIN = 31
local P3_DURATION_MAX = 37
local DEADLINE_OFFSET = 2.5
local REMINDER_LEAD = 10

local P3_ANCHORS = {
    32.222,
    63.333,
    96.666,
    133.333,
    164.444,
}

---@type CalloutManagerHandle|nil
local presented = nil
---@type "odd"|"even"|nil
local presentedParity = nil
---@type ResourceScope|nil
local reminderScope = nil
---@type { duration: number, receivedAt: number }[]
local pendingI2 = {}
---@type table<string, number>
local lastDeadlineByKey = {}
---@type table<integer, boolean>
local p3Used = {}

local function HidePresented()
    if presented then
        presented:Dismiss()
        presented = nil
    end
    presentedParity = nil
end

---@param parity "odd"|"even"|nil
function Internals.HideOrbCarryCallout(parity)
    if parity ~= nil and presentedParity ~= parity then
        return
    end
    HidePresented()
end

---@param duration number
---@return "odd"|"even"|nil
function Internals.MatchOrbCarryP1Wave(duration)
    if type(duration) ~= "number" then
        return nil
    end
    if math.abs(duration - P1_ODD_DURATION) <= DURATION_TOLERANCE then
        return "odd"
    end
    if math.abs(duration - P1_EVEN_DURATION) <= DURATION_TOLERANCE then
        return "even"
    end
    return nil
end

---@param duration number
---@return boolean
function Internals.IsOrbCarryP3Duration(duration)
    return type(duration) == "number" and duration >= P3_DURATION_MIN and duration <= P3_DURATION_MAX
end

---@param predictedTime number
---@return integer|nil
function Internals.MatchOrbCarryP3Anchor(predictedTime)
    if type(predictedTime) ~= "number" then
        return nil
    end
    for index = 1, #P3_ANCHORS do
        if math.abs(predictedTime - P3_ANCHORS[index]) <= DURATION_TOLERANCE then
            return index
        end
    end
    return nil
end

---@param anchorIndex integer
---@return "odd"|"even"
function Internals.OrbCarryWaveForAnchor(anchorIndex)
    if anchorIndex % 2 == 1 then
        return "odd"
    end
    return "even"
end

---@param parity "odd"|"even"
---@return boolean
local function IsParityEnabled(parity)
    if parity == "odd" then
        return CoiledAltar:IsOrbCarryOddReminderEnabled()
    end
    return CoiledAltar:IsOrbCarryEvenReminderEnabled()
end

local function ResetReminderScope()
    if reminderScope then
        reminderScope:Dispose()
    end
    reminderScope = ns.ResourceScope.New()
end

local function CancelScheduledReminders()
    pendingI2 = {}
    lastDeadlineByKey = {}
    p3Used = {}
    ResetReminderScope()
    HidePresented()
end

---@param occurrenceKey string
---@param deadline number
---@return boolean
local function ClaimOccurrence(occurrenceKey, deadline)
    local previous = lastDeadlineByKey[occurrenceKey]
    if previous and math.abs(previous - deadline) <= DURATION_TOLERANCE then
        return false
    end
    lastDeadlineByKey[occurrenceKey] = deadline
    return true
end

---@param parity "odd"|"even"
---@param deadline number
local function ShowReminder(parity, deadline)
    if not IsParityEnabled(parity) then
        return
    end
    HidePresented()
    presentedParity = parity
    presented = CalloutManager.Show({
        source = CALLOUT_SOURCE,
        text = L.COILED_ALTAR_ORB_CARRY_CALLOUT,
        expiresAt = deadline,
        appendTimer = true,
    })
end

---@param parity "odd"|"even"
---@param duration number
---@param occurrenceKey string
---@param receivedAt number
local function ScheduleReminder(parity, duration, occurrenceKey, receivedAt)
    if not IsParityEnabled(parity) then
        return
    end
    local now = Timer.GetTime()
    local deadline = receivedAt + duration - DEADLINE_OFFSET
    if deadline <= now then
        return
    end
    if not ClaimOccurrence(occurrenceKey, deadline) then
        return
    end
    local reminderStart = deadline - REMINDER_LEAD
    local delay = reminderStart - now
    if delay <= 0 then
        ShowReminder(parity, deadline)
        return
    end
    if not reminderScope then
        return
    end
    reminderScope:After(delay, function()
        ShowReminder(parity, deadline)
    end)
end

---@param duration number
local function TryScheduleP1(duration)
    local parity = Internals.MatchOrbCarryP1Wave(duration)
    if not parity then
        return
    end
    ScheduleReminder(parity, duration, PHASE_P1 .. "-" .. parity, Timer.GetTime())
end

---@param duration number
---@param receivedAt number
---@param p3StartTime number
local function TryScheduleP3(duration, receivedAt, p3StartTime)
    if not Internals.IsOrbCarryP3Duration(duration) then
        return
    end
    local predictedTime = (receivedAt - p3StartTime) + duration
    local anchorIndex = Internals.MatchOrbCarryP3Anchor(predictedTime)
    if not anchorIndex or p3Used[anchorIndex] then
        return
    end
    p3Used[anchorIndex] = true
    local parity = Internals.OrbCarryWaveForAnchor(anchorIndex)
    ScheduleReminder(parity, duration, PHASE_P3 .. "-" .. tostring(anchorIndex), receivedAt)
end

---@param p3StartTime number
local function FlushPendingI2(p3StartTime)
    local candidates = pendingI2
    pendingI2 = {}
    for index = 1, #candidates do
        local candidate = candidates[index]
        TryScheduleP3(candidate.duration, candidate.receivedAt, p3StartTime)
    end
end

---@param eventInfo table|nil
local function OnTimelineEventAdded(eventInfo)
    if type(eventInfo) ~= "table" then
        return
    end
    if eventInfo.source ~= EncounterTimeline.EVENT_SOURCE_ENCOUNTER then
        return
    end
    local duration = eventInfo.duration
    if type(duration) ~= "number" then
        return
    end
    local phase = Internals.PhaseDetector.GetPhase()
    if phase == PHASE_P1 then
        TryScheduleP1(duration)
        return
    end
    if phase == PHASE_P3 then
        local p3StartTime = Internals.PhaseDetector.GetPhaseStartTime()
        if p3StartTime ~= nil then
            TryScheduleP3(duration, Timer.GetTime(), p3StartTime)
        end
        return
    end
    if phase == PHASE_I2 and Internals.IsOrbCarryP3Duration(duration) then
        pendingI2[#pendingI2 + 1] = {
            duration = duration,
            receivedAt = Timer.GetTime(),
        }
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
        FlushPendingI2(at)
    end
end

---Owns this pull's timeline listener, phase-change hook, and scheduled reminders until `scope` is disposed.
---@param scope ResourceScope
function Internals.StartOrbCarry(scope)
    CancelScheduledReminders()
    scope:Subscribe(EncounterTimeline.OnAnyEventAdded, OnTimelineEventAdded)
    scope:Subscribe(Internals.PhaseDetector.OnChanged, OnPhaseChanged)
    scope:Add(function()
        CancelScheduledReminders()
        reminderScope = nil
    end)
end
