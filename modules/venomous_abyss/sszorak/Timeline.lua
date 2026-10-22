local _, ns = ...
local Internals = ns.Modules.Internals("Sszorak")
local Instance = ns.Api.Instance

-- Horizontal stations: home (entrance / left side), center, far (exit / right side).
local STATION_HOME = 1
local STATION_CENTER = 2
local STATION_FAR = 3

---@class SszorakTimelineEntry
---@field time number  Elapsed encounter seconds when dots jump to `station`.
---@field station integer

---@class SszorakTimelineSchedule
---@field positionTimeline SszorakTimelineEntry[]  Starts on home at 0; frozen after the last entry.
---@field warningAnchors number[]  Pull-relative ENCOUNTER_WARNING times (see communication/Host.lua).

-- Heroic: each warning-anchor group of 4 drives one home→far→home cycle:
-- 2nd+5.7 → CENTER, that+11.7 → FAR, 4th+5.7 → CENTER, that+46.4 → HOME.
---@type SszorakTimelineSchedule
local HEROIC = {
    positionTimeline = {
        { time = 42.9, station = STATION_CENTER },
        { time = 54.6, station = STATION_FAR },
        { time = 95.2, station = STATION_CENTER },
        { time = 141.6, station = STATION_HOME },
        { time = 181.2, station = STATION_CENTER },
        { time = 192.9, station = STATION_FAR },
        { time = 233.2, station = STATION_CENTER },
        { time = 279.6, station = STATION_HOME },
        { time = 319.2, station = STATION_CENTER },
        { time = 330.9, station = STATION_FAR },
        { time = 371.3, station = STATION_CENTER },
        { time = 417.7, station = STATION_HOME },
    },
    warningAnchors = {
        35.2,
        37.2,
        87.5,
        89.5,
        173.5,
        175.5,
        225.5,
        227.5,
        311.5,
        313.5,
        363.6,
        365.6,
    },
}

-- Mythic Sszorak in The Venomous Abyss.
---@type SszorakTimelineSchedule
local MYTHIC = {
    positionTimeline = {
        { time = 38.7, station = STATION_CENTER },
        { time = 50, station = STATION_FAR },
        { time = 75.3, station = STATION_CENTER },
        { time = 130, station = STATION_HOME },
        { time = 165.8, station = STATION_CENTER },
        { time = 177, station = STATION_FAR },
        { time = 212.8, station = STATION_CENTER },
        { time = 257.1, station = STATION_HOME },
        { time = 292.8, station = STATION_CENTER },
        { time = 304.1, station = STATION_FAR },
        { time = 339.8, station = STATION_CENTER },
        { time = 384.1, station = STATION_HOME },
    },
    warningAnchors = { 32, 34, 79, 81, 159, 161, 206, 208, 285.5, 287.5, 332.5, 334.5 },
}

---@type table<integer, SszorakTimelineSchedule>
local schedules = {
    [Instance.DIFFICULTY_HEROIC_RAID] = HEROIC,
    [Instance.DIFFICULTY_MYTHIC_RAID] = MYTHIC,
}

---@class SszorakTimeline
local Timeline = {
    STATION_HOME = STATION_HOME,
    STATION_CENTER = STATION_CENTER,
    STATION_FAR = STATION_FAR,
}

---Pull schedule for `difficultyID`. Falls back to heroic when that difficulty has none.
---@param difficultyID number|nil
---@return SszorakTimelineSchedule
function Timeline.GetSchedule(difficultyID)
    return schedules[difficultyID] or HEROIC
end

Internals.Timeline = Timeline
