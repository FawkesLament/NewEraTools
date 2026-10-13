local _, ns = ...
local L = ns.L
local Chat = ns.Api.Chat
local Encounter = ns.Api.Encounter
local Timer = ns.Api.Timer
local Util = ns.Util

local Sszorak = ns.Modules.Get("Sszorak")

-- Raid leader callouts saved per home phase; text may be secret values and is stored opaque.
local RAID_LEADER_MESSAGE_LIMIT = 3
-- How long a matched callout stays on screen (wall-clock), unless a later callout replaces it.
local CALLOUT_DURATION_ENCOUNTER = 10
local CALLOUT_DURATION_TEST = 10
-- ENCOUNTER_WARNING filters: High severity, ~3.5s duration, near one of these pull-relative anchors.
local WARNING_SEVERITY = 2
local WARNING_DURATION = 3.5
local WARNING_DURATION_TOLERANCE = 0.1
local WARNING_TIME_WINDOW = 1.2
local WARNING_ANCHORS = { 32, 34, 79, 81, 159, 161, 206, 208, 285.5, 287.5, 332.5, 334.5 }
-- Anchors are processed in groups of this size; the index within the group selects a saved message.
local WARNING_ANCHOR_GROUP_SIZE = 4

Sszorak.RAID_LEADER_MESSAGE_LIMIT = RAID_LEADER_MESSAGE_LIMIT
Sszorak.CALLOUT_DURATION_ENCOUNTER = CALLOUT_DURATION_ENCOUNTER
Sszorak.CALLOUT_DURATION_TEST = CALLOUT_DURATION_TEST
Sszorak.WARNING_SEVERITY = WARNING_SEVERITY
Sszorak.WARNING_DURATION = WARNING_DURATION
Sszorak.WARNING_DURATION_TOLERANCE = WARNING_DURATION_TOLERANCE
Sszorak.WARNING_TIME_WINDOW = WARNING_TIME_WINDOW
Sszorak.WARNING_ANCHORS = WARNING_ANCHORS
Sszorak.WARNING_ANCHOR_GROUP_SIZE = WARNING_ANCHOR_GROUP_SIZE

---Outcome of resolving a saved raid-leader message (or a fixed callout like exit).
---A non-nil resolve always has `hudMessage`. Modes return `nil` when nothing should be shown
---(e.g. jailbreak has not identified a marker yet) — an empty table is not used for that.
---`hudMessage` is not always derivable from `targetEdge` (normal keeps RL text; exit uses locale).
---`targetEdge` is the map path tip (`nil` = no arrow); the marker on that edge is from the assignment.
---@class SszorakCalloutResolve
---@field hudMessage any  Opaque / formatted text for SetFormattedText; required.
---@field targetEdge integer|nil  Arena edge for the path overlay (e.g. exit or jailbreak destination).

---@class SszorakCalloutMode
---@field id string
---@field Resolve fun(self: SszorakCalloutMode, savedMessage: any, context: table|nil): SszorakCalloutResolve|nil
---@field GetEdgeMacroBody fun(self: SszorakCalloutMode, edge: integer, assignment: table<integer, WorldMarker>): string
---@field Listen fun(self: SszorakCalloutMode): fun()  Subscribe mode listeners; returns unsubscribe.

---@type table<string, SszorakCalloutMode>
local modes = {}

-- Session-only: first raid leader messages since the last time dots returned home (opaque values).
local raidLeaderMessages = {}
-- Session-only: whether CHAT_MSG_RAID_LEADER is stored (boss fight or map test only).
local raidLeaderCapture = false
-- Session-only: opaque callout text currently shown on screen (nil when hidden).
local displayedCallout = nil
local calloutExpireTime = nil
local displayedCalloutAppendTimer = false
local calloutToken = 0
-- Session-only: last resolve payload (for map overlays); cleared with the HUD callout.
---@type SszorakCalloutResolve|nil
local displayedResolve = nil
-- True after OnEnable has asked the active mode to listen (mode switches rebind while true).
local calloutModeListening = false
---@type fun()|nil
local stopCalloutModeListeners = nil

---@param mode SszorakCalloutMode
function Sszorak.RegisterCalloutMode(mode)
    assert(type(mode) == "table" and type(mode.id) == "string", "Bad callout mode")
    assert(type(mode.Resolve) == "function", "Callout mode requires Resolve")
    assert(type(mode.GetEdgeMacroBody) == "function", "Callout mode requires GetEdgeMacroBody")
    assert(type(mode.Listen) == "function", "Callout mode requires Listen")
    modes[mode.id] = mode
end

