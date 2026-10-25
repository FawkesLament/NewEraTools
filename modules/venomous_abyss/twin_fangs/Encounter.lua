local _, ns = ...
local Internals = ns.Modules.Internals("TwinFangs")
local L = ns.L
local CalloutManager = ns.CalloutManager
local Encounter = ns.Api.Encounter
local EncounterTimeline = ns.Api.EncounterTimeline
local Instance = ns.Api.Instance
local Timer = ns.Api.Timer

local CALLOUT_SOURCE = "TwinFangs"

local TwinFangs = ns.Modules.Get("TwinFangs")
local Schema = Internals.Schema

-- Mythic Twin Fangs in The Venomous Abyss.
local ENCOUNTER_ID = 3421
-- Timeline bar lengths that round to these values mark Ravenous Feast's begin cast.
local FEAST_DURATION = 57
local CYCLE_DURATION = 61
-- Every 8th ~61s bar is also a Ravenous Feast begin cast. The 5th bar in that cycle is Rouse the Brood.
local CYCLE_LENGTH = 8
local BROOD_SLOT = 5
-- The 2nd ~33s bar is also Rouse the Brood. This count does not wrap.
local BROOD_DURATION = 33
local BROOD_DURATION_INDEX = 2
-- Begin cast until the first hit, then the gaps between the three consecutive hits.
local CAST_SECONDS = 4.25
local HIT2_GAP = 2
local HIT3_GAP = 1.5
-- Hit 1 is announced this long beforehand. Later hits are warned the same long before the previous hit.
local HIT1_LEAD = 7
local PREPARE_LEAD = 7

TwinFangs.ENCOUNTER_ID = ENCOUNTER_ID
TwinFangs.FEAST_DURATION = FEAST_DURATION
TwinFangs.CYCLE_DURATION = CYCLE_DURATION
TwinFangs.CYCLE_LENGTH = CYCLE_LENGTH
TwinFangs.BROOD_SLOT = BROOD_SLOT
TwinFangs.BROOD_DURATION = BROOD_DURATION
TwinFangs.BROOD_DURATION_INDEX = BROOD_DURATION_INDEX
TwinFangs.CAST_SECONDS = CAST_SECONDS
TwinFangs.HIT2_GAP = HIT2_GAP
TwinFangs.HIT3_GAP = HIT3_GAP
TwinFangs.HIT1_LEAD = HIT1_LEAD
TwinFangs.PREPARE_LEAD = PREPARE_LEAD

-- Casts 1, 2, 5, and 6 (and the same slots every 6 casts): right, left, middle.
local ORDER_RIGHT_FIRST = { Schema.GROUP_RIGHT, Schema.GROUP_LEFT, Schema.GROUP_MIDDLE }
-- Casts 3 and 4: left, right, middle.
local ORDER_LEFT_FIRST = { Schema.GROUP_LEFT, Schema.GROUP_RIGHT, Schema.GROUP_MIDDLE }

---@type EncounterWhileIn|nil
local fight = nil
---@type fun()|nil
local unsubscribeTimeline = nil
---@type fun()|nil
local unsubscribeNameplateHint = nil
---@type fun()|nil
local unsubscribeInterruptStatus = nil
-- Identified Ravenous Feast begin casts this pull.
local feastCount = 0
-- ~61s bars seen this pull.
local cycleCount = 0
-- ~33s bars seen this pull. Does not wrap; only the 2nd is Brood.
local broodDurationCount = 0
local soakScheduleToken = 0
local broodToken = 0
---@type table<string, CalloutManagerHandle>
local calloutByKind = {}

local function CurrentCallout()
    local current = CalloutManager.GetCurrent()
    if current and current.source == CALLOUT_SOURCE then
        return current
    end
    return nil
end

---@class TwinFangsCalloutOptions
---@field kind string|nil
---@field appendTimer boolean|nil

---Shows `text` until `expiresAt`. A later show drops the current message immediately.
---@param text string
---@param expiresAt number
---@param options TwinFangsCalloutOptions|nil
function TwinFangs:ShowCallout(text, expiresAt, options)
    options = options or {}
    local handle = CalloutManager.Show({
        source = CALLOUT_SOURCE,
        text = text,
        expiresAt = expiresAt,
        appendTimer = options.appendTimer == true,
    })
    if options.kind then
        calloutByKind[options.kind] = handle
    end
end

---@param kind string|nil  When set, only clears a callout of that kind.
function TwinFangs:CancelCallout(kind)
    if kind ~= nil then
        local handle = calloutByKind[kind]
        calloutByKind[kind] = nil
        if handle then
            handle:Dismiss()
        end
        return
    end
    calloutByKind = {}
    CalloutManager.ClearSource(CALLOUT_SOURCE)
end

function TwinFangs:CancelSoakCallout()
    soakScheduleToken = soakScheduleToken + 1
    self:CancelCallout("soak")
end

---@return boolean
function TwinFangs:GetCalloutAppendTimer()
    local current = CurrentCallout()
    return current ~= nil and current.appendTimer == true
end

local function ResetPull()
    feastCount = 0
    cycleCount = 0
    broodDurationCount = 0
    broodToken = broodToken + 1
    soakScheduleToken = soakScheduleToken + 1
    TwinFangs:CancelCallout()
    TwinFangs:EndInterruptStatusWindow()
end

---@param duration number|nil
---@return number|nil
local function RoundedDuration(duration)
    if type(duration) ~= "number" then
        return nil
    end
    return math.floor(duration + 0.5)
