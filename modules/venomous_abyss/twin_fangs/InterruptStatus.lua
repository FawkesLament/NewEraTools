local _, ns = ...
local Internals = ns.Modules.Internals("TwinFangs")
local L = ns.L
local GameEvents = ns.Api.GameEvents
local Timer = ns.Api.Timer

local TwinFangs = ns.Modules.Get("TwinFangs")
local InterruptChain = Internals.InterruptChain
local Schema = Internals.Schema

-- Visible after Brood fires; interrupt reports do not extend this window.
local WINDOW_SECONDS = 14
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
---@field indexEnd integer
---@field interruptCount integer
---@field chainLength integer

---@class TwinFangsInterruptMonitor
---@field channels table<string, TwinFangsInterruptChannel>
---@field primaryRegion string|nil
---@field primaryIndex integer|nil
---@field primaryIndexEnd integer|nil
---@field primaryLength integer|nil
---@field backupRegion string|nil
---@field backupLength integer|nil

local SUPPORTED_CHANNEL_EVENTS = {
    { channel = Schema.CHANNEL_PARTY, events = { "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER" } },
    { channel = Schema.CHANNEL_RAID, events = { "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER" } },
    { channel = Schema.CHANNEL_SAY, events = { "CHAT_MSG_SAY" } },
    { channel = Schema.CHANNEL_YELL, events = { "CHAT_MSG_YELL" } },
    { channel = Schema.CHANNEL_EMOTE, events = { "CHAT_MSG_EMOTE" } },
    { channel = Schema.CHANNEL_NOD, events = { "CHAT_MSG_TEXT_EMOTE" } },
    { channel = Schema.CHANNEL_MARKER, events = { "RAID_TARGET_UPDATE" } },
}

---@type integer
local windowToken = 0
local windowActive = false
---@type TwinFangsInterruptMonitor|nil
local encounterMonitor = nil
---@type table<string, integer>
local encounterCounts = {}
---@type string|nil
local windowRegion = nil
---@type integer|nil
local windowIndex = nil
---@type integer|nil
local windowIndexEnd = nil
---@type integer|nil
local windowChainLength = nil
---@type string|nil
local windowBackupRegion = nil
---@type integer|nil
local windowBackupChainLength = nil
local testMode = false
---@type table<string, integer>
local testCounts = {}
---@type "primary"|"backup"|nil
local interruptCalloutRole = nil
---@type integer|nil
local interruptCalloutRound = nil
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
    interruptCalloutRound = nil
    TwinFangs:CancelCallout("interrupt")
end

---@param snapshot TwinFangsInterruptStatus|nil
---@return boolean
local function AssignmentCovers(snapshot, round)
    local first = snapshot.index
    local last = snapshot.indexEnd or snapshot.index
    return round >= first and round <= last
end

local function PrimaryDue(snapshot)
    return snapshot ~= nil and AssignmentCovers(snapshot, snapshot.interruptCount + 1)
end

---@param snapshot TwinFangsInterruptStatus|nil
---@return boolean
local function BackupDue(snapshot)
    return snapshot ~= nil and (snapshot.interruptCount + 1) > snapshot.chainLength
end

---@param role "primary"|"backup"
---@param snapshot TwinFangsInterruptStatus
local function ShowInterruptCallout(role, snapshot)
    local round = snapshot.interruptCount + 1
    if interruptCalloutRole == role and interruptCalloutRound == round then
        return
    end
    interruptCalloutRole = role
    interruptCalloutRound = round
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

---@param chain TwinFangsInterruptChainSettings|nil
---@param regionId string
---@return integer
local function RegionLength(chain, regionId)
    local region = type(chain) == "table" and chain[regionId] or nil
    return region and type(region.players) == "table" and #region.players or 0
end

