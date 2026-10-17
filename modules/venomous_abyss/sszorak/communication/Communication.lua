local _, ns = ...
local L = ns.L
local Chat = ns.Api.Chat
local Encounter = ns.Api.Encounter
local Timer = ns.Api.Timer
local Util = ns.Util

local Sszorak = ns.Modules.Get("Sszorak")

-- How long a matched callout stays on screen (wall-clock), unless a later callout replaces it.
local CALLOUT_DURATION_ENCOUNTER = 10
local CALLOUT_DURATION_TEST = 10
-- ENCOUNTER_WARNING filters: High severity, ~3.5s duration, near one of these pull-relative anchors.
local WARNING_SEVERITY = 2
local WARNING_DURATION = 3.5
local WARNING_DURATION_TOLERANCE = 0.1
local WARNING_TIME_WINDOW = 1.2
-- Anchors are processed in groups of this size; the last slot of each group is the exit drop.
local WARNING_ANCHOR_GROUP_SIZE = 4

Sszorak.CALLOUT_DURATION_ENCOUNTER = CALLOUT_DURATION_ENCOUNTER
Sszorak.CALLOUT_DURATION_TEST = CALLOUT_DURATION_TEST
Sszorak.WARNING_SEVERITY = WARNING_SEVERITY
Sszorak.WARNING_DURATION = WARNING_DURATION
Sszorak.WARNING_DURATION_TOLERANCE = WARNING_DURATION_TOLERANCE
Sszorak.WARNING_TIME_WINDOW = WARNING_TIME_WINDOW
Sszorak.WARNING_ANCHOR_GROUP_SIZE = WARNING_ANCHOR_GROUP_SIZE

---Payload passed to ShowResolvedCallout for HUD text and optional map path.
---A non-nil value always has `hudMessage`. Pass `nil` when nothing should be shown
---(e.g. jailbreak has not identified a marker yet) — an empty table is not used for that.
---`hudMessage` is not always derivable from `targetEdge` (normal keeps RL text; exit uses locale).
---`targetEdge` is the map path tip (`nil` = no arrow); the marker on that edge is from the assignment.
---@class SszorakCalloutResolve
---@field hudMessage any  Opaque / formatted text for SetFormattedText; required.
---@field targetEdge integer|nil  Arena edge for the path overlay (e.g. exit or jailbreak destination).

---@class SszorakCalloutMode
---@field id string
---@field GetEdgeMacroBody fun(self: SszorakCalloutMode, edge: integer, assignment: table<integer, WorldMarker>): string
---@field Listen fun(self: SszorakCalloutMode): fun()  Subscribe mode listeners; returns unsubscribe.
---@field OnViscousCystWarning fun(self: SszorakCalloutMode, anchorIndex: integer): SszorakCalloutResolve|nil
---@field BeginCapture fun(self: SszorakCalloutMode)|nil  Encounter / map-test started.
---@field EndCapture fun(self: SszorakCalloutMode)|nil  Encounter / map-test ended.
---@field ClearMessages fun(self: SszorakCalloutMode)|nil  Dots returned home mid-timeline.
---@field IsCapturing fun(self: SszorakCalloutMode): boolean|nil  Map-test / encounter capture active.

---@type table<string, SszorakCalloutMode>
local modes = {}

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
-- Mode id whose Listen is currently subscribed. Nil before ListenForCalloutMode.
---@type string|nil
local listeningModeId = nil
-- Preferred provider arrived during a pull or capture; apply it when that session ends.
local pendingPreferredActivation = false

---@param mode SszorakCalloutMode
function Sszorak.RegisterCalloutMode(mode)
    assert(type(mode) == "table" and type(mode.id) == "string", "Bad callout mode")
    assert(type(mode.GetEdgeMacroBody) == "function", "Callout mode requires GetEdgeMacroBody")
    assert(type(mode.Listen) == "function", "Callout mode requires Listen")
    assert(type(mode.OnViscousCystWarning) == "function", "Callout mode requires OnViscousCystWarning")
    modes[mode.id] = mode
end

-- External addons register this extension type through NewEraToolsAPI. See docs/extensions.md.
local COMMUNICATION_EXTENSION = "sszorak.communication"

Sszorak.COMMUNICATION_EXTENSION = COMMUNICATION_EXTENSION

---Reads the callout-mode contract fields and does not call them.
---@param provider table
---@return boolean
local function ImplementsCalloutMode(provider)
    return type(provider.id) == "string"
        and type(provider.GetEdgeMacroBody) == "function"
        and type(provider.Listen) == "function"
        and type(provider.OnViscousCystWarning) == "function"
end

local function NotifyCalloutModesChanged()
    if Sszorak.OnCalloutModesChanged then
        Sszorak:OnCalloutModesChanged()
    end
end

---Saved preference, including a provider that has not registered yet.
---@return string
function Sszorak:GetPreferredCalloutMode()
    return self.db.calloutMode
end

---@param value any
---@return boolean
local function IsModeId(value)
    return type(value) == "string" and #value >= 1 and #value <= 64 and value:match("^[A-Za-z][A-Za-z0-9_.%-]*$") ~= nil