---@param modeId string
---@return boolean
function Sszorak.IsCalloutModeAvailable(modeId)
    return modes[modeId] ~= nil
end

---@return SszorakCalloutMode
function Sszorak:GetActiveCalloutMode()
    local id = self.db.calloutMode
    local mode = modes[id] or modes[Sszorak.CALLOUT_MODE_NORMAL]
    return assert(mode, "No callout mode registered")
end

---@return string
function Sszorak:GetCalloutMode()
    local id = self.db.calloutMode
    if modes[id] then
        return id
    end
    return Sszorak.CALLOUT_MODE_NORMAL
end

local function StopCalloutModeListeners()
    if not stopCalloutModeListeners then
        return
    end
    local stop = stopCalloutModeListeners
    stopCalloutModeListeners = nil
    stop()
end

local function RestartCalloutModeListeners()
    if not calloutModeListening then
        return
    end
    StopCalloutModeListeners()
    stopCalloutModeListeners = Sszorak:GetActiveCalloutMode():Listen() or function() end
end

---@param modeId string
function Sszorak:SetCalloutMode(modeId)
    assert(modes[modeId], "Unknown callout mode: " .. tostring(modeId))
    if self.db.calloutMode == modeId then
        return
    end
    self.db.calloutMode = modeId
    RestartCalloutModeListeners()
    -- Macro bodies are mode-specific; sync is bound from SszorakMacros.lua.
    Sszorak.RequestMacroSync()
end

---Starts the active callout mode's listeners. Called from OnEnable; mode switches rebind while active.
function Sszorak:ListenForCalloutMode()
    calloutModeListening = true
    RestartCalloutModeListeners()
end

local function NotifyRaidLeaderMessagesChanged()
    if Sszorak.OnRaidLeaderMessagesChanged then
        Sszorak:OnRaidLeaderMessagesChanged()
    end
end

local function NotifyCalloutChanged()
    if Sszorak.OnCalloutChanged then
        Sszorak:OnCalloutChanged()
    end
end

local function ClearDisplayedCallout()
    calloutToken = calloutToken + 1
    calloutExpireTime = nil
    displayedCalloutAppendTimer = false
    displayedResolve = nil
    if displayedCallout == nil then
        return
    end
    displayedCallout = nil
    NotifyCalloutChanged()
end

---Shows a resolved callout until `duration` elapses or the callout is cleared.
---No-ops when `resolve` is nil (mode: nothing to show). Non-nil resolves require `hudMessage`.
---@param resolve SszorakCalloutResolve|nil
---@param duration number
---@param appendTimer boolean|nil
local function ShowResolvedCallout(resolve, duration, appendTimer)
    if resolve == nil then
        return
    end
    local message = assert(resolve.hudMessage, "SszorakCalloutResolve requires hudMessage")
    calloutToken = calloutToken + 1
    local token = calloutToken
    displayedResolve = resolve
    displayedCallout = message
    calloutExpireTime = Timer.GetTime() + duration
    displayedCalloutAppendTimer = appendTimer == true
    NotifyCalloutChanged()
    Timer.After(duration, function()
        if token ~= calloutToken then
            return
        end
        displayedCallout = nil
        displayedResolve = nil
        calloutExpireTime = nil
        displayedCalloutAppendTimer = false
        NotifyCalloutChanged()
    end)
end

---@param savedMessage any
---@param duration number
---@param appendTimer boolean|nil
local function ResolveAndShow(savedMessage, duration, appendTimer)
    local resolve = Sszorak:GetActiveCalloutMode():Resolve(savedMessage, nil)
    ShowResolvedCallout(resolve, duration, appendTimer)
end

local function ClearRaidLeaderMessages()
    ClearDisplayedCallout()
    if #raidLeaderMessages == 0 then
        return
    end
    Util.Wipe(raidLeaderMessages)
    NotifyRaidLeaderMessagesChanged()
end

---Closest warning anchor within the time window, or nil.
---@param elapsed number
---@return integer|nil
local function FindMatchingAnchorIndex(elapsed)
    local bestIndex
    local bestDistance
    for index, anchor in ipairs(WARNING_ANCHORS) do
        local distance = math.abs(elapsed - anchor)
        if distance <= WARNING_TIME_WINDOW and (not bestDistance or distance < bestDistance) then
            bestIndex = index
            bestDistance = distance
        end
    end
    return bestIndex
end

