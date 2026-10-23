local _, ns = ...
local Internals = ns.Modules.Internals("TwinFangs")
local GameEvents = ns.Api.GameEvents
local Timer = ns.Api.Timer

local TwinFangs = ns.Modules.Get("TwinFangs")
local InterruptChain = Internals.InterruptChain

-- Visible after Brood fires; interrupt reports do not extend this window.
local WINDOW_SECONDS = 11
-- Edit Mode uses the same snapshot as a live window at round 1 in front-left, assignment 3.
local PREVIEW_REGION = InterruptChain.FRONT_LEFT
local PREVIEW_INDEX = 3
local PREVIEW_COUNT = 0
local PREVIEW_CHAIN_LENGTH = 5

TwinFangs.INTERRUPT_STATUS_DURATION = WINDOW_SECONDS

---@class TwinFangsInterruptStatus
---@field region string
---@field index integer
---@field interruptCount integer
---@field chainLength integer

---@type integer
local windowToken = 0
local windowActive = false
local interruptCount = 0
---@type string|nil
local windowRegion = nil
---@type integer|nil
local windowIndex = nil
---@type integer|nil
local windowChainLength = nil
local testMode = false
local testCount = 0
---@type fun()|nil
local unsubscribeTest = nil

local function Notify()
    if TwinFangs.OnInterruptStatusChanged then
        TwinFangs:OnInterruptStatusChanged()
    end
end

local function NotifyTestMode()
    if TwinFangs.OnInterruptStatusTestModeChanged then
        TwinFangs:OnInterruptStatusTestModeChanged()
    end
    Notify()
end

---Counts party and party-leader chat by occurrence only. Does not read event arguments.
---@param handler fun()
---@return fun()
local function ListenForPartyChat(handler)
    local unsubscribeParty = GameEvents.Listen("CHAT_MSG_PARTY", handler)
    local unsubscribeLeader = GameEvents.Listen("CHAT_MSG_PARTY_LEADER", handler)
    return function()
        unsubscribeParty()
        unsubscribeLeader()
    end
end

---@return string|nil, integer|nil, integer|nil
local function PrimaryAssignment()
    local identity = InterruptChain.ResolveLocalPlayerName()
    local chain = TwinFangs.db.interruptReminder.chain
    local duties = InterruptChain.GetPlayerResponsibilities(chain, identity)
    if not duties.region or not duties.index then
        return nil, nil, nil
    end
    local region = type(chain) == "table" and chain[duties.region] or nil
    local chainLength = region and type(region.players) == "table" and #region.players or 0
    if chainLength < 1 then
        return nil, nil, nil
    end
    return duties.region, duties.index, chainLength
end

---@return TwinFangsInterruptStatus|nil
local function LiveAssignmentStatus(count)
    local region, index, chainLength = PrimaryAssignment()
    if not region or not index or not chainLength then
        return nil
    end
    return {
        region = region,
        index = index,
        interruptCount = count,
        chainLength = chainLength,
    }
end

---@return boolean
function TwinFangs:HasPrimaryInterruptAssignment()
    local region, index = PrimaryAssignment()
    return region ~= nil and index ~= nil
end

local function ClearWindow()
    local wasActive = windowActive
    windowActive = false
    interruptCount = 0
    windowRegion = nil
    windowIndex = nil
    windowChainLength = nil
    if wasActive then
        Notify()
    end
end

---@return boolean
function TwinFangs:IsInterruptStatusActive()
    return windowActive == true
end

---@return integer
function TwinFangs:GetInterruptCount()
    return interruptCount
end

---@return boolean
function TwinFangs:IsInterruptStatusTestMode()
    return testMode == true
end

---Shows the HUD from the current primary assignment and counts party chat until stopped.
---@param enabled boolean
function TwinFangs:SetInterruptStatusTestMode(enabled)
    enabled = enabled == true and self:IsInterruptReminderEnabled()
    if testMode == enabled then
        return
    end
    testMode = enabled
    if enabled then
        testCount = 0
        if not unsubscribeTest then
            unsubscribeTest = ListenForPartyChat(function()
                TwinFangs:NoteInterruptTestReport()
            end)
        end
    else
        if unsubscribeTest then
            unsubscribeTest()
            unsubscribeTest = nil
        end
        testCount = 0
    end
    NotifyTestMode()
end

---@return TwinFangsInterruptStatus|nil
function TwinFangs:GetInterruptStatus()
    if self:IsInterruptStatusTestMode() then
        return LiveAssignmentStatus(testCount)
    end
    if
        not windowActive
        or not windowRegion
        or not windowIndex
        or not windowChainLength
        or not self:HasPrimaryInterruptAssignment()
    then
        return nil
    end
    return {
        region = windowRegion,
        index = windowIndex,
        interruptCount = interruptCount,
        chainLength = windowChainLength,
    }
end

---Same region / index / count as a live window at round 1; preview chain length is a mock.
---@return TwinFangsInterruptStatus
function TwinFangs:GetInterruptStatusPreview()
    return {
        region = PREVIEW_REGION,
        index = PREVIEW_INDEX,
        interruptCount = PREVIEW_COUNT,
        chainLength = PREVIEW_CHAIN_LENGTH,
    }
end

---Starts an 11-second interrupt-status window. No-op without a primary assignment.
function TwinFangs:BeginInterruptStatusWindow()
    if not self:IsInEncounter() or not self:IsInterruptReminderEnabled() then
        return
    end
    local region, index, chainLength = PrimaryAssignment()
    if not region or not index or not chainLength then
        return
    end
    windowToken = windowToken + 1
    local token = windowToken
    windowActive = true
    interruptCount = 0
    windowRegion = region
    windowIndex = index
    windowChainLength = chainLength
    Notify()
    Timer.After(WINDOW_SECONDS, function()
        if token ~= windowToken then
            return
        end
        ClearWindow()
    end)
end

---Hides the runtime HUD and resets the interrupt count. Invalidates a pending hide.
function TwinFangs:EndInterruptStatusWindow()
    windowToken = windowToken + 1
    ClearWindow()
end

---One party or party-leader chat during an active window is one interrupt report. Payload is unused.
function TwinFangs:NoteInterruptReport()
    if not windowActive then
        return
    end
    interruptCount = interruptCount + 1
    Notify()
end

---One party or party-leader chat during test mode is one interrupt report. Payload is unused.
function TwinFangs:NoteInterruptTestReport()
    if not testMode then
        return
    end
    testCount = testCount + 1
    Notify()
end

---@return fun()
function TwinFangs:ListenForInterruptStatus()
    return ListenForPartyChat(function()
        TwinFangs:NoteInterruptReport()
    end)
end
