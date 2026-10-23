local _, ns = ...
local Internals = ns.Modules.Internals("TwinFangs")
local L = ns.L
local GameEvents = ns.Api.GameEvents
local Timer = ns.Api.Timer

local TwinFangs = ns.Modules.Get("TwinFangs")
local InterruptChain = Internals.InterruptChain

-- Visible after Brood fires; interrupt reports do not extend this window.
local WINDOW_SECONDS = 11
local CALLOUT_SECONDS = 10
-- Edit Mode uses the same snapshot as a live window at round 1 in front-left, assignment 3.
local PREVIEW_REGION = InterruptChain.FRONT_LEFT
local PREVIEW_INDEX = 3
local PREVIEW_COUNT = 0
local PREVIEW_CHAIN_LENGTH = 5

TwinFangs.INTERRUPT_STATUS_DURATION = WINDOW_SECONDS
TwinFangs.INTERRUPT_CALLOUT_DURATION = CALLOUT_SECONDS

---@class TwinFangsInterruptStatus
---@field region string
---@field index integer
---@field interruptCount integer
---@field chainLength integer

---@type integer
local windowToken = 0
local windowActive = false
local interruptCount = 0
local backupCount = 0
---@type string|nil
local windowRegion = nil
---@type integer|nil
local windowIndex = nil
---@type integer|nil
local windowChainLength = nil
---@type string|nil
local windowBackupRegion = nil
---@type integer|nil
local windowBackupChainLength = nil
local testMode = false
local testCount = 0
local testBackupCount = 0
---@type "primary"|"backup"|nil
local interruptCalloutRole = nil
---@type fun()|nil
local unsubscribeTest = nil

---@param regionId string
---@return string
local function RegionLabel(regionId)
    if regionId == InterruptChain.FRONT_LEFT then
        return L.TWIN_FANGS_INTERRUPT_REGION_FRONT_LEFT
    elseif regionId == InterruptChain.FRONT_RIGHT then
        return L.TWIN_FANGS_INTERRUPT_REGION_FRONT_RIGHT
    elseif regionId == InterruptChain.BACK_LEFT then
        return L.TWIN_FANGS_INTERRUPT_REGION_BACK_LEFT
    elseif regionId == InterruptChain.BACK_RIGHT then
        return L.TWIN_FANGS_INTERRUPT_REGION_BACK_RIGHT
    end
    return regionId
end

local function HideInterruptCallout()
    if not interruptCalloutRole then
        return
    end
    interruptCalloutRole = nil
    TwinFangs:CancelCallout("interrupt")
end

---@param snapshot TwinFangsInterruptStatus|nil
---@return boolean
local function PrimaryDue(snapshot)
    return snapshot ~= nil and (snapshot.interruptCount + 1) == snapshot.index
end

---@param snapshot TwinFangsInterruptStatus|nil
---@return boolean
local function BackupDue(snapshot)
    return snapshot ~= nil and (snapshot.interruptCount + 1) > snapshot.chainLength
end

---@param role "primary"|"backup"
---@param snapshot TwinFangsInterruptStatus
local function ShowInterruptCallout(role, snapshot)
    if interruptCalloutRole == role then
        return
    end
    interruptCalloutRole = role
    TwinFangs:ShowCallout(L.TWIN_FANGS_INTERRUPT_CALLOUT:format(RegionLabel(snapshot.region)), Timer.GetTime() + CALLOUT_SECONDS, {
        kind = "interrupt",
        appendTimer = false,
    })
end

local function SyncInterruptCallout()
    local backup = TwinFangs:GetBackupInterruptStatus()
    if BackupDue(backup) then
        ShowInterruptCallout("backup", backup)
        return
    end
    local primary = TwinFangs:GetInterruptStatus()
    if PrimaryDue(primary) then
        ShowInterruptCallout("primary", primary)
        return
    end
    HideInterruptCallout()
end

local function Notify()
    SyncInterruptCallout()
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

---Counts incoming whispers by occurrence only. Does not read event arguments:
---CHAT_MSG_WHISPER text can be a secret value, and comparing it throws.
---@param handler fun()
---@return fun()
local function ListenForIncomingWhispers(handler)
    return GameEvents.Listen("CHAT_MSG_WHISPER", handler)
end

---Outgoing whispers. Used in test mode so a self-sent `/w` advances the backup HUD.
---@param handler fun()
---@return fun()
local function ListenForOutgoingWhispers(handler)
    return GameEvents.Listen("CHAT_MSG_WHISPER_INFORM", handler)
end

---@param onParty fun()
---@param onWhisper fun()
---@param onOutgoingWhisper fun()|nil
---@return fun()
local function ListenForInterruptReports(onParty, onWhisper, onOutgoingWhisper)
    local unsubscribeParty = ListenForPartyChat(onParty)
    local unsubscribeWhisper = ListenForIncomingWhispers(onWhisper)
    local unsubscribeOutgoing
    if onOutgoingWhisper then
        unsubscribeOutgoing = ListenForOutgoingWhispers(onOutgoingWhisper)
    end
    return function()
        unsubscribeParty()
        unsubscribeWhisper()
        if unsubscribeOutgoing then
            unsubscribeOutgoing()
        end
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

