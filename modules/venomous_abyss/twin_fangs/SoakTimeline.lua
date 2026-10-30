local _, ns = ...
local Internals = ns.Modules.Internals("TwinFangs")

local TwinFangs = ns.Modules.Get("TwinFangs")

local HIT_COUNT = 3
local FLASH_SECONDS = 0.2
local HOLD_SECONDS = 0.75

local HIT_AT = {
    TwinFangs.CAST_SECONDS,
    TwinFangs.CAST_SECONDS + TwinFangs.HIT2_GAP,
    TwinFangs.CAST_SECONDS + TwinFangs.HIT2_GAP + TwinFangs.HIT3_GAP,
}
local DURATION = HIT_AT[HIT_COUNT]
local LOOP = DURATION + HOLD_SECONDS

---@alias TwinFangsSoakTimelineNodeStatus "pending"|"active"|"completed"

---@class TwinFangsSoakTimelineNode
---@field hit integer
---@field status TwinFangsSoakTimelineNodeStatus
---@field flashing boolean

---@class TwinFangsSoakTimelineState
---@field elapsed number  Sequence time, 0..DURATION.
---@field progress number  Fill fraction, 0..1.
---@field activeHit integer|nil
---@field nodes TwinFangsSoakTimelineNode[]

local SoakTimeline = {
    HIT_COUNT = HIT_COUNT,
    HIT_AT = HIT_AT,
    DURATION = DURATION,
    HOLD = HOLD_SECONDS,
    FLASH = FLASH_SECONDS,
    LOOP = LOOP,
}
Internals.SoakTimeline = SoakTimeline

---@param index integer
---@return number
function SoakTimeline.HitFraction(index)
    return HIT_AT[index] / DURATION
end

---@param elapsed number
---@param flashElapsed number
---@return TwinFangsSoakTimelineState
local function BuildState(elapsed, flashElapsed)
    local completed = 0
    for index = 1, HIT_COUNT do
        if elapsed >= HIT_AT[index] then
            completed = index
        end
    end
    local activeHit
    if completed < HIT_COUNT then
        activeHit = completed + 1
    end

    local nodes = {}
    for index = 1, HIT_COUNT do
        local status = "pending"
        if index <= completed then
            status = "completed"
        elseif index == activeHit then
            status = "active"
        end
        local sinceHit = flashElapsed - HIT_AT[index]
        nodes[index] = {
            hit = index,
            status = status,
            flashing = sinceHit >= 0 and sinceHit < FLASH_SECONDS,
        }
    end

    return {
        elapsed = elapsed,
        progress = elapsed / DURATION,
        activeHit = activeHit,
        nodes = nodes,
    }
end

---One 0..DURATION pass. Used in combat; does not loop.
---@param elapsed number
---@return TwinFangsSoakTimelineState
function SoakTimeline.SequenceState(elapsed)
    elapsed = tonumber(elapsed) or 0
    if elapsed < 0 then
        elapsed = 0
    elseif elapsed > DURATION then
        elapsed = DURATION
    end
    return BuildState(elapsed, elapsed)
end

---@param loopElapsed number
---@return TwinFangsSoakTimelineState
function SoakTimeline.StateAt(loopElapsed)
    loopElapsed = tonumber(loopElapsed) or 0
    if loopElapsed < 0 then
        loopElapsed = 0
    end
    local cycle = loopElapsed % LOOP
    local elapsed = cycle
    if elapsed > DURATION then
        elapsed = DURATION
    end
    return BuildState(elapsed, cycle)
end
