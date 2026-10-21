local _, ns = ...
local Nameplate = ns.Api.Nameplate
local Spell = ns.Api.Spell
local Timer = ns.Api.Timer
local Unit = ns.Api.Unit

local TwinFangs = ns.Modules.Get("TwinFangs")

-- Add interrupt waves. The i-th cast in a wave is start + (i - 1) seconds.
local WAVE_STARTS = { 37.5, 98.5, 192.5, 253.5, 347.5, 408.5 }
local ANCHORS_PER_WAVE = 10
local ANCHOR_WINDOW = 0.15

TwinFangs.NAMEPLATE_WAVE_STARTS = WAVE_STARTS
TwinFangs.NAMEPLATE_ANCHORS_PER_WAVE = ANCHORS_PER_WAVE
TwinFangs.NAMEPLATE_ANCHOR_WINDOW = ANCHOR_WINDOW

local pullStartTime = 0
---@type table<string, integer>
local assigned = {}

---@param elapsed number
---@return integer|nil
local function MatchAnchor(elapsed)
    if type(elapsed) ~= "number" then
        return nil
    end
    local lastOffset = (ANCHORS_PER_WAVE - 1) + ANCHOR_WINDOW
    for i = 1, #WAVE_STARTS do
        local offset = elapsed - WAVE_STARTS[i]
        if offset >= -ANCHOR_WINDOW and offset <= lastOffset then
            local index = math.floor(offset + 0.5) + 1
            if index >= 1 and index <= ANCHORS_PER_WAVE then
                local anchor = WAVE_STARTS[i] + (index - 1)
                if math.abs(elapsed - anchor) <= ANCHOR_WINDOW then
                    return index
                end
            end
        end
    end
    return nil
end

---@param unit any
---@return boolean
local function IsAddNameplate(unit)
    if not Nameplate.IsUnitToken(unit) then
        return false
    end
    return Unit.IsBossMob(unit) == false
end

local function NotifyShow(unit, number)
    if TwinFangs.OnNameplateHintShow then
        TwinFangs:OnNameplateHintShow(unit, number)
    end
end

local function NotifyHide(unit)
    if TwinFangs.OnNameplateHintHide then
        TwinFangs:OnNameplateHintHide(unit)
    end
end

local function NotifyCleared()
    if TwinFangs.OnNameplateHintCleared then
        TwinFangs:OnNameplateHintCleared()
    end
end

local function ClearAssignments()
    if next(assigned) == nil then
        return
    end
    for unit in pairs(assigned) do
        assigned[unit] = nil
    end
    NotifyCleared()
end

---@param unit string
local function OnNameplateRemoved(unit)
    if not Nameplate.IsUnitToken(unit) or assigned[unit] == nil then
        return
    end
    assigned[unit] = nil
end

---@param unit any
local function OnCastStart(unit)
    if not TwinFangs:IsNameplateHintEnabled() then
        return
    end
    if not IsAddNameplate(unit) then
        return
    end
    local elapsed = Timer.GetTime() - pullStartTime
    local index = MatchAnchor(elapsed)
    if not index then
        return
    end
    assigned[unit] = index
    NotifyShow(unit, index)
end

---@param unit any
local function OnCastStop(unit)
    if not TwinFangs:IsNameplateHintEnabled() or not IsAddNameplate(unit) then
        return
    end
    assigned[unit] = nil
    NotifyHide(unit)
end

---Subscribes to add casts for this Mythic pull. The returned function drops the subscription and any badges.
---@return fun()
function TwinFangs:ListenForNameplateHint()
    pullStartTime = Timer.GetTime()
    local unsubscribeStart = Spell.OnCastStart(OnCastStart)
    local unsubscribeStop = Spell.OnCastStop(OnCastStop)
    local unsubscribeRemoved = Nameplate.OnRemoved(OnNameplateRemoved)
    return function()
        unsubscribeStart()
        unsubscribeStop()
        unsubscribeRemoved()
        pullStartTime = 0
        ClearAssignments()
    end
end

function TwinFangs:ClearNameplateHints()
    ClearAssignments()
end

function TwinFangs:ReplayNameplateHints()
    for unit, number in pairs(assigned) do
        NotifyShow(unit, number)
    end
end