---Frozen duties and per-zone channels. Backup is omitted when the zone uses party.
---@return TwinFangsInterruptMonitor
local function CaptureMonitor()
    local chain = TwinFangs.db.interruptReminder.chain
    local identity = InterruptChain.ResolveLocalPlayerName()
    local duties = InterruptChain.GetPlayerResponsibilities(chain, identity)
    local channels = {}
    for _, regionId in ipairs(InterruptChain.REGION_IDS) do
        local region = type(chain) == "table" and chain[regionId] or nil
        channels[regionId] = Schema.CoerceChannel(region and region.channel)
    end
    local primaryRegion, primaryIndex, primaryIndexEnd, primaryLength
    if duties.region and duties.index then
        local n = RegionLength(chain, duties.region)
        if n >= 1 then
            primaryRegion = duties.region
            primaryIndex = duties.index
            primaryIndexEnd = duties.indexEnd or duties.index
            primaryLength = n
        end
    end
    local backupRegion, backupLength
    if duties.backup then
        local n = RegionLength(chain, duties.backup)
        if n >= 1 and Schema.ChannelAllowsBackup(channels[duties.backup]) then
            backupRegion, backupLength = duties.backup, n
        end
    end
    return {
        channels = channels,
        primaryRegion = primaryRegion,
        primaryIndex = primaryIndex,
        primaryIndexEnd = primaryIndexEnd,
        primaryLength = primaryLength,
        backupRegion = backupRegion,
        backupLength = backupLength,
    }
end

---At most one monitored zone per event. Primary wins when both match.
---@param monitor TwinFangsInterruptMonitor
---@param channel TwinFangsInterruptChannel
---@return string|nil
local function MatchMonitoredRegion(monitor, channel)
    if monitor.primaryRegion and monitor.channels[monitor.primaryRegion] == channel then
        return monitor.primaryRegion
    end
    local backup = monitor.backupRegion
    if backup and backup ~= monitor.primaryRegion and monitor.channels[backup] == channel then
        return backup
    end
    return nil
end

---@param regionId string
---@param counts table<string, integer>
local function OnInterruptSignal(regionId, counts)
    counts[regionId] = (counts[regionId] or 0) + 1
end

---Counts supported channel events by occurrence only. Does not read arguments
---(chat text, sender, GUID, and RAID_TARGET_UPDATE have no inspected payload).
---@param onChannel fun(channel: TwinFangsInterruptChannel)
---@return fun()
local function ListenForSupportedChannels(onChannel)
    local unsubs = {}
    for _, spec in ipairs(SUPPORTED_CHANNEL_EVENTS) do
        for _, event in ipairs(spec.events) do
            unsubs[#unsubs + 1] = GameEvents.Listen(event, function()
                onChannel(spec.channel)
            end)
        end
    end
    return function()
        for i = 1, #unsubs do
            unsubs[i]()
        end
    end
end

---@return string|nil, integer|nil, integer|nil, integer|nil
local function PrimaryAssignment()
    local monitor = CaptureMonitor()
    return monitor.primaryRegion, monitor.primaryIndex, monitor.primaryLength, monitor.primaryIndexEnd
end

---@return string|nil, integer|nil
local function BackupAssignment()
    local monitor = CaptureMonitor()
    return monitor.backupRegion, monitor.backupLength
end

