local _, ns = ...
local Internals = ns.Modules.Internals("Ulatek")
local Instance = ns.Api.Instance

-- Pull-relative hit times and callout lead times for Ulatek mechanics.

---@alias UlatekMechanicId "causticWaves"|"eggDeadline"|"wretchAoe"
---@alias UlatekPadGroupId "wave"|"boss"|"markers"

---@class UlatekPadWindow
---@field group UlatekPadGroupId
---@field openAt number  Pull-elapsed seconds when the group unlocks and fades in.
---@field closeAt number  Pull-elapsed seconds when the group locks and fades out.

---@class UlatekMechanicTimeline
---@field leadTime number  Seconds before the hit to show the callout.
---@field hits number[]  Pull-elapsed seconds when the mechanic hits.

---@class UlatekTimelineSchedule
---@field causticWaves UlatekMechanicTimeline
---@field eggDeadline UlatekMechanicTimeline
---@field wretchAoe UlatekMechanicTimeline

local CAUSTIC_WAVES = "causticWaves"
local EGG_DEADLINE = "eggDeadline"
local WRETCH_AOE = "wretchAoe"
local PAD_WAVE = "wave"
local PAD_BOSS = "boss"
local PAD_MARKERS = "markers"

---@param leadTime number
---@param hits number[]
---@return UlatekMechanicTimeline
local function Mechanic(leadTime, hits)
    return { leadTime = leadTime, hits = hits }
end

---@type UlatekTimelineSchedule
local HEROIC = {
    causticWaves = Mechanic(5, { 48, 100, 416.7, 471.7, 521.7, 566.7 }),
    eggDeadline = Mechanic(8, {}),
    wretchAoe = Mechanic(8, {}),
}

---@type UlatekTimelineSchedule
local MYTHIC = {
    causticWaves = Mechanic(5, { 56, 113, 426.7, 481.6, 531.7, 575.7 }),
    eggDeadline = Mechanic(8, { 29, 113 }),
    wretchAoe = Mechanic(8, { 38.4, 70.5, 107.8, 140.3 }),
}

---@type table<integer, UlatekTimelineSchedule>
local schedules = {
    [Instance.DIFFICULTY_HEROIC_RAID] = HEROIC,
    [Instance.DIFFICULTY_MYTHIC_RAID] = MYTHIC,
}

-- Mythic tactical-pad click windows, from ENCOUNTER_START.
---@type UlatekPadWindow[]
local MYTHIC_PAD_WINDOWS = {
    { group = PAD_WAVE, openAt = 50, closeAt = 62 },
    { group = PAD_BOSS, openAt = 73.4, closeAt = 85.4 },
    { group = PAD_WAVE, openAt = 107, closeAt = 119 },
    { group = PAD_MARKERS, openAt = 325, closeAt = 340 },
}

---@class UlatekTimeline
local Timeline = {
    CAUSTIC_WAVES = CAUSTIC_WAVES,
    EGG_DEADLINE = EGG_DEADLINE,
    WRETCH_AOE = WRETCH_AOE,
    PAD_WAVE = PAD_WAVE,
    PAD_BOSS = PAD_BOSS,
    PAD_MARKERS = PAD_MARKERS,
    -- Preview plays the pad click windows this many times faster than a real pull.
    PAD_TEST_RATE = 3,
    -- Pad-test clock time when preview stops (11:00 of pull-elapsed time).
    PAD_TEST_DURATION = 11 * 60,
    MECHANICS = { CAUSTIC_WAVES, EGG_DEADLINE, WRETCH_AOE },
}

---Pull schedule for Heroic or Mythic. Nil on easier difficulties (no alerts).
---@param difficultyID number|nil
---@return UlatekTimelineSchedule|nil
function Timeline.GetSchedule(difficultyID)
    return schedules[difficultyID]
end

---Mythic pad click windows. Empty on other difficulties.
---@param difficultyID number|nil
---@return UlatekPadWindow[]
function Timeline.GetPadWindows(difficultyID)
    if difficultyID ~= Instance.DIFFICULTY_MYTHIC_RAID then
        return {}
    end
    return MYTHIC_PAD_WINDOWS
end

Internals.Timeline = Timeline
