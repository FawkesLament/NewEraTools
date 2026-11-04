local _, ns = ...
local Client = ns.Api.Client
local Encounter = ns.Api.Encounter
local GameEvents = ns.Api.GameEvents
local Secrets = ns.Api.Secrets
local Timer = ns.Api.Timer
local Unit = ns.Api.Unit

local SECRET_TEXT = "<secret>"

local LOGGED_EVENTS = {
    "UNIT_SPELLCAST_START",
    "UNIT_SPELLCAST_SUCCEEDED",
    "UNIT_SPELLCAST_INTERRUPTED",
    "UNIT_SPELLCAST_STOP",
    "UNIT_SPELLCAST_CHANNEL_START",
    "UNIT_SPELLCAST_CHANNEL_STOP",
    "NAME_PLATE_UNIT_ADDED",
    "NAME_PLATE_UNIT_REMOVED",
    "ENCOUNTER_TIMELINE_EVENT_ADDED",
    "ENCOUNTER_TIMELINE_EVENT_REMOVED",
    "ENCOUNTER_WARNING",
    "ENCOUNTER_STATE_CHANGED",
    "INSTANCE_ENCOUNTER_ADD_TIMER",
    "INSTANCE_ENCOUNTER_ENGAGE_UNIT",
    "INSTANCE_ENCOUNTER_OBJECTIVE_COMPLETE",
    "INSTANCE_ENCOUNTER_OBJECTIVE_START",
    "INSTANCE_ENCOUNTER_OBJECTIVE_UPDATE",
}

local ENEMY_UNIT_EVENTS = {
    UNIT_SPELLCAST_START = true,
    UNIT_SPELLCAST_SUCCEEDED = true,
    UNIT_SPELLCAST_INTERRUPTED = true,
    UNIT_SPELLCAST_STOP = true,
    UNIT_SPELLCAST_CHANNEL_START = true,
    UNIT_SPELLCAST_CHANNEL_STOP = true,
    NAME_PLATE_UNIT_ADDED = true,
    NAME_PLATE_UNIT_REMOVED = true,
}

---@class EventLog: Module
---@field OnSavedLogChanged fun(self: EventLog)|nil  Defined by the UI; called when the saved log identity changes.
local EventLog = ns.Modules.New("EventLog", {
    defaults = {
        enabled = false,
    },
})

---@class EventLogSaved
---@field encounterID number
---@field startedAt string

---@type string[]
local lines = {}
local listening = false
---@type number|nil
local encounterStart
---@type ResourceScope|nil
local sessionScope
---@type number|nil
local savedEncounterID
---@type string|nil
local savedStartedAt

local function NotifySavedLogChanged()
    if EventLog.OnSavedLogChanged then
        EventLog:OnSavedLogChanged()
    end
end

---@param value any
---@return number
local function ClockField(value)
    return tonumber(value) or 0
end

---@return string
local function FormatStartTime()
    local clock = Client.GetCalendarTime()
    if type(clock) ~= "table" then
        return "00-00-00-00:00:00"
    end
    return string.format(
        "%02d-%02d-%02d-%02d:%02d:%02d",
        ClockField(clock.year) % 100,
        ClockField(clock.month),
        ClockField(clock.monthDay),
        ClockField(clock.hour),
        ClockField(clock.minute),
        ClockField(clock.second)
    )
end

---@param a any
---@param b any
---@return boolean
local function KeyLess(a, b)
    local typeA, typeB = type(a), type(b)
    if typeA ~= typeB then
        return typeA < typeB
    end
    if typeA == "number" or typeA == "string" then
        return a < b
    end
    return tostring(a) < tostring(b)
end

---@param out string[]
---@param value any
---@param seen table
local function AppendSanitized(out, value, seen)
    if Secrets.IsSecret(value) then
        out[#out + 1] = SECRET_TEXT
        return
    end
    if type(value) ~= "table" then
        out[#out + 1] = tostring(value)
        return
    end
    if seen[value] then
        return
    end
    seen[value] = true
    local keys = {}
    for key in pairs(value) do
        keys[#keys + 1] = key
    end
    table.sort(keys, KeyLess)
    for i = 1, #keys do
        AppendSanitized(out, value[keys[i]], seen)
    end
end

---@return string[]
local function SanitizePayload(...)
    local out = {}
    local seen = {}
    local count = select("#", ...)
    for i = 1, count do
        AppendSanitized(out, (select(i, ...)), seen)
    end
    return out
end

---@param unitToken any
---@return boolean
local function ShouldLogEnemyUnit(unitToken)
    if Secrets.IsSecret(unitToken) then
        return false
    end
    return Unit.IsEnemy(unitToken) == true
end

---@param callback fun(event: string, ...)
---@return fun()
local function SubscribeLoggedEvents(callback)
    local unsubs = {}
    for i = 1, #LOGGED_EVENTS do
        local event = LOGGED_EVENTS[i]
        unsubs[i] = GameEvents.Listen(event, function(...)
            if ENEMY_UNIT_EVENTS[event] and not ShouldLogEnemyUnit(...) then
                return
            end
            callback(event, ...)
        end)
    end
    return function()
        for i = 1, #unsubs do
            unsubs[i]()
        end
    end
end

local function StopSession()
    local scope = sessionScope
    sessionScope = nil
    encounterStart = nil
    if scope then
        scope:Dispose()
    end
end

local function OnLoggedEvent(event, ...)
    local startTime = encounterStart
    if not startTime then
        return
    end
    local fields = { event, string.format("%.3f", Timer.GetTime() - startTime) }
    local payload = SanitizePayload(...)
    for i = 1, #payload do
        fields[#fields + 1] = payload[i]
    end
    lines[#lines + 1] = table.concat(fields, " ")
end

---@param encounterID number|nil
local function BeginEncounter(encounterID)
    StopSession()
    if not EventLog:IsEnabled() then
        return
    end
    lines = {}
    encounterStart = Timer.GetTime()
    savedEncounterID = tonumber(encounterID) or 0
    savedStartedAt = FormatStartTime()
    local scope = ns.ResourceScope.New()
    sessionScope = scope
    scope:Subscribe(SubscribeLoggedEvents, OnLoggedEvent)
    if sessionScope ~= scope then
        scope:Dispose()
    end
    NotifySavedLogChanged()
end

---@return boolean
function EventLog:IsEnabled()
    return self.db.enabled == true
end

---@param enabled boolean
function EventLog:SetEnabled(enabled)
    enabled = enabled == true
    if self.db.enabled == enabled then
        return
    end
    self.db.enabled = enabled
    if not enabled then
        StopSession()
    end
end

---Current encounter log lines. Cleared when a new encounter starts while enabled.
---@return string[]
function EventLog:GetLines()
    return lines
end

---Log lines joined for the viewer. Empty when nothing has been recorded yet.
---@return string
function EventLog:GetLogText()
    return table.concat(lines, "\n")
end

---Identity of the last recorded encounter, or nil when no log has been saved.
---@return EventLogSaved|nil
function EventLog:GetSavedLog()
    if savedEncounterID == nil or savedStartedAt == nil then
        return nil
    end
    return {
        encounterID = savedEncounterID,
        startedAt = savedStartedAt,
    }
end

---Registers encounter start/end listeners once. Called from OnEnable.
function EventLog:StartListening()
    if listening then
        return
    end
    listening = true
    Encounter.OnStart(BeginEncounter)
    Encounter.OnEnd(StopSession)
end