end

---Replaces a preference that is not a mode id. An id with no provider yet is kept.
---Called from OnInit, which can run before another addon registers.
function Sszorak:RepairCalloutMode()
    if not IsModeId(self.db.calloutMode) then
        self.db.calloutMode = Sszorak.CALLOUT_MODE_NORMAL
    end
end

---@return string
local function CurrentModeId()
    if pendingPreferredActivation and listeningModeId and modes[listeningModeId] then
        return listeningModeId
    end
    local preferred = Sszorak.db and Sszorak.db.calloutMode
    if preferred and modes[preferred] then
        return preferred
    end
    return Sszorak.CALLOUT_MODE_NORMAL
end

---@return SszorakCalloutMode
function Sszorak:GetActiveCalloutMode()
    local mode = modes[CurrentModeId()] or modes[Sszorak.CALLOUT_MODE_NORMAL]
    return assert(mode, "No callout mode registered")
end

---Mode driving callouts right now. Falls back to normal when the preference has no provider.
---@return string
function Sszorak:GetCalloutMode()
    return CurrentModeId()
end

local function StopCalloutModeListeners()
    if not stopCalloutModeListeners then
        return
    end
    local stop = stopCalloutModeListeners
    stopCalloutModeListeners = nil
    stop()
end

local function BindCalloutMode(modeId)
    StopCalloutModeListeners()
    listeningModeId = modeId
    stopCalloutModeListeners = modes[modeId]:Listen() or function() end
end

---True while a pull is running, or while the bound mode is still collecting a map test.
---@return boolean
local function ActivationBlocked()
    if Sszorak:IsInEncounter() then
        return true
    end
    if not listeningModeId then
        return false
    end
    local mode = modes[listeningModeId]
    return mode ~= nil and mode.IsCapturing ~= nil and mode:IsCapturing() == true
end

---Binds the preferred provider when it is registered and no pull or capture is in progress.
---Macro edits still go through RequestMacroSync, which defers during lockdown.
local function ApplyPreferredMode()
    pendingPreferredActivation = false
    if not Sszorak.db then
        NotifyCalloutModesChanged()
        return
    end
    local targetId = modes[Sszorak.db.calloutMode] and Sszorak.db.calloutMode or Sszorak.CALLOUT_MODE_NORMAL
    if not calloutModeListening or listeningModeId == targetId then
        NotifyCalloutModesChanged()
        return
    end
    BindCalloutMode(targetId)
    Sszorak.RequestMacroSync()
    NotifyCalloutModesChanged()
end

local function ConsiderPreferredProvider(providerId)
    if not Sszorak.db or Sszorak.db.calloutMode ~= providerId then
        NotifyCalloutModesChanged()
        return
    end
    if ActivationBlocked() then
        pendingPreferredActivation = true
        NotifyCalloutModesChanged()
        return
    end
    ApplyPreferredMode()
end

---Forwards an external communication provider into the callout mode table.
---Built-in modes already occupy their ids; those registrations are rejected so the mode table stays authoritative.
---Registration does not itself subscribe. A provider that matches the saved preference is activated when safe.
---@param _extensionType string
---@param providerId string
---@param provider table
local function AcceptExternalCalloutMode(_extensionType, providerId, provider)
    if not ImplementsCalloutMode(provider) then
        error("Sszorak communication extension does not implement the callout mode contract")
    end
    if provider.id ~= providerId then
        error("Sszorak communication extension id must match the provider id")
    end
    if modes[providerId] then
        error("Sszorak communication extension already registered: " .. providerId)
    end
    Sszorak.RegisterCalloutMode(provider)
    ConsiderPreferredProvider(providerId)
end

-- Subscribed at file load so the callback exists before OnInit and before dependent addons run.
ns.Extensions.OnRegistered(COMMUNICATION_EXTENSION, AcceptExternalCalloutMode)

---@param modeId string
---@return boolean
function Sszorak.IsCalloutModeAvailable(modeId)
    return modes[modeId] ~= nil
end

---The registered provider, or nil. Host code uses this; it is not a second mode list.
---@param modeId string
---@return SszorakCalloutMode|nil
function Sszorak.GetRegisteredCalloutMode(modeId)
    return modes[modeId]
end

---@param modeId string
function Sszorak:SetCalloutMode(modeId)
    assert(modes[modeId], "Unknown callout mode: " .. tostring(modeId))
    pendingPreferredActivation = false
    local unchanged = self.db.calloutMode == modeId
    if unchanged and (not calloutModeListening or listeningModeId == modeId) then
        return
    end
    self.db.calloutMode = modeId
    if calloutModeListening then
        BindCalloutMode(modeId)
    end
    -- Macro bodies are mode-specific. Macros.lua defers the edit during lockdown.
    Sszorak.RequestMacroSync()
    if not unchanged then
        NotifyCalloutModesChanged()
    end
end

---Starts the active callout mode's listeners. Called from OnEnable; mode switches rebind while active.
function Sszorak:ListenForCalloutMode()
    calloutModeListening = true
    pendingPreferredActivation = false
    BindCalloutMode(CurrentModeId())