---@return string|nil, integer|nil
local function BackupAssignment()
    local identity = InterruptChain.ResolveLocalPlayerName()
    local chain = TwinFangs.db.interruptReminder.chain
    local duties = InterruptChain.GetPlayerResponsibilities(chain, identity)
    if not duties.backup then
        return nil, nil
    end
    local region = type(chain) == "table" and chain[duties.backup] or nil
    local chainLength = region and type(region.players) == "table" and #region.players or 0
    if chainLength < 1 then
        return nil, nil
    end
    return duties.backup, chainLength
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

---@return TwinFangsInterruptStatus|nil
local function LiveBackupStatus(count)
    local region, chainLength = BackupAssignment()
    if not region or not chainLength then
        return nil
    end
    return {
        region = region,
        index = chainLength + 1,
        interruptCount = count,
        chainLength = chainLength,
    }
end

---@return boolean
function TwinFangs:HasPrimaryInterruptAssignment()
    local region, index = PrimaryAssignment()
    return region ~= nil and index ~= nil
end

---@return boolean
function TwinFangs:HasBackupInterruptAssignment()
    local region = BackupAssignment()
    return region ~= nil
end

local function ClearWindow()
    local wasActive = windowActive
    windowActive = false
    interruptCount = 0
    backupCount = 0
    windowRegion = nil
    windowIndex = nil
    windowChainLength = nil
    windowBackupRegion = nil
    windowBackupChainLength = nil
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

---@return integer
function TwinFangs:GetBackupInterruptCount()
    return backupCount
end

---@return boolean
function TwinFangs:IsInterruptStatusTestMode()
    return testMode == true
end

---Shows HUDs from the current assignments and counts party chat / backup whispers until stopped.
---@param enabled boolean
function TwinFangs:SetInterruptStatusTestMode(enabled)
    enabled = enabled == true and self:IsInterruptReminderEnabled()
    if testMode == enabled then
        return
    end
    testMode = enabled
    if enabled then
        testCount = 0
        testBackupCount = 0
        if not unsubscribeTest then
            unsubscribeTest = ListenForInterruptReports(function()
                TwinFangs:NoteInterruptTestReport()
            end, function()
                TwinFangs:NoteInterruptTestBackupReport()
            end, function()
                TwinFangs:NoteInterruptTestBackupReport()
            end)
        end
    else
        if unsubscribeTest then
            unsubscribeTest()
            unsubscribeTest = nil
        end
        testCount = 0
        testBackupCount = 0
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

---@return TwinFangsInterruptStatus|nil
function TwinFangs:GetBackupInterruptStatus()
    if self:IsInterruptStatusTestMode() then
        return LiveBackupStatus(testBackupCount)
    end
    if
        not windowActive
        or not windowBackupRegion
        or not windowBackupChainLength
        or not self:HasBackupInterruptAssignment()
    then
        return nil
    end
    return {
        region = windowBackupRegion,
        index = windowBackupChainLength + 1,
        interruptCount = backupCount,
        chainLength = windowBackupChainLength,
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

---Starts an 11-second interrupt-status window. No-op without a primary or backup assignment.
function TwinFangs:BeginInterruptStatusWindow()
    if not self:IsInEncounter() or not self:IsInterruptReminderEnabled() then
        return
    end
    local region, index, chainLength = PrimaryAssignment()
    local backupRegion, backupChainLength = BackupAssignment()
    if not region and not backupRegion then
        return
    end
    windowToken = windowToken + 1
    local token = windowToken
    windowActive = true
    interruptCount = 0
    backupCount = 0
    windowRegion = region
    windowIndex = index
    windowChainLength = chainLength
    windowBackupRegion = backupRegion
    windowBackupChainLength = backupChainLength
    Notify()
    Timer.After(WINDOW_SECONDS, function()
        if token ~= windowToken then
            return
        end
        ClearWindow()
    end)
end

---Hides the runtime HUD and resets the interrupt counts. Invalidates a pending hide.
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

---One incoming whisper during an active window is one backup-region report. Payload is unused.
function TwinFangs:NoteInterruptBackupReport()
    if not windowActive then
        return
    end
    backupCount = backupCount + 1
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

---One incoming or outgoing whisper during test mode is one backup-region report. Payload is unused.
function TwinFangs:NoteInterruptTestBackupReport()
    if not testMode then
        return
    end
    testBackupCount = testBackupCount + 1
    Notify()
end

---@return fun()
function TwinFangs:ListenForInterruptStatus()
    return ListenForInterruptReports(function()
        TwinFangs:NoteInterruptReport()
    end, function()
        TwinFangs:NoteInterruptBackupReport()
    end)
end
