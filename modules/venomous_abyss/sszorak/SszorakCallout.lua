local _, ns = ...
local Encounter = ns.Api.Encounter
local Timer = ns.Api.Timer

local Sszorak = ns.Modules.Get("Sszorak")

-- How long a matched callout stays on screen (wall-clock), unless a later callout replaces it.
local CALLOUT_DURATION_ENCOUNTER = 10
local CALLOUT_DURATION_TEST = 10
-- ENCOUNTER_WARNING filters: High severity, ~3.5s duration, near one of these pull-relative anchors.
local WARNING_SEVERITY = 2
local WARNING_DURATION = 3.5
local WARNING_DURATION_TOLERANCE = 0.1
local WARNING_TIME_WINDOW = 1.2

Sszorak.CALLOUT_DURATION_ENCOUNTER = CALLOUT_DURATION_ENCOUNTER
Sszorak.CALLOUT_DURATION_TEST = CALLOUT_DURATION_TEST
Sszorak.WARNING_SEVERITY = WARNING_SEVERITY
Sszorak.WARNING_DURATION = WARNING_DURATION
Sszorak.WARNING_DURATION_TOLERANCE = WARNING_DURATION_TOLERANCE
Sszorak.WARNING_TIME_WINDOW = WARNING_TIME_WINDOW

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
---@field OnMatchedWarning fun(self: SszorakCalloutMode, anchorIndex: integer): SszorakCalloutResolve|nil  Shared filter matched a warning.
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

---@param mode SszorakCalloutMode
function Sszorak.RegisterCalloutMode(mode)
    assert(type(mode) == "table" and type(mode.id) == "string", "Bad callout mode")
    assert(type(mode.GetEdgeMacroBody) == "function", "Callout mode requires GetEdgeMacroBody")
    assert(type(mode.Listen) == "function", "Callout mode requires Listen")
    assert(type(mode.OnMatchedWarning) == "function", "Callout mode requires OnMatchedWarning")
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
    local resolve = Sszorak:GetActiveCalloutMode():OnMatchedWarning(anchorIndex)
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

---Map test only: left→center / right→center preview the same slots warnings use (anchors 1 and 3).
---@param fromStation integer
---@param toStation integer
local function OnStationChangedForMapTest(fromStation, toStation)
    local mode = Sszorak:GetActiveCalloutMode()
    local capturing = mode.IsCapturing and mode:IsCapturing()
    if Sszorak:IsInEncounter() or not capturing or toStation ~= Sszorak.STATION_CENTER then
        return
    end
    local anchorIndex
    if fromStation == Sszorak.STATION_HOME then
        anchorIndex = 1
    elseif fromStation == Sszorak.STATION_FAR then
        anchorIndex = 3
    else
        return
    end
    Sszorak.ShowResolvedCallout(mode:OnMatchedWarning(anchorIndex), CALLOUT_DURATION_TEST, true)
end

Sszorak.BindCalloutHooks({
    beginCapture = function()
        CallActiveMode("BeginCapture")
    end,
    endCapture = function()
        CallActiveMode("EndCapture")
    end,
    clearMessages = function()
        CallActiveMode("ClearMessages")
    end,
    onStationChanged = OnStationChangedForMapTest,
})