end

local function NotifyCalloutChanged()
    if Sszorak.OnCalloutChanged then
        Sszorak:OnCalloutChanged()
    end
end

---Clears the on-screen callout (modes call this when capture ends or messages reset).
function Sszorak.ClearDisplayedCallout()
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
---No-ops when `resolve` is nil (nothing to show). Non-nil resolves require `hudMessage`.
---@param resolve SszorakCalloutResolve|nil
---@param duration number
---@param appendTimer boolean|nil
function Sszorak.ShowResolvedCallout(resolve, duration, appendTimer)
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

---Closest warning anchor within the time window, or nil.
---@param elapsed number
---@return integer|nil
local function FindMatchingAnchorIndex(elapsed)
    local bestIndex
    local bestDistance
    for index, anchor in ipairs(Sszorak.ACTIVE_SCHEDULE.warningAnchors) do
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
    local resolve = Sszorak:GetActiveCalloutMode():OnViscousCystWarning(anchorIndex)
    Sszorak.ShowResolvedCallout(resolve, CALLOUT_DURATION_ENCOUNTER, true)
end

---Shared by every callout mode: ENCOUNTER_WARNING filter + anchor match, then show the mode's resolve.
---@return fun()
function Sszorak.SubscribeSharedCalloutListeners()
    return Encounter.OnWarning(OnEncounterWarning)
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

local function CallActiveMode(methodName, ...)
    local mode = Sszorak:GetActiveCalloutMode()
    local method = mode[methodName]
    if method then
        method(mode, ...)
    end
end

-- Session-only: resolves queried when dots reach center. Slots 1–2 from home, 3–4 from the far side.
local savedEdgeResolves = {}

local function ClearSavedEdgeResolves()
    savedEdgeResolves = {}
end

---Resolve saved for `anchorIndex` (1–4) at the last matching move to center, or nil.
---@param anchorIndex integer
---@return SszorakCalloutResolve|nil
function Sszorak:GetSavedEdgeResolve(anchorIndex)
    return savedEdgeResolves[anchorIndex]
end

---Encounter and map test ask the active protocol to start collecting signals.
function Sszorak:BeginCalloutCapture()
    ClearSavedEdgeResolves()
    Sszorak.ClearDisplayedCallout()
    CallActiveMode("BeginCapture")
end

---Encounter end and map-test end ask the active protocol to drop what it collected.
---A preferred provider that arrived during that session is bound once the session is over.
function Sszorak:EndCalloutCapture()
    ClearSavedEdgeResolves()
    Sszorak.ClearDisplayedCallout()
    CallActiveMode("EndCapture")
    if pendingPreferredActivation and not ActivationBlocked() then
        ApplyPreferredMode()
    end
end

---A return to the home station asks the active protocol to drop its buffer.
function Sszorak:ClearCalloutMessages()
    Sszorak.ClearDisplayedCallout()
    CallActiveMode("ClearMessages")
end

---HUD text for chat. Icon tags are expanded; a missing resolve becomes the empty placeholder.
---@param resolve SszorakCalloutResolve|nil
---@return string
local function DecodedHudText(resolve)
    local text = resolve and resolve.hudMessage
    if type(text) ~= "string" then
        return L.SSZORAK_HUD_EMPTY
    end
    return Chat.ReplaceIconAndGroupExpressions(text)
end

---Home→center is anchors 1 and 2. Far→center is anchors 3 and 4. Other moves are not a pair.
---@param fromStation integer
---@param toStation integer
---@return integer|nil
---@return integer|nil
local function CenterAnchorPair(fromStation, toStation)
    if toStation ~= Sszorak.STATION_CENTER then
        return nil, nil
    end
    if fromStation == Sszorak.STATION_HOME then
        return 1, 2
    end
    if fromStation == Sszorak.STATION_FAR then
        return 3, 4
    end
    return nil, nil
end

---Pulls and map tests: on each move to center, save that side's two resolves and print them.
---Map test still previews the first of the pair on the HUD. Encounter warnings own the fight HUD.
---@param fromStation integer
---@param toStation integer
function Sszorak:NotifyCalloutStationChanged(fromStation, toStation)
    local firstIndex, secondIndex = CenterAnchorPair(fromStation, toStation)
    if not firstIndex or not secondIndex then
        return
    end
    local mode = Sszorak:GetActiveCalloutMode()
    local capturing = mode.IsCapturing and mode:IsCapturing()
    if not capturing then
        return
    end
    local first = mode:OnViscousCystWarning(firstIndex)
    local second = mode:OnViscousCystWarning(secondIndex)
    savedEdgeResolves[firstIndex] = first
    savedEdgeResolves[secondIndex] = second
    Util.Print(string.format(L.SSZORAK_HUD_PAIR, firstIndex, DecodedHudText(first), secondIndex, DecodedHudText(second)))
    if not Sszorak:IsInEncounter() then
        Sszorak.ShowResolvedCallout(first, CALLOUT_DURATION_TEST, true)
    end
end
