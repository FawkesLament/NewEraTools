-- Encounter-local phase state machine for Coiled Altar. Queryable, with enter notifications; no UI.
local _, ns = ...
local Internals = ns.Modules.Internals("CoiledAltar")
local EncounterTimeline = ns.Api.EncounterTimeline
local Spell = ns.Api.Spell
local Timer = ns.Api.Timer

local PHASE_P1 = "P1"
local PHASE_P2 = "P2"
local PHASE_I2 = "I2"
local PHASE_P3 = "P3"

local P2_DURATION = 70
local P2_MIN_ELAPSED = 5
local P3_BATCH_WINDOW = 0.01
local P3_BATCH_SIZE = 4
local I2_CHANNEL_UNIT = "boss2"

---@alias CoiledAltarPhase "P1"|"P2"|"I2"|"P3"

local Detector = {}
Internals.PhaseDetector = Detector

---@type CoiledAltarPhase|nil
local phase = nil
---@type number|nil
local phaseStartTime = nil
---@type number|nil
local p3BatchStart = nil
local p3BatchCount = 0
---@type fun(phase: CoiledAltarPhase, at: number)[]
local changedListeners = {}

local function ClearPhase()
    phase = nil
    phaseStartTime = nil
    p3BatchStart = nil
    p3BatchCount = 0
end

local function NotifyChanged()
    for index = 1, #changedListeners do
        changedListeners[index](phase, phaseStartTime)
    end
end

---@param nextPhase CoiledAltarPhase
---@param at number
local function Enter(nextPhase, at)
    phase = nextPhase
    phaseStartTime = at
    p3BatchStart = nil
    p3BatchCount = 0
    NotifyChanged()
end

---Notifies after each phase enter. Does not fire when the pull is cleared.
---@param callback fun(phase: CoiledAltarPhase, at: number)
---@return fun()
function Detector.OnChanged(callback)
    assert(type(callback) == "function", "PhaseDetector.OnChanged requires a callback")
    table.insert(changedListeners, callback)
    local removed = false
    return function()
        if removed then
            return
        end
        removed = true
        for index, candidate in ipairs(changedListeners) do
            if candidate == callback then
                table.remove(changedListeners, index)
                return
            end
        end
    end
end

---@return CoiledAltarPhase|nil
function Detector.GetPhase()
    return phase
end

---@return number|nil
function Detector.GetPhaseStartTime()
    return phaseStartTime
end

---@return number|nil
function Detector.GetPhaseElapsed()
    if phaseStartTime == nil then
        return nil
    end
    return Timer.GetTime() - phaseStartTime
end

---@return boolean
local function HasActiveEncounterEvent()
    local eventIDs = EncounterTimeline.GetEventList()
    for index = 1, #eventIDs do
        local eventID = eventIDs[index]
        local eventInfo = EncounterTimeline.GetEventInfo(eventID)
        if
            type(eventInfo) == "table"
            and eventInfo.source == EncounterTimeline.EVENT_SOURCE_ENCOUNTER
            and EncounterTimeline.GetEventState(eventID) == EncounterTimeline.EVENT_STATE_ACTIVE
        then
            return true
        end
    end
    return false
end

---@param eventInfo table|nil
local function OnTimelineEventAdded(eventInfo)
    if type(eventInfo) ~= "table" then
        return
    end
    if eventInfo.source ~= EncounterTimeline.EVENT_SOURCE_ENCOUNTER then
        return
    end
    local now = Timer.GetTime()
    if phase == PHASE_P1 then
        if eventInfo.duration == P2_DURATION and now - phaseStartTime >= P2_MIN_ELAPSED then
            Enter(PHASE_P2, now)
        end
        return
    end
    if phase ~= PHASE_I2 then
        return
    end
    if p3BatchStart == nil or now - p3BatchStart > P3_BATCH_WINDOW then
        p3BatchStart = now
        p3BatchCount = 1
    else
        p3BatchCount = p3BatchCount + 1
    end
    if p3BatchCount >= P3_BATCH_SIZE then
        Enter(PHASE_P3, now)
    end
end

local function OnBoss2ChannelStart()
    if phase ~= PHASE_P2 then
        return
    end
    if HasActiveEncounterEvent() then
        return
    end
    Enter(PHASE_I2, Timer.GetTime())
end

---Owns this pull's phase state until `scope` is disposed.
---@param scope ResourceScope
function Detector.Start(scope)
    Enter(PHASE_P1, Timer.GetTime())
    scope:Subscribe(EncounterTimeline.OnAnyEventAdded, OnTimelineEventAdded)
    scope:Add(Spell.OnUnitChannelStart(I2_CHANNEL_UNIT, OnBoss2ChannelStart))
    scope:Add(ClearPhase)
end
