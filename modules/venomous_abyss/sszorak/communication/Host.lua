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

---Map edge to highlight and the HUD text to show. Nil means show nothing; an empty table is not used for that.
---A mode may omit `hudMessage` when `targetEdge` is set. The host then builds the warning for that edge.
---A returned `hudMessage` is kept, including when `targetEdge` is also set.
---@class CystGuidance
---@field targetEdge? number  Arena edge. Nil means no map path.
---@field hudMessage? any  Opaque / formatted text. Nil with a `targetEdge` asks the host to fill it in.

---@class SszorakCalloutMode
---@field id string
---@field GetEdgeMacroBody fun(self: SszorakCalloutMode, edge: integer, assignment: table<integer, WorldMarker>): string
---@field Listen fun(self: SszorakCalloutMode): fun()  Subscribe mode listeners; returns unsubscribe.
---@field OnViscousCystWarning fun(self: SszorakCalloutMode, anchorIndex: integer): CystGuidance|nil
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
---@type CystGuidance|nil
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
---@param resolve CystGuidance|nil
---@param duration number
---@param appendTimer boolean|nil
function Sszorak.ShowResolvedCallout(resolve, duration, appendTimer)
    if resolve == nil then
        return
    end
    local message = assert(resolve.hudMessage, "CystGuidance requires hudMessage")
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

local SIDE_TEXT = {
    same = L.SSZORAK_SIDE_SAME,
    opposite = L.SSZORAK_SIDE_OPPOSITE,
}

local DEPTH_TEXT = {
    near = L.SSZORAK_DEPTH_NEAR,
    mid = L.SSZORAK_DEPTH_MID,
    far = L.SSZORAK_DEPTH_FAR,
}

---Same-side or opposite-side phrase for `edge`, flipped when the player is on the exit side of the room.
---@param edge integer
---@param fromEntranceSide boolean
---@return string|nil
local function RelativePosition(edge, fromEntranceSide)
    local absoluteDepth = Sszorak:GetEdgeEntranceDepth(edge)
    local edgeGroup = Sszorak:GetEdgeGroup(edge)
    if not absoluteDepth or not edgeGroup then
        return nil
    end
    local depth = absoluteDepth
    if absoluteDepth ~= "mid" and not fromEntranceSide then
        depth = absoluteDepth == "near" and "far" or "near"
    end
    local sideText = edgeGroup == Sszorak:GetPlayerGroup() and SIDE_TEXT.same or SIDE_TEXT.opposite
    local depthText = DEPTH_TEXT[depth]
    if not sideText or not depthText then
        return nil
    end
    return string.format(L.SSZORAK_RELATIVE_POSITION, sideText, depthText)
end

---GUI warning for `edge`: the exit phrase, or that edge's raid-target icon plus its position relative to the player.
---`fromEntranceSide` is ignored for the exit. Other edges return nil when they have no marker.
---@param edge integer
---@param fromEntranceSide boolean?
---@return string?
local function HudMessageForEdge(edge, fromEntranceSide)
    if type(edge) ~= "number" then
        return nil
    end
    if edge == Sszorak.EXIT_EDGE then
        return L.SSZORAK_EXIT
    end
    local marker = Sszorak:GetEdgeMarker(edge)
    local raidTarget = marker and Sszorak.MARKER_RAID_TARGET[marker]
    if not raidTarget then
        return nil
    end
    local relative = RelativePosition(edge, fromEntranceSide == true)
    if not relative then
        return nil
    end
    return Chat.ReplaceIconAndGroupExpressions("{rt" .. raidTarget .. "}") .. " " .. relative
end

---Slots 1 and 2 of each warning group are the entrance side. Slot 3, and the exit slot, are the exit side.
---@param anchorIndex integer
---@return boolean
local function EntranceSideAnchor(anchorIndex)
    local slot = ((anchorIndex - 1) % WARNING_ANCHOR_GROUP_SIZE) + 1
    return slot <= 2
end

---Fills `hudMessage` when a mode returns only `targetEdge`. A provided `hudMessage` is kept with its edge.
---Returns nil when the host cannot build a message, including an edge with no marker.
---@param guidance CystGuidance|nil
---@param anchorIndex integer
---@return CystGuidance|nil
local function BackfillGuidance(guidance, anchorIndex)
    if type(guidance) ~= "table" then
        return nil
    end
    if guidance.hudMessage ~= nil then
        return guidance
    end
    if type(guidance.targetEdge) ~= "number" then
        return nil
    end
    local hudMessage = HudMessageForEdge(guidance.targetEdge, EntranceSideAnchor(anchorIndex))
    if hudMessage == nil then
        return nil
    end
    return {
        hudMessage = hudMessage,
        targetEdge = guidance.targetEdge,
    }
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
    local backfilled = BackfillGuidance(Sszorak:GetActiveCalloutMode():OnViscousCystWarning(anchorIndex), anchorIndex)
    Sszorak.ShowResolvedCallout(backfilled, CALLOUT_DURATION_ENCOUNTER, true)
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
---@return CystGuidance|nil
function Sszorak:GetDisplayedCalloutResolve()
    return displayedResolve
end

---Absolute Timer.GetTime() when the current callout hides, or nil when nothing is shown.
---@return number|nil
function Sszorak:GetCalloutExpiresAt()
    if displayedCallout == nil then
        return nil
    end
    return calloutExpireTime
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
---@return CystGuidance|nil
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
---@param resolve CystGuidance|nil
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
    local first = BackfillGuidance(mode:OnViscousCystWarning(firstIndex), firstIndex)
    local second = BackfillGuidance(mode:OnViscousCystWarning(secondIndex), secondIndex)
    savedEdgeResolves[firstIndex] = first
    savedEdgeResolves[secondIndex] = second
    Util.Print(
        string.format(L.SSZORAK_HUD_PAIR, firstIndex, DecodedHudText(first), secondIndex, DecodedHudText(second))
    )
    if not Sszorak:IsInEncounter() then
        Sszorak.ShowResolvedCallout(first, CALLOUT_DURATION_TEST, true)
    end
end
