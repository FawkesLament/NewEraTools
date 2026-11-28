local _, ns = ...
local Internals = ns.Modules.Internals("Ulatek")
local Instance = ns.Api.Instance

-- Pull-relative hit times and callout lead times for Ulatek mechanics.

---@alias UlatekMechanicId "causticWaves"|"eggDeadline"|"wretchAoe"

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

---@class UlatekTimeline
local Timeline = {
    CAUSTIC_WAVES = CAUSTIC_WAVES,
    EGG_DEADLINE = EGG_DEADLINE,
    WRETCH_AOE = WRETCH_AOE,
    MECHANICS = { CAUSTIC_WAVES, EGG_DEADLINE, WRETCH_AOE },
}

---Pull schedule for Heroic or Mythic. Nil on easier difficulties (no alerts).
---@param difficultyID number|nil
---@return UlatekTimelineSchedule|nil
function Timeline.GetSchedule(difficultyID)
    return schedules[difficultyID]
end

Internals.Timeline = Timeline