---@param warningInfo table
local function OnEncounterWarning(warningInfo)
    if not Sszorak:IsInEncounter() or type(warningInfo) ~= "table" then
        return
    end
    if warningInfo.severity ~= WARNING_SEVERITY then
        return
    end
    local duration = warningInfo.duration
    if type(duration) ~= "number" or math.abs(duration - WARNING_DURATION) > WARNING_DURATION_TOLERANCE then
        return
    end
    local anchorIndex = FindMatchingAnchorIndex(Sszorak:GetTimelineElapsed())
    if not anchorIndex then
        return
    end
    local messageIndex = ((anchorIndex - 1) % WARNING_ANCHOR_GROUP_SIZE) + 1
    -- Last slot in each anchor group is always the exit drop (no raid-leader message).
    if messageIndex == WARNING_ANCHOR_GROUP_SIZE then
        ShowResolvedCallout({
            hudMessage = L.SSZORAK_EXIT,
            targetEdge = Sszorak.EXIT_EDGE,
        }, CALLOUT_DURATION_ENCOUNTER, true)
        return
    end
    local message = raidLeaderMessages[messageIndex]
    if message == nil then
        return
    end
    ResolveAndShow(message, CALLOUT_DURATION_ENCOUNTER, true)
end

local function TrySaveRaidLeaderMessage(message)
    if not raidLeaderCapture or #raidLeaderMessages >= RAID_LEADER_MESSAGE_LIMIT then
        return
    end
    table.insert(raidLeaderMessages, message)
    NotifyRaidLeaderMessagesChanged()
end

---Shared by every callout mode: raid-leader capture + encounter-warning matching. Returns unsubscribe.
---@return fun()
function Sszorak.SubscribeSharedCalloutListeners()
    local stopWarning = Encounter.OnWarning(OnEncounterWarning)
    local stopRaidLeader = Chat.OnRaidLeaderMessage(TrySaveRaidLeaderMessage)
    return function()
        stopWarning()
        stopRaidLeader()
    end
end

function Sszorak:BeginRaidLeaderCapture()
    raidLeaderCapture = true
    ClearRaidLeaderMessages()
end

function Sszorak:EndRaidLeaderCapture()
    if not raidLeaderCapture then
        return
    end
    raidLeaderCapture = false
    ClearRaidLeaderMessages()
end

---In map test only: show saved callouts at the same left→center / right→center moves warnings use in a real pull.
---@param fromStation integer
---@param toStation integer
function Sszorak:OnStationChangedForCallout(fromStation, toStation)
    if Sszorak:IsInEncounter() or not raidLeaderCapture or toStation ~= Sszorak.STATION_CENTER then
        return
    end
    local messageIndex
    if fromStation == Sszorak.STATION_HOME then
        messageIndex = 1
    elseif fromStation == Sszorak.STATION_FAR then
        messageIndex = 3
    else
        return
    end
    local message = raidLeaderMessages[messageIndex]
    if message == nil then
        return
    end
    ResolveAndShow(message, CALLOUT_DURATION_TEST, true)
end

function Sszorak:ClearRaidLeaderMessages()
    ClearRaidLeaderMessages()
end

---@return boolean  Whether raid leader messages are being captured.
function Sszorak:IsCapturingRaidLeaderMessages()
    return raidLeaderCapture
end

---The saved raid leader messages for this home phase (opaque; may be secret values).
---@return table
function Sszorak:GetRaidLeaderMessages()
    return raidLeaderMessages
end

---The on-screen callout text (opaque; may be secret), or nil when nothing is shown.
---@return any|nil
function Sszorak:GetDisplayedCallout()
    return displayedCallout
end

---Last resolve payload (for map overlays), or nil when nothing is shown.
---@return SszorakCalloutResolve|nil
function Sszorak:GetDisplayedCalloutResolve()
    return displayedResolve
end

---Whole seconds left on the current callout countdown, or nil when nothing is shown.
---@return integer|nil
function Sszorak:GetCalloutRemainingSeconds()
    if displayedCallout == nil or not calloutExpireTime then
        return nil
    end
    return math.max(0, math.ceil(calloutExpireTime - Timer.GetTime()))
end

---Whether the HUD should append a whole-second countdown to the current callout.
---@return boolean
function Sszorak:GetCalloutAppendTimer()
    return displayedCalloutAppendTimer
end

Sszorak.BindCalloutHooks({
    beginCapture = function()
        Sszorak:BeginRaidLeaderCapture()
    end,
    endCapture = function()
        Sszorak:EndRaidLeaderCapture()
    end,
    clearMessages = function()
        ClearRaidLeaderMessages()
    end,
    onStationChanged = function(fromStation, toStation)
        Sszorak:OnStationChangedForCallout(fromStation, toStation)
    end,
})
