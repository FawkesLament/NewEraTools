local _, ns = ...
local Internals = ns.Modules.Internals("Ulatek")
local L = ns.L
local CalloutManager = ns.CalloutManager
local Encounter = ns.Api.Encounter
local Instance = ns.Api.Instance
local Timer = ns.Api.Timer
local ResourceScope = ns.ResourceScope

local Ulatek = ns.Modules.Get("Ulatek")
local Timeline = Internals.Timeline

-- Ulatek in The Venomous Abyss.
local ENCOUNTER_ID = 3492
local CALLOUT_SOURCE = "Ulatek"

Ulatek.ENCOUNTER_ID = ENCOUNTER_ID

---@type { SetCalloutGroupActive: fun(group: UlatekPadGroupId, active: boolean), ResetCalloutGroups: fun() }
local padCallouts = {
    SetCalloutGroupActive = function() end,
    ResetCalloutGroups = function() end,
}

---Map binds combat-safe pad visuals after it loads. No-ops until then (logic-only tests).
---@param ui { SetCalloutGroupActive: fun(group: UlatekPadGroupId, active: boolean), ResetCalloutGroups: fun() }
function Internals.BindPadCallouts(ui)
    padCallouts = ui
end

---@type { OnTick: fun(elapsed: number, duration: number), OnFinished: fun(), OnEnded: fun() }
local padTestUi = {
    OnTick = function() end,
    OnFinished = function() end,
    OnEnded = function() end,
}

---Window binds test-timer chrome after it loads.
---@param ui { OnTick: fun(elapsed: number, duration: number), OnFinished: fun(), OnEnded: fun() }
function Internals.BindPadTestUi(ui)
    padTestUi = ui
end

---@type ResourceScope|nil
local padTestScope = nil

---@type table<UlatekMechanicId, CalloutManagerHandle>
local handles = {}

---@param mechanicId UlatekMechanicId
---@return boolean
local function IsMechanicEnabled(mechanicId)
    if mechanicId == Timeline.CAUSTIC_WAVES then
        return Ulatek:IsCausticWavesReminderEnabled()
    end
    if mechanicId == Timeline.EGG_DEADLINE then
        return Ulatek:IsEggDeadlineReminderEnabled()
    end
    return Ulatek:IsWretchAoeReminderEnabled()
end

---@param mechanicId UlatekMechanicId
---@return string
local function CalloutText(mechanicId)
    if mechanicId == Timeline.CAUSTIC_WAVES then
        return L.ULATEK_CAUSTIC_WAVES_CALLOUT
    end
    if mechanicId == Timeline.EGG_DEADLINE then
        return L.ULATEK_EGG_DEADLINE_CALLOUT
    end
    return L.ULATEK_WRETCH_AOE_CALLOUT
end

---@param mechanicId UlatekMechanicId
function Internals.HideMechanicCallout(mechanicId)
    local handle = handles[mechanicId]
    handles[mechanicId] = nil
    if handle then
        handle:Dismiss()
    end
end

local function ClearCallouts()
    handles = {}
    CalloutManager.ClearSource(CALLOUT_SOURCE)
end

---@param mechanicId UlatekMechanicId
---@param expiresAt number
local function ShowCallout(mechanicId, expiresAt)
    if not IsMechanicEnabled(mechanicId) then
        return
    end
    handles[mechanicId] = CalloutManager.Show({
        source = CALLOUT_SOURCE,
        key = CALLOUT_SOURCE .. ":" .. mechanicId,
        text = CalloutText(mechanicId),
        expiresAt = expiresAt,
        appendTimer = true,
    })
end