---@return TwinFangsInterruptStatus|nil
local function LiveAssignmentStatus(count)
    local region, index, chainLength, indexEnd = PrimaryAssignment()
    if not region or not index or not chainLength then
        return nil
    end
    return {
        region = region,
        index = index,
        indexEnd = indexEnd or index,
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
        indexEnd = chainLength + 1,
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
    encounterCounts = {}
    windowRegion = nil
    windowIndex = nil
    windowIndexEnd = nil
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
    if not windowRegion then
        return 0
    end
    return encounterCounts[windowRegion] or 0
end

---@return integer
function TwinFangs:GetBackupInterruptCount()
    if not windowBackupRegion then
        return 0
    end
    return encounterCounts[windowBackupRegion] or 0
end

---@return boolean
function TwinFangs:IsInterruptStatusTestMode()
    return testMode == true
end

---Shows HUDs from the current assignments and counts configured-channel signals until stopped.
---No-op unless the interrupt reminder is on and the player is in a raid.
---@param enabled boolean
function TwinFangs:SetInterruptStatusTestMode(enabled)
    enabled = enabled == true and self:IsInterruptReminderEnabled() and ns.Api.Group.IsInRaid()
    if testMode == enabled then
        return
    end
    testMode = enabled
    if enabled then
        testCounts = {}
        if not unsubscribeTest then
            unsubscribeTest = ListenForSupportedChannels(function(channel)
                if not testMode then
                    return
                end
                local regionId = MatchMonitoredRegion(CaptureMonitor(), channel)
                if not regionId then
                    return
                end
                OnInterruptSignal(regionId, testCounts)
                Notify()
            end)
        end
    else
        if unsubscribeTest then
            unsubscribeTest()
            unsubscribeTest = nil
        end
        testCounts = {}
    end
    NotifyTestMode()
end

---@return TwinFangsInterruptStatus|nil
function TwinFangs:GetInterruptStatus()
    if self:IsInterruptStatusTestMode() then
        local region = CaptureMonitor().primaryRegion
        return LiveAssignmentStatus(region and testCounts[region] or 0)
    end
    if not windowActive or not windowRegion or not windowIndex or not windowChainLength then
        return nil
    end
    return {
        region = windowRegion,
        index = windowIndex,
        indexEnd = windowIndexEnd or windowIndex,
        interruptCount = encounterCounts[windowRegion] or 0,
        chainLength = windowChainLength,
    }
end

---@return TwinFangsInterruptStatus|nil
function TwinFangs:GetBackupInterruptStatus()
    if self:IsInterruptStatusTestMode() then
        local region = CaptureMonitor().backupRegion
        return LiveBackupStatus(region and testCounts[region] or 0)
    end
    if not windowActive or not windowBackupRegion or not windowBackupChainLength then
        return nil
    end
    return {
        region = windowBackupRegion,
        index = windowBackupChainLength + 1,
        indexEnd = windowBackupChainLength + 1,
        interruptCount = encounterCounts[windowBackupRegion] or 0,
        chainLength = windowBackupChainLength,
    }
end

---Same region / index / count as a live window at round 1; preview chain length is a mock.
---@return TwinFangsInterruptStatus
function TwinFangs:GetInterruptStatusPreview()
    return {
        region = PREVIEW_REGION,
        index = PREVIEW_INDEX,
        indexEnd = PREVIEW_INDEX,
        interruptCount = PREVIEW_COUNT,
        chainLength = PREVIEW_CHAIN_LENGTH,
    }
end

---Starts a 14-second interrupt-status window. No-op without a primary or backup assignment.
function TwinFangs:BeginInterruptStatusWindow()
    if not self:IsInEncounter() or not self:IsInterruptReminderEnabled() then
        return
    end
    local monitor = encounterMonitor or CaptureMonitor()
    if not monitor.primaryRegion and not monitor.backupRegion then
        return
    end
    windowToken = windowToken + 1
    local token = windowToken
    windowActive = true
    encounterCounts = {}
    windowRegion = monitor.primaryRegion
    windowIndex = monitor.primaryIndex
    windowIndexEnd = monitor.primaryIndexEnd or monitor.primaryIndex
    windowChainLength = monitor.primaryLength
    windowBackupRegion = monitor.backupRegion
    windowBackupChainLength = monitor.backupLength
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

---@return fun()
function TwinFangs:ListenForInterruptStatus()
    encounterMonitor = CaptureMonitor()
    local unsubscribe = ListenForSupportedChannels(function(channel)
        if not windowActive or not encounterMonitor then
            return
        end
        local regionId = MatchMonitoredRegion(encounterMonitor, channel)
        if not regionId then
            return
        end
        OnInterruptSignal(regionId, encounterCounts)
        Notify()
    end)
    return function()
        unsubscribe()
        encounterMonitor = nil
    end
end
