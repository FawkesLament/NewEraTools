-- Matches ENCOUNTER_WARNING to the ghost-chase schedule and shows a timed Callout.
local _, ns = ...
local Internals = ns.Modules.Internals("CoiledAltar")
local CalloutManager = ns.CalloutManager
local Encounter = ns.Api.Encounter
local Instance = ns.Api.Instance
local L = ns.L

local CoiledAltar = ns.Modules.Get("CoiledAltar")

local CALLOUT_SOURCE = "CoiledAltarGhostChase"
local CALLOUT_DURATION = 22
local WARNING_SEVERITY = 1
local WARNING_DURATION = 4
local WARNING_DURATION_TOLERANCE = 0.5
-- Accept a hit from 3s before to 5s after the phase-elapsed anchor.
local WARNING_EARLY = 3
local WARNING_LATE = 5

CoiledAltar.GHOST_CHASE_CALLOUT_DURATION = CALLOUT_DURATION
CoiledAltar.GHOST_CHASE_WARNING_SEVERITY = WARNING_SEVERITY
CoiledAltar.GHOST_CHASE_WARNING_DURATION = WARNING_DURATION
CoiledAltar.GHOST_CHASE_WARNING_DURATION_TOLERANCE = WARNING_DURATION_TOLERANCE
CoiledAltar.GHOST_CHASE_WARNING_EARLY = WARNING_EARLY
CoiledAltar.GHOST_CHASE_WARNING_LATE = WARNING_LATE

---@type table<integer, table<CoiledAltarPhase, number[]>>
local ANCHORS = {
    [Instance.DIFFICULTY_HEROIC_RAID] = {
        P2 = { 13, 50, 95 },
        P3 = { 72.3, 171.3 },
    },
    [Instance.DIFFICULTY_MYTHIC_RAID] = {
        P2 = { 12.5, 49.8, 97.9, 136, 183.4 },
        P3 = { 62.4, 158.4 },
    },
}

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

---Closest unused anchor in [anchor - early, anchor + late], or nil.
---@param elapsed number
---@param anchors number[]
---@param used table<integer, boolean>
---@return integer|nil
function Internals.MatchGhostChaseAnchor(elapsed, anchors, used)
    local bestIndex
    local bestDistance
    for index = 1, #anchors do
        if not used[index] then
            local delta = elapsed - anchors[index]
            if delta >= -WARNING_EARLY and delta <= WARNING_LATE then
                local distance = math.abs(delta)
                if not bestDistance or distance < bestDistance then
                    bestIndex = index
                    bestDistance = distance
                end
            end
        end
    end
    return bestIndex
end

---@param warningInfo table
---@param schedule table<CoiledAltarPhase, number[]>
---@param used table<CoiledAltarPhase, table<integer, boolean>>
local function OnEncounterWarning(warningInfo, schedule, used)
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
    if type(duration) ~= "number" or math.abs(duration - WARNING_DURATION) > WARNING_DURATION_TOLERANCE then
        return
    end
    local phase = Internals.PhaseDetector.GetPhase()
    local elapsed = Internals.PhaseDetector.GetPhaseElapsed()
    local anchors = phase and schedule[phase]
    if not anchors or elapsed == nil then
        return
    end
    local consumed = used[phase]
    if not consumed then
        consumed = {}
        used[phase] = consumed
    end
    local index = Internals.MatchGhostChaseAnchor(elapsed, anchors, consumed)
    if not index then
        return
    end
    consumed[index] = true
    HidePresented()
    presented = CalloutManager.Show({
        source = CALLOUT_SOURCE,
        text = L.COILED_ALTAR_GHOST_CHASE_CALLOUT,
        duration = CALLOUT_DURATION,
        appendTimer = true,
    })
end

---Owns this pull's warning listener and consumed anchors until `scope` is disposed.
---@param scope ResourceScope
---@param difficultyID number
function Internals.StartGhostChase(scope, difficultyID)
    local schedule = ANCHORS[difficultyID]
    if not schedule then
        return
    end
    local used = {}
    scope:Subscribe(Encounter.OnWarning, function(warningInfo)
        OnEncounterWarning(warningInfo, schedule, used)
    end)
    scope:Add(HidePresented)
end