---Owns this pull's scheduled mechanic callouts until `scope` is disposed.
---@param scope ResourceScope
---@param difficultyID number
function Internals.StartAlerts(scope, difficultyID)
    local schedule = Timeline.GetSchedule(difficultyID)
    if not schedule then
        return
    end
    local pullStart = Timer.GetTime()
    local now = pullStart
    ---Captures per-hit values so Lua 5.1 closures do not share loop locals.
    ---@param mechanicId UlatekMechanicId
    ---@param delay number
    ---@param expiresAt number
    local function ScheduleShow(mechanicId, delay, expiresAt)
        if delay <= 0 then
            ShowCallout(mechanicId, expiresAt)
            return
        end
        scope:After(delay, function()
            ShowCallout(mechanicId, expiresAt)
        end)
    end
    for _, mechanicId in ipairs(Timeline.MECHANICS) do
        local mechanic = schedule[mechanicId]
        for index = 1, #mechanic.hits do
            local expiresAt = pullStart + mechanic.hits[index]
            if expiresAt > now then
                ScheduleShow(mechanicId, expiresAt - mechanic.leadTime - now, expiresAt)
            end
        end
    end
    scope:Add(ClearCallouts)
end

---Schedules tactical-pad wave/boss click windows. Map applies combat-safe visuals.
---@param scope ResourceScope
---@param difficultyID number
---@param rate number|nil  Timeline speed. Defaults to 1.
function Internals.StartPadCallouts(scope, difficultyID, rate)
    local windows = Timeline.GetPadWindows(difficultyID)
    if #windows == 0 then
        return
    end
    rate = rate or 1
    ---Captures per-window values so Lua 5.1 closures do not share loop locals.
    ---@param group UlatekPadGroupId
    ---@param delay number
    ---@param active boolean
    local function ScheduleGroup(group, delay, active)
        local function Apply()
            padCallouts.SetCalloutGroupActive(group, active)
        end
        if delay <= 0 then
            Apply()
            return
        end
        scope:After(delay, Apply)
    end
    for _, window in ipairs(windows) do
        ScheduleGroup(window.group, window.openAt / rate, true)
        ScheduleGroup(window.group, window.closeAt / rate, false)
    end
    scope:Add(function()
        padCallouts.ResetCalloutGroups()
    end)
end

local function NotifyEncounterChanged()
    if Ulatek.OnEncounterChanged then
        Ulatek:OnEncounterChanged()
    end
end

---Ends the 3x pad preview. Safe to call when no test is running.
function Ulatek:EndPadTest()
    local scope = padTestScope
    if not scope then
        return
    end
    padTestScope = nil
    scope:Dispose()
end

---Whether the 3x pad preview timeline is running.
---@return boolean
function Ulatek:IsPadTestActive()
    return padTestScope ~= nil
end

---Starts (or restarts) the Mythic pad click windows at `Timeline.PAD_TEST_RATE`.
function Ulatek:StartPadTest()
    self:EndPadTest()
    local rate = Timeline.PAD_TEST_RATE
    local duration = Timeline.PAD_TEST_DURATION
    local scope = ResourceScope.New()
    padTestScope = scope
    local startTime = Timer.GetTime()
    Internals.StartPadCallouts(scope, Instance.DIFFICULTY_MYTHIC_RAID, rate)
    padTestUi.OnTick(0, duration)
    scope:Ticker(0.05, function()
        local elapsed = (Timer.GetTime() - startTime) * rate
        if elapsed > duration then
            elapsed = duration
        end
        padTestUi.OnTick(elapsed, duration)
    end)
    scope:After(duration / rate, function()
        padTestUi.OnFinished()
    end)
    scope:Add(function()
        padTestUi.OnEnded()
    end)
end

---Starts watching this boss fight. Called from OnEnable.
function Ulatek:ListenForEncounter()
    Encounter.WhileIn(ENCOUNTER_ID, function(difficultyID, scope)
        -- Drop the 3x preview so production windows own the pad from pull-start.
        Ulatek:EndPadTest()
        NotifyEncounterChanged()
        scope:Add(NotifyEncounterChanged)
        Internals.StartAlerts(scope, difficultyID)
        Internals.StartPadCallouts(scope, difficultyID)
    end)
end
