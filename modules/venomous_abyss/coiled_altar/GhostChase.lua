-- Matches ENCOUNTER_WARNING to Mythic ghost-chase (not dreadmarch) and shows a timed Callout.
local _, ns = ...
local Internals = ns.Modules.Internals("CoiledAltar")
local CalloutManager = ns.CalloutManager
local Encounter = ns.Api.Encounter
local Instance = ns.Api.Instance
local Spell = ns.Api.Spell
local L = ns.L

local CoiledAltar = ns.Modules.Get("CoiledAltar")

local CALLOUT_SOURCE = "CoiledAltarGhostChase"
local CALLOUT_DURATION = 22
local WARNING_SEVERITY = 1
local WARNING_DURATION = 4
local WARNING_DURATION_TOLERANCE = 0.2
local BOSS2_UNIT = "boss2"
local PHASE_P2 = "P2"
local PHASE_I2 = "I2"
local PHASE_P3 = "P3"
local P2_CYCLE = 85
local P2_WINDOW1_START = 1.5
local P2_WINDOW1_END = 7.5
local P2_WINDOW2_START = 35.5
local P2_WINDOW2_END = 44.5
-- Window 1 may open early when o is in [70, 85 + 1.5] (the 1.5 wraps into the next round).
local P2_WINDOW1_EARLY_FROM = 70
local P3_WINDOW_START = 55
local P3_WINDOW_END = 60
local P3_WINDOW_EARLY_FROM = 38

CoiledAltar.GHOST_CHASE_CALLOUT_DURATION = CALLOUT_DURATION
CoiledAltar.GHOST_CHASE_WARNING_SEVERITY = WARNING_SEVERITY
CoiledAltar.GHOST_CHASE_WARNING_DURATION = WARNING_DURATION
CoiledAltar.GHOST_CHASE_WARNING_DURATION_TOLERANCE = WARNING_DURATION_TOLERANCE

---@type CalloutManagerHandle|nil
local presented = nil

local function HidePresented()
    if presented then
        presented:Dismiss()
        presented = nil
    end
end

function Internals.HideGhostChaseCallout()
    HidePresented()
end

---@param elapsed number
---@return number
local function P2Offset(elapsed)
    return elapsed % P2_CYCLE
end

---@param elapsed number
---@return boolean
local function IsP2Window1EarlyEligible(elapsed)
    local offset = P2Offset(elapsed)
    return offset >= P2_WINDOW1_EARLY_FROM or offset <= P2_WINDOW1_START
end

---Absolute phase-elapsed when an early-opened P2 window 1 closes.
---@param earlyStart number
---@return number
function Internals.GhostChaseP2Window1EarlyEnd(earlyStart)
    local round = math.floor(earlyStart / P2_CYCLE)
    if P2Offset(earlyStart) >= P2_WINDOW1_EARLY_FROM then
        return (round + 1) * P2_CYCLE + P2_WINDOW1_END
    end
    return round * P2_CYCLE + P2_WINDOW1_END
end

---True when a P2/P3 severity-1 4s warning at `elapsed` is dreadmarch, not ghost chase.
---@param phase CoiledAltarPhase
---@param elapsed number
---@param p2Window1EarlyStart number|nil
---@param p3EarlyStart number|nil
---@return boolean
function Internals.IsDreadmarchWindow(phase, elapsed, p2Window1EarlyStart, p3EarlyStart)
    if phase == PHASE_P2 then
        if
            p2Window1EarlyStart
            and elapsed >= p2Window1EarlyStart
            and elapsed <= Internals.GhostChaseP2Window1EarlyEnd(p2Window1EarlyStart)
        then
            return true
        end
        local offset = P2Offset(elapsed)
        if offset >= P2_WINDOW1_START and offset <= P2_WINDOW1_END then
            return true
        end
        return offset >= P2_WINDOW2_START and offset <= P2_WINDOW2_END
    end
    if phase == PHASE_P3 then
        local windowStart = P3_WINDOW_START
        if p3EarlyStart then
            windowStart = p3EarlyStart
        end
        return elapsed >= windowStart and elapsed <= P3_WINDOW_END
    end
    return false
end

---@param warningInfo table
---@param earlyOpen { p2Window1Start: number|nil, p3Start: number|nil }
local function OnEncounterWarning(warningInfo, earlyOpen)
    if not CoiledAltar:IsGhostChaseReminderEnabled() then
        return
    end
    if type(warningInfo) ~= "table" then
        return
    end
    if warningInfo.severity ~= WARNING_SEVERITY then
        return
    end
    local duration = warningInfo.duration
    -- Inclusive range: abs(duration - 4) > 0.2 rejects 3.8/4.2 because those floats are not exact.
    if
        type(duration) ~= "number"
        or duration < WARNING_DURATION - WARNING_DURATION_TOLERANCE
        or duration > WARNING_DURATION + WARNING_DURATION_TOLERANCE
    then
        return
    end
    local phase = Internals.PhaseDetector.GetPhase()
    local elapsed = Internals.PhaseDetector.GetPhaseElapsed()
    if elapsed == nil or (phase ~= PHASE_P2 and phase ~= PHASE_P3) then
        return
    end
    if Internals.IsDreadmarchWindow(phase, elapsed, earlyOpen.p2Window1Start, earlyOpen.p3Start) then
        return
    end
    HidePresented()
    presented = CalloutManager.Show({
        source = CALLOUT_SOURCE,
        key = CALLOUT_SOURCE,
        text = L.COILED_ALTAR_GHOST_CHASE_CALLOUT,
        duration = CALLOUT_DURATION,
        appendTimer = true,
    })
end

---@param unitTarget string
---@param earlyOpen { p2Window1Start: number|nil, p3Start: number|nil }
local function OnCastStop(unitTarget, earlyOpen)
    if unitTarget ~= BOSS2_UNIT then
        return
    end
    local phase = Internals.PhaseDetector.GetPhase()
    local elapsed = Internals.PhaseDetector.GetPhaseElapsed()
    if elapsed == nil then
        return
    end
    if phase == PHASE_P2 then
        if IsP2Window1EarlyEligible(elapsed) then
            earlyOpen.p2Window1Start = elapsed
        end
        return
    end
    if phase == PHASE_P3 and elapsed >= P3_WINDOW_EARLY_FROM and elapsed <= P3_WINDOW_START then
        earlyOpen.p3Start = elapsed
    end
end

---Owns this pull's warning listener and dreadmarch window state until `scope` is disposed.
---@param scope ResourceScope
---@param difficultyID number
function Internals.StartGhostChase(scope, difficultyID)
    if difficultyID ~= Instance.DIFFICULTY_MYTHIC_RAID then
        return
    end
    local earlyOpen = {
        p2Window1Start = nil,
        p3Start = nil,
    }
    scope:Subscribe(Encounter.OnWarning, function(warningInfo)
        OnEncounterWarning(warningInfo, earlyOpen)
    end)
    scope:Subscribe(Spell.OnCastStop, function(unitTarget)
        OnCastStop(unitTarget, earlyOpen)
    end)
    scope:Add(Internals.PhaseDetector.OnChanged(function(nextPhase)
        if nextPhase == PHASE_I2 then
            earlyOpen.p2Window1Start = nil
        end
    end))
    scope:Add(HidePresented)
end
