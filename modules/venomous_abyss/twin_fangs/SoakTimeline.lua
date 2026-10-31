local _, ns = ...
local Internals = ns.Modules.Internals("TwinFangs")

local TwinFangs = ns.Modules.Get("TwinFangs")
local Schema = Internals.Schema
local Timer = ns.Api.Timer

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

-- Matches Encounter soak order: casts 1, 2, 5, 6 (and the same slots every 6) vs 3 and 4.
local ORDER_RIGHT_FIRST = { Schema.GROUP_RIGHT, Schema.GROUP_LEFT, Schema.GROUP_MIDDLE }
local ORDER_LEFT_FIRST = { Schema.GROUP_LEFT, Schema.GROUP_RIGHT, Schema.GROUP_MIDDLE }

---@alias TwinFangsSoakTimelineNodeStatus "pending"|"active"|"completed"

---@class TwinFangsSoakTimelineNode
---@field hit integer
---@field status TwinFangsSoakTimelineNodeStatus
---@field flashing boolean
---@field assigned boolean

---@class TwinFangsSoakTimelineState
---@field elapsed number  Sequence time, 0..DURATION.
---@field progress number  Fill fraction, 0..1.
---@field activeHit integer|nil
---@field assignedHit integer|nil
---@field nodes TwinFangsSoakTimelineNode[]

---@alias TwinFangsSoakCalloutKind "enter"|"prepare"|"now"

---@class TwinFangsSoakCalloutState
---@field kind TwinFangsSoakCalloutKind
---@field remaining number

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

---@param assignedHit any
---@return integer|nil
local function NormalizeAssignedHit(assignedHit)
    assignedHit = tonumber(assignedHit)
    if not assignedHit then
        return nil
    end
    assignedHit = math.floor(assignedHit)
    if assignedHit < 1 or assignedHit > HIT_COUNT then
        return nil
    end
    return assignedHit
end

---Which of the three hits belongs to `group` on this feast. Preview uses feast 1.
---@param group string|nil
---@param feastIndex number|nil
---@return integer|nil
function SoakTimeline.AssignedHitForGroup(group, feastIndex)
    feastIndex = tonumber(feastIndex) or 1
    local slot = feastIndex % 6
    local order
    if slot == 3 or slot == 4 then
        order = ORDER_LEFT_FIRST
    else
        order = ORDER_RIGHT_FIRST
    end
    for index = 1, HIT_COUNT do
        if order[index] == group then
            return index
        end
    end
    return nil
end

---@param elapsed number
---@param flashElapsed number
---@param assignedHit integer|nil
---@return TwinFangsSoakTimelineState
local function BuildState(elapsed, flashElapsed, assignedHit)
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
    assignedHit = NormalizeAssignedHit(assignedHit)

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
            assigned = index == assignedHit,
        }
    end

    return {
        elapsed = elapsed,
        progress = elapsed / DURATION,
        activeHit = activeHit,
        assignedHit = assignedHit,
        nodes = nodes,
    }
end

---One 0..DURATION pass. Used in combat; does not loop.
---@param elapsed number
---@param assignedHit integer|nil
---@return TwinFangsSoakTimelineState
function SoakTimeline.SequenceState(elapsed, assignedHit)
    elapsed = tonumber(elapsed) or 0
    if elapsed < 0 then
        elapsed = 0
    elseif elapsed > DURATION then
        elapsed = DURATION
    end
    return BuildState(elapsed, elapsed, assignedHit)
end

---@param loopElapsed number
---@param assignedHit integer|nil
---@return TwinFangsSoakTimelineState
function SoakTimeline.StateAt(loopElapsed, assignedHit)
    loopElapsed = tonumber(loopElapsed) or 0
    if loopElapsed < 0 then
        loopElapsed = 0
    end
    local cycle = loopElapsed % LOOP
    local elapsed = cycle
    if elapsed > DURATION then
        elapsed = DURATION
    end
    return BuildState(elapsed, cycle, assignedHit)
end

---Soak-reminder text at `elapsed` seconds after feast begin (beginAt). Preview loops with PreviewCallout.
---@param elapsed number
---@param assignedHit integer|nil
---@return TwinFangsSoakCalloutState|nil
function SoakTimeline.CalloutAt(elapsed, assignedHit)
    assignedHit = NormalizeAssignedHit(assignedHit)
    elapsed = tonumber(elapsed) or 0
    if not assignedHit then
        return nil
    end
    local ownAt = HIT_AT[assignedHit]
    if assignedHit == 1 then
        local startAt = ownAt - TwinFangs.HIT1_LEAD
        if elapsed >= startAt and elapsed < ownAt then
            return { kind = "enter", remaining = ownAt - elapsed }
        end
        return nil
    end
    local precedingAt = HIT_AT[assignedHit - 1]
    local prepareStart = precedingAt - TwinFangs.PREPARE_LEAD
    if elapsed >= prepareStart and elapsed < precedingAt then
        return { kind = "prepare", remaining = precedingAt - elapsed }
    end
    if elapsed >= precedingAt and elapsed < ownAt then
        return { kind = "now", remaining = ownAt - elapsed }
    end
    return nil
end

---@param loopElapsed number
---@param assignedHit integer|nil
---@return TwinFangsSoakCalloutState|nil
function SoakTimeline.PreviewCallout(loopElapsed, assignedHit)
    loopElapsed = tonumber(loopElapsed) or 0
    if loopElapsed < 0 then
        loopElapsed = 0
    end
    return SoakTimeline.CalloutAt(loopElapsed % LOOP, assignedHit)
end

---@type number|nil
local previewOrigin

function SoakTimeline.BeginPreviewClock()
    if not previewOrigin then
        previewOrigin = Timer.GetTime()
    end
end

---@return number
function SoakTimeline.PreviewElapsed()
    if not previewOrigin then
        return 0
    end
    return Timer.GetTime() - previewOrigin
end

function SoakTimeline.EndPreviewClock()
    previewOrigin = nil
end
