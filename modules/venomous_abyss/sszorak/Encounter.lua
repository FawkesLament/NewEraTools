local _, ns = ...
local Encounter = ns.Api.Encounter
local Timer = ns.Api.Timer

local Sszorak = ns.Modules.Get("Sszorak")
local Timeline = ns.SszorakTimeline

-- Mythic Sszorak in The Venomous Abyss; matches DBM/WCL encounter ID 3420.
local ENCOUNTER_ID = 3420
-- The boss is tanked on the entrance-exit centerline, near the entrance edge at x = 1.
local BOSS_X = 0.7
-- How far each group stands above or below the boss.
local GROUP_OFFSET = 0.25
-- At entrance/exit stations, groups sit this much closer to center on X than the boss (boss unchanged).
local GROUP_EDGE_INSET = 0.1
-- Preview plays the same timeline this many times faster than a real pull.
local ANIM_PREVIEW_RATE = 10
local STATION_HOME = Timeline.STATION_HOME
local STATION_CENTER = Timeline.STATION_CENTER
local STATION_FAR = Timeline.STATION_FAR
local STATION_X = {
    [STATION_HOME] = BOSS_X,
    [STATION_CENTER] = 0,
    [STATION_FAR] = -BOSS_X,
}

-- Group A stands below the boss, group B above.
local GROUP_DIRECTIONS = {
    A = -1,
    B = 1,
}

Sszorak.ENCOUNTER_ID = ENCOUNTER_ID
Sszorak.ANIM_PREVIEW_RATE = ANIM_PREVIEW_RATE
Sszorak.STATION_HOME = STATION_HOME
Sszorak.STATION_CENTER = STATION_CENTER
Sszorak.STATION_FAR = STATION_FAR

---@type SszorakGroup[]
Sszorak.GROUPS = { "A", "B" }

-- Session-only: schedule for the current pull / map test (heroic when difficulty is unknown).
---@type SszorakTimelineSchedule
Sszorak.ACTIVE_SCHEDULE = Timeline.GetSchedule()

local function SetActiveSchedule(difficultyID)
    Sszorak.ACTIVE_SCHEDULE = Timeline.GetSchedule(difficultyID)
end

-- Session-only: GetTime() when the current pull/test timeline started.
local pullStartTime = nil
-- Session-only map animation: which horizontal station the dots occupy, and a token to cancel timers.
local positionStation = STATION_HOME
local animToken = 0
local animRate = 1
---@type EncounterWhileIn|nil
local fight = nil

---@return boolean
function Sszorak:IsInEncounter()
    return fight ~= nil and fight:IsInside()
end

---Whether a pull or map-test timeline is running.
---@return boolean
function Sszorak:IsMapAnimating()
    return pullStartTime ~= nil
end

---Whether the boss/group dots are at the entrance-side home station.
---@return boolean
function Sszorak:IsAtHomeStation()
    return positionStation == STATION_HOME
end

---Elapsed timeline seconds since the current pull/test started (scaled by animation rate).
---@return number
function Sszorak:GetTimelineElapsed()
    if not pullStartTime then
        return 0
    end
    return (Timer.GetTime() - pullStartTime) * animRate
end

local function NotifyPositionsChanged()
    if Sszorak.OnPositionsChanged then
        Sszorak:OnPositionsChanged()
    end
end

local function NotifyMapAnimationStarted()
    if Sszorak.OnMapAnimationStarted then
        Sszorak:OnMapAnimationStarted()
    end
end

local function NotifyMapAnimationStopped()
    if Sszorak.OnMapAnimationStopped then
        Sszorak:OnMapAnimationStopped()
    end
end

local function SetPositionStation(station)
    if positionStation == station then
        return
    end
    local fromStation = positionStation
    positionStation = station
    if station == STATION_HOME and fromStation ~= STATION_HOME then
        -- communication/Communication.lua. Home returns clear the active protocol's buffer.
        Sszorak:ClearCalloutMessages()
    end
    Sszorak:NotifyCalloutStationChanged(fromStation, station)
    NotifyPositionsChanged()
end

local function CurrentPositionX()
    return STATION_X[positionStation]
end

---Group X: same station as the boss, but nudged toward center on entrance/exit sides.
local function CurrentGroupPositionX()
    local x = CurrentPositionX()
    if x > 0 then
        return x - GROUP_EDGE_INSET
    end
    if x < 0 then
        return x + GROUP_EDGE_INSET
    end
    return 0
end

---@class MapAnimationOptions
---@field rate number|nil  How fast timeline seconds elapse. Defaults to 1.

-- Schedules every timeline jump. `token` must still match `animToken` when each fires.
local function SchedulePositionTimeline(token)
    for _, entry in ipairs(Sszorak.ACTIVE_SCHEDULE.positionTimeline) do
        Timer.After(entry.time / animRate, function()
            if token ~= animToken then
                return
            end
            SetPositionStation(entry.station)
        end)
    end
end

---Starts map test mode: fast timeline plus protocol capture until `EndMapTest`.
function Sszorak:StartMapTest()
    SetActiveSchedule(nil)
    self:BeginCalloutCapture()
    self:StartMapAnimation({ rate = ANIM_PREVIEW_RATE })
end

---Ends map test mode and stops protocol capture.
function Sszorak:EndMapTest()
    self:EndCalloutCapture()
    self:StopMapAnimation()
end

---Starts (or restarts) the map animation from home and follows `ACTIVE_SCHEDULE`.
---@param options MapAnimationOptions|nil
function Sszorak:StartMapAnimation(options)
    options = options or {}
    animToken = animToken + 1
    local token = animToken
    animRate = options.rate or 1
    pullStartTime = Timer.GetTime()
    positionStation = STATION_HOME
    NotifyPositionsChanged()
    NotifyMapAnimationStarted()
    SchedulePositionTimeline(token)
end

---Stops the map animation and snaps the dots back home.
function Sszorak:StopMapAnimation()
    animToken = animToken + 1
    animRate = 1
    pullStartTime = nil
    SetPositionStation(STATION_HOME)
    NotifyMapAnimationStopped()
end

local function NotifyEncounterChanged()
    if Sszorak.OnEncounterChanged then
        Sszorak:OnEncounterChanged()
    end
end

---Starts watching for this boss fight. Called from OnEnable.
---Map test mode (`StartMapTest`) is separate and does not use this scope.
function Sszorak:ListenForEncounter()
    fight = Encounter.WhileIn(ENCOUNTER_ID, function(difficultyID)
        -- Always restart from pull, even if preview was already animating.
        SetActiveSchedule(difficultyID)
        Sszorak:BeginCalloutCapture()
        Sszorak:StartMapAnimation()
        NotifyEncounterChanged()
        return function()
            Sszorak:StopMapAnimation()
            Sszorak:EndCalloutCapture()
            NotifyEncounterChanged()
        end
    end)
end

---@return ArenaPoint  In the same coordinates as GetArenaVertices.
function Sszorak:GetBossPosition()
    return { x = CurrentPositionX(), y = 0 }
end

---@param group SszorakGroup
---@return ArenaPoint  In the same coordinates as GetArenaVertices.
function Sszorak:GetGroupPosition(group)
    local direction = assert(GROUP_DIRECTIONS[group], "Unknown group: " .. tostring(group))
    return { x = CurrentGroupPositionX(), y = direction * GROUP_OFFSET }
end