end

---Soak order repeats every 6 casts: 1, 2, 5, 6 are right-left-middle; 3 and 4 are left-right-middle.
---@param feastIndex integer
---@return string[]
local function SoakOrder(feastIndex)
    local slot = feastIndex % 6
    if slot == 3 or slot == 4 then
        return ORDER_LEFT_FIRST
    end
    return ORDER_RIGHT_FIRST
end

---@param feastIndex integer
---@param group string
---@return integer|nil
local function HitIndexForGroup(feastIndex, group)
    local order = SoakOrder(feastIndex)
    for index, candidate in ipairs(order) do
        if candidate == group then
            return index
        end
    end
    return nil
end

---@param text string
---@param untilTime number
---@param token integer
local function ShowUntil(text, untilTime, token)
    if token ~= soakScheduleToken then
        return
    end
    if not TwinFangs:IsSoakReminderEnabled() or not TwinFangs:IsInEncounter() then
        return
    end
    local remaining = untilTime - Timer.GetTime()
    if remaining <= 0 then
        return
    end
    TwinFangs:ShowCallout(text, untilTime, { kind = "soak", appendTimer = true })
end

---Opens the interrupt-status window when this bar elapses.
---@param duration number
local function ScheduleBrood(duration)
    local token = broodToken
    Timer.After(duration, function()
        if token ~= broodToken or not TwinFangs:IsInEncounter() then
            return
        end
        TwinFangs:BeginInterruptStatusWindow()
    end)
end

---@param duration number
local function ScheduleFeast(duration)
    feastCount = feastCount + 1
    local feastIndex = feastCount
    local hitIndex = HitIndexForGroup(feastIndex, TwinFangs:GetSoakGroup())
    if hitIndex == nil then
        return
    end
    local token = soakScheduleToken
    local now = Timer.GetTime()
    local beginAt = now + duration
    local hitAt = {
        beginAt + CAST_SECONDS,
        beginAt + CAST_SECONDS + HIT2_GAP,
        beginAt + CAST_SECONDS + HIT2_GAP + HIT3_GAP,
    }
    if hitIndex == 1 then
        Timer.After(hitAt[1] - HIT1_LEAD - now, function()
            ShowUntil(L.TWIN_FANGS_SOAK_ENTER, hitAt[1], token)
        end)
        return
    end
    local preceding = hitAt[hitIndex - 1]
    Timer.After(preceding - PREPARE_LEAD - now, function()
        ShowUntil(L.TWIN_FANGS_SOAK_PREPARE, preceding, token)
    end)
    Timer.After(preceding - now, function()
        ShowUntil(L.TWIN_FANGS_SOAK_NOW, hitAt[hitIndex], token)
    end)
end

---@param eventInfo table
local function OnTimelineEventAdded(eventInfo)
    local rounded = RoundedDuration(eventInfo.duration)
    if rounded == FEAST_DURATION then
        ScheduleFeast(eventInfo.duration)
        return
    end
    if rounded == BROOD_DURATION then
        broodDurationCount = broodDurationCount + 1
        if broodDurationCount == BROOD_DURATION_INDEX then
            ScheduleBrood(eventInfo.duration)
        end
        return
    end
    if rounded ~= CYCLE_DURATION then
        return
    end
    cycleCount = cycleCount + 1
    if cycleCount % CYCLE_LENGTH == 0 then
        ScheduleFeast(eventInfo.duration)
    elseif cycleCount % CYCLE_LENGTH == BROOD_SLOT then
        ScheduleBrood(eventInfo.duration)
    end
end

local function StopListener(unsubscribe)
    if not unsubscribe then
        return nil
    end
    unsubscribe()
    return nil
end

---@return boolean
function TwinFangs:IsInEncounter()
    return fight ~= nil and fight:IsInside()
end

---Whether this pull is subscribed to encounter timeline events.
---@return boolean
function TwinFangs:IsListeningForTimeline()
    return unsubscribeTimeline ~= nil
end

---Whether this pull is subscribed to nameplate-hint cast events.
---@return boolean
function TwinFangs:IsListeningForNameplateHint()
    return unsubscribeNameplateHint ~= nil
end

---@return string|nil
function TwinFangs:GetDisplayedCallout()
    local current = CurrentCallout()
    return current and current.text
end

---@return number|nil
function TwinFangs:GetCalloutExpiresAt()
    local current = CurrentCallout()
    return current and current.expiresAt
end

---Starts watching for this boss fight. Timeline events and nameplate-hint casts are subscribed only on Mythic.
---Called from OnEnable.
function TwinFangs:ListenForEncounter()
    fight = Encounter.WhileIn(ENCOUNTER_ID, function(difficultyID)
        if difficultyID ~= Instance.DIFFICULTY_MYTHIC_RAID then
            return
        end
        ResetPull()
        unsubscribeTimeline = EncounterTimeline.OnEventAdded(OnTimelineEventAdded)
        unsubscribeNameplateHint = TwinFangs:ListenForNameplateHint()
        unsubscribeInterruptStatus = TwinFangs:ListenForInterruptStatus()
        return function()
            unsubscribeTimeline = StopListener(unsubscribeTimeline)
            unsubscribeNameplateHint = StopListener(unsubscribeNameplateHint)
            unsubscribeInterruptStatus = StopListener(unsubscribeInterruptStatus)
            ResetPull()
        end
    end)
end
